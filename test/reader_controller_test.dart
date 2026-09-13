import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/isar_test_env.dart';

const _sourceId = 9;
const _manga = '/manga/example';

class _Methods implements SourceMethods {
  _Methods(this.source);

  @override
  final Source source;

  /// Pages per chapter url, so a test can give each chapter a different length.
  Map<String, List<PageUrl>> pagesByChapter = {};
  Object? failWith;

  /// Every chapter the source was actually asked for. A downloaded chapter
  /// must not appear here — reading from disk that still hits the site is
  /// indistinguishable from not being downloaded at all.
  final pageListCalls = <String>[];

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    pageListCalls.add(url);
    if (failWith != null) throw failWith!;
    return pagesByChapter[url] ?? const [];
  }

  @override
  bool get supportsLatest => true;
  @override
  String get sourceBaseUrl => 'https://example.test';
  @override
  Map<String, String> getHeaders() => const {};
  @override
  Future<MPages> getPopular(int p) async => MPages(list: []);
  @override
  Future<MPages> getLatestUpdates(int p) async => MPages(list: []);
  @override
  Future<MPages> search(String q, int p, FilterList f) async =>
      MPages(list: []);
  @override
  Future<MManga> getDetail(String url) async => MManga();
  @override
  FilterList getFilterList() => FilterList([]);
  @override
  List<SourcePreference> getSourcePreferences() => const [];
  @override
  void dispose() {}
}

class _Sources implements SourceRepository {
  _Sources(this.methods, this.row);
  final _Methods methods;
  final Source row;

  @override
  Future<SourceMethods> methodsFor(int id) async => methods;
  @override
  Future<Source?> sourceById(int id) async => row;
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
  ..sourceCode = 'X';

List<PageUrl> _pages(int n) => [
  for (var i = 0; i < n; i++) PageUrl('https://img/$i.jpg'),
];

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('reader', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final library = LibraryRepositoryImpl();

  Future<void> seed() => library.upsertFromSource(
    sourceId: _sourceId,
    url: _manga,
    manga: MManga(
      name: 'Example',
      chapters: [
        MChapter(url: '/c-1', name: 'Chapter 1'),
        MChapter(url: '/c-2', name: 'Chapter 2'),
        MChapter(url: '/c-3', name: 'Chapter 3'),
      ],
    ),
  );

  Future<(ReaderController, _Methods)> open(
    String chapterUrl, {
    Map<String, List<PageUrl>>? pages,
  }) async {
    final methods = _Methods(_row())
      ..pagesByChapter =
          pages ?? {'/c-1': _pages(3), '/c-2': _pages(4), '/c-3': _pages(2)};
    final c = ReaderController(
      sources: _Sources(methods, _row()),
      library: library,
      sourceId: _sourceId,
      mangaUrl: _manga,
      chapterUrl: chapterUrl,
    )..onInit();
    // Waited on rather than pumped a fixed number of times: how many turns the
    // load takes depends on the path it goes down — reading a directory from
    // disk and clearing a stale pointer are both several more than a plain
    // fetch, and a fixed count silently returns an empty controller instead of
    // failing on what the test meant to assert.
    for (var i = 0; i < 100 && c.isLoading.value; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return (c, methods);
  }

  test('loads pages and orders chapters ascending', () async {
    await seed();
    final (c, _) = await open('/c-2');

    expect(c.pages, hasLength(4));
    // Ascending, so Next means the next one to read. The details screen shows
    // newest first; inheriting that would make Next walk backwards.
    expect(c.chaptersInOrder.map((x) => x.number), [1, 2, 3]);
    expect(c.hasNext, isTrue);
    expect(c.hasPrevious, isTrue);
  });

  test('reaching the last page marks the chapter read', () async {
    await seed();
    final (c, _) = await open('/c-1');

    c.onPageChanged(2); // last of three
    await c.flush();
    await Future<void>.delayed(Duration.zero);

    final entry = (await library.find(_sourceId, _manga))!;
    final chapter = entry.chapters.firstWhere((x) => x.url == '/c-1');
    expect(chapter.read, isTrue);
    expect(chapter.lastPageRead, 2);
    expect(chapter.totalPages, 3);
  });

  test('stopping short does not mark the chapter read', () async {
    await seed();
    final (c, _) = await open('/c-2');

    c.onPageChanged(1); // of four
    await c.flush();
    await Future<void>.delayed(Duration.zero);

    final chapter = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-2');
    expect(chapter.read, isFalse);
    expect(chapter.lastPageRead, 1);
  });

  test('reopening a finished chapter never marks it unread', () async {
    // The reader writes progress on every page change, so a chapter finished
    // earlier would otherwise flip back to unread the moment it was reopened
    // at page one.
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-1',
      lastPageRead: 2,
      totalPages: 3,
      markRead: true,
    );

    final (c, _) = await open('/c-1');
    c.onPageChanged(0);
    await c.flush();
    await Future<void>.delayed(Duration.zero);

    final chapter = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-1');
    expect(chapter.read, isTrue);
  });

  test('an unfinished chapter resumes where it was left', () async {
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-2',
      lastPageRead: 2,
      totalPages: 4,
    );

    final (c, _) = await open('/c-2');

    expect(c.initialPage, 2);
    expect(c.page.value, 2);
  });

  test('a finished chapter restarts at the top, not on its last page', () async {
    // Reopening something you have read means re-reading it; dropping the user
    // on the final page looks broken.
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-1',
      lastPageRead: 2,
      totalPages: 3,
      markRead: true,
    );

    final (c, _) = await open('/c-1');

    expect(c.initialPage, 0);
  });

  test('a stored position past the end is clamped, not crashed', () async {
    // A source can republish a chapter with fewer pages.
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-3',
      lastPageRead: 40,
      totalPages: 41,
    );

    final (c, _) = await open('/c-3');

    expect(c.initialPage, 1, reason: 'the chapter now has two pages');
  });

  test('a webtoon scroll position is stored and restored', () async {
    // A page index is not enough in continuous mode: the user stops partway
    // down a strip. The screen previously computed a page index from the scroll
    // fraction and never restored anything, so webtoon resume did nothing at
    // all -- while the commit message claimed it worked.
    await seed();
    final (first, _) = await open('/c-2');
    first.onScroll(1840.5, 6000);
    first.onPageChanged(1);
    await first.flush();

    final stored = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-2');
    expect(stored.currentOffset, 1840.5);
    expect(stored.maxOffset, 6000);

    final (second, _) = await open('/c-2');
    expect(second.initialOffset, 1840.5);
  });

  test('a finished chapter restarts at the top of the strip too', () async {
    await seed();
    final (first, _) = await open('/c-1');
    first.onScroll(900, 1000);
    first.onPageChanged(2); // last page -> read
    await first.flush();

    final (second, _) = await open('/c-1');
    expect(second.initialOffset, 0);
    expect(second.initialPage, 0);
  });

  test('paged reading does not erase a stored webtoon offset', () async {
    // updateChapterProgress takes nullable offsets; null means "not in
    // continuous mode" and must leave a previous webtoon position alone.
    await seed();
    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-2',
      lastPageRead: 1,
      totalPages: 4,
      currentOffset: 500,
      maxOffset: 2000,
    );

    await library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-2',
      lastPageRead: 2,
      totalPages: 4,
    );

    final stored = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-2');
    expect(stored.currentOffset, 500);
    expect(stored.lastPageRead, 2);
  });

  test('opening a one-page chapter does not mark it read', () async {
    // Page 0 of 1 is also the last page, so an unguarded save on load would
    // finish a chapter the user has not looked at.
    await seed();
    final (c, _) = await open('/c-1', pages: {'/c-1': _pages(1)});

    final chapter = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-1');
    expect(chapter.read, isFalse);
    expect(c.pages, hasLength(1));
  });

  test('unnumbered extras sort after numbered chapters, not before', () async {
    // `?? 0` put every extra before chapter 1, so Next walked the extras first.
    await library.upsertFromSource(
      sourceId: _sourceId,
      url: _manga,
      manga: MManga(
        name: 'Example',
        chapters: [
          MChapter(url: '/extra', name: 'Omake'),
          MChapter(url: '/c-1', name: 'Chapter 1'),
          MChapter(url: '/c-2', name: 'Chapter 2'),
        ],
      ),
    );
    final (c, _) = await open('/c-1', pages: {'/c-1': _pages(2)});

    expect(c.chaptersInOrder.map((x) => x.url), ['/c-1', '/c-2', '/extra']);
  });

  test('next moves forward and saves the chapter being left', () async {
    await seed();
    final (c, _) = await open('/c-1');
    c.onPageChanged(1);

    await c.next();

    expect(c.currentChapterUrl.value, '/c-2');
    expect(c.pages, hasLength(4));
    final left = (await library.find(
      _sourceId,
      _manga,
    ))!.chapters.firstWhere((x) => x.url == '/c-1');
    expect(
      left.lastPageRead,
      1,
      reason: 'progress was flushed before the move',
    );
  });

  test('there is no next past the last chapter', () async {
    await seed();
    final (c, _) = await open('/c-3');

    expect(c.hasNext, isFalse);
    await c.next(); // must not throw

    expect(c.currentChapterUrl.value, '/c-3');
  });

  test(
    'an empty page list reads as a source failure, not an empty chapter',
    () async {
      // A blank reader would look like the app lost the images.
      await seed();
      final (c, _) = await open('/c-1', pages: {'/c-1': const []});

      expect(c.error.value, contains('no pages'));
      expect(c.pages, isEmpty);
    },
  );

  test('a failed page list reports the site', () async {
    await seed();
    final methods = _Methods(_row())..failWith = StateError('403');
    final c = ReaderController(
      sources: _Sources(methods, _row()),
      library: library,
      sourceId: _sourceId,
      mangaUrl: _manga,
      chapterUrl: '/c-1',
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(c.error.value, contains('site may be down'));
    expect(c.isLoading.value, isFalse);
  });

  group('reading from disk', () {
    late Directory downloads;

    setUp(() {
      downloads = Directory.systemTemp.createTempSync('otaku-reader-offline');
    });
    tearDown(() {
      if (downloads.existsSync()) downloads.deleteSync(recursive: true);
    });

    Future<void> markDownloaded(String chapterUrl, String path) =>
        library.setChapterLocalPath(
          sourceId: _sourceId,
          url: _manga,
          chapterUrl: chapterUrl,
          localPath: path,
        );

    test('a downloaded chapter reads from disk, not from the source', () async {
      await seed();
      for (final name in ['0001.jpg', '0002.png', '0003.webp']) {
        File(p.join(downloads.path, name)).writeAsBytesSync([0]);
      }
      await markDownloaded('/c-1', downloads.path);

      final (c, methods) = await open('/c-1');

      expect(c.isOffline.value, isTrue);
      expect(c.pages, hasLength(3));
      expect(methods.pageListCalls, isEmpty, reason: 'the site is not touched');
      expect(c.pages.map((x) => p.basename(x.url)), [
        '0001.jpg',
        '0002.png',
        '0003.webp',
      ]);
    });

    test('a file the downloader did not write is not a page', () async {
      // A `.nomedia`, or a thumbnail from a gallery app that scanned the
      // folder. It sorts ahead of `0001.jpg`, so without the filter it becomes
      // the broken first page of every downloaded chapter.
      await seed();
      File(p.join(downloads.path, '.nomedia')).writeAsBytesSync([0]);
      File(p.join(downloads.path, '0001.jpg')).writeAsBytesSync([0]);
      File(p.join(downloads.path, 'Thumbs.db')).writeAsBytesSync([0]);
      await markDownloaded('/c-1', downloads.path);

      final (c, _) = await open('/c-1');

      expect(c.pages.map((x) => p.basename(x.url)), ['0001.jpg']);
    });

    test('a stale pointer falls back to the source and is cleared', () async {
      // Storage cleared, or the folder moved. Falling back is only half an
      // answer: the details screen reads the same field and would go on
      // offering "delete" for a download that is not there.
      await seed();
      await markDownloaded('/c-1', p.join(downloads.path, 'gone'));

      final (c, methods) = await open('/c-1');

      expect(c.isOffline.value, isFalse);
      expect(c.pages, hasLength(3), reason: 'fetched from the source instead');
      expect(methods.pageListCalls, ['/c-1']);

      final entry = await library.find(_sourceId, _manga);
      final chapter = entry!.chapters.firstWhere((x) => x.url == '/c-1');
      expect(chapter.localPath, isNull);
    });

    test('a downloaded chapter that is empty is treated as stale', () async {
      await seed();
      await markDownloaded('/c-1', downloads.path);

      final (c, _) = await open('/c-1');

      expect(c.isOffline.value, isFalse);
      expect(c.pages, hasLength(3));
      final entry = await library.find(_sourceId, _manga);
      final chapter = entry!.chapters.firstWhere((x) => x.url == '/c-1');
      expect(chapter.localPath, isNull);
    });
  });
}
