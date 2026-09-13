import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/search/controllers/global_search_controller.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/isar_test_env.dart';

class _Methods implements SourceMethods {
  _Methods(this.source);

  @override
  final Source source;

  /// Hits this source answers with, keyed by query.
  final Map<String, List<MManga>> hits = {};
  Object? failWith;

  /// Held open by the test to control when this source's search returns.
  Completer<void>? gate;

  final List<String> queries = [];

  @override
  Future<MPages> search(String q, int p, FilterList f) async {
    queries.add(q);
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
    return MPages(list: hits[q] ?? const []);
  }

  @override
  bool get supportsLatest => true;
  @override
  String get sourceBaseUrl => 'https://${source.name}.test';
  @override
  Map<String, String> getHeaders() => const {};
  @override
  Future<MManga> getDetail(String url) async => MManga();
  @override
  Future<MPages> getPopular(int p) async => MPages(list: []);
  @override
  Future<MPages> getLatestUpdates(int p) async => MPages(list: []);
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
  _Sources(this.rows);

  final List<Source> rows;
  final Map<int, _Methods> methods = {};

  _Methods methodsOf(int id) => methods.putIfAbsent(
    id,
    () => _Methods(rows.firstWhere((r) => r.sourceId == id)),
  );

  @override
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  }) async => rows
      .where((r) => includeNsfw || !r.isNsfw)
      .where((r) => langs == null || langs.contains(r.lang) || r.lang == 'all')
      .toList();

  @override
  Future<SourceMethods> methodsFor(int id) async => methodsOf(id);
  @override
  Future<Source?> sourceById(int id) async =>
      rows.where((r) => r.sourceId == id).firstOrNull;
  @override
  Future<void> markUsed(int id) async {}
  @override
  void evict(int id) {}
  @override
  void evictAll() {}
}

Source _row(int id, String name, {String lang = 'en', bool nsfw = false}) =>
    Source()
      ..sourceId = id
      ..name = name
      ..lang = lang
      ..isNsfw = nsfw
      ..baseUrl = 'https://stored.test'
      ..sourceCode = 'X';

MManga _manga(String name) => MManga(name: name, link: '/m/$name');

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('gsearch', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  test('every source gets a row, including one that fails', () async {
    final sources = _Sources([_row(1, 'Alpha'), _row(2, 'Beta')]);
    final c = GlobalSearchController(sources: sources);
    sources.methodsOf(1).hits['one piece'] = [_manga('One Piece')];
    sources.methodsOf(2).failWith = StateError('502');

    await c.search('one piece');

    expect(c.results.map((r) => r.source.name), ['Alpha', 'Beta']);
    expect(c.results.first.items.map((m) => m.name), ['One Piece']);
    // A source that failed must stay visible and say so -- dropping the row
    // reads as "this manga is not on that source", which is a different and
    // wrong answer.
    expect(c.results.last.error, isNotNull);
    expect(c.results.last.isLoading, isFalse);
    expect(c.isSearching.value, isFalse);
  });

  test('the effective base URL wins over the stored one', () async {
    // A mirror preference moves a source's base URL, and cover requests need
    // the one actually in effect for their Referer.
    final sources = _Sources([_row(1, 'Alpha')]);
    final c = GlobalSearchController(sources: sources);
    sources.methodsOf(1).hits['x'] = [_manga('X')];

    await c.search('x');

    expect(c.results.single.baseUrl, 'https://Alpha.test');
  });

  test('a slow source from a superseded query cannot land', () async {
    final sources = _Sources([_row(1, 'Alpha')]);
    final c = GlobalSearchController(sources: sources);
    final held = Completer<void>();
    final alpha = sources.methodsOf(1)
      ..hits['old'] = [_manga('Old hit')]
      ..hits['new'] = [_manga('New hit')]
      ..gate = held;

    final slow = c.search('old');
    await Future<void>.delayed(Duration.zero);

    // The second search starts while the first is still blocked, then finishes
    // first -- the ordering that makes a stale response overwrite a fresh one.
    alpha.gate = null;
    await c.search('new');
    expect(c.results.single.items.map((m) => m.name), ['New hit']);

    // Only now does the first query's response arrive.
    held.complete();
    await slow;

    expect(c.results.single.items.map((m) => m.name), [
      'New hit',
    ], reason: 'the superseded response was dropped');
  });

  test('an empty query clears the results instead of searching', () async {
    final sources = _Sources([_row(1, 'Alpha')]);
    final c = GlobalSearchController(sources: sources);
    sources.methodsOf(1).hits['x'] = [_manga('X')];
    await c.search('x');
    expect(c.results, isNotEmpty);

    await c.search('   ');

    expect(c.results, isEmpty);
    expect(sources.methodsOf(1).queries, ['x'], reason: 'no blank search ran');
  });

  test('no installed sources is a named state, not an empty list', () async {
    final c = GlobalSearchController(sources: _Sources([]));

    await c.search('anything');

    expect(c.error.value, contains('No sources installed'));
    expect(c.isSearching.value, isFalse);
  });

  test('NSFW sources are searched only when the user allows them', () async {
    final sources = _Sources([_row(1, 'Safe'), _row(2, 'Adult', nsfw: true)]);
    final c = GlobalSearchController(sources: sources);

    await c.search('x');
    expect(c.results.map((r) => r.source.name), ['Safe']);

    SourceKeys.showNsfwSources.set<bool>(true);
    await c.search('x');
    expect(c.results.map((r) => r.source.name), ['Adult', 'Safe']);
  });

  test('no stored language preference searches everything', () async {
    // An empty set meaning "no languages" would give a first-run user an empty
    // result that looks exactly like every source failing.
    final sources = _Sources([
      _row(1, 'English'),
      _row(2, 'French', lang: 'fr'),
    ]);
    final c = GlobalSearchController(sources: sources);

    await c.search('x');

    expect(c.results, hasLength(2));
  });

  test('pinned sources are searched and listed first', () async {
    final sources = _Sources([_row(1, 'Alpha'), _row(2, 'Zeta')]);
    SourceKeys.pinnedSourceIds.set<List<String>>(['2']);
    final c = GlobalSearchController(sources: sources);

    await c.search('x');

    expect(c.results.map((r) => r.source.name), ['Zeta', 'Alpha']);
  });

  test('results are capped per source', () async {
    final sources = _Sources([_row(1, 'Alpha')]);
    final c = GlobalSearchController(sources: sources);
    sources.methodsOf(1).hits['x'] = [
      for (var i = 0; i < 40; i++) _manga('m$i'),
    ];

    await c.search('x');

    expect(
      c.results.single.items,
      hasLength(GlobalSearchController.perSourceLimit),
    );
  });
}
