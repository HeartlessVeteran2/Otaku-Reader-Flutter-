import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/theme/one_ui.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/data/anilist/anilist_metadata_service.dart';
import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/data/repository/download_repository_impl.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/downloads/controllers/downloads_controller.dart';
import 'package:otaku_reader/features/details/controllers/manga_details_controller.dart';
import 'package:otaku_reader/features/details/screens/manga_details_screen.dart';
import 'package:otaku_reader/features/downloads/screens/downloads_screen.dart';
import 'package:otaku_reader/domain/repository/anilist_repository.dart';
import 'package:otaku_reader/features/history/screens/history_screen.dart';
import 'package:otaku_reader/features/home/controllers/home_controller.dart';
import 'package:otaku_reader/features/home/screens/home_screen.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';
import 'package:otaku_reader/features/library/screens/library_screen.dart';
import 'package:otaku_reader/features/more/screens/about_screen.dart';
import 'package:otaku_reader/features/more/screens/more_screen.dart';
import 'package:otaku_reader/features/settings/screens/settings_screen.dart';
import 'package:otaku_reader/features/updates/controllers/updates_controller.dart';
import 'package:otaku_reader/features/updates/screens/updates_screen.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/anilist_fakes.dart';
import 'helpers/fake_source_repository.dart';
import 'helpers/isar_test_env.dart';

/// These suites exist because a One UI conversion is exactly the kind of change
/// that analyses clean, passes every controller test, and then throws on the
/// device.
///
/// The specific hazard is the sliver slot. `OneUiScaffold` builds a
/// `CustomScrollView`, so everything handed to it must produce a `RenderSliver`
/// — and a plain box widget in that list is a *runtime* failure, invisible to
/// `flutter analyze` because `Widget` is the declared type either way. `Obx`
/// and `FutureBuilder` make it worse: they are composition widgets with no
/// render object of their own, so whether they are legal in a sliver slot
/// depends on what their builder happens to return.
///
/// Nothing else in the suite renders these screens, so without this file the
/// whole visual pass is unverified.
void main() {
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('oneui', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());

  late Directory root;
  late LibraryRepositoryImpl library;
  late NsfwPreference nsfw;

  setUp(() {
    env!.clear();
    Get.reset();
    Get.put<ThemeController>(ThemeController());
    // Settings, Home and Browse all resolve the one holder rather than each
    // keeping a copy — registering it is what makes them agree.
    // **The same instance everyone else gets.** Registering one and injecting
    // a *different* one into a controller is the very bug this PR fixes — a
    // harness shaped that way cannot fail when a Settings write stops reaching
    // Home, which is the regression the suite exists to catch.
    nsfw = NsfwPreference();
    Get.put<NsfwPreference>(nsfw);
    root = Directory.systemTemp.createTempSync('otaku-oneui');

    // **One repository instance, shared by everything here.**
    //
    // `LibraryRepositoryImpl._changes` is a per-instance broadcast controller,
    // so two instances over the same database share their rows but not their
    // notifications: a write through one never reaches a listener on the
    // other. A harness that hands each controller its own instance therefore
    // cannot fail when the change-notification path breaks — and that path is
    // load-bearing, because `didChangeDependencies` cannot fire on an
    // `IndexedStack` reselection, which is the whole reason `changes` exists.
    library = LibraryRepositoryImpl();

    Get.put<DownloadRepository>(
      DownloadRepositoryImpl(
        sources: const NoSources(),
        library: library,
        root: root,
      ),
    );
    // History builds its own controller from these; Library and Updates
    // resolve theirs with `Get.find`, so those have to be registered too.
    Get.put<LibraryRepository>(library);
    Get.put<SourceRepository>(const NoSources());
    Get.put<LibraryController>(
      LibraryController(library: library, sources: const NoSources()),
    );
    Get.put<UpdatesController>(
      UpdatesController(library: library, sources: const NoSources()),
    );
    // Every AniList lookup answers "nothing", which is also the path a first
    // launch with no network takes — and the one that renders the empty state.
    Get.put<HomeController>(
      HomeController(anilist: _NoAniList(), library: library, nsfw: nsfw),
    );
    // The details screen builds its own controller from these four.
    Get.put<AniListMetadataService>(
      AniListMetadataService(anilist: _NoAniList()),
    );
    // Settings reads this for its Accounts row. Unconfigured and never
    // restored, which is a first launch on a fresh clone — the state every
    // other suite here would silently fail to notice, because a screen that
    // calls `Get.find` for something nobody registered throws at *build*.
    Get.put<AniListAuth>(AniListAuth(storage: FakeVault(), clientId: ''));
  });

  tearDown(() {
    // Disposes the controllers, which cancels `LibraryController`'s 300ms
    // change debounce. Left running it outlives the widget tree and the test
    // fails with "a Timer is still pending" rather than on anything real.
    Get.reset();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Widget wrap(Widget child) => MediaQuery(
    data: const MediaQueryData(size: Size(400, 800)),
    child: MaterialApp(home: child),
  );

  /// Every screen converted to [OneUiScaffold]. Rendering each one is the
  /// assertion: a box widget in a sliver slot throws during layout, so a clean
  /// pump *is* the proof that the sliver contract holds on that screen.
  final screens = <String, Widget Function()>{
    'Settings': () => const SettingsScreen(),
    'More': () => const MoreScreen(),
    'About': () => const AboutScreen(),
    'Downloads': () => const DownloadsScreen(),
  };

  for (final entry in screens.entries) {
    testWidgets('${entry.key} renders inside a CustomScrollView', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entry.value()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.byType(CustomScrollView),
        findsOneWidget,
        reason: 'the collapsing header is what makes it One UI',
      );
      // The title is rendered twice while the header is expanded — once in the
      // bar and once in the large title — so this asserts presence, not count.
      expect(find.text(entry.key), findsWidgets);
    });

    testWidgets('${entry.key} survives being scrolled', (tester) async {
      // A sliver that reports the wrong extent lays out fine at rest and
      // throws once it is scrolled, so the drag is the assertion.
      //
      // Deliberately *not* claiming the header collapses here. On a screen
      // whose rows fit the viewport `maxScrollExtent` is 0 and nothing moves,
      // so a drag-then-expect-no-exception passes without testing anything —
      // the collapse itself is pinned below, on content built to be long
      // enough to have somewhere to scroll to.
      await tester.pumpWidget(wrap(entry.value()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }

  Widget rows(int n) => OneUiScaffold(
    title: 'T',
    slivers: [
      SliverOneUiGroup(
        children: [for (var i = 0; i < n; i++) ListTile(title: Text('r$i'))],
      ),
    ],
  );

  testWidgets('a long screen collapses its header when scrolled', (
    tester,
  ) async {
    // Measured on the *large* title, not on the content. A drag scrolls a long
    // list whether or not there is a header at all, so asserting that rows
    // moved proves nothing about the collapse — it passes with
    // `expandedHeight` set to zero. The large title is the header: at rest it
    // sits low in the expanded bar, and collapsing is it sliding up out of
    // view.
    await tester.pumpWidget(wrap(rows(30)));
    await tester.pumpAndSettle();

    final large = find.text('T').first;
    final before = tester.getTopLeft(large).dy;
    expect(
      before,
      greaterThan(40),
      reason: 'the expanded title starts below the collapsed bar',
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(large).dy,
      lessThan(before - 40),
      reason: 'the large title rose into the bar, which is the collapse',
    );
  });

  testWidgets('a short screen keeps its header expanded', (tester) async {
    // There is nothing to scroll to on four rows, so the large title stays put
    // — One UI's own behaviour, not a shortfall. Pinned so the claim in
    // `OneUiScaffold`'s doc cannot quietly stop being true.
    await tester.pumpWidget(wrap(rows(4)));
    await tester.pumpAndSettle();

    final large = find.text('T').first;
    final before = tester.getTopLeft(large).dy;
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.maxScrollExtent, 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(large).dy, before);
  });

  // The three list tabs, converted in the same pass. Each has three states
  // behind one `Obx` — loading, empty, populated — and every one of them has
  // to be a sliver. The empty state is the one a fresh install sees and the
  // one most likely to be written as a bare box.
  final tabs = <String, Widget Function()>{
    'Library': () => const LibraryScreen(),
    'Updates': () => const UpdatesScreen(),
    'History': () => const HistoryScreen(),
    'Home': () => const HomeScreen(),
  };

  for (final entry in tabs.entries) {
    testWidgets('${entry.key} renders its empty state as a sliver', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entry.value()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.text(entry.key), findsWidgets);
    });

    testWidgets('${entry.key} survives being scrolled while empty', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entry.value()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the Library grid renders rows through a sliver grid', (
    tester,
  ) async {
    // The populated branch. `SliverGrid` replaced a `GridView` that carried
    // its own scroll view, so getting this wrong nests two scrollables rather
    // than failing loudly.
    for (var i = 1; i <= 4; i++) {
      await library.upsertFromSource(
        sourceId: 7,
        url: '/m-$i',
        manga: MManga(
          name: 'Series $i',
          chapters: [MChapter(url: '/c-1')],
        ),
      );
      await library.toggleFavorite(7, '/m-$i');
    }

    // Rebuilt here, after seeding, and deliberately not driven through the
    // change stream. The controller from `setUp` is created outside
    // `testWidgets`' fake-async zone, so its 300ms debounce timer never fires
    // under the test clock however far the clock is advanced — a reload that
    // never happens would look exactly like a grid that fails to render.
    //
    // The notification path itself is covered where it belongs, by
    // `library_controller_test.dart`'s "a favourite added elsewhere reaches
    // the grid without a reselect". What this test is for is the sliver grid.
    await Get.delete<LibraryController>();
    Get.put<LibraryController>(
      LibraryController(library: library, sources: const NoSources()),
    );

    await tester.pumpWidget(wrap(const LibraryScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.text('Series 1'), findsOneWidget);
    expect(
      find.textContaining('Your library is empty'),
      findsNothing,
      reason: 'the populated branch replaced the empty one',
    );
  });

  testWidgets('Home renders the Continue Reading carousel', (tester) async {
    // The populated branch. Shelves are AniList-driven and answer nothing
    // here, but Continue Reading is local — it is the part of Home that still
    // works with no network, and the part a fresh-install-only test misses.
    for (var i = 1; i <= 3; i++) {
      await library.upsertFromSource(
        sourceId: 7,
        url: '/m-$i',
        manga: MManga(
          name: 'Series $i',
          chapters: [
            MChapter(url: '/c-1'),
            MChapter(url: '/c-2'),
          ],
        ),
      );
      await library.toggleFavorite(7, '/m-$i');
      // Continue Reading means *started*, not merely favourited — it filters
      // on `lastRead != null` with unread chapters left. Reading the first of
      // two is exactly that state, and favouriting alone would render nothing.
      await library.setChapterRead(7, '/m-$i', '/c-1', true);
    }

    // Built here, after seeding, for the same reason as the Library grid: a
    // controller constructed in `setUp` lives outside the fake-async zone.
    await Get.delete<HomeController>();
    Get.put<HomeController>(
      HomeController(anilist: _NoAniList(), library: library, nsfw: nsfw),
    );

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Continue reading'), findsOneWidget);
    expect(find.text('Series 1'), findsOneWidget);
  });

  testWidgets('Home renders an AniList shelf as its own sliver', (
    tester,
  ) async {
    // The shelf branch, which every other Home test leaves unrendered because
    // `_NoAniList` answers nothing. Without this, deleting the
    // `SliverToBoxAdapter` around `_Shelf` changes no test and analyze stays
    // clean — the shelves are exactly the content Home exists to show.
    await Get.delete<HomeController>();
    Get.put<HomeController>(
      HomeController(anilist: _OneShelf(), library: library, nsfw: nsfw),
    );

    await tester.pumpWidget(wrap(const HomeScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Trending now'), findsOneWidget);
    expect(find.text('Example Manga'), findsOneWidget);
  });

  testWidgets('a slow earlier Home load cannot overwrite a newer one', (
    tester,
  ) async {
    // Two callers can overlap: pull-to-refresh and the error banner's retry —
    // and the banner is on screen precisely when a previous load failed, so
    // tapping retry and then pulling is an ordinary thing to do.
    //
    // This PR widened the window rather than inventing it. Before, the loading
    // branch was a bare spinner with no `RefreshIndicator` above it, so a pull
    // during the first load was impossible; the scaffold's refresh now wraps
    // every branch, that one included.
    final anilist = _GatedShelves();
    await Get.delete<HomeController>();
    final c = HomeController(anilist: anilist, library: library, nsfw: nsfw);

    // Load 0 will answer 'Trending now', slowly.
    anilist.answer(0, 'trending', delay: true);
    final stale = c.load();
    // Load 1 answers 'Top rated' immediately.
    anilist.answer(1, 'topRated', delay: false);
    await c.load();
    expect(c.shelves.single.title, 'Top rated');

    // Now let the older one land. It must not win, and it must not clear the
    // spinner out from under a load that is still running.
    anilist.release();
    await stale;

    expect(
      c.shelves.single.title,
      'Top rated',
      reason: 'the stale load finished last and was discarded',
    );
  });

  testWidgets('the details screen renders its sliver body', (tester) async {
    // The largest screen in the app, and until this pass rendered by no test
    // at all. It is already sliver-based, so nothing here converted it; what
    // this guards is that its `CustomScrollView` still lays out.
    //
    // `NoSources` cannot resolve a source, so this takes the *error* branch —
    // a box widget returned from the same `Obx` that otherwise returns
    // slivers, which is exactly the shape that throws in the wrong slot. It
    // deliberately does **not** cover the AniList sections; the test below
    // does that, because this one structurally cannot.
    await tester.pumpWidget(
      wrap(const MangaDetailsScreen(sourceId: 7, url: '/m')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the AniList sections render at the shared radius', (
    tester,
  ) async {
    // The test that actually covers this PR's change. The one above uses
    // `NoSources`, so the load fails and `anilist_sections.dart` — the file
    // whose radii were retokenised — never builds at all. Found by
    // `codeant-ai`, and it is the fifth time in this pass that a branch turned
    // out unexercised, this time in the test written to close the fourth.
    await Get.delete<SourceRepository>();
    Get.put<SourceRepository>(_OneSource());

    await tester.pumpWidget(
      wrap(const MangaDetailsScreen(sourceId: 7, url: '/m')),
    );
    await tester.pumpAndSettle();

    // Metadata is set on the live controller rather than faked through the
    // service: what is under test is the rendering, and the resolve path has
    // its own suite.
    final c = Get.find<MangaDetailsController>(tag: 'details-7-/m');
    c.anilist.value = const AniListMedia(
      id: 1,
      titles: AniListTitles(userPreferred: 'Example'),
      chapters: 12,
      volumes: 3,
      characters: [AniListPerson(id: 1, name: 'A Character', role: 'MAIN')],
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('A Character'), findsOneWidget);
    expect(find.text('Chapters'), findsOneWidget);

    // The radius is the change. Asserting the sections merely *appear* would
    // pass with every literal still in place.
    final radii = tester
        .widgetList<ClipRRect>(find.byType(ClipRRect))
        .map((c) => c.borderRadius)
        .whereType<BorderRadius>()
        .map((b) => b.topLeft.x)
        .toSet();
    expect(
      radii,
      contains(OneUi.radiusSmall),
      reason: 'the portraits draw from the token, not from a literal 8',
    );
  });

  // A plain `test`, not `testWidgets`: this drives the controller, and
  // `onInit`'s real Isar reads never complete inside the fake-async zone a
  // widget test installs — the first version of this hung for ten minutes
  // rather than failing on anything real.
  test('flipping the 18+ preference re-filters the home shelves', () async {
    // Issue #31. The shelves are filtered when they are *built*, so flipping
    // the preference could not change shelves that already existed — the home
    // page went on showing adult titles until the app restarted.
    //
    // Asserting only that `showNsfw` changed would pass with the re-filter
    // missing, which is the whole reason the bug survived: the flag was always
    // correct, the shelves were not. This asserts the shelves.
    nsfw.setShown(true);
    await Get.delete<HomeController>();
    final c = HomeController(
      anilist: _AdultShelf(),
      library: library,
      nsfw: nsfw,
    )..onInit();
    for (var i = 0; i < 50 && c.shelves.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.shelves.single.items, hasLength(2));

    nsfw.setShown(false);
    await Future<void>.delayed(Duration.zero);

    expect(c.shelves.single.items.map((m) => m.titles.userPreferred), [
      'Safe',
    ], reason: 'the adult entry left the shelf without another AniList call');

    nsfw.setShown(true);
    await Future<void>.delayed(Duration.zero);
    expect(
      c.shelves.single.items,
      hasLength(2),
      reason: 'and comes back, from the retained payload',
    );
    c.onClose();
  });

  testWidgets('the Settings switch writes the shared preference', (
    tester,
  ) async {
    // Half of issue #31's chain, and the half a unit test cannot reach: the
    // switch must write the *shared* holder rather than the key directly or a
    // copy of its own. The other half — Home re-filtering when that holder
    // changes — is the test below.
    //
    // Deliberately no `HomeController` here. Driving one through `onInit`
    // inside a widget test hangs on real Isar reads that never complete in the
    // fake-async zone; that is a known trap in this repo, not a thing to
    // rediscover by waiting ten minutes for a timeout.
    nsfw.setShown(true);

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();

    expect(
      nsfw.shown.value,
      isFalse,
      reason: 'the switch wrote the holder every other screen observes',
    );
  });

  testWidgets('a group renders its label above the rows, not inside them', (
    tester,
  ) async {
    // The label sitting outside the rounded container is what separates a One
    // UI group from a Material section header, so it is worth pinning.
    await tester.pumpWidget(
      wrap(
        const OneUiScaffold(
          title: 'T',
          slivers: [
            SliverOneUiGroup(
              label: 'Group',
              children: [ListTile(title: Text('Row'))],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final label = tester.getTopLeft(find.text('Group'));
    final row = tester.getTopLeft(find.text('Row'));
    expect(label.dy, lessThan(row.dy));
    expect(
      find.byType(ClipRRect),
      findsWidgets,
      reason: 'the rows are clipped to the group radius',
    );
  });

  testWidgets('an empty group renders nothing at all', (tester) async {
    // Not an empty rounded box: a group whose rows are all conditional is a
    // real case, and an empty container reads as a rendering bug.
    await tester.pumpWidget(
      wrap(
        const OneUiScaffold(
          title: 'T',
          slivers: [SliverOneUiGroup(label: 'Group', children: [])],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Group'), findsNothing);
  });

  testWidgets('Settings keeps every control it had before the restyle', (
    tester,
  ) async {
    // The restyle must not lose a setting. A screen that reads better and does
    // less is a regression, so this names the controls rather than counting
    // them.
    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    for (final label in [
      'Theme',
      'Pure black dark theme',
      'Colour source',
      'Tint from the cover',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    for (final label in [
      'Reading layout',
      'Reading direction',
      'Keep the screen on',
      'Show the page number',
      'Show 18+ sources',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('Downloads shows its empty state through the sliver list', (
    tester,
  ) async {
    // The task list is an `Obx` in a sliver slot, which is legal only because
    // it returns a sliver on *both* branches. The empty branch is the one a
    // fresh install hits, and it is a different widget from the populated one.
    await tester.pumpWidget(wrap(const DownloadsScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Nothing downloading'), findsOneWidget);
  });

  testWidgets('pull-to-refresh fires on a Downloads list that fits', (
    tester,
  ) async {
    // Pins the user-facing behaviour — a fresh install's empty queue can still
    // be pulled to re-measure — not the line that makes it work. This passes
    // with `OneUiScaffold`'s `AlwaysScrollableScrollPhysics` deleted, so it is
    // not a guard on that; the comment there says why the line stays anyway.
    final queue = _FixedQueue([]);
    await Get.delete<DownloadRepository>();
    Get.put<DownloadRepository>(queue);

    await tester.pumpWidget(wrap(const DownloadsScreen()));
    await tester.pumpAndSettle();
    final onOpen = queue.usageScans;
    expect(onOpen, greaterThan(0), reason: 'measured once on open');

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 300),
      800,
    );
    await tester.pumpAndSettle();

    expect(
      queue.usageScans,
      greaterThan(onOpen),
      reason: 'the pull reached the indicator and it re-measured',
    );
  });

  testWidgets('Downloads renders a queue through SliverList.builder', (
    tester,
  ) async {
    // The other branch, and the one that actually needs covering: the empty
    // state is a `SliverToBoxAdapter` while the queue is a
    // `SliverList.builder`, so a suite that only ever sees an empty repository
    // leaves the populated sliver — and every row widget in it — unrendered.
    //
    // Served from a fixed list rather than by running real downloads. Driving
    // the real queue here means real file I/O inside `testWidgets`' fake-async
    // zone, which hangs rather than failing; and a task still queued draws an
    // indeterminate progress bar, so `pumpAndSettle` would never settle. What
    // is under test is the sliver and the rows, not the queue — that has its
    // own suite.
    await Get.delete<DownloadRepository>();
    Get.put<DownloadRepository>(
      _FixedQueue([
        _task('Chapter 1', DownloadState.running, downloaded: 3, total: 10),
        _task('Chapter 2', DownloadState.done, downloaded: 8, total: 8),
        _task('Chapter 3', DownloadState.failed, error: 'the site refused'),
      ]),
    );

    await tester.pumpWidget(wrap(const DownloadsScreen()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SliverList), findsOneWidget);
    expect(find.text('Example'), findsNWidgets(3));
    expect(find.textContaining('Nothing downloading'), findsNothing);
    // Each state renders a different trailing control, and a running task is
    // the only one that offers a cancel.
    expect(find.textContaining('3 of 10 pages'), findsOneWidget);
    expect(find.textContaining('saved'), findsOneWidget);
    expect(find.textContaining('the site refused'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);
  });
  testWidgets('a slow earlier usage scan cannot overwrite a newer one', (
    tester,
  ) async {
    // `onInit` starts a scan without awaiting it and a pull starts another, so
    // two walks of the download directory can be in flight at once. Last
    // writer wins, and the loser is whichever finishes second — which may be
    // the *older* one, leaving the header showing a figure from before the
    // download that prompted the pull.
    final queue = _SlowQueue();
    // No `onInit` and no Get registration: `onInit` would fire a scan of its
    // own and shift every call index, and the watch it sets up is not what is
    // under test.
    final controller = DownloadsController(downloads: queue);

    // Scan 0 will answer 1 MB, but only once released.
    queue.answer(0, 1024 * 1024);
    final stale = controller.refreshUsage();
    // Scan 1 answers 5 MB straight away.
    queue.answer(1, 5 * 1024 * 1024, delay: false);
    await controller.refreshUsage();
    expect(controller.usedBytes.value, 5 * 1024 * 1024);

    // Now let the older one land. It must not win.
    queue.release();
    await stale;

    expect(
      controller.usedBytes.value,
      5 * 1024 * 1024,
      reason: 'the stale scan finished last and was discarded',
    );
  });
}

DownloadTask _task(
  String label,
  DownloadState state, {
  int downloaded = 0,
  int total = 0,
  String? error,
}) => DownloadTask(
  sourceId: 7,
  mangaUrl: '/m',
  chapterUrl: '/$label',
  title: 'Example',
  chapterLabel: label,
  state: state,
  downloaded: downloaded,
  total: total,
  error: error,
);

/// A queue that is simply a list. Enough to render the screen; the real
/// queue's behaviour belongs to `download_repository_test.dart`.
class _FixedQueue implements DownloadRepository {
  _FixedQueue(this.tasks);

  @override
  final List<DownloadTask> tasks;

  /// How many times the screen has asked for a fresh measurement.
  int usageScans = 0;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<int> usedBytes() async {
    usageScans++;
    return 1024 * 1024;
  }

  @override
  Future<void> enqueue({
    required int sourceId,
    required String mangaUrl,
    required Chapter chapter,
    required String mangaTitle,
  }) async {}

  @override
  Future<void> cancel(String key) async {}

  @override
  Future<void> deleteChapter({
    required int sourceId,
    required String mangaUrl,
    required String chapterUrl,
  }) async {}

  @override
  void clearFinished() {}
}

/// A queue whose `usedBytes` can be made to answer out of order.
class _SlowQueue extends _FixedQueue {
  _SlowQueue() : super([]);

  final _held = <Completer<void>>[];
  final _answers = <int, int>{};
  var _call = 0;

  void answer(int call, int bytes, {bool delay = true}) {
    _answers[call] = bytes;
    if (delay) _slow.add(call);
  }

  final _slow = <int>{};

  void release() {
    for (final c in _held) {
      if (!c.isCompleted) c.complete();
    }
    _held.clear();
  }

  @override
  Future<int> usedBytes() async {
    final call = _call++;
    usageScans++;
    if (_slow.contains(call)) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    return _answers[call] ?? 0;
  }
}

/// Every AniList lookup answers "nothing". The home shelves are AniList-driven
/// and this suite is about the chrome, not the shelves.
class _NoAniList implements AniListRepository {
  @override
  Future<AniListMedia?> media(int id) async => null;
  @override
  Future<TitleMatch?> match(String title) async => null;
  @override
  Future<List<TitleMatch>> searchCandidates(String title) async => const [];
  @override
  Future<Map<String, List<AniListMedia>>> home({int perPage = 20}) async =>
      const {};
}

/// One populated shelf, so the shelf sliver is actually built.
class _OneShelf extends _NoAniList {
  @override
  Future<Map<String, List<AniListMedia>>> home({int perPage = 20}) async => {
    'trending': [
      const AniListMedia(
        id: 1,
        titles: AniListTitles(userPreferred: 'Example Manga'),
      ),
    ],
  };
}

/// AniList whose `home()` can be made to answer out of order.
class _GatedShelves extends _NoAniList {
  final _held = <Completer<void>>[];
  final _answers = <int, String>{};
  final _slow = <int>{};
  var _call = 0;

  void answer(int call, String shelfKey, {required bool delay}) {
    _answers[call] = shelfKey;
    if (delay) _slow.add(call);
  }

  void release() {
    for (final c in _held) {
      if (!c.isCompleted) c.complete();
    }
    _held.clear();
  }

  @override
  Future<Map<String, List<AniListMedia>>> home({int perPage = 20}) async {
    final call = _call++;
    if (_slow.contains(call)) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    final key = _answers[call];
    if (key == null) return const {};
    return {
      key: [
        const AniListMedia(id: 1, titles: AniListTitles(userPreferred: 'M')),
      ],
    };
  }
}

/// A source that actually resolves, so the details screen reaches its loaded
/// state instead of its error branch.
class _OneSource implements SourceRepository {
  static final _row = Source()
    ..id = 7
    ..name = 'Example Source'
    ..baseUrl = 'https://example.test';

  @override
  Future<SourceMethods> methodsFor(int id) async => _OneMethods();
  @override
  Future<Source?> sourceById(int id) async => _row;
  @override
  Future<void> markUsed(int id) async {}
  @override
  void evict(int id) {}
  @override
  void evictAll() {}
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OneMethods implements SourceMethods {
  @override
  Source get source => _OneSource._row;
  @override
  String get sourceBaseUrl => 'https://example.test';
  @override
  bool get supportsLatest => true;
  @override
  Map<String, String> getHeaders() => const {};
  @override
  Future<MManga> getDetail(String url) async => MManga(
    name: 'Example',
    description: 'A description.',
    chapters: [MChapter(url: '/c-1', name: 'Chapter 1')],
  );
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

/// One shelf holding one adult title and one safe one.
class _AdultShelf extends _NoAniList {
  @override
  Future<Map<String, List<AniListMedia>>> home({int perPage = 20}) async => {
    'trending': [
      const AniListMedia(id: 1, titles: AniListTitles(userPreferred: 'Safe')),
      const AniListMedia(
        id: 2,
        titles: AniListTitles(userPreferred: 'Adult'),
        isAdult: true,
      ),
    ],
  };
}
