import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/details/controllers/manga_details_controller.dart';
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
  _Methods(this.source, this.detail);

  @override
  final Source source;
  MManga detail;
  Object? failWith;
  int detailCalls = 0;

  @override
  Future<MManga> getDetail(String url) async {
    detailCalls++;
    if (failWith != null) throw failWith!;
    return detail;
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
  Future<List<PageUrl>> getPageList(String url) async => const [];
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
  ..baseUrl = 'https://example.test'
  ..sourceCode = 'X';

MChapter _ch(String url, String name) => MChapter(url: url, name: name);

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('details', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final library = LibraryRepositoryImpl();

  Future<(MangaDetailsController, _Methods)> build(
    MManga detail, {
    MManga? initial,
  }) async {
    final methods = _Methods(_row(), detail);
    final c = MangaDetailsController(
      sources: _Sources(methods, _row()),
      library: library,
      sourceId: _sourceId,
      url: _url,
      initial: initial,
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return (c, methods);
  }

  test(
    'loads the detail and stores it without adding to the library',
    () async {
      final (c, _) = await build(
        MManga(
          name: 'Example',
          author: 'Someone',
          chapters: [_ch('/c-1', 'Chapter 1')],
        ),
      );

      expect(c.entry.value?.title, 'Example');
      expect(c.entry.value?.author, 'Someone');
      expect(c.isFavorite, isFalse);
      expect(await library.favorites(), isEmpty);
    },
  );

  test(
    'chapters sort newest first by default and the order can be flipped',
    () async {
      final (c, _) = await build(
        MManga(
          name: 'Example',
          chapters: [
            _ch('/c-1', 'Chapter 1'),
            _ch('/c-3', 'Chapter 3'),
            _ch('/c-2', 'Chapter 2'),
          ],
        ),
      );

      expect(c.chapters.map((x) => x.number), [3, 2, 1]);

      c.toggleSort();
      expect(c.chapters.map((x) => x.number), [1, 2, 3]);
    },
  );

  test('chapters with no parsable number sort last, not first', () async {
    // Many sources title one-shots and extras by name. Sorting those to the top
    // would bury the actual chapter 1.
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [
          _ch('/extra', 'Extra: Behind the scenes'),
          _ch('/c-1', 'Chapter 1'),
          _ch('/c-2', 'Chapter 2'),
        ],
      ),
    );

    expect(c.chapters.last.url, '/extra');
  });

  test('unnumbered chapters keep the order the source listed them in', () async {
    // Dart's List.sort is not stable, so a comparator returning 0 lets their
    // order shuffle between rebuilds. Their position in the source's listing is
    // the only order they have.
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [
          _ch('/omake', 'Omake'),
          _ch('/c-1', 'Chapter 1'),
          _ch('/extra', 'Extra'),
          _ch('/afterword', 'Afterword'),
        ],
      ),
    );

    final unnumbered = c.chapters.where((x) => x.number == null).toList();
    expect(unnumbered.map((x) => x.url), ['/omake', '/extra', '/afterword']);

    // Flipping the numeric direction must not reorder them either.
    c.toggleSort();
    expect(c.chapters.where((x) => x.number == null).map((x) => x.url), [
      '/omake',
      '/extra',
      '/afterword',
    ]);
  });

  test('the unread filter hides read chapters and the count follows', () async {
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [_ch('/c-1', 'Chapter 1'), _ch('/c-2', 'Chapter 2')],
      ),
    );
    expect(c.unreadCount, 2);

    await c.setRead(c.chapters.last, true); // chapter 1

    expect(c.unreadCount, 1);
    c.setFilter(ChapterFilter.unread);
    expect(c.chapters.map((x) => x.number), [2]);
  });

  test('mark-read-up-to sets everything at or below that chapter', () async {
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [
          _ch('/c-1', 'Chapter 1'),
          _ch('/c-2', 'Chapter 2'),
          _ch('/c-3', 'Chapter 3'),
          _ch('/c-4', 'Chapter 4'),
        ],
      ),
    );

    final chapterThree = c.chapters.firstWhere((x) => x.number == 3);
    await c.markReadUpTo(chapterThree);

    final read = {for (final x in c.chapters) x.number: x.read};
    expect(read, {4.0: false, 3.0: true, 2.0: true, 1.0: true});
  });

  test('toggling favorite persists', () async {
    final (c, _) = await build(MManga(name: 'Example'));

    await c.toggleFavorite();

    expect(c.isFavorite, isTrue);
    expect((await library.favorites()).single.url, _url);
  });

  test(
    'a stored entry plus a failed refresh is a usable page, not an error',
    () async {
      // Reopening a manga you have read must work offline.
      final (first, _) = await build(
        MManga(name: 'Example', chapters: [_ch('/c-1', 'Chapter 1')]),
      );
      expect(first.entry.value, isNotNull);

      final methods = _Methods(_row(), MManga())
        ..failWith = StateError('offline');
      final second = MangaDetailsController(
        sources: _Sources(methods, _row()),
        library: library,
        sourceId: _sourceId,
        url: _url,
      )..onInit();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(second.error.value, isNull, reason: 'there is something to show');
      expect(second.entry.value?.title, 'Example');
      expect(second.chapters, hasLength(1));
    },
  );

  test('a first visit that fails does report an error', () async {
    final methods = _Methods(_row(), MManga())..failWith = StateError('502');
    final c = MangaDetailsController(
      sources: _Sources(methods, _row()),
      library: library,
      sourceId: _sourceId,
      url: _url,
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(c.error.value, contains('site may be down'));
    expect(c.isLoading.value, isFalse);
  });

  test('favorite is refused when there is no row to favourite', () async {
    final methods = _Methods(_row(), MManga())..failWith = StateError('502');
    final c = MangaDetailsController(
      sources: _Sources(methods, _row()),
      library: library,
      sourceId: _sourceId,
      url: _url,
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await c.toggleFavorite(); // must not throw

    expect(c.isFavorite, isFalse);
  });

  test(
    'the preview from the grid is available before the detail lands',
    () async {
      final preview = MManga(
        name: 'From the grid',
        imageUrl: 'https://c/i.jpg',
      );
      final (c, _) = await build(MManga(name: 'Example'), initial: preview);

      expect(c.preview?.name, 'From the grid');
    },
  );
}
