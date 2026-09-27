import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/data/repository/download_repository_impl.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/isar_test_env.dart';
import 'helpers/network_status_fake.dart';

const _sourceId = 7;
const _url = '/manga/example';

class _Methods implements SourceMethods {
  _Methods(this.source);

  @override
  final Source source;

  /// Page urls to hand back, per chapter url.
  final Map<String, List<String>> pages = {};
  Object? failWith;

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    if (failWith != null) throw failWith!;
    return [for (final u in pages[url] ?? const <String>[]) PageUrl(u)];
  }

  @override
  bool get supportsLatest => true;
  @override
  String get sourceBaseUrl => 'https://example.test';
  @override
  Map<String, String> getHeaders() => const {};
  @override
  Future<MManga> getDetail(String url) async => MManga();
  @override
  Future<MPages> getPopular(int p) async => MPages(list: []);
  @override
  Future<MPages> getLatestUpdates(int p) async => MPages(list: []);
  @override
  Future<MPages> search(String q, int p, FilterList f) async =>
      MPages(list: []);
  @override
  FilterList getFilterList() => FilterList([]);
  @override
  List<SourcePreference> getSourcePreferences() => const [];
  @override
  void dispose() {}
}

class _Sources implements SourceRepository {
  _Sources(this.methods);
  final _Methods methods;

  @override
  Future<SourceMethods> methodsFor(int id) async => methods;
  @override
  Future<Source?> sourceById(int id) async => methods.source;
  @override
  Future<void> markUsed(int id) async {}
  @override
  void evict(int id) {}
  @override
  void evictAll() {}
  @override
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  }) async => const [];
}

Source _row() => Source()
  ..sourceId = _sourceId
  ..name = 'Example Source'
  ..lang = 'en'
  ..baseUrl = 'https://example.test'
  ..sourceCode = 'X';

/// Delegates everything, but refuses to store a chapter's local path.
///
/// Stands in for the one failure the staging design cannot cover by itself:
/// the move has already happened when this throws.
class _FailingWrite implements LibraryRepository {
  _FailingWrite(this._inner);
  final LibraryRepository _inner;

  @override
  Future<void> setChapterLocalPath({
    required int sourceId,
    required String url,
    required String chapterUrl,
    required String? localPath,
  }) async => throw const FileSystemException('database is locked');

  @override
  Stream<void> get changes => _inner.changes;
  @override
  Future<MangaEntry?> find(int sourceId, String url) =>
      _inner.find(sourceId, url);
  @override
  Future<MangaEntry> upsertFromSource({
    required int sourceId,
    required String url,
    required MManga manga,
  }) => _inner.upsertFromSource(sourceId: sourceId, url: url, manga: manga);
  @override
  Future<bool> toggleFavorite(int sourceId, String url) =>
      _inner.toggleFavorite(sourceId, url);
  @override
  Future<List<MangaEntry>> favorites() => _inner.favorites();
  @override
  Future<List<MangaEntry>> allEntries() => _inner.allEntries();
  @override
  Future<void> clearChapterHistory(
    int sourceId,
    String url,
    String chapterUrl,
  ) => _inner.clearChapterHistory(sourceId, url, chapterUrl);
  @override
  Future<void> clearHistory() => _inner.clearHistory();
  @override
  Future<void> setChapterRead(
    int sourceId,
    String url,
    String chapterUrl,
    bool read,
  ) => _inner.setChapterRead(sourceId, url, chapterUrl, read);
  @override
  Future<void> updateChapterProgress({
    required int sourceId,
    required String url,
    required String chapterUrl,
    required int lastPageRead,
    required int totalPages,
    double? currentOffset,
    double? maxOffset,
    bool markRead = false,
  }) => _inner.updateChapterProgress(
    sourceId: sourceId,
    url: url,
    chapterUrl: chapterUrl,
    lastPageRead: lastPageRead,
    totalPages: totalPages,
    currentOffset: currentOffset,
    maxOffset: maxOffset,
    markRead: markRead,
  );
}

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;
  late Directory root;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('downloads', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());

  /// Fresh per test, because the Wi-Fi cases script it — and a shared one
  /// would let a test that dropped the connection decide what the next test's
  /// queue does.
  late FakeNetworkStatus network;

  setUp(() {
    env!.clear();
    root = Directory.systemTemp.createTempSync('otaku-downloads');
    network = FakeNetworkStatus();
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    network.close();
  });

  final library = LibraryRepositoryImpl();

  /// Stores a manga with [chapters] and returns the source methods stub.
  ///
  /// [name] builds each chapter's title from its url. The default gives every
  /// chapter a distinct, numbered name; a test that needs two chapters to
  /// *collide* passes one that ignores the url.
  Future<_Methods> seed(
    List<String> chapters, {
    String Function(String url)? name,
  }) async {
    await library.upsertFromSource(
      sourceId: _sourceId,
      url: _url,
      manga: MManga(
        name: 'Example',
        chapters: [
          for (final c in chapters)
            MChapter(url: c, name: name?.call(c) ?? 'Chapter $c'),
        ],
      ),
    );
    return _Methods(_row());
  }

  DownloadRepositoryImpl build(_Methods methods, {PageFetcher? fetch}) =>
      DownloadRepositoryImpl(
        sources: _Sources(methods),
        library: library,
        root: root,
        network: network,
        fetch: fetch ?? (url, headers) async => [1, 2, 3],
      );

  Future<Chapter> chapterOf(String url) async {
    final entry = await library.find(_sourceId, _url);
    return entry!.chapters.firstWhere((c) => c.url == url);
  }

  /// Waits for the queue to go quiet.
  Future<void> settle(DownloadRepository downloads) async {
    // 400, not 200: a page fetch here touches the filesystem, and the full
    // suite runs several files at once, so the original bound was tight enough
    // that a busy machine could trip it. It still fails loudly rather than
    // returning early, which is the property that matters.
    for (var i = 0; i < 400; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final busy = downloads.tasks.any(
        (t) =>
            t.state == DownloadState.queued || t.state == DownloadState.running,
      );
      if (!busy) return;
    }
    fail('the download queue never settled');
  }

  test(
    'a finished download writes every page and points the row at it',
    () async {
      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = [
        'https://cdn.test/a.jpg',
        'https://cdn.test/b.png',
        'https://cdn.test/c.jpg',
      ];
      final downloads = build(methods);

      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      await settle(downloads);

      final path = (await chapterOf('/c-1')).localPath;
      expect(path, isNotNull, reason: 'the row points at the pages');
      final files = Directory(path!).listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, hasLength(3));
      // Zero-padded, so a plain sort is reading order. "10" before "2" would
      // shuffle any chapter past nine pages.
      expect(files.map((f) => f.uri.pathSegments.last), [
        '0001.jpg',
        '0002.png',
        '0003.jpg',
      ]);
      expect(downloads.tasks.single.state, DownloadState.done);
    },
  );

  test('a download that fails part-way leaves nothing readable', () async {
    // The whole contract: a chapter is downloaded or it is not. A directory of
    // three pages out of ten, with a row pointing at it, is a chapter that
    // opens and then stops.
    final methods = await seed(['/c-1']);
    methods.pages['/c-1'] = [
      for (var i = 0; i < 10; i++) 'https://cdn.test/$i.jpg',
    ];
    var served = 0;
    final downloads = build(
      methods,
      fetch: (url, headers) async {
        if (served++ >= 3) throw const SocketException('connection reset');
        return [1, 2, 3];
      },
    );

    await downloads.enqueue(
      sourceId: _sourceId,
      mangaUrl: _url,
      chapter: await chapterOf('/c-1'),
      mangaTitle: 'Example',
    );
    await settle(downloads);

    expect((await chapterOf('/c-1')).localPath, isNull);
    // Not a single page file survives. Empty parent directories do — they are
    // scaffolding `create(recursive: true)` made and nothing points at them —
    // but three of ten pages sitting on disk under a row that claimed to be
    // downloaded is the exact state this design exists to make impossible.
    expect(
      root.listSync(recursive: true).whereType<File>(),
      isEmpty,
      reason: 'a partial chapter was not left behind',
    );
    final task = downloads.tasks.single;
    expect(task.state, DownloadState.failed);
    expect(
      task.error,
      'Could not reach the site',
      reason: 'every hard failure in the live sweep was external',
    );
  });

  test(
    'a source that returns no pages is a failure, not an empty chapter',
    () async {
      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = const [];
      final downloads = build(methods);

      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      await settle(downloads);

      expect(downloads.tasks.single.state, DownloadState.failed);
      expect((await chapterOf('/c-1')).localPath, isNull);
    },
  );

  test('queueing a chapter twice does not download it twice', () async {
    final methods = await seed(['/c-1']);
    methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
    var fetches = 0;
    final downloads = build(
      methods,
      fetch: (url, headers) async {
        fetches++;
        return [1];
      },
    );
    final chapter = await chapterOf('/c-1');

    await downloads.enqueue(
      sourceId: _sourceId,
      mangaUrl: _url,
      chapter: chapter,
      mangaTitle: 'Example',
    );
    await downloads.enqueue(
      sourceId: _sourceId,
      mangaUrl: _url,
      chapter: chapter,
      mangaTitle: 'Example',
    );
    await settle(downloads);

    expect(fetches, 1);
    expect(downloads.tasks, hasLength(1));
  });

  test('deleting a download frees the files and keeps read state', () async {
    final methods = await seed(['/c-1']);
    methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
    final downloads = build(methods);
    await downloads.enqueue(
      sourceId: _sourceId,
      mangaUrl: _url,
      chapter: await chapterOf('/c-1'),
      mangaTitle: 'Example',
    );
    await settle(downloads);
    await library.setChapterRead(_sourceId, _url, '/c-1', true);
    final path = (await chapterOf('/c-1')).localPath!;
    expect(Directory(path).existsSync(), isTrue);

    await downloads.deleteChapter(
      sourceId: _sourceId,
      mangaUrl: _url,
      chapterUrl: '/c-1',
    );

    expect(Directory(path).existsSync(), isFalse);
    final chapter = await chapterOf('/c-1');
    expect(chapter.localPath, isNull);
    expect(
      chapter.read,
      isTrue,
      reason: 'freeing space is not the same as un-reading a chapter',
    );
  });

  test(
    'deleting clears the row even when the files are already gone',
    () async {
      // The state that matters: a row pointing at a directory the user deleted
      // from a file manager makes the reader render an empty chapter instead of
      // fetching it.
      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
      final downloads = build(methods);
      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      await settle(downloads);
      Directory((await chapterOf('/c-1')).localPath!)
          .deleteSync(recursive: true);

      await downloads.deleteChapter(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapterUrl: '/c-1',
      );

      expect((await chapterOf('/c-1')).localPath, isNull);
    },
  );

  test('an unfamiliar page extension lands as .jpg, not as itself', () async {
    // The extension comes from a third-party url and becomes a filename.
    final methods = await seed(['/c-1']);
    methods.pages['/c-1'] = ['https://cdn.test/page.php?id=1'];
    final downloads = build(methods);

    await downloads.enqueue(
      sourceId: _sourceId,
      mangaUrl: _url,
      chapter: await chapterOf('/c-1'),
      mangaTitle: 'Example',
    );
    await settle(downloads);

    final path = (await chapterOf('/c-1')).localPath!;
    expect(Directory(path).listSync().single.uri.pathSegments.last, '0001.jpg');
  });

  test('usedBytes counts what is actually on disk', () async {
    final methods = await seed(['/c-1']);
    methods.pages['/c-1'] = [
      'https://cdn.test/a.jpg',
      'https://cdn.test/b.jpg',
    ];
    final downloads = build(
      methods,
      fetch: (url, headers) async => List.filled(500, 7),
    );
    expect(await downloads.usedBytes(), 0);

    await downloads.enqueue(
      sourceId: _sourceId,
      mangaUrl: _url,
      chapter: await chapterOf('/c-1'),
      mangaTitle: 'Example',
    );
    await settle(downloads);

    expect(await downloads.usedBytes(), 1000);
  });

  test('clearFinished drops the rows and keeps the files', () async {
    final methods = await seed(['/c-1']);
    methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
    final downloads = build(methods);
    await downloads.enqueue(
      sourceId: _sourceId,
      mangaUrl: _url,
      chapter: await chapterOf('/c-1'),
      mangaTitle: 'Example',
    );
    await settle(downloads);
    final path = (await chapterOf('/c-1')).localPath!;

    downloads.clearFinished();

    expect(downloads.tasks, isEmpty);
    expect(
      Directory(path).existsSync(),
      isTrue,
      reason: 'clearing the list is not deleting the downloads',
    );
    expect((await chapterOf('/c-1')).localPath, isNotNull);
  });

  // Run twice, because the delete has two windows to land in and a different
  // check guards each. Holding an early page puts it in front of the loop's
  // per-page check; holding the *last* page puts it past that check entirely,
  // between the final write and the move — which only the check after the
  // loop can see. A single case passes with the other guard deleted.
  for (final hold in const [
    (page: 1, when: 'mid-download'),
    (page: 5, when: 'after the last page'),
  ]) {
    test(
      'deleting ${hold.when} does not let the download finish behind you',
      () async {
        // Without this, the run completes after the delete, writes the path
        // back and republishes itself as downloaded — so the user is left with
        // the files they just removed and a row that disagrees with the button
        // they pressed.
        final methods = await seed(['/c-1']);
        methods.pages['/c-1'] = [
          for (var i = 0; i < 6; i++) 'https://cdn.test/$i.jpg',
        ];
        final held = Completer<void>();
        var served = 0;
        final downloads = build(
          methods,
          fetch: (url, headers) async {
            if (served++ == hold.page) await held.future;
            return [1, 2, 3];
          },
        );

        await downloads.enqueue(
          sourceId: _sourceId,
          mangaUrl: _url,
          chapter: await chapterOf('/c-1'),
          mangaTitle: 'Example',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(downloads.tasks.single.state, DownloadState.running);

        final deleting = downloads.deleteChapter(
          sourceId: _sourceId,
          mangaUrl: _url,
          chapterUrl: '/c-1',
        );
        held.complete();
        await deleting;
        // Well past any remaining page fetch.
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect((await chapterOf('/c-1')).localPath, isNull);
        expect(downloads.tasks, isEmpty);
        expect(
          root.listSync(recursive: true).whereType<File>(),
          isEmpty,
          reason: 'the half-download went with it',
        );
      },
    );
  }

  // `cancel` returns without waiting for the run — unlike `deleteChapter`,
  // which awaits it and then cleans up whatever it left. So cancel is the
  // operation that depends on the run stopping *itself*, and the same two
  // windows apply: an early page is caught by the loop's per-page check, the
  // last page only by the check after the loop.
  for (final hold in const [
    (page: 1, when: 'mid-download'),
    (page: 5, when: 'on the last page'),
  ]) {
    test('cancelling ${hold.when} leaves no download behind', () async {
      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = [
        for (var i = 0; i < 6; i++) 'https://cdn.test/$i.jpg',
      ];
      final held = Completer<void>();
      var served = 0;
      final downloads = build(
        methods,
        fetch: (url, headers) async {
          if (served++ == hold.page) await held.future;
          return [1, 2, 3];
        },
      );

      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(downloads.tasks.single.state, DownloadState.running);

      await downloads.cancel(downloads.tasks.single.key);
      held.complete();
      // Well past every remaining page fetch.
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        downloads.tasks,
        isEmpty,
        reason: 'a cancelled download does not report itself as done',
      );
      expect((await chapterOf('/c-1')).localPath, isNull);
      expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
      // Cancel has to stop the *fetching*, not just discard the result. The
      // check after the loop would leave this end state either way, so
      // without the per-page check a cancelled download quietly pulls every
      // remaining page from the site before throwing them all away.
      expect(
        served,
        hold.page + 1,
        reason: 'nothing is fetched after the page that was in flight',
      );
    });
  }

  test('a row write that fails after the move leaves no orphan', () async {
    // The move landed and the row write did not, so nothing points at the
    // directory and nothing ever will — but `usedBytes` keeps counting it and
    // every retry adds another copy.
    final methods = await seed(['/c-1']);
    methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
    final downloads = DownloadRepositoryImpl(
      sources: _Sources(methods),
      library: _FailingWrite(library),
      root: root,
      network: network,
      fetch: (url, headers) async => [1, 2, 3],
    );

    await downloads.enqueue(
      sourceId: _sourceId,
      mangaUrl: _url,
      chapter: await chapterOf('/c-1'),
      mangaTitle: 'Example',
    );
    await settle(downloads);

    expect(downloads.tasks.single.state, DownloadState.failed);
    expect(await downloads.usedBytes(), 0);
    expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('two chapters of the same manga do not share a directory', () async {
    // Sources title chapters identically all the time ("Oneshot", ""), and one
    // overwriting the other would silently replace a downloaded chapter.
    // Both named "Oneshot", and digit-free so the chapter-number parser finds
    // nothing to tell them apart either. That is the whole point: with a
    // label-only directory name these two land in the same place and the
    // second silently replaces the first.
    final methods = await seed(['/c-1', '/c-2'], name: (_) => 'Oneshot');
    methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
    methods.pages['/c-2'] = ['https://cdn.test/b.jpg'];
    final downloads = build(methods);

    for (final url in ['/c-1', '/c-2']) {
      final chapter = await chapterOf(url);
      expect(chapter.number, isNull, reason: 'nothing numeric separates them');
      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: chapter,
        mangaTitle: 'Example',
      );
    }
    await settle(downloads);

    final first = (await chapterOf('/c-1')).localPath;
    final second = (await chapterOf('/c-2')).localPath;
    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first, isNot(second));
  });

  group('resolveRoot', () {
    test('a configured path that cannot be created falls back', () async {
      // This runs before `runApp`, and the path is a *stored preference* — an
      // SD card that was removed, a permission revoked. Throwing means a blank
      // screen with no route to the setting that caused it, and clearing app
      // data as the only way out, which takes the library with it.
      final blocker = File(p.join(root.path, 'not-a-directory'))
        ..writeAsBytesSync([0]);
      DownloadKeys.downloadPath.set<String>(p.join(blocker.path, 'downloads'));
      addTearDown(DownloadKeys.downloadPath.delete);

      final resolved = await DownloadRepositoryImpl.resolveRoot(root);

      expect(resolved.existsSync(), isTrue);
      expect(resolved.path, p.join(root.path, 'downloads'));
      expect(
        DownloadKeys.downloadPath.get<String?>(null),
        isNotNull,
        reason: 'the setting still records what the user chose',
      );
    });

    test('a usable configured path is honoured', () async {
      final chosen = p.join(root.path, 'sd-card', 'scans');
      DownloadKeys.downloadPath.set<String>(chosen);
      addTearDown(DownloadKeys.downloadPath.delete);

      final resolved = await DownloadRepositoryImpl.resolveRoot(root);

      expect(resolved.path, chosen);
      expect(resolved.existsSync(), isTrue);
    });
  });
  group('how many at once', () {
    /// A fetcher that blocks until released, recording the highest number of
    /// pages in flight at the same moment.
    ///
    /// The **peak** is the measurement, not the total: a limit of one and a
    /// limit of four fetch exactly the same pages in the end, so anything that
    /// counts calls passes with the limit ignored. Pages within a chapter are
    /// fetched one at a time, so concurrent pages means concurrent *chapters*.
    ({PageFetcher fetch, int Function() peak, void Function() release})
    gatedFetcher() {
      // **Re-armed on every release, not a one-shot.** A single `Completer`
      // lets everything through for the rest of the test, so nothing after the
      // first release ever overlaps and the peak can only ever be whatever the
      // first batch reached -- which made the "read per slot" case below
      // unable to observe the very raise it is named for.
      var gate = Completer<void>();
      var inFlight = 0;
      var peak = 0;
      Future<List<int>> fetch(Uri url, Map<String, String> headers) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await gate.future;
        inFlight--;
        return [1, 2, 3];
      }

      return (
        fetch: fetch,
        peak: () => peak,
        release: () {
          final open = gate;
          gate = Completer<void>();
          if (!open.isCompleted) open.complete();
        },
      );
    }

    Future<void> enqueueAll(
      DownloadRepositoryImpl downloads,
      List<String> chapters,
    ) async {
      for (final c in chapters) {
        await downloads.enqueue(
          sourceId: _sourceId,
          mangaUrl: _url,
          chapter: await chapterOf(c),
          mangaTitle: 'Example',
        );
      }
    }

    /// Waits until [want] page fetches are in flight at once.
    ///
    /// **Not a fixed number of turns.** The first version spun 20 microtasks
    /// and passed on this machine every time it was run alone, then failed in
    /// the full parallel suite: starting a task does real file I/O, so how many
    /// turns it takes depends on how busy the machine is. That is this
    /// project's own "wait on the condition, never on a turn count" rule, and
    /// a flake that only appears under load is worse than one that always
    /// fails.
    Future<void> waitForPeak(int Function() peak, int want) async {
      for (var i = 0; i < 600 && peak() < want; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(peak(), greaterThanOrEqualTo(want), reason: 'reached $want slots');
    }

    /// Waits past [want] to catch the queue running *more* than it should.
    ///
    /// Reaching a limit only proves it is not too low. The two halves are
    /// separate because they fail for opposite reasons and a single assertion
    /// cannot say which happened.
    Future<void> expectPeakStaysAt(int Function() peak, int want) async {
      await waitForPeak(peak, want);
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(peak(), want, reason: 'and never went past $want');
    }

    /// Opens the gate repeatedly until the queue is empty.
    ///
    /// One release only frees the batch currently blocked, because the gate
    /// re-arms; a queue deeper than one batch needs as many as it has batches.
    Future<void> releaseAll(
      void Function() release,
      DownloadRepository downloads,
    ) async {
      for (var i = 0; i < 60; i++) {
        release();
        // A real millisecond rather than a microtask drain: a released batch
        // has to get through its file writes before the next one can start,
        // and that is wall-clock work.
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final busy = downloads.tasks.any(
          (t) =>
              t.state == DownloadState.queued ||
              t.state == DownloadState.running,
        );
        if (!busy) return;
      }
      fail('the gated queue never drained');
    }

    test('the stored limit is what runs, not the old constant', () async {
      DownloadKeys.concurrentDownloads.set<int>(4);
      addTearDown(DownloadKeys.concurrentDownloads.delete);

      final methods = await seed(['/c-1', '/c-2', '/c-3', '/c-4', '/c-5']);
      for (final c in ['/c-1', '/c-2', '/c-3', '/c-4', '/c-5']) {
        methods.pages[c] = ['https://cdn.test/$c.jpg'];
      }
      final g = gatedFetcher();
      final downloads = build(methods, fetch: g.fetch);
      addTearDown(downloads.dispose);

      await enqueueAll(downloads, ['/c-1', '/c-2', '/c-3', '/c-4', '/c-5']);

      // Four in flight, the fifth waiting for a slot.
      await expectPeakStaysAt(g.peak, 4);
      await releaseAll(g.release, downloads);
    });

    test('the limit is read per slot, not once at construction', () async {
      // The guard that separates a live setting from a dead one. Caching the
      // value in the constructor passes every test above: the queue still
      // honours whatever was stored when the app started, and the slider only
      // appears to do nothing until the next launch -- which is the shape of
      // the two dead switches in this project's history.
      DownloadKeys.concurrentDownloads.set<int>(1);
      addTearDown(DownloadKeys.concurrentDownloads.delete);

      final methods = await seed(['/c-1', '/c-2', '/c-3']);
      for (final c in ['/c-1', '/c-2', '/c-3']) {
        methods.pages[c] = ['https://cdn.test/$c.jpg'];
      }
      final g = gatedFetcher();
      final downloads = build(methods, fetch: g.fetch);
      addTearDown(downloads.dispose);

      await enqueueAll(downloads, ['/c-1', '/c-2', '/c-3']);
      await expectPeakStaysAt(g.peak, 1);

      // Raised while a download is in flight. The next free slot is where it
      // takes effect, so releasing the first is what proves it.
      DownloadKeys.concurrentDownloads.set<int>(3);
      await releaseAll(g.release, downloads);

      expect(
        g.peak(),
        greaterThan(1),
        reason: 'the raise reached the queue without a restart',
      );
      // Not asserted as an exact number: with three pending and a limit of
      // three, how many share a slot depends on when each finishes, and the
      // claim under test is only that the new limit was consulted at all.
    });

    test('a stored zero does not stop the queue for ever', () async {
      // Nothing in the app writes this; a restore or a hand-edited row can.
      // Unclamped it is a queue that accepts work and never runs any of it,
      // with no failure and nothing on screen to say why.
      DownloadKeys.concurrentDownloads.set<int>(0);
      addTearDown(DownloadKeys.concurrentDownloads.delete);

      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
      final downloads = build(methods);
      addTearDown(downloads.dispose);

      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      await settle(downloads);

      expect(downloads.tasks.single.state, DownloadState.done);
    });

    test('a stored number above the ceiling is capped', () async {
      DownloadKeys.concurrentDownloads.set<int>(99);
      addTearDown(DownloadKeys.concurrentDownloads.delete);

      final chapters = ['/c-1', '/c-2', '/c-3', '/c-4', '/c-5', '/c-6', '/c-7'];
      final methods = await seed(chapters);
      for (final c in chapters) {
        methods.pages[c] = ['https://cdn.test/$c.jpg'];
      }
      final g = gatedFetcher();
      final downloads = build(methods, fetch: g.fetch);
      addTearDown(downloads.dispose);

      await enqueueAll(downloads, chapters);

      await expectPeakStaysAt(g.peak, DownloadDefaults.maxConcurrentDownloads);
      await releaseAll(g.release, downloads);
    });
  });

  group('only on Wi-Fi', () {
    /// Real wall-clock time, not a microtask drain.
    ///
    /// These cases mostly assert that something did **not** happen, which is
    /// the direction where waiting too little passes for free — a broken gate
    /// and a queue that simply had not got going yet look identical. A real
    /// delay makes the opportunity genuinely pass. (The mutation that removes
    /// the gate does fail these, so they are not vacuous today; this is what
    /// keeps that true on a slower machine.)
    Future<void> spin() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }

    test(
      'a metered connection holds the queue instead of failing it',
      () async {
        DownloadKeys.downloadOnWifiOnly.set<bool>(true);
        addTearDown(DownloadKeys.downloadOnWifiOnly.delete);
        network.unmetered = false;

        final methods = await seed(['/c-1']);
        methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
        var fetched = 0;
        final downloads = build(
          methods,
          fetch: (url, headers) async {
            fetched++;
            return [1, 2, 3];
          },
        );
        addTearDown(downloads.dispose);

        await downloads.enqueue(
          sourceId: _sourceId,
          mangaUrl: _url,
          chapter: await chapterOf('/c-1'),
          mangaTitle: 'Example',
        );
        await spin();

        expect(fetched, 0, reason: 'nothing left the device');
        expect(
          downloads.tasks.single.state,
          DownloadState.queued,
          reason: 'held, not failed -- a failure would need re-queuing by hand',
        );
        expect(downloads.heldForWifi, isTrue);
      },
    );

    test(
      'Wi-Fi coming back starts the queue with no other prompting',
      () async {
        // The guard for the whole reason `NetworkStatus.onChanged` exists. The
        // queue re-pumps when a task finishes, and when everything is held
        // nothing finishes -- so without the event this queue waits for ever,
        // and every test above still passes.
        DownloadKeys.downloadOnWifiOnly.set<bool>(true);
        addTearDown(DownloadKeys.downloadOnWifiOnly.delete);
        network.unmetered = false;

        final methods = await seed(['/c-1']);
        methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
        final downloads = build(methods);
        addTearDown(downloads.dispose);

        await downloads.enqueue(
          sourceId: _sourceId,
          mangaUrl: _url,
          chapter: await chapterOf('/c-1'),
          mangaTitle: 'Example',
        );
        await spin();
        expect(downloads.tasks.single.state, DownloadState.queued);

        network.change(unmetered: true);
        await settle(downloads);

        expect(downloads.tasks.single.state, DownloadState.done);
        expect(downloads.heldForWifi, isFalse);
      },
    );

    test('losing Wi-Fi mid-chapter does not discard the pages already got', () async {
      // A download here is all-or-nothing, so stopping one part-way throws
      // away every page fetched and leaves nothing readable. Honouring a
      // switch flipped afterwards by destroying the reader's work is the worse
      // answer, and `cancel` is there for when they mean it.
      DownloadKeys.downloadOnWifiOnly.set<bool>(true);
      addTearDown(DownloadKeys.downloadOnWifiOnly.delete);

      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = [
        'https://cdn.test/a.jpg',
        'https://cdn.test/b.jpg',
      ];
      var fetched = 0;
      final downloads = build(
        methods,
        fetch: (url, headers) async {
          fetched++;
          // The connection drops between the first page and the second.
          if (fetched == 1) network.change(unmetered: false);
          return [1, 2, 3];
        },
      );
      addTearDown(downloads.dispose);

      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      await settle(downloads);

      expect(fetched, 2, reason: 'the chapter in flight finished');
      expect(downloads.tasks.single.state, DownloadState.done);
    });

    test(
      'the switch off means a metered connection downloads anyway',
      () async {
        network.unmetered = false;

        final methods = await seed(['/c-1']);
        methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
        final downloads = build(methods);
        addTearDown(downloads.dispose);

        await downloads.enqueue(
          sourceId: _sourceId,
          mangaUrl: _url,
          chapter: await chapterOf('/c-1'),
          mangaTitle: 'Example',
        );
        await settle(downloads);

        expect(downloads.tasks.single.state, DownloadState.done);
        expect(downloads.heldForWifi, isFalse);
      },
    );

    test('turning the gate off releases a queue already held', () async {
      // `codeant-ai`, Major: writing the key alone changes `heldForWifi`'s
      // answer immediately but pumps nothing, so chapters already held sit
      // there until the next connectivity event or the next enqueue — which
      // reads exactly like the switch not working. The fix is that Settings
      // goes through `setWifiOnly`, so this asserts the *release*, not the
      // stored value.
      DownloadKeys.downloadOnWifiOnly.set<bool>(true);
      addTearDown(DownloadKeys.downloadOnWifiOnly.delete);
      network.unmetered = false;

      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
      final downloads = build(methods);
      addTearDown(downloads.dispose);

      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      await spin();
      expect(downloads.tasks.single.state, DownloadState.queued);

      // Still on mobile data. Only the setting changed.
      await downloads.setWifiOnly(false);
      await settle(downloads);

      expect(downloads.tasks.single.state, DownloadState.done);
      expect(downloads.heldForWifi, isFalse);
    });

    test(
      'turning the gate off publishes, so a mounted screen re-reads',
      () async {
        // The other half of the same gap, and the half a state assertion cannot
        // see: the Downloads controller mirrors `heldForWifi` on the `changes`
        // stream, so a value that changes without publishing leaves the banner
        // rendering the old answer.
        DownloadKeys.downloadOnWifiOnly.set<bool>(true);
        addTearDown(DownloadKeys.downloadOnWifiOnly.delete);
        network.unmetered = false;

        final methods = await seed(['/c-1']);
        final downloads = build(methods);
        addTearDown(downloads.dispose);

        var published = 0;
        final sub = downloads.changes.listen((_) => published++);
        addTearDown(sub.cancel);

        // Settled and the count taken **after**, because the constructor's own
        // network read publishes too. Counting from zero passed with the
        // publish in `setWifiOnly` deleted -- the right answer for the wrong
        // reason, and the second time in this slice that an assertion made
        // before an asynchronous constructor read had landed measured nothing.
        await spin();
        final before = published;

        await downloads.setWifiOnly(true);
        await spin();

        expect(
          published,
          greaterThan(before),
          reason: 'the setting change itself published',
        );
      },
    );

    test('an older connectivity answer cannot overwrite a newer one', () async {
      // Two events in quick succession start two `isUnmetered()` calls and
      // nothing orders their completions, so the older can land second and
      // hold a queue that should run. Found by `codeant-ai`. The fake answers
      // from a mutable field, so scripting the *second* event first and then
      // letting both resolve is what puts them out of order.
      DownloadKeys.downloadOnWifiOnly.set<bool>(true);
      addTearDown(DownloadKeys.downloadOnWifiOnly.delete);
      network.unmetered = false;

      final methods = await seed(['/c-1', '/c-2']);
      methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
      methods.pages['/c-2'] = ['https://cdn.test/b.jpg'];
      final downloads = build(methods);
      addTearDown(downloads.dispose);

      // Off, then straight back on — and the first read is made *slower* than
      // the second, so the stale `false` lands last. That inversion is the
      // whole state under test; without it the reads finish in the order they
      // started and the guard cannot be falsified.
      network.answerDelays.addAll([6, 0]);
      network.change(unmetered: false);
      // Pumped **between** the two events, and that is load-bearing. A
      // broadcast stream delivers in a microtask, so firing both back to back
      // sets the fake's field twice before either listener runs — and then both
      // reads capture the same value and there is no stale answer to guard
      // against. Measured: the guard was unfalsifiable until this line.
      await Future<void>.delayed(Duration.zero);
      network.change(unmetered: true);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Asserted on the **next** enqueue, deliberately. Anything queued before
      // the events runs the moment the newer `true` lands, and the stale answer
      // arrives too late to stop it — so a chapter enqueued earlier reaches
      // `done` whether or not the guard exists. What the stale value actually
      // costs is every decision *after* it: the device is on Wi-Fi and the
      // queue thinks it is not.
      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-2'),
        mangaTitle: 'Example',
      );
      await settle(downloads);

      expect(
        downloads.tasks.single.state,
        DownloadState.done,
        reason: 'the newest answer decided, not whichever landed last',
      );
      expect(downloads.heldForWifi, isFalse);
    });

    test('the gate holds until the first network answer arrives', () async {
      // `codeant-ai`, and correct. `_unmetered` started `true` while the
      // constructor's read is asynchronous, so a chapter enqueued before that
      // answer landed started on whatever connection was there -- and by this
      // queue's own deliberate design a running download is never stopped, so
      // the later answer could not undo it. Against an explicit "only on
      // Wi-Fi" promise that is the user's money, already spent.
      //
      // The tell was a comment I wrote myself: it justified the optimistic
      // default with `ConnectivityNetworkStatus`'s reasoning, which is right
      // for a library refresh -- a feature that silently never runs is worse
      // than one extra refresh -- and wrong for a gate. Holding while the
      // answer is unknown fails *visibly*, because the banner says what it is
      // waiting for and the switch is one tap away.
      DownloadKeys.downloadOnWifiOnly.set<bool>(true);
      addTearDown(DownloadKeys.downloadOnWifiOnly.delete);
      network.unmetered = false;
      // The constructor's read is made slow, which is the whole state under
      // test: on a real cold start it is a platform channel.
      network.answerDelays.add(30);

      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
      var fetched = 0;
      final downloads = build(
        methods,
        fetch: (url, headers) async {
          fetched++;
          return [1, 2, 3];
        },
      );
      addTearDown(downloads.dispose);

      // Enqueued immediately, before the answer can have landed.
      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      expect(
        fetched,
        0,
        reason: 'nothing left the device while the connection was unknown',
      );
      expect(downloads.heldForWifi, isTrue);

      // And once the answer says metered it stays held, rather than the hold
      // being an artefact of the answer not having arrived.
      await spin();
      expect(fetched, 0);
      expect(downloads.tasks.single.state, DownloadState.queued);
    });

    test('the gate lets a Wi-Fi device straight through', () async {
      // The case the other new tests do not reach, and it is what pins the
      // ordering inside `_refreshNetwork`. The first answer on an unmetered
      // device is `true`, which *equals* `_unmetered`'s starting value — so
      // recording `_networkKnown` after the unchanged-value early return would
      // leave the connection permanently unknown in the commonest case of all,
      // and this gate would hold for ever on a device that is on Wi-Fi.
      DownloadKeys.downloadOnWifiOnly.set<bool>(true);
      addTearDown(DownloadKeys.downloadOnWifiOnly.delete);

      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
      final downloads = build(methods);
      addTearDown(downloads.dispose);

      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      await settle(downloads);

      expect(downloads.tasks.single.state, DownloadState.done);
      expect(downloads.heldForWifi, isFalse);
    });

    test('with the gate off, an unknown connection holds nothing', () async {
      // The correction to the suggested remedy, and the reason it is a
      // separate test. CodeAnt proposed `!_networkReady ||` *outside* the key
      // check, which satisfies the disjunction on its own -- so every download
      // would wait for a platform round trip at startup even for a reader who
      // never turned the gate on. A finding can be right about the defect and
      // wrong about the remedy; this is what tells the two apart.
      network.unmetered = false;
      network.answerDelays.add(30);

      final methods = await seed(['/c-1']);
      methods.pages['/c-1'] = ['https://cdn.test/a.jpg'];
      final downloads = build(methods);
      addTearDown(downloads.dispose);

      await downloads.enqueue(
        sourceId: _sourceId,
        mangaUrl: _url,
        chapter: await chapterOf('/c-1'),
        mangaTitle: 'Example',
      );
      await settle(downloads);

      expect(downloads.tasks.single.state, DownloadState.done);
      expect(downloads.heldForWifi, isFalse);
    });

    test('an empty queue is never reported as held', () async {
      // Otherwise the banner outlives the thing it explains: a screen opened
      // on mobile data with nothing queued would say chapters are waiting.
      DownloadKeys.downloadOnWifiOnly.set<bool>(true);
      addTearDown(DownloadKeys.downloadOnWifiOnly.delete);
      network.unmetered = false;

      final methods = await seed(['/c-1']);
      final downloads = build(methods);
      addTearDown(downloads.dispose);

      // Spun on purpose. `_unmetered` is refreshed asynchronously from the
      // constructor, so asserting straight away passes because the answer has
      // not arrived yet rather than because the queue is empty -- which is
      // exactly what this was doing until the mutation that drops the
      // empty-queue check failed to fail.
      await spin();

      expect(downloads.heldForWifi, isFalse);
    });
  });
}
