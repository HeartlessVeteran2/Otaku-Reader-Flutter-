// prefer_initializing_formals wants `this._library`, which Dart does not allow:
// a named parameter cannot be private.
// ignore_for_file: prefer_initializing_formals

import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';

/// One new chapter, with the manga it belongs to.
class ChapterUpdate {
  const ChapterUpdate({
    required this.entry,
    required this.chapter,
    required this.fetchedAt,
  });

  final MangaEntry entry;
  final Chapter chapter;
  final DateTime fetchedAt;
}

/// A manga whose refresh failed, and why.
///
/// Kept and shown rather than swallowed: a source that has moved domain fails
/// every refresh silently otherwise, and the only symptom is a series that
/// quietly stops getting chapters.
class UpdateError {
  const UpdateError({required this.entry, required this.message});

  final MangaEntry entry;
  final String message;
}

/// The Updates tab: chapters that appeared after the app already knew a series.
class UpdatesController extends GetxController {
  UpdatesController({
    required LibraryRepository library,
    required SourceRepository sources,
  }) : _library = library,
       _sources = sources;

  final LibraryRepository _library;
  final SourceRepository _sources;

  /// How many series are refreshed at once. Same reasoning as global search:
  /// one request per library entry would be hundreds of connections at once,
  /// and rate-limiting is how a site answers that.
  static const _concurrency = 3;

  final updates = <ChapterUpdate>[].obs;
  final errors = <UpdateError>[].obs;
  final isLoading = false.obs;
  final isRefreshing = false.obs;

  /// How far through a refresh we are, for the progress line.
  final done = 0.obs;
  final total = 0.obs;

  final lastChecked = Rxn<DateTime>();

  /// Source base URLs, for the cover requests' Referer and Origin. Cached per
  /// load rather than resolved per tile, because every tile rebuilds on scroll
  /// and the lookup hits the database.
  final _baseUrls = <int, String>{};

  String baseUrlFor(MangaEntry entry) {
    final id = LibraryRepository.sourceIdOf(entry);
    return id == null ? '' : _baseUrls[id] ?? '';
  }

  @override
  void onInit() {
    super.onInit();
    final stored = UpdateKeys.lastUpdateCheck.get<int?>(null);
    if (stored != null) {
      lastChecked.value = DateTime.fromMillisecondsSinceEpoch(stored);
    }
    load();
  }

  /// How many listed updates are still unread — the bottom bar's badge.
  ///
  /// Derived rather than stored, so marking one read from any screen moves the
  /// badge without a second source of truth to keep in step.
  int get unreadCount => updates.where((u) => !u.chapter.read).length;

  /// Reads what is already stored. No network.
  Future<void> load() async {
    isLoading.value = true;
    try {
      final favourites = await _library.favorites();
      final rows = <ChapterUpdate>[];
      for (final entry in favourites) {
        for (final chapter in entry.chapters) {
          final at = chapter.dateFetch;
          if (at == null) continue;
          rows.add(
            ChapterUpdate(
              entry: entry,
              chapter: chapter,
              fetchedAt: DateTime.fromMillisecondsSinceEpoch(at),
            ),
          );
        }
      }
      rows.sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
      updates.value = rows;

      for (final entry in favourites) {
        final id = LibraryRepository.sourceIdOf(entry);
        if (id == null || _baseUrls.containsKey(id)) continue;
        _baseUrls[id] = (await _sources.sourceById(id))?.baseUrl ?? '';
      }
    } finally {
      isLoading.value = false;
    }
  }

  /// Refreshes every favourite against its source, then reloads the list.
  ///
  /// Not named `refresh`: `GetxController` already has one, from the notifier
  /// mixin, and GetX calls it internally to rebuild listeners. Shadowing it
  /// with a library-wide network fetch would fire a full refresh every time
  /// the framework wanted a repaint.
  Future<void> refreshLibrary() async {
    if (isRefreshing.value) return;
    isRefreshing.value = true;
    errors.clear();
    done.value = 0;
    try {
      final favourites = await _library.favorites();
      total.value = favourites.length;

      var next = 0;
      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= favourites.length) return;
          await _refreshOne(favourites[i]);
          done.value++;
        }
      }

      await Future.wait([
        for (var i = 0; i < _concurrency && i < favourites.length; i++)
          worker(),
      ]);

      final now = DateTime.now();
      UpdateKeys.lastUpdateCheck.set<int>(now.millisecondsSinceEpoch);
      lastChecked.value = now;
      await load();
    } finally {
      isRefreshing.value = false;
      total.value = 0;
      done.value = 0;
    }
  }

  Future<void> _refreshOne(MangaEntry entry) async {
    final sourceId = LibraryRepository.sourceIdOf(entry);
    if (sourceId == null) {
      errors.add(
        UpdateError(entry: entry, message: 'This entry has no usable source'),
      );
      return;
    }
    try {
      final methods = await _sources.methodsFor(sourceId);
      final manga = await methods.getDetail(entry.url);
      await _library.upsertFromSource(
        sourceId: sourceId,
        url: entry.url,
        manga: manga,
      );
    } catch (e) {
      // One failing series must not stop the rest of the library from
      // refreshing, which is why this catches per entry rather than per run.
      errors.add(UpdateError(entry: entry, message: _describe(e)));
    }
  }

  Future<void> markRead(ChapterUpdate update, bool read) async {
    final sourceId = LibraryRepository.sourceIdOf(update.entry);
    final chapterUrl = update.chapter.url;
    if (sourceId == null || chapterUrl == null) return;
    await _library.setChapterRead(sourceId, update.entry.url, chapterUrl, read);
    update.chapter.read = read;
    updates.refresh();
  }

  Future<void> markAllRead() async {
    for (final update in [...updates]) {
      if (!update.chapter.read) await markRead(update, true);
    }
  }

  static String _describe(Object error) {
    final text = '$error';
    // Every hard failure in this project's own live sweep was external -- a
    // dead domain, a 301, a TLS refusal. A message implying the app is broken
    // sends the user to the wrong place.
    if (text.contains('SocketException') ||
        text.contains('HandshakeException') ||
        text.contains('TimeoutException')) {
      return 'Could not reach the site';
    }
    return text;
  }
}
