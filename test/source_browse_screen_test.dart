import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/browse/screens/source_browse_screen.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/isar_test_env.dart';

class _Methods implements SourceMethods {
  _Methods(
    this.source, {
    this.fail = false,
    this.latest = true,
    this.empty = false,
  });

  @override
  final Source source;
  final bool fail;
  final bool latest;
  final bool empty;

  Future<MPages> _p(String label) async {
    if (fail) throw StateError('502');
    if (empty) return MPages(list: [], hasNextPage: false);
    return MPages(list: [MManga(name: '$label One')], hasNextPage: false);
  }

  @override
  Future<MPages> getPopular(int page) => _p('Popular');
  @override
  Future<MPages> getLatestUpdates(int page) => _p('Latest');
  @override
  Future<MPages> search(String q, int p, FilterList f) => _p('Search');
  @override
  bool get supportsLatest => latest;
  @override
  String get sourceBaseUrl => 'https://example.test';
  @override
  Map<String, String> getHeaders() => const {};
  @override
  Future<MManga> getDetail(String url) async => MManga();
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
  final SourceMethods methods;
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
  ..sourceId = 1
  ..name = 'Example Source'
  ..lang = 'en'
  ..baseUrl = 'https://example.test'
  ..sourceCode = 'X';

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('browseui', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() {
    env!.clear();
    Get.reset();
  });

  Future<void> pump(WidgetTester tester, SourceMethods methods) async {
    Get.put<SourceRepository>(_Sources(methods, _row()));
    await tester.pumpWidget(
      const GetMaterialApp(home: SourceBrowseScreen(sourceId: 1)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the grid without an Obx misuse error', (tester) async {
    await pump(tester, _Methods(_row()));

    expect(find.text('Example Source'), findsOneWidget);
    expect(find.text('Popular One'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a source that cannot list shows the site, not a blank grid', (
    tester,
  ) async {
    await pump(tester, _Methods(_row(), fail: true));

    expect(find.textContaining('Example Source'), findsWidgets);
    expect(find.textContaining('site may be down'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a source that returns nothing lays out and can be pulled', (
    tester,
  ) async {
    // The empty state sits inside the pull-to-refresh scrollable rather than
    // replacing it, so a source that has simply gone quiet can be retried. That
    // puts an unbounded-height `Center` in a `ListView` slot, which is exactly
    // the shape that throws if it does not shrink-wrap -- so this asserts no
    // exception as much as it asserts the text.
    await pump(tester, _Methods(_row(), empty: true));

    expect(find.text('This source returned nothing.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Latest chip is hidden when the source has no latest feed', (
    tester,
  ) async {
    await pump(tester, _Methods(_row(), latest: false));

    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('Latest'), findsNothing);
  });
}
