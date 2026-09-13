// prefer_initializing_formals wants `this._sources`, which Dart does not
// allow: a named parameter cannot be private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/http/m_client.dart';
import 'package:otaku_reader/source/util/log.dart';

/// Fetches one page image. Injected so the queue can be tested without the
/// open internet.
typedef PageFetcher = Future<List<int>> Function(
  Uri url,
  Map<String, String> headers,
);

Future<List<int>> _httpGetBytes(Uri url, Map<String, String> headers) async {
  final client = MClient.init();
  try {
    final response = await client.get(url, headers: headers);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    return response.bodyBytes;
  } finally {
    client.close();
  }
}

class DownloadRepositoryImpl implements DownloadRepository {
  DownloadRepositoryImpl({
    required SourceRepository sources,
    required LibraryRepository library,
    required Directory root,
    PageFetcher? fetch,
  }) : _sources = sources,
       _library = library,
       _root = root,
       _fetch = fetch ?? _httpGetBytes;

  final SourceRepository _sources;
  final LibraryRepository _library;
  final Directory _root;
  final PageFetcher _fetch;

  /// Concurrent chapter downloads. The same reasoning as everywhere else that
  /// fans out over sources: a site that is handed twenty parallel requests
  /// rate-limits the user rather than serving them faster. Pages *within* a
  /// chapter are fetched one at a time for the same reason, and because page
  /// order is the only thing that makes a chapter readable.
  static const maxConcurrent = 2;

  final _changes = StreamController<void>.broadcast();
  final _tasks = <String, DownloadTask>{};
  final _cancelled = <String>{};

  var _running = 0;
  final _pending = <String>[];

  /// The future of each running task, so [deleteChapter] can wait for one to
  /// stop rather than racing it.
  final _inFlight = <String, Future<void>>{};

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<DownloadTask> get tasks => _tasks.values.toList().reversed.toList();

  void _publish(DownloadTask task) {
    _tasks[task.key] = task;
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> enqueue({
    required int sourceId,
    required String mangaUrl,
    required Chapter chapter,
    required String mangaTitle,
  }) async {
    final chapterUrl = chapter.url;
    if (chapterUrl == null || chapterUrl.isEmpty) return;
    final key = '$sourceId $mangaUrl $chapterUrl';

    // Already in hand, in flight, or waiting. Re-queuing would re-fetch pages
    // that are on disk — the button is a toggle, not a repeat.
    final existing = _tasks[key];
    if (existing != null &&
        (existing.state == DownloadState.queued ||
            existing.state == DownloadState.running ||
            existing.state == DownloadState.done)) {
      return;
    }
    if (chapter.localPath != null) return;

    _cancelled.remove(key);
    _publish(
      DownloadTask(
        sourceId: sourceId,
        mangaUrl: mangaUrl,
        chapterUrl: chapterUrl,
        title: mangaTitle,
        chapterLabel: _label(chapter),
        state: DownloadState.queued,
      ),
    );
    _pending.add(key);
    unawaited(_pump());
  }

  /// Starts as many queued tasks as the concurrency limit allows.
  Future<void> _pump() async {
    while (_running < maxConcurrent && _pending.isNotEmpty) {
      final key = _pending.removeAt(0);
      final task = _tasks[key];
      if (task == null || _cancelled.remove(key)) {
        _tasks.remove(key);
        if (!_changes.isClosed) _changes.add(null);
        continue;
      }
      _running++;
      final future = _run(task).whenComplete(() {
        _running--;
        _inFlight.remove(key);
        unawaited(_pump());
      });
      _inFlight[key] = future;
      unawaited(future);
    }
  }

  Future<void> _run(DownloadTask task) async {
    _publish(_copy(task, state: DownloadState.running));
    // Written to, then moved into place as one step. A crash or a cancel
    // leaves this directory behind and nothing points at it, so there is no
    // state in which a reader can open a chapter that is missing pages.
    final target = Directory(_chapterDir(task));
    final staging = Directory('${target.path}.part');

    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);

      final methods = await _sources.methodsFor(task.sourceId);
      final pages = await methods.getPageList(task.chapterUrl);
      if (pages.isEmpty) {
        // The same rule the reader uses: a source that returns no pages has
        // failed, it has not found an empty chapter.
        throw const FormatException('The source returned no pages');
      }
      _publish(_copy(task, state: DownloadState.running, total: pages.length));

      final baseUrl = methods.sourceBaseUrl;
      for (var i = 0; i < pages.length; i++) {
        if (_cancelled.contains(task.key)) {
          await staging.delete(recursive: true);
          _tasks.remove(task.key);
          _cancelled.remove(task.key);
          if (!_changes.isClosed) _changes.add(null);
          return;
        }
        final page = pages[i];
        final bytes = await _fetch(
          Uri.parse(page.url),
          MClient.pageImageHeaders(page.headers, baseUrl),
        );
        // Zero-padded so a plain directory listing is in reading order — the
        // reader sorts by name, and "10" sorting before "2" would shuffle the
        // chapter.
        final name = '${'${i + 1}'.padLeft(4, '0')}${_extension(page.url)}';
        await File(p.join(staging.path, name)).writeAsBytes(bytes);
        _publish(
          _copy(
            task,
            state: DownloadState.running,
            downloaded: i + 1,
            total: pages.length,
          ),
        );
      }

      // Checked once more after the last page: the in-loop check cannot see a
      // cancel that arrives between the final fetch and the move, and this is
      // the window `deleteChapter` runs in — without it, deleting a chapter
      // mid-download lets the run finish afterwards, write the path back and
      // republish itself as downloaded.
      if (_cancelled.contains(task.key)) {
        await staging.delete(recursive: true);
        _tasks.remove(task.key);
        _cancelled.remove(task.key);
        if (!_changes.isClosed) _changes.add(null);
        return;
      }

      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);

      await _library.setChapterLocalPath(
        sourceId: task.sourceId,
        url: task.mangaUrl,
        chapterUrl: task.chapterUrl,
        localPath: target.path,
      );
      _publish(
        _copy(
          task,
          state: DownloadState.done,
          downloaded: pages.length,
          total: pages.length,
        ),
      );
    } catch (e) {
      Log.error('Download failed for ${task.chapterUrl}: $e');
      if (await staging.exists()) {
        await staging.delete(recursive: true).catchError((_) => staging);
      } else if (await target.exists()) {
        // The move landed and the row write did not. Nothing points at this
        // directory, so nothing will ever read it — but `usedBytes` keeps
        // counting it and every retry adds another. Staging being gone is what
        // says the move happened: the only other thing that removes it is this
        // same branch.
        await target.delete(recursive: true).catchError((_) => target);
      }
      _publish(_copy(task, state: DownloadState.failed, error: _describe(e)));
    }
  }

  @override
  Future<void> cancel(String key) async {
    final task = _tasks[key];
    if (task == null) return;
    if (task.state == DownloadState.running) {
      // Stopped at the next page boundary rather than mid-write, so a partial
      // file is never left in the staging directory for the next attempt to
      // mistake for a finished page.
      _cancelled.add(key);
      return;
    }
    _pending.remove(key);
    _tasks.remove(key);
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<void> deleteChapter({
    required int sourceId,
    required String mangaUrl,
    required String chapterUrl,
  }) async {
    final key = '$sourceId $mangaUrl $chapterUrl';
    // Stopped *first*, and waited for. A download still running would otherwise
    // finish after the delete, write the path back and republish itself as
    // downloaded — leaving the user with the files they just removed and a row
    // that disagrees with the button they pressed.
    final task = _tasks[key];
    if (task != null &&
        (task.state == DownloadState.queued ||
            task.state == DownloadState.running)) {
      _cancelled.add(key);
      _pending.remove(key);
      await _inFlight[key];
    }

    final entry = await _library.find(sourceId, mangaUrl);
    final chapter = entry?.chapters
        .where((c) => c.url == chapterUrl)
        .firstOrNull;
    final path = chapter?.localPath;
    if (path != null) {
      final dir = Directory(path);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    // Cleared even when the directory was already gone: the row pointing at a
    // path that does not exist is exactly the state that makes the reader show
    // an empty chapter instead of fetching it.
    await _library.setChapterLocalPath(
      sourceId: sourceId,
      url: mangaUrl,
      chapterUrl: chapterUrl,
      localPath: null,
    );
    _tasks.remove(key);
    _cancelled.remove(key);
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  void clearFinished() {
    _tasks.removeWhere(
      (_, t) =>
          t.state == DownloadState.done || t.state == DownloadState.failed,
    );
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<int> usedBytes() async {
    if (!await _root.exists()) return 0;
    var total = 0;
    await for (final entity in _root.list(recursive: true)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Where a chapter's pages live.
  ///
  /// The readable part is for the user browsing their own storage; the hash
  /// suffix is what makes it unique. A title alone collides — two sources
  /// carry the same series, and sources emit chapters with identical names —
  /// and a url alone is not a legal path. Nothing reads the path *back* into
  /// an identity: `Chapter.localPath` stores it verbatim, so this only has to
  /// be stable and unique, not reversible.
  String _chapterDir(DownloadTask task) => p.join(
    _root.path,
    '${task.sourceId}',
    _safe(task.title, task.mangaUrl),
    _safe(task.chapterLabel, task.chapterUrl),
  );

  static String _safe(String label, String unique) {
    final cleaned = label
        .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    // Truncated: several filesystems cap a single path component at 255 bytes,
    // and a source that titles a chapter with its whole synopsis is not rare.
    final head = cleaned.length > 60
        ? cleaned.substring(0, 60).trim()
        : cleaned;
    final digest = sha256.convert(unique.codeUnits).toString().substring(0, 8);
    return head.isEmpty ? digest : '$head-$digest';
  }

  static String _extension(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final ext = p.extension(path).toLowerCase();
    // Anything unfamiliar becomes .jpg rather than being trusted: the string
    // comes from a third-party url, and it lands on disk as a filename.
    return kDownloadedPageExtensions.contains(ext) ? ext : '.jpg';
  }

  static String _label(Chapter chapter) {
    final number = chapter.formattedNumber;
    if (number.isNotEmpty) return 'Chapter $number';
    return chapter.name?.trim().isNotEmpty ?? false
        ? chapter.name!.trim()
        : 'Chapter';
  }

  static DownloadTask _copy(
    DownloadTask task, {
    required DownloadState state,
    int? downloaded,
    int? total,
    String? error,
  }) => DownloadTask(
    sourceId: task.sourceId,
    mangaUrl: task.mangaUrl,
    chapterUrl: task.chapterUrl,
    title: task.title,
    chapterLabel: task.chapterLabel,
    state: state,
    downloaded: downloaded ?? task.downloaded,
    total: total ?? task.total,
    error: error,
  );

  static String _describe(Object error) {
    final text = '$error';
    if (text.contains('SocketException') ||
        text.contains('HandshakeException') ||
        text.contains('TimeoutException')) {
      return 'Could not reach the site';
    }
    if (error is FormatException) return error.message;
    return text;
  }

  /// The download directory, created **eagerly at startup**.
  ///
  /// Deliberately not lazy. Creating it on the first download means a bad
  /// configured path — an SD card that is not mounted, a directory the app
  /// cannot write — surfaces as a failed download rather than as something the
  /// app can report, and only for the user who tried. Doing it in `main` puts
  /// the failure in one place.
  ///
  /// **Never throws for a configured path.** This runs before `runApp`, so a
  /// throw here is a blank screen with no route to the setting that caused it.
  /// An unusable configured path falls back to the app documents directory;
  /// only the platform's own directory failing is allowed to propagate,
  /// because at that point there is nothing left to fall back to.
  ///
  /// Honours [DownloadKeys.downloadPath] when the user has set one, so a device
  /// with an SD card can put a library of scans somewhere other than internal
  /// storage.
  static Future<Directory> resolveRoot(Directory appDocuments) async {
    final configured = DownloadKeys.downloadPath.get<String?>(null);
    if (configured != null && configured.trim().isNotEmpty) {
      final dir = Directory(configured.trim());
      try {
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      } catch (e) {
        // A configured path is a *stored preference*, so it can name somewhere
        // that is no longer usable — an SD card removed, a permission revoked,
        // a path typed by hand. This runs before `runApp`, so letting it throw
        // means the app never starts and the user cannot reach the setting to
        // correct it; clearing app data would be the only way out, and that
        // takes the library with it.
        //
        // The preference is deliberately *not* cleared. It still records what
        // the user chose, and it starts working again by itself when the
        // volume comes back — discarding it would make a removable card a
        // permanent loss of the setting.
        Log.error('Download path "$configured" is unusable, falling back: $e');
      }
    }
    // The platform's own documents directory. If this fails there is nothing
    // left to fall back to, and the failure is the device's rather than
    // anything the user configured.
    final fallback = Directory(p.join(appDocuments.path, 'downloads'));
    if (!await fallback.exists()) await fallback.create(recursive: true);
    return fallback;
  }
}
