import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/browse/controllers/source_browse_controller.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

MManga _manga(String name) => MManga(name: name, link: '/$name');

class _FakeMethods implements SourceMethods {
  _FakeMethods(this.source);

  @override
  final Source source;

  final List<String> calls = [];

  /// Gates a *specific* call, keyed by its label, so a test controls exactly
  /// which response lands first. A single shared gate is not enough: it holds
  /// the superseding call open too, and then the completion order decides the
  /// outcome rather than the code under test.
  final Map<String, Completer<void>> gates = {};
  Object? failWith;
  int popularPages = 2;

  Future<MPages> _page(String label, int page) async {
    final key = '$label:$page';
    calls.add(key);
    final gate = gates[key];
    if (gate != null) await gate.future;
    if (failWith != null) throw failWith!;
    return MPages(
      list: [_manga('$label-p$page-a'), _manga('$label-p$page-b')],
      hasNextPage: page < popularPages,
    );
  }

  @override
  Future<MPages> getPopular(int page) => _page('popular', page);
  @override
  Future<MPages> getLatestUpdates(int page) => _page('latest', page);
  @override
  Future<MPages> search(String q, int page, FilterList f) =>
      _page('search($q)', page);

  @override
  bool get supportsLatest => true;
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

class _FakeSources implements SourceRepository {
  _FakeSources(this.methods, {this.row});

  final _FakeMethods? methods;
  final Source? row;
  Object? methodsFailWith;
  int marked = 0;

  @override
  Future<SourceMethods> methodsFor(int id) async {
    if (methodsFailWith != null) throw methodsFailWith!;
    return methods!;
  }

  @override
  Future<Source?> sourceById(int id) async => row;
  @override
  Future<void> markUsed(int id) async => marked++;
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
  Future<(SourceBrowseController, _FakeMethods, _FakeSources)> build() async {
    final row = _row();
    final methods = _FakeMethods(row);
    final sources = _FakeSources(methods, row: row);
    final c = SourceBrowseController(sources: sources, sourceId: 1)..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return (c, methods, sources);
  }

  test(
    'loads the first page of popular and records the source as used',
    () async {
      final (c, methods, sources) = await build();

      expect(c.items.map((m) => m.name), ['popular-p1-a', 'popular-p1-b']);
      expect(c.hasNextPage.value, isTrue);
      expect(methods.calls, ['popular:1']);
      expect(sources.marked, 1);
    },
  );

  test('loadMore appends rather than replacing', () async {
    final (c, _, _) = await build();

    await c.loadMore();

    expect(c.items.map((m) => m.name), [
      'popular-p1-a',
      'popular-p1-b',
      'popular-p2-a',
      'popular-p2-b',
    ]);
    expect(c.hasNextPage.value, isFalse, reason: 'page 2 was the last');
  });

  test('loadMore does nothing once the last page is in', () async {
    final (c, methods, _) = await build();
    await c.loadMore();
    methods.calls.clear();

    await c.loadMore();

    expect(methods.calls, isEmpty);
  });

  test('a late page from a superseded listing is discarded', () async {
    // The bug this guards only appears on a slow network: search while page 2
    // of popular is still in flight, and the old results append underneath the
    // new ones.
    final (c, methods, _) = await build();

    // Hold popular page 2 open, and only that call.
    methods.gates['popular:2'] = Completer<void>();
    final slow = c.loadMore();
    await Future<void>.delayed(Duration.zero);

    // The search supersedes it and lands first, ungated.
    c.setQuery('naruto');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(
      c.items.every((m) => m.name!.startsWith('search')),
      isTrue,
      reason: 'precondition: the search results are what is on screen',
    );

    // Now the superseded page finally arrives.
    methods.gates['popular:2']!.complete();
    await slow;
    await Future<void>.delayed(Duration.zero);

    expect(
      c.items.every((m) => m.name!.startsWith('search')),
      isTrue,
      reason: 'the late popular page must not append under the search results',
    );
    expect(c.items.map((m) => m.name), isNot(contains('popular-p2-a')));
  });

  test('a superseded loadMore does not wedge paging forever', () async {
    // Resetting isLoadingMore only for the current generation left it stuck
    // true whenever a reload superseded an in-flight loadMore -- and loadMore
    // refuses to run while it is set, so paging was dead for the rest of the
    // screen's life. My own stale-response test missed this because it never
    // looked at the flag afterwards.
    final (c, methods, _) = await build();

    methods.gates['popular:2'] = Completer<void>();
    final slow = c.loadMore();
    await Future<void>.delayed(Duration.zero);
    expect(c.isLoadingMore.value, isTrue);

    c.setQuery('naruto');
    await Future<void>.delayed(Duration.zero);
    methods.gates['popular:2']!.complete();
    await slow;
    await Future<void>.delayed(Duration.zero);

    expect(c.isLoadingMore.value, isFalse, reason: 'the flag was released');

    // And paging actually works again.
    methods.calls.clear();
    await c.loadMore();
    expect(methods.calls, isNotEmpty);
  });

  test('a superseded page does not release a newer requestguard', () async {
    // The first fix cleared the flag unconditionally, which swapped a
    // stuck-forever bug for a subtler one: the late response released the
    // *newer* request's guard, and the next scroll appended a duplicate page.
    final (c, methods, _) = await build();

    methods.gates['popular:2'] = Completer<void>();
    final first = c.loadMore();
    await Future<void>.delayed(Duration.zero);

    c.setQuery('naruto');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // A new page request on the search listing.
    methods.gates['search(naruto):2'] = Completer<void>();
    final second = c.loadMore();
    await Future<void>.delayed(Duration.zero);
    expect(c.isLoadingMore.value, isTrue);

    // The superseded popular page finally lands.
    methods.gates['popular:2']!.complete();
    await first;
    await Future<void>.delayed(Duration.zero);

    expect(
      c.isLoadingMore.value,
      isTrue,
      reason: 'the newer request still owns the guard',
    );

    methods.gates['search(naruto):2']!.complete();
    await second;
    expect(c.isLoadingMore.value, isFalse);
  });

  test('switching mode restarts from page 1', () async {
    final (c, methods, _) = await build();
    await c.loadMore();

    c.setMode(BrowseMode.latest);
    await Future<void>.delayed(Duration.zero);

    expect(c.items.map((m) => m.name), ['latest-p1-a', 'latest-p1-b']);
    expect(methods.calls.last, 'latest:1');
  });

  test(
    'an empty query returns to popular rather than searching for nothing',
    () async {
      final (c, methods, _) = await build();
      c.setQuery('naruto');
      await Future<void>.delayed(Duration.zero);
      expect(c.mode.value, BrowseMode.search);

      c.setQuery('   ');
      await Future<void>.delayed(Duration.zero);

      expect(c.mode.value, BrowseMode.popular);
      expect(methods.calls.last, 'popular:1');
    },
  );

  test('a failed reload keeps what was already on screen', () async {
    final (c, methods, _) = await build();
    expect(c.items, isNotEmpty);

    methods.failWith = StateError('502 from the site');
    await c.reload();

    expect(c.items, isNotEmpty, reason: 'a refresh failure is not a wipe');
    expect(c.error.value, contains('Example Source'));
    expect(
      c.error.value,
      contains('site may be down'),
      reason:
          'every hard failure in the live sweep was external; the message '
          'should not imply the app is broken',
    );
  });

  test(
    'a failed loadMore stops paging instead of retrying every scroll',
    () async {
      final (c, methods, _) = await build();
      methods.failWith = StateError('timeout');

      await c.loadMore();

      expect(c.hasNextPage.value, isFalse);
      expect(c.isLoadingMore.value, isFalse);
    },
  );

  test(
    'a source that will not start reports it rather than spinning forever',
    () async {
      final sources = _FakeSources(null, row: _row())
        ..methodsFailWith = StateError('not installed');
      final c = SourceBrowseController(sources: sources, sourceId: 1)..onInit();
      await Future<void>.delayed(Duration.zero);

      expect(c.error.value, contains('not installed'));
      expect(c.isLoading.value, isFalse);
    },
  );
}
