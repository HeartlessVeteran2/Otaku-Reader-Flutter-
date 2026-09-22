import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/source/model/m_status.dart';
import 'package:otaku_reader/features/updates/scheduling/update_schedule.dart';
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

import 'helpers/network_status_fake.dart';
import 'helpers/isar_test_env.dart';

const _sourceId = 7;
const _url = '/manga/example';

class _Methods implements SourceMethods {
  _Methods(this.source, this.detail);

  @override
  final Source source;
  MManga detail;
  Object? failWith;

  /// How many times a source was actually asked.
  ///
  /// The count, not just the end state: "waiting for Wi-Fi" and "refreshed
  /// and found nothing" leave the same updates list behind, and the whole
  /// point of the guard is that one of them crawled every installed source
  /// and the other did not.
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
        env = await IsarTestEnv.open('updates', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

  final library = LibraryRepositoryImpl();

  late FakeNetworkStatus network;

  Future<(UpdatesController, _Methods)> build(
    MManga detail, {
    bool unmetered = true,
  }) async {
    final methods = _Methods(_row(), detail);
    network = FakeNetworkStatus(unmetered: unmetered);
    final c = UpdatesController(
      library: library,
      sources: _Sources(methods, _row()),
      network: network,
    )..onInit();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return (c, methods);
  }

  /// Puts a manga in the library with the chapters a source first reported.
  Future<void> seed(List<MChapter> chapters, {Status? status}) async {
    await library.upsertFromSource(
      sourceId: _sourceId,
      url: _url,
      manga: MManga(name: 'Example', chapters: chapters, status: status),
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

  group('the scheduled refresh', () {
    test('manual never runs, and never asks the platform', () async {
      UpdateKeys.updateInterval.set<int>(UpdateInterval.manual.index);
      await seed([MChapter(url: '/c-1', name: 'Chapter 1')]);
      final (c, methods) = await build(
        MManga(
          name: 'Example',
          chapters: [MChapter(url: '/c-1')],
        ),
      );

      expect(await c.refreshIfDue(), UpdateDecision.disabled);
      expect(methods.detailCalls, 0, reason: 'no source was asked');
      expect(
        network.asked,
        0,
        reason: 'a disabled schedule does not touch a platform channel',
      );
      c.onClose();
    });

    test('a due schedule refreshes and stamps the check', () async {
      UpdateKeys.updateInterval.set<int>(UpdateInterval.daily.index);
      UpdateKeys.updateOnWifiOnly.set<bool>(false);
      await seed([MChapter(url: '/c-1', name: 'Chapter 1')]);
      final (c, methods) = await build(
        MManga(
          name: 'Example',
          chapters: [
            MChapter(url: '/c-1'),
            MChapter(url: '/c-2'),
          ],
        ),
      );

      expect(await c.refreshIfDue(), UpdateDecision.run);
      expect(methods.detailCalls, 1);
      expect(c.lastChecked.value, isNotNull);
      c.onClose();
    });

    test('the platform is only asked once the schedule has said yes', () async {
      // The ordering, and it is what a decision-only test cannot see. Asking
      // the connectivity channel first would hit it on **every app resume** to
      // answer a question that usually ends in "not due".
      UpdateKeys.updateInterval.set<int>(UpdateInterval.weekly.index);
      UpdateKeys.updateOnWifiOnly.set<bool>(true);
      await seed([MChapter(url: '/c-1', name: 'Chapter 1')]);
      final (c, _) = await build(
        MManga(
          name: 'Example',
          chapters: [MChapter(url: '/c-1')],
        ),
      );
      // Freshly checked, so nothing is due.
      c.lastChecked.value = DateTime.now();

      expect(await c.refreshIfDue(), UpdateDecision.notDue);
      expect(network.asked, 0);
      c.onClose();
    });

    test('mobile data holds off, and the source is never asked', () async {
      UpdateKeys.updateInterval.set<int>(UpdateInterval.daily.index);
      UpdateKeys.updateOnWifiOnly.set<bool>(true);
      await seed([MChapter(url: '/c-1', name: 'Chapter 1')]);
      final (c, methods) = await build(
        MManga(
          name: 'Example',
          chapters: [MChapter(url: '/c-1')],
        ),
        unmetered: false,
      );

      expect(await c.refreshIfDue(), UpdateDecision.waitingForWifi);
      expect(network.asked, 1);
      expect(methods.detailCalls, 0, reason: 'nothing was crawled');
      c.onClose();
    });

    test('an explicit pull-to-refresh ignores the schedule entirely', () async {
      // A gesture is the user asking. Silently dropping it because an interval
      // has not elapsed is the feature deciding it knows better.
      UpdateKeys.updateInterval.set<int>(UpdateInterval.manual.index);
      UpdateKeys.updateOnWifiOnly.set<bool>(true);
      await seed([MChapter(url: '/c-1', name: 'Chapter 1')]);
      final (c, methods) = await build(
        MManga(
          name: 'Example',
          chapters: [MChapter(url: '/c-1')],
        ),
        unmetered: false,
      );

      await c.refreshLibrary();

      expect(methods.detailCalls, 1);
      expect(network.asked, 0, reason: 'the network never gates a gesture');
      c.onClose();
    });
  });

  group('skip finished series', () {
    test('an unknown status counts as ongoing', () {
      // Most sources do not report status at all. Treating "I don't know" as
      // finished would quietly stop updating most of a library.
      final entry = MangaEntry()..status = Status.unknown.index;
      expect(UpdatesController.isOngoing(entry), isTrue);
    });

    test('completed, cancelled and finished are skipped', () {
      for (final status in [
        Status.completed,
        Status.canceled,
        Status.publishingFinished,
      ]) {
        final entry = MangaEntry()..status = status.index;
        expect(
          UpdatesController.isOngoing(entry),
          isFalse,
          reason: status.name,
        );
      }
    });

    test('ongoing and on-hiatus are still refreshed', () {
      for (final status in [Status.ongoing, Status.onHiatus]) {
        final entry = MangaEntry()..status = status.index;
        expect(UpdatesController.isOngoing(entry), isTrue, reason: status.name);
      }
    });

    test('a refresh actually skips a finished series', () async {
      // **The guard that matters.** The three tests above exercise
      // `isOngoing` and nothing else, so deleting the filter from
      // `refreshLibrary` left every one of them green — measured, `+15` with
      // the call site removed. A test that builds the feature's enabled state
      // proves the mechanism; the defect lives in whether any caller uses it.
      UpdateKeys.updateOnlyOngoing.set<bool>(true);
      await seed([
        MChapter(url: '/c-1', name: 'Chapter 1'),
      ], status: Status.completed);
      final (c, methods) = await build(
        MManga(
          name: 'Example',
          chapters: [
            MChapter(url: '/c-1'),
            MChapter(url: '/c-2'),
          ],
        ),
      );

      await c.refreshLibrary();

      expect(methods.detailCalls, 0, reason: 'the source was never asked');
      expect(c.total.value, 0);
      c.onClose();
    });

    test('with the switch off, a finished series is still refreshed', () async {
      UpdateKeys.updateOnlyOngoing.set<bool>(false);
      await seed([
        MChapter(url: '/c-1', name: 'Chapter 1'),
      ], status: Status.completed);
      final (c, methods) = await build(
        MManga(
          name: 'Example',
          chapters: [MChapter(url: '/c-1')],
        ),
      );

      await c.refreshLibrary();

      expect(methods.detailCalls, 1);
      c.onClose();
    });
  });
}
