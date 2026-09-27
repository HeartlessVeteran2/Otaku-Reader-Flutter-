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
import 'package:otaku_reader/features/reader/display/eink_flash.dart';
import 'package:otaku_reader/features/reader/display/reader_display.dart';
import 'package:otaku_reader/features/reader/display/reader_display_layer.dart';
import 'package:otaku_reader/features/reader/display/reader_display_settings.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone_settings.dart';
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

import 'package:otaku_reader/features/reader/screen_controls.dart';

import 'helpers/screen_controls_fake.dart';
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

  /// How many pages this chapter has. Mutable so one test can ask for a
  /// chapter long enough that its later pages are genuinely off screen, which
  /// is the only state the position-restore guard is about.
  int pageCount = 3;

  @override
  Future<List<PageUrl>> getPageList(String url) async => _pages(pageCount);

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
  _Sources({int pageCount = 3}) {
    _methods.pageCount = pageCount;
  }

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
    Get.put<ReaderScreenControls>(FakeScreenControls());
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

  group('switching axis keeps the reader where it was', () {
    // `sourcery-ai` on #56, and it was right. `_rebuildForAxis` hands
    // continuous mode a fresh `ScrollController`, which starts at 0 — and a
    // `ListView` only builds the children near its current offset, so for any
    // page past the first screenful the target's `GlobalKey` has no context.
    // `Scrollable.ensureVisible` then had nothing to act on and the callback
    // returned silently: the reader sat at the top of the chapter, and the
    // scroll notification that followed overwrote the saved index with 0 —
    // which `_persist` wrote to disk. The place was lost for good, from a
    // change that looked like it only flipped an axis.
    //
    // **The rendered reproduction is not available here**, and that is
    // measured rather than assumed: a `_Page` has no extent under
    // `flutter test` because `Image.file` never reaches its `errorBuilder`,
    // even inside `runAsync`. Every page lays out at zero height, so every
    // page is always "built" and the state this guard is about cannot exist.
    // Faking extent would mean faking the thing under test. So the decision
    // is asserted where it is made.

    test('a layout change invalidates the scroll views, not only an axis one', () {
      // `codeant-ai`'s Major on #56, and it is the fix one case earlier in the
      // same file left un-applied to its neighbour. Paged and continuous keep
      // *separate* controllers, so switching between them at the same axis
      // rebuilt neither: the `PageView` kept its page while the strip kept an
      // offset from a different read, whichever was showing overwrote `page`,
      // and switching back showed the old page under the other one's counter.
      //
      // The rendered reproduction is blocked by the same measured limitation
      // as the walk below: with no page extent the strip never reports
      // anything, so the disagreement cannot arise here.
      expect(
        modeInvalidatesScroll(
          wasAxis: Axis.vertical,
          nowAxis: Axis.vertical,
          wasLayout: ReadingLayout.paged,
          nowLayout: ReadingLayout.webtoon,
        ),
        isTrue,
        reason: 'same axis, different layout',
      );
    });

    test('an axis change invalidates them too', () {
      // The half that already worked. Without it, dropping the axis clause
      // would satisfy the test above.
      expect(
        modeInvalidatesScroll(
          wasAxis: Axis.horizontal,
          nowAxis: Axis.vertical,
          wasLayout: ReadingLayout.webtoon,
          nowLayout: ReadingLayout.webtoon,
        ),
        isTrue,
        reason: 'same layout, different axis',
      );
    });

    testWidgets('a change of sign alone does not, and that is measured', (
      tester,
    ) async {
      // `codeant-ai` filed this as a correctness issue: that `reverse` puts
      // offset 0 at the opposite visual edge, so a retained controller at a
      // non-zero offset lands on a different logical page. It was right that
      // the claim had only ever been *asserted* -- `CLAUDE.md` stated it and
      // nothing checked it -- and right that the predicate takes no sign, so
      // the test that used to stand here passed two identical arguments and
      // could not have seen a sign change at all. That is a test whose name
      // claimed a rule it was structurally unable to test.
      //
      // Measured rather than argued, which is what the finding asked for:
      //
      //   PageView   before  page 3, offset 2400, page 3 on screen
      //              after   page 3, offset 2400, page 3 on screen
      //   ListView   before  offset 1000, row 10 top =   0
      //              after   offset 1000, row 10 top = 500
      //
      // A scroll offset is **content-relative**, not screen-relative: it
      // measures distance from the start of child 0 along the axis, and
      // `reverse` changes which screen edge that start is painted at, not
      // which child it is. So the logical position survives, and `_webtoonPage`
      // already accounts for the paint flip -- at these numbers its
      // `extent - (start + size)` gives 600 - (500 + 100) = 0, the same leading
      // offset the unreversed branch reads from `start`.
      //
      // Rebuilding on a sign change would therefore throw away a good position
      // for nothing, several times per cycle of the reader's four-way control.
      final pages = PageController();
      addTearDown(pages.dispose);
      Widget paged(bool reverse) => MaterialApp(
        home: PageView.builder(
          controller: pages,
          reverse: reverse,
          itemCount: 5,
          itemBuilder: (_, i) => Center(child: Text('page $i')),
        ),
      );

      await tester.pumpWidget(paged(false));
      pages.jumpToPage(3);
      await tester.pumpAndSettle();
      await tester.pumpWidget(paged(true));
      await tester.pumpAndSettle();

      expect(pages.page, 3, reason: 'the paged reader keeps its page');
      expect(find.text('page 3'), findsOneWidget);

      final strip = ScrollController();
      addTearDown(strip.dispose);
      Widget continuous(bool reverse) => MaterialApp(
        home: ListView.builder(
          controller: strip,
          reverse: reverse,
          itemCount: 20,
          itemBuilder: (_, i) => SizedBox(height: 100, child: Text('row $i')),
        ),
      );

      await tester.pumpWidget(continuous(false));
      strip.jumpTo(1000);
      await tester.pumpAndSettle();
      await tester.pumpWidget(continuous(true));
      await tester.pumpAndSettle();

      expect(strip.offset, 1000, reason: 'the strip keeps its offset');
      expect(
        find.text('row 10'),
        findsOneWidget,
        reason: 'and the offset still means the same child',
      );

      // The predicate agrees, which is the point: nothing about a sign change
      // reaches it, so nothing about a sign change rebuilds.
      expect(
        modeInvalidatesScroll(
          wasAxis: Axis.horizontal,
          nowAxis: Axis.horizontal,
          wasLayout: ReadingLayout.paged,
          nowLayout: ReadingLayout.paged,
        ),
        isFalse,
      );
    });

    test('a target that is not built yet means keep walking', () {
      // The mutation guard, and the bug in one line: the first version
      // answered `done` here, which is what left the reader at the top.
      expect(
        nextRestoreStep(
          targetIsBuilt: false,
          pixels: 0,
          maxScrollExtent: 8000,
          step: 0,
        ),
        RestoreStep.advance,
      );
    });

    test('a target on screen ends the walk', () {
      expect(
        nextRestoreStep(
          targetIsBuilt: true,
          pixels: 3200,
          maxScrollExtent: 8000,
          step: 7,
        ),
        RestoreStep.done,
      );
    });

    test('the end of the strip ends the walk', () {
      // A chapter that came back shorter than the one being read has no page
      // to reach. Without this the walk asks again every frame until the step
      // limit, scrolling nothing.
      expect(
        nextRestoreStep(
          targetIsBuilt: false,
          pixels: 8000,
          maxScrollExtent: 8000,
          step: 3,
        ),
        RestoreStep.done,
      );
    });

    test('the step budget ends the walk', () {
      // The other terminator. A walk with neither would be an unbounded
      // post-frame loop, which is a hang rather than a wrong answer.
      expect(
        nextRestoreStep(
          targetIsBuilt: false,
          pixels: 0,
          maxScrollExtent: 8000,
          step: 9,
          stepLimit: 9,
        ),
        RestoreStep.done,
      );
    });

    test('the walk terminates from any starting state', () {
      // Mechanism-independent: whatever the three inputs, following the walk
      // reaches `done`. A guard on each terminator individually still allows a
      // combination that loops, and a post-frame loop that never ends is the
      // one failure mode a reader cannot recover from.
      for (final extent in [0.0, 1.0, 8000.0]) {
        var pixels = 0.0;
        var step = 0;
        while (nextRestoreStep(
              targetIsBuilt: false,
              pixels: pixels,
              maxScrollExtent: extent,
              step: step,
              stepLimit: 20,
            ) ==
            RestoreStep.advance) {
          pixels = (pixels + 360).clamp(0.0, extent);
          step++;
          expect(step, lessThanOrEqualTo(20), reason: 'extent $extent');
        }
      }
    });
  });

  group('a tap lands in a zone', () {
    // The whole point of the feature, and the only thing that makes the model
    // more than a key nothing reads. Paged mode is used throughout because its
    // pages are viewport-sized whatever the image does, so a page turn is
    // observable here where a strip's position is not — see the harness note
    // above.

    Future<PageController> openPaged(
      WidgetTester tester, {
      required ReadingDirection direction,
      bool zones = true,
      bool mirror = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      ReaderKeys.readingLayout.set<int>(ReadingLayout.paged.index);
      ReaderKeys.readingDirection.set<int>(direction.index);
      TapZoneSettings.setEnabled(zones);
      TapZoneSettings.setMirrorWhenReversed(mirror);
      // Off, because a real channel call in a widget test is noise rather than
      // signal; the haptic is asserted separately through the setting.
      TapZoneSettings.setHaptics(false);
      await openReader(tester);
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      // Page 1 of 3, so there is somewhere to go in both directions without
      // falling off the chapter and into its neighbour.
      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      return controller;
    }

    /// Taps a fraction of the way across the screen and settles the animation.
    Future<void> tapAcross(WidgetTester tester, double fraction) async {
      await tester.tapAt(Offset(400 * fraction, 400));
      await tester.pumpAndSettle();
    }

    testWidgets('the leading third goes back and the trailing third goes on', (
      tester,
    ) async {
      final controller = await openPaged(
        tester,
        direction: ReadingDirection.leftToRight,
      );

      await tapAcross(tester, 0.1);
      expect(controller.page, 0, reason: 'the left third is previous');

      await tapAcross(tester, 0.9);
      await tapAcross(tester, 0.9);
      expect(controller.page, 2, reason: 'the right third is next');
    });

    testWidgets('reading right to left mirrors them', (tester) async {
      // **The correction AnymeX does not have**, and the reason this guard
      // exists at all. Its `_navNextPage`/`_navPrevPage` walk the page index
      // with no reference to `reversed`, so the same screen position fires the
      // same action whichever way the manga reads — and the leading side of a
      // right-to-left manga, which is most manga, goes backwards.
      //
      // Same tap as the test above, opposite answer.
      final controller = await openPaged(
        tester,
        direction: ReadingDirection.rightToLeft,
      );

      await tapAcross(tester, 0.1);
      expect(controller.page, 2, reason: 'the left third is now *next*');

      await tapAcross(tester, 0.9);
      await tapAcross(tester, 0.9);
      expect(controller.page, 0, reason: 'and the right third is previous');
    });

    testWidgets('unless the mirroring is switched off', (tester) async {
      // The other half, and it is what stops the mirror being unconditional.
      // Both preferences are real: mirror with the text, or keep the zones
      // where a thumb learned them.
      final controller = await openPaged(
        tester,
        direction: ReadingDirection.rightToLeft,
        mirror: false,
      );

      await tapAcross(tester, 0.1);
      expect(controller.page, 0, reason: 'physical sides, as authored');
    });

    testWidgets('the middle band toggles the chrome instead', (tester) async {
      final controller = await openPaged(
        tester,
        direction: ReadingDirection.leftToRight,
      );
      expect(find.byTooltip('Next chapter'), findsOneWidget);

      await tapAcross(tester, 0.5);

      expect(controller.page, 1, reason: 'the middle turns no page');
      expect(find.byTooltip('Next chapter'), findsNothing);
    });

    testWidgets('with zones off, any tap still toggles the chrome', (
      tester,
    ) async {
      // The switch turns the feature off, not the screen's only gesture. A
      // reader that stopped responding to taps entirely would read as broken,
      // and this is the behaviour the reader had before zones existed.
      final controller = await openPaged(
        tester,
        direction: ReadingDirection.leftToRight,
        zones: false,
      );

      await tapAcross(tester, 0.1);

      expect(controller.page, 1, reason: 'the edge turns no page');
      expect(find.byTooltip('Next chapter'), findsNothing);
    });
  });

  group('the display treatment reaches the reader', () {
    // These are the guards that count. Every assertion in
    // `reader_display_test.dart` builds a `ReaderDisplayLayer` **by hand**, so
    // between them they prove a filter filters -- and could not see that
    // nothing on any screen asks it to. That is the glow-slider row of the
    // mistakes table verbatim, and the rule it left behind: a setting is only
    // live if it changes a surface no test had to opt into. So these open the
    // reader exactly as the app does and read what is there.

    testWidgets('nothing is applied when every treatment is off', (
      tester,
    ) async {
      await openReader(tester);
      expect(
        find.descendant(
          of: find.byType(ReaderDisplayLayer),
          matching: find.byType(ColorFiltered),
        ),
        findsNothing,
      );
      expect(find.byType(ReaderDimVeil), findsNothing);
    });

    testWidgets('the stored tint reaches the page', (tester) async {
      ReaderDisplaySettings.setFilterEnabled(true);
      ReaderDisplaySettings.setFilterColor(0x80FF0000);
      ReaderDisplaySettings.setFilterBlend(ReaderBlend.multiply);

      await openReader(tester);

      final layer = tester.widget<ReaderDisplayLayer>(
        find.byType(ReaderDisplayLayer),
      );
      expect(layer.filter, const Color(0x80FF0000));
      expect(layer.blend, ReaderBlend.multiply);
    });

    testWidgets('greyscale and invert both reach the page at once', (
      tester,
    ) async {
      ReaderDisplaySettings.setGreyscale(true);
      ReaderDisplaySettings.setInvert(true);

      await openReader(tester);

      final layer = tester.widget<ReaderDisplayLayer>(
        find.byType(ReaderDisplayLayer),
      );
      expect(layer.greyscale, isTrue);
      expect(layer.invert, isTrue);
    });

    testWidgets('the dim is drawn over the page and under the chrome', (
      tester,
    ) async {
      ReaderDisplaySettings.setDimEnabled(true);
      ReaderDisplaySettings.setDim(40);

      await openReader(tester);

      expect(find.byType(ReaderDimVeil), findsOneWidget);
      expect(
        tester.widget<ReaderDimVeil>(find.byType(ReaderDimVeil)).percent,
        40,
      );

      // Placement, not merely presence. Dimming the controls along with the
      // artwork makes the one surface a reader reaches for when the page is too
      // bright the hardest thing on screen to read -- which is what AnymeX
      // does, stacking its overlay above everything it draws.
      final veil = find.byType(ReaderDimVeil);
      final indicator = find.byType(ReaderPageIndicator);
      final all = tester.allWidgets.toList();
      expect(
        all.indexOf(tester.widget(veil)),
        lessThan(all.indexOf(tester.widget(indicator))),
        reason: 'the veil is painted before the chrome, so it sits under it',
      );
    });

    testWidgets('the stored background reaches the scaffold', (tester) async {
      ReaderDisplaySettings.setBackground(ReaderBackground.white);

      await openReader(tester);

      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.white,
      );
    });
  });
  group('the e-ink flash on open', () {
    // `codeant-ai` filed this against the reader: "the flash is triggered when
    // asynchronous loading changes `page` from zero to a saved resume page, so
    // opening a resumed chapter flashes even though no page was turned."
    //
    // It does not happen, and the reason is worth pinning rather than
    // restating. Two things have to hold at once, and neither is local to
    // `EInkFlash`:
    //
    //   1. the body is gated on `isLoading && pages.isEmpty`, so nothing in
    //      the `Stack` -- `EInkFlash` included -- is mounted until the pages
    //      are there; and
    //   2. `load()` runs `pages.value = list` and `_afterPagesLoaded`, which
    //      sets `page.value`, in the **same synchronous turn**. Both `Rx`
    //      writes coalesce into one `Obx` rebuild, so `EInkFlash`'s first
    //      build already carries the resumed page -- and `didUpdateWidget`,
    //      which is the entire trigger, does not run on a first build.
    //
    // Put an `await` between those two writes and the finding becomes real,
    // which is exactly the mutation this test is written against. The existing
    // `eink_flash_test.dart` cases cannot see any of it: they construct the
    // widget by hand, so they test the mechanism and not whether the reader
    // ever asks it to fire.
    //
    // The flash duration is set to the controller's own ceiling -- it clamps
    // the stored value to 2000ms, so asking for more is a number that never
    // reaches the widget -- which is still far longer than the load. A flash
    // that fired during the load is therefore still painted when the assertion
    // looks, where sampling for it would make the guard depend on pump
    // granularity.
    Future<void> seedResume() => library.updateChapterProgress(
      sourceId: _sourceId,
      url: _manga,
      chapterUrl: '/c-1',
      lastPageRead: 2,
      totalPages: 3,
    );

    /// True while the flash is painting. Scoped to `EInkFlash`, because
    /// `MaterialApp` renders a transparent `ColoredBox` of its own and an
    /// unscoped finder would answer about the harness.
    bool flashing(WidgetTester tester) => find
        .descendant(
          of: find.byType(EInkFlash),
          matching: find.byType(ColoredBox),
        )
        .evaluate()
        .isNotEmpty;

    testWidgets('resuming mid-chapter does not flash', (tester) async {
      ReaderKeys.displayRefreshEnabled.set<bool>(true);
      ReaderKeys.displayRefreshDurationMs.set<int>(2000);
      await seedResume();

      await openReader(tester);

      expect(find.byType(EInkFlash), findsOneWidget);
      expect(tester.widget<EInkFlash>(find.byType(EInkFlash)).page, 2);
      expect(flashing(tester), isFalse);
    });

    testWidgets('a resumed chapter opens on the stored page', (tester) async {
      // Found while writing the test above, and it is a different defect from
      // the one CodeAnt filed -- the reader's `page` was right all along; the
      // `PageView` under it was not.
      //
      // `_ReaderScreenState` rebuilds the `PageController` from
      // `ever(_c.pages)`, and GetX dispatches that **synchronously** from the
      // `pages.value =` assignment. `load()` assigned `pages` and *then* called
      // `_afterPagesLoaded`, which is what computes `initialPage` -- so the
      // controller was always built from the previous value, which on a fresh
      // open is 0. The counter said "3 / 3" over page one.
      //
      // Asserted on the `PageController`, not on `_c.page`, because `_c.page`
      // was correct the whole time the view was wrong. That is the whole shape
      // of the bug.
      await seedResume();

      await openReader(tester);

      expect(
        tester
            .widget<PageView>(find.byType(PageView))
            .controller!
            .page!
            .round(),
        2,
      );
    });

    testWidgets('the first real page turn does flash', (tester) async {
      // The other half. Without it the test above passes with the flash wired
      // to nothing at all -- which is this repo's most-repeated defect, and
      // the reason a "does not fire" assertion is never enough on its own.
      ReaderKeys.displayRefreshEnabled.set<bool>(true);
      ReaderKeys.displayRefreshDurationMs.set<int>(2000);
      await seedResume();

      await openReader(tester);
      expect(flashing(tester), isFalse);

      // Dragged rather than poked through the controller, which is tagged per
      // screen instance and so is not reachable by a bare `Get.find` anyway.
      // The resume page is the *last* one, so the turn that exists here is
      // backwards -- and a backwards turn ghosts exactly as much as a forwards
      // one, which is the point of the feature.
      // Turned through the `PageView`'s own controller rather than through a
      // synthetic drag. A drag has to win a gesture arena against the
      // `InteractiveViewer` wrapping every page and the reader's own tap
      // detector, and losing it would make this test fail for a reason that
      // has nothing to do with the flash. `jumpToPage` still goes the whole
      // way round -- `onPageChanged` -> `ReaderController.onPageChanged` ->
      // `page` -> `didUpdateWidget` -- which is the path under test.
      tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
      await tester.pump();

      expect(flashing(tester), isTrue);
    });
  });
}
