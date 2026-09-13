import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/updates/controllers/updates_controller.dart';
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

  @override
  Future<MManga> getDetail(String url) async {
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
        env = await IsarTestEnv.open('updates', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final library = LibraryRepositoryImpl();

  Future<(UpdatesController, _Methods)> build(MManga detail) async {
    final methods = _Methods(_row(), detail);
    final c = UpdatesController(
      library: library,
      sources: _Sources(methods, _row()),
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return (c, methods);
  }

  /// Puts a manga in the library with the chapters a source first reported.
  Future<void> seed(List<MChapter> chapters) async {
    await library.upsertFromSource(
      sourceId: _sourceId,
      url: _url,
      manga: MManga(name: 'Example', chapters: chapters),
    );
    await library.toggleFavorite(_sourceId, _url);
  }

  test('a first fetch produces no updates at all', () async {
    // Otherwise adding a series with a long back catalogue announces every
    // chapter of it as new.
    await seed([for (var i = 1; i <= 40; i++) _ch('/c-$i', 'Chapter $i')]);

    final (c, _) = await build(MManga(name: 'Example'));

    expect(c.updates, isEmpty);
  });

  test('a chapter that appears on a refresh is an update', () async {
    await seed([_ch('/c-1', 'Chapter 1')]);
    final (c, methods) = await build(
      MManga(
        name: 'Example',
        chapters: [_ch('/c-1', 'Chapter 1'), _ch('/c-2', 'Chapter 2')],
      ),
    );
    expect(c.updates, isEmpty, reason: 'nothing new before the refresh');

    await c.refreshLibrary();

    expect(c.updates.map((u) => u.chapter.url), ['/c-2']);
    expect(c.updates.single.chapter.read, isFalse);
    expect(methods.failWith, isNull);
  });

  test('a second refresh does not re-announce the same chapter', () async {
    await seed([_ch('/c-1', 'Chapter 1')]);
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [_ch('/c-1', 'Chapter 1'), _ch('/c-2', 'Chapter 2')],
      ),
    );

    await c.refreshLibrary();
    final firstSeen = c.updates.single.fetchedAt;
    await c.refreshLibrary();

    expect(c.updates, hasLength(1));
    expect(
      c.updates.single.fetchedAt,
      firstSeen,
      reason: 'the stamp is when it first appeared, not when it was last seen',
    );
  });

  test('a failed refresh is reported per series, not swallowed', () async {
    // A source that has moved domain fails every refresh, and the only other
    // symptom is a series that quietly stops getting chapters.
    await seed([_ch('/c-1', 'Chapter 1')]);
    final (c, methods) = await build(MManga(name: 'Example'));
    methods.failWith = StateError('SocketException: no route to host');

    await c.refreshLibrary();

    expect(c.errors, hasLength(1));
    expect(c.errors.single.entry.displayTitle, 'Example');
    expect(
      c.errors.single.message,
      'Could not reach the site',
      reason: 'every hard failure in the live sweep was external',
    );
    expect(c.isRefreshing.value, isFalse);
  });

  test('only favourites are refreshed', () async {
    // Opening a manga stores it; that is not the same as following it, and
    // refreshing everything ever opened would be an unbounded crawl.
    await library.upsertFromSource(
      sourceId: _sourceId,
      url: _url,
      manga: MManga(name: 'Merely opened', chapters: [_ch('/c-1', 'One')]),
    );
    final (c, _) = await build(
      MManga(
        name: 'Merely opened',
        chapters: [_ch('/c-1', 'One'), _ch('/c-2', 'Two')],
      ),
    );

    await c.refreshLibrary();

    expect(c.updates, isEmpty);
    expect(c.errors, isEmpty);
  });

  test('marking an update read persists and keeps it listed', () async {
    await seed([_ch('/c-1', 'Chapter 1')]);
    final (c, _) = await build(
      MManga(
        name: 'Example',
        chapters: [_ch('/c-1', 'Chapter 1'), _ch('/c-2', 'Chapter 2')],
      ),
    );
    await c.refreshLibrary();

    await c.markRead(c.updates.single, true);

    expect(c.updates.single.chapter.read, isTrue);
    final stored = await library.find(_sourceId, _url);
    expect(
      stored!.chapters.firstWhere((x) => x.url == '/c-2').read,
      isTrue,
      reason: 'the list is a view of the library, not a copy of it',
    );
    // Read updates stay listed: the tab is a record of what arrived, not only
    // of what is outstanding.
    expect(c.updates, hasLength(1));
  });

  test('the last check time is recorded', () async {
    await seed([_ch('/c-1', 'Chapter 1')]);
    final (c, _) = await build(MManga(name: 'Example'));
    expect(c.lastChecked.value, isNull);

    await c.refreshLibrary();

    expect(c.lastChecked.value, isNotNull);
    expect(UpdateKeys.lastUpdateCheck.get<int?>(null), isNotNull);
  });
}
