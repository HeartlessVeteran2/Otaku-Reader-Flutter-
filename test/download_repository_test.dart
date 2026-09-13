import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
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

  setUp(() {
    env!.clear();
    root = Directory.systemTemp.createTempSync('otaku-downloads');
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
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
        fetch: fetch ?? (url, headers) async => [1, 2, 3],
      );

  Future<Chapter> chapterOf(String url) async {
    final entry = await library.find(_sourceId, _url);
    return entry!.chapters.firstWhere((c) => c.url == url);
  }

  /// Waits for the queue to go quiet.
  Future<void> settle(DownloadRepository downloads) async {
    for (var i = 0; i < 200; i++) {
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
}
