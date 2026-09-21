import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/data/anilist/anilist_metadata_service.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/domain/repository/anilist_repository.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/features/reader/screen_wakelock.dart';
import 'package:otaku_reader/features/reader/screens/reader_screen.dart';
import 'package:otaku_reader/features/reader/widgets/reader_page_indicator.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/source_methods.dart';

import 'helpers/anilist_fakes.dart';
import 'helpers/isar_test_env.dart';

const _sourceId = 11;
const _manga = '/manga/example';

Source _row() => Source()
  ..sourceId = _sourceId
  ..name = 'Example Source'
  ..lang = 'en'
  ..sourceCode = 'X';

/// Pages are deliberately **not** `http` urls.
///
/// `_Page` routes anything that is not to `Image.file`, which fails to its own
/// placeholder and touches nothing outside the process. The
/// `CachedNetworkImage` branch reaches a cache manager that wants
/// `path_provider`, which a host VM does not have — so a test using real urls
/// would fail on the plumbing rather than on what it asserts.
List<PageUrl> _pages(int n) => [
  for (var i = 0; i < n; i++) PageUrl('/nowhere/$i.jpg'),
];

class _Methods implements SourceMethods {
  _Methods(this.source);

  @override
  final Source source;

  @override
  Future<List<PageUrl>> getPageList(String url) async => _pages(3);

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
  final _methods = _Methods(_row());

  @override
  Future<SourceMethods> methodsFor(int id) async => _methods;
  @override
  Future<Source?> sourceById(int id) async => _row();
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

/// Answers nothing. The reader only reaches AniList to *report* progress, and
/// the auth below is signed out, so nothing here is ever called.
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

class _FakeWakelock implements ScreenWakelock {
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

void main() {
  IsarTestEnv? env;

  setUpAll(
    () async => env = await IsarTestEnv.open(
      'reader-screen',
      db.AppDatabaseSchemas.all,
    ),
  );
  tearDownAll(() async => env?.close());

  late LibraryRepository library;

  setUp(() async {
    env!.clear();
    Get.reset();
    library = LibraryRepositoryImpl();
    await library.upsertFromSource(
      sourceId: _sourceId,
      url: _manga,
      manga: MManga(
        name: 'Example',
        chapters: [MChapter(url: '/c-1', name: 'Chapter 1')],
      ),
    );
    Get.put<SourceRepository>(_Sources());
    Get.put<LibraryRepository>(library);
    Get.put<AniListListService>(
      AniListListService(AniListAuth(storage: FakeVault())),
    );
    Get.put<AniListMetadataService>(
      AniListMetadataService(anilist: _NoAniList()),
    );
    Get.put<ScreenWakelock>(_FakeWakelock());
  });

  tearDown(Get.reset);

  Future<void> openReader(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReaderScreen(
          sourceId: _sourceId,
          mangaUrl: _manga,
          chapterUrl: '/c-1',
        ),
      ),
    );
    // The load reads the library row and may touch disk, so the number of turns
    // is not fixed. Pump until the pages arrive rather than counting frames.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(ReaderPageIndicator).evaluate().isNotEmpty) break;
    }
    // Past the pill's 300ms fade, so opacity is settled either way.
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// What the user actually meets: a faded-out pill is still in the tree.
  double indicatorOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(ReaderPageIndicator),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('the pill shows the page while the chrome is hidden', (
    tester,
  ) async {
    ReaderKeys.showPageIndicator.set<bool>(true);
    await openReader(tester);

    // The reader opens with its chrome up; tap the page to hide it.
    await tester.tap(find.byType(PageView));
    await tester.pump(const Duration(milliseconds: 400));

    expect(indicatorOpacity(tester), 1);
    expect(
      find.descendant(
        of: find.byType(ReaderPageIndicator),
        matching: find.text('1 / 3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('with the setting off there is no pill at all', (tester) async {
    // The default, and the state every existing install is in.
    await openReader(tester);
    await tester.tap(find.byType(PageView));
    await tester.pump(const Duration(milliseconds: 400));

    expect(indicatorOpacity(tester), 0);
  });

  testWidgets('the chrome carries the number, so the pill stands down', (
    tester,
  ) async {
    ReaderKeys.showPageIndicator.set<bool>(true);
    await openReader(tester);

    // Two counters exist in the tree: the chrome's, and the pill's — which is
    // mounted whatever the setting says, so that it can fade rather than pop.
    // The point is that only one of them is on screen.
    expect(
      find.text('1 / 3'),
      findsNWidgets(2),
      reason: "the chrome's counter and the faded-out pill",
    );
    expect(
      find.descendant(
        of: find.byType(ReaderPageIndicator),
        matching: find.text('1 / 3'),
      ),
      findsOneWidget,
    );
    expect(indicatorOpacity(tester), 0);
  });

  testWidgets('the pill follows the page', (tester) async {
    ReaderKeys.showPageIndicator.set<bool>(true);
    await openReader(tester);
    await tester.tap(find.byType(PageView));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ReaderPageIndicator),
        matching: find.text('2 / 3'),
      ),
      findsOneWidget,
    );
  });

  group('the pill on its own', () {
    Future<void> pump(
      WidgetTester tester, {
      required double width,
      double textScale = 1,
      bool visible = true,
      int page = 0,
      int total = 3,
      VoidCallback? onTapBehind,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onTapBehind ?? () {},
                    child: const SizedBox.expand(),
                  ),
                  Center(
                    child: ReaderPageIndicator(
                      page: page,
                      total: total,
                      visible: visible,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    // 320 / 360 / 384 because a layout test at one width proves one width, and
    // this project has already shipped a row that fit at 411 and overflowed on
    // a Pixel. The long count is the realistic worst case: MangaRead.org's
    // longest series runs to four digits of chapters, and a webtoon strip can
    // be hundreds of pages.
    for (final width in [320.0, 360.0, 384.0]) {
      testWidgets('fits at ${width.toInt()}px with a doubled system font', (
        tester,
      ) async {
        await pump(tester, width: width, textScale: 2, page: 998, total: 1200);

        expect(tester.takeException(), isNull);
        // getRect, not getSize: post-transform is the only number a finger or
        // an eye meets.
        final rect = tester.getRect(find.byType(ReaderPageIndicator));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
      });
    }

    // The reader's one gesture is tap-to-toggle-the-chrome, and this pill sits
    // over the top-middle of the page. Either state would be a dead spot: a
    // faded-out pill is one with nothing drawn in it, and a visible one is one
    // right under the number the user is watching. Both, because the guard is
    // a single `IgnorePointer` and a version that only covered `!visible` is
    // the one that suggests itself.
    for (final visible in [true, false]) {
      testWidgets('a ${visible ? 'visible' : 'hidden'} pill lets the tap '
          'through to the page', (tester) async {
        var tapsBehind = 0;
        await pump(
          tester,
          width: 360,
          visible: visible,
          onTapBehind: () => tapsBehind++,
        );

        await tester.tap(find.byType(ReaderPageIndicator), warnIfMissed: false);
        await tester.pump();

        expect(tapsBehind, 1);
      });
    }
  });

  group('the reader reads along the direction it was given', () {
    // The controller tests prove the stored value reaches the controller. They
    // say nothing about whether anything on screen moved, and that gap is this
    // repo's most-repeated defect -- a key that round-trips perfectly while no
    // widget reads it is exactly what shipped as two dead Settings switches.
    // So these assert the laid-out scroll view.

    Future<void> openWith(
      WidgetTester tester, {
      required ReadingLayout layout,
      required ReadingDirection direction,
    }) async {
      ReaderKeys.readingLayout.set<int>(layout.index);
      ReaderKeys.readingDirection.set<int>(direction.index);
      ReaderKeys.webtoonDirection.set<int>(direction.index);
      await openReader(tester);
    }

    for (final direction in ReadingDirection.values) {
      testWidgets('paged lays out ${direction.name}', (tester) async {
        await openWith(
          tester,
          layout: ReadingLayout.paged,
          direction: direction,
        );

        final view = tester.widget<PageView>(find.byType(PageView));
        expect(view.scrollDirection, direction.axis, reason: direction.name);
        expect(view.reverse, direction.reversed, reason: direction.name);
      });

      testWidgets('continuous lays out ${direction.name}', (tester) async {
        await openWith(
          tester,
          layout: ReadingLayout.webtoon,
          direction: direction,
        );

        final view = tester.widget<ListView>(find.byType(ListView));
        expect(view.scrollDirection, direction.axis, reason: direction.name);
        expect(view.reverse, direction.reversed, reason: direction.name);
      });
    }

    /// The constraints the first page is handed inside the strip.
    ///
    /// Constraints rather than a painted rect, and that is not a stylistic
    /// choice. `_Page` is private, so the image it builds is the handle — and
    /// under `flutter test` that image never resolves, so every page lays out
    /// at zero extent and the finder reports it **offstage**. A rect would be
    /// measuring the harness. What the viewport hands down is the thing the
    /// pin actually changes, and it is true whether or not a byte ever loads.
    BoxConstraints firstPageConstraints(WidgetTester tester) => tester
        .renderObject<RenderBox>(
          find
              .descendant(
                of: find.byType(ListView),
                // `skipOffstage: false` on **both**. `find.descendant`
                // filters by its own flag, which defaults to true, so setting
                // it on the inner finder alone changes nothing and the match
                // comes back empty -- which reads exactly like the page not
                // being there.
                matching: find.byType(Image, skipOffstage: false),
                skipOffstage: false,
              )
              .first,
        )
        .constraints;

    for (final width in [320.0, 411.0]) {
      testWidgets('a horizontal strip pins each page to the $width viewport', (
        tester,
      ) async {
        // Turned on its side, a page has an unbounded *main* axis, and an
        // image with one falls back to its intrinsic width — whatever the scan
        // was encoded at, which has nothing to do with the screen. Nothing
        // throws either way, which is why this is asserted rather than
        // assumed.
        //
        // Two widths, because a pin hardcoded to one phone satisfies a single
        // sample, and that is the fix that suggests itself.
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await openWith(
          tester,
          layout: ReadingLayout.webtoon,
          direction: ReadingDirection.leftToRight,
        );

        final constraints = firstPageConstraints(tester);
        expect(constraints.maxWidth, width, reason: 'pinned to the viewport');
        expect(constraints.minWidth, width, reason: 'tightly, not loosely');
      });
    }

    testWidgets('a vertical strip leaves each page its own main axis', (
      tester,
    ) async {
      // The other half, and the one that catches an over-eager fix: pinning
      // the *cross* axis is a no-op in a vertical list, so only the main axis
      // can tell the two apart. A page given the viewport's height here would
      // be a paged reader wearing a ListView, and the width assertions above
      // cannot see that.
      await tester.binding.setSurfaceSize(const Size(360, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openWith(
        tester,
        layout: ReadingLayout.webtoon,
        direction: ReadingDirection.topToBottom,
      );

      final constraints = firstPageConstraints(tester);
      expect(constraints.maxWidth, 360, reason: 'the cross axis is the screen');
      expect(
        constraints.maxHeight,
        double.infinity,
        reason: 'the main axis belongs to the page, not the screen',
      );
    });

    testWidgets('the quick control edits the layout on screen, not the other', (
      tester,
    ) async {
      // The reader's direction button used to be paged-only and toggled two
      // values. It now cycles four and has to write whichever key the layout
      // in force reads -- a button that edited the paged key while a webtoon
      // was on screen would look completely inert.
      await openWith(
        tester,
        layout: ReadingLayout.webtoon,
        direction: ReadingDirection.topToBottom,
      );

      await tester.tap(find.byTooltip(ReadingDirection.topToBottom.label));
      await tester.pumpAndSettle();

      expect(
        ReaderKeys.webtoonDirection.get<int>(0),
        ReadingDirection.topToBottom.next.index,
      );
      expect(
        ReaderKeys.readingDirection.get<int>(0),
        ReadingDirection.topToBottom.index,
        reason: 'the paged direction is not what is on screen',
      );
    });
  });
}
