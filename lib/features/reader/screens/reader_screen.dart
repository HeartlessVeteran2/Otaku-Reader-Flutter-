import 'package:cached_network_image/cached_network_image.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/data/anilist/anilist_metadata_service.dart';
import 'package:otaku_reader/data/anilist/anilist_progress_sync.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/features/reader/screen_wakelock.dart';
import 'package:otaku_reader/features/reader/display/reader_display_layer.dart';
import 'package:otaku_reader/features/reader/display/reader_display_settings.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone_settings.dart';
import 'package:otaku_reader/features/reader/widgets/reader_page_indicator.dart';
import 'package:otaku_reader/source/http/m_client.dart';
import 'package:otaku_reader/source/model/page_url.dart';

/// How many viewports a restore walk may advance before giving up.
///
/// Bounded because a target that can no longer be reached — a chapter that came
/// back shorter than the one being read — would otherwise walk to the end and
/// keep asking.
const kRestoreStepLimit = 400;

/// Whether a restore walk has finished, or must advance to build more pages.
enum RestoreStep { done, advance }

/// Whether a mode change leaves the reader's scroll views holding state that is
/// no longer about what is on screen.
///
/// The first version asked only about the **axis**, and `codeant-ai` caught
/// what that misses: paged and continuous keep *separate* controllers, so
/// switching between them at the same axis rebuilt neither. The `PageView`
/// kept its page while the strip kept an offset belonging to a different read,
/// whichever was showing overwrote `page` with its own answer, and switching
/// back showed the old page while the counter reported the other one.
///
/// Eighth instance of this repo's most-repeated defect: the rule was applied
/// one case earlier in the same file and not to its neighbour.
@visibleForTesting
bool modeInvalidatesScroll({
  required Axis wasAxis,
  required Axis nowAxis,
  required ReadingLayout wasLayout,
  required ReadingLayout nowLayout,
}) => wasAxis != nowAxis || wasLayout != nowLayout;

/// What a restore walk should do next.
///
/// Lifted out of [_restorePage] so the decision can be asserted directly.
/// The state it turns on — a page laid out beyond the first screenful — is
/// **not reachable in this harness**: a `_Page` has no extent under
/// `flutter test`, because `Image.file` never reaches its `errorBuilder`
/// there even inside `runAsync` (measured). A rendered reproduction would
/// therefore have to fake the very thing it was testing.
///
/// The case that matters is `built: false` with room left, which the first
/// version of this answered with [RestoreStep.done] — and that is the whole
/// bug: giving up leaves the reader at the top of the chapter.
@visibleForTesting
RestoreStep nextRestoreStep({
  required bool targetIsBuilt,
  required double pixels,
  required double maxScrollExtent,
  required int step,
  int stepLimit = kRestoreStepLimit,
}) {
  if (targetIsBuilt) return RestoreStep.done;
  if (step >= stepLimit) return RestoreStep.done;
  // Never past the end: a chapter that came back shorter has no page to
  // reach, and asking again would walk until the step limit for nothing.
  if (pixels >= maxScrollExtent) return RestoreStep.done;
  return RestoreStep.advance;
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.sourceId,
    required this.mangaUrl,
    required this.chapterUrl,
  });

  final int sourceId;
  final String mangaUrl;
  final String chapterUrl;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  // Unique per screen instance, not per manga. A tag keyed only by source and
  // manga is shared by any second reader for the same manga on the stack, and
  // then one screen's dispose deletes the other's controller.
  late final String _tag = 'reader-${identityHashCode(this)}';
  late final ReaderController _c = Get.put(
    ReaderController(
      sources: Get.find<SourceRepository>(),
      library: Get.find<LibraryRepository>(),
      anilistProgress: AniListProgressSync(
        Get.find<AniListMetadataService>(),
        Get.find<AniListListService>(),
      ),
      wakelock: Get.find<ScreenWakelock>(),
      sourceId: widget.sourceId,
      mangaUrl: widget.mangaUrl,
      chapterUrl: widget.chapterUrl,
    ),
    tag: _tag,
  );

  PageController? _pageController;
  ScrollController? _scroll;
  bool _chromeVisible = true;

  /// Identifies the webtoon list itself, so a child's offset can be measured
  /// against the viewport rather than against the screen.
  final _webtoonKey = GlobalKey();

  /// One key per page, so [_webtoonPage] can ask where each laid-out page
  /// actually sits. Cleared when the chapter changes: the keys are indexed, and
  /// a key left pointing at the previous chapter's widget would answer for it.
  final _pageKeys = <int, GlobalKey>{};

  GlobalKey _pageKey(int i) => _pageKeys.putIfAbsent(i, GlobalKey.new);

  /// Retained so it can be disposed. An unowned `ever` worker keeps firing
  /// after the screen is popped — creating controllers for an unmounted state
  /// and disposing ones already disposed — whenever the reader is closed while
  /// `load()` is still awaiting pages.
  Worker? _pagesWorker;

  /// Watches for a change of *axis*, which is the one change a live scroll
  /// controller cannot survive: its stored `pixels` were measured down a strip
  /// and mean nothing across one. A change of sign is deliberately not
  /// watched — `reverse` flips the whole coordinate system, so offset 0 is
  /// still the first page either way.
  Worker? _axisWorker;

  /// The axis and layout the current controllers were built for.
  Axis _axis = Axis.horizontal;
  ReadingLayout _layout = ReadingLayout.paged;

  /// True while [_restorePage] is walking the strip back to where the reader
  /// was.
  ///
  /// The walk scrolls, and scrolling reports a page. Without this the restore
  /// overwrites the very index it is trying to reach — and `_persist` saves
  /// that, so the place is lost on disk and not merely on screen.
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    // Immersive by default: a reader is the one screen where the system bars
    // are pure obstruction.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    // Rebuild the PageView at the resume position once the pages arrive.
    _pagesWorker = ever<List<PageUrl>>(_c.pages, (list) {
      if (list.isEmpty || !mounted) return;
      _pageController?.dispose();
      _pageController = PageController(initialPage: _c.initialPage);
      // Continuous mode resumes by pixel offset, which is the only thing that
      // means anything on a strip with no page boundaries. `initialScrollOffset`
      // is applied before the first layout, so the list opens at the stored
      // position rather than jumping after the user can already see the top.
      _scroll?.dispose();
      _scroll = ScrollController(initialScrollOffset: _c.initialOffset);
      _pageKeys.clear();
      setState(() {});
      // `initialScrollOffset` positions the list before the first layout, which
      // is what stops it jumping once the user can already see the top — but it
      // is a raw pixel value measured against a strip that may now be a
      // different height: images decode at another resolution, the device
      // rotated, the source republished the chapter longer. Corrected once the
      // real extent is known.
      WidgetsBinding.instance.addPostFrameCallback((_) => _correctResume());
    });
    _axis = _c.activeDirection.axis;
    _layout = _c.layout.value;
    _axisWorker = everAll([_c.layout, _c.direction, _c.webtoonDirection], (_) {
      if (!mounted) return;
      final axis = _c.activeDirection.axis;
      final layout = _c.layout.value;
      if (!modeInvalidatesScroll(
        wasAxis: _axis,
        nowAxis: axis,
        wasLayout: _layout,
        nowLayout: layout,
      )) {
        return;
      }
      _axis = axis;
      _layout = layout;
      _rebuildForMode();
    });
  }

  /// Hands both modes a controller built for the axis now in force.
  ///
  /// The page *index* survives the switch and the pixel offset cannot, so the
  /// index is what is restored: paged reopens on it directly, and continuous
  /// scrolls to that page's laid-out child once there is a layout to measure.
  void _rebuildForMode() {
    final current = _c.page.value;
    _pageController?.dispose();
    _pageController = PageController(initialPage: current);
    _scroll?.dispose();
    _scroll = ScrollController();
    setState(() {});
    _restorePage(current);
  }

  /// Puts [target] back on screen after the scroll view under it was replaced.
  ///
  /// Paged restores itself, because a `PageController` takes an initial page.
  /// Continuous cannot, and the first version of this assumed it could: a
  /// fresh `ScrollController` starts at 0 and a `ListView` only builds the
  /// children near its current offset, so for any page past the first screenful
  /// the target's `GlobalKey` has **no context**, `ensureVisible` has nothing
  /// to act on, and the callback returned silently. The reader sat at the top,
  /// and the scroll notification that followed overwrote the saved index with
  /// 0 — which `_persist` then wrote to disk, so the place was lost for good.
  /// Found by `sourcery-ai`.
  ///
  /// Advancing a viewport at a time is what forces the next band of children to
  /// build, which is the only thing that can give the target a context. An
  /// offset cannot be computed instead: page heights vary, and the arithmetic
  /// version of that question is already a row in this repo's mistakes table.
  void _restorePage(int target, [int step = 0]) {
    // A fresh controller already sits at the first page.
    if (target <= 0) return;
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _scroll;
      if (!mounted || controller == null || !controller.hasClients) {
        _restoring = false;
        return;
      }
      final context = _pageKeys[target]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context);
        _restoring = false;
        return;
      }
      final position = controller.position;
      final next = nextRestoreStep(
        targetIsBuilt: false,
        pixels: position.pixels,
        maxScrollExtent: position.maxScrollExtent,
        step: step,
      );
      if (next == RestoreStep.done) {
        _restoring = false;
        return;
      }
      controller.jumpTo(
        math.min(
          position.pixels + position.viewportDimension,
          position.maxScrollExtent,
        ),
      );
      _restorePage(target, step + 1);
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Before deleting the controller, so the worker cannot fire against a
    // disposed Rx or a dead State.
    _pagesWorker?.dispose();
    _axisWorker?.dispose();
    _pageController?.dispose();
    _scroll?.dispose();
    Get.delete<ReaderController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The backdrop is a setting now, not a constant. Resolved through the
      // enum so `system` can read the theme, which a stored colour cannot.
      backgroundColor: ReaderDisplaySettings.background.colorFor(context),
      body: Obx(() {
        if (_c.isLoading.value && _c.pages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = _c.error.value;
        if (error != null) return _Error(message: error, onRetry: _c.load);

        return Stack(
          children: [
            // The `LayoutBuilder` is what makes the tap arithmetic honest.
            // `details.localPosition` is relative to the `GestureDetector`, so
            // the extent it is divided by has to be that same box — reading a
            // size off the `State`'s own render object instead happens to agree
            // here only because nothing sits above the body, and this repo has
            // already shipped a lookup that was right for one caller and
            // silently wrong for the rest.
            // Wrapped rather than applied per page: the treatment is a
            // property of the reading surface, so a paged view and a strip get
            // it identically and neither builder has to remember to ask.
            ReaderDisplayLayer(
              greyscale: ReaderDisplaySettings.greyscale,
              invert: ReaderDisplaySettings.invert,
              filter: ReaderDisplaySettings.filterEnabled
                  ? Color(ReaderDisplaySettings.filterColor)
                  : null,
              blend: ReaderDisplaySettings.filterBlend,
              child: LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  // `onTapUp` rather than `onTap`, because a zone needs to know
                  // *where*. With zones off this still toggles the chrome from
                  // anywhere, which is what the reader did before they existed —
                  // the switch turns the feature off, not the screen's only
                  // gesture.
                  onTapUp: (details) => _onTapUp(details, constraints.biggest),
                  child: _c.layout.value == ReadingLayout.webtoon
                      ? _webtoon()
                      : _paged(),
                ),
              ),
            ),
            // Over the page, under the chrome. Dimming the controls with the
            // artwork makes the one surface a reader reaches for when the page
            // is too bright the hardest thing on screen to read.
            if (ReaderDisplaySettings.dimEnabled)
              Positioned.fill(
                child: ReaderDimVeil(percent: ReaderDisplaySettings.dim),
              ),
            if (_chromeVisible) _chrome(),
            // The chrome's bottom bar carries the counter while it is up, so
            // this one fills the gap that actually exists: reading with the
            // chrome hidden, where until now there was no page number at all.
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 0,
              right: 0,
              child: Center(
                child: ReaderPageIndicator(
                  page: _c.page.value,
                  total: _c.pages.length,
                  visible: _c.showPageIndicator.value && !_chromeVisible,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _paged() {
    final controller = _pageController;
    if (controller == null) return const SizedBox.shrink();
    // Right-to-left is the default for a great deal of manga, and bottom-to-top
    // exists for the same reason one axis over: flipping the scroll direction
    // is what makes the swipe match the page order rather than fighting it.
    final direction = _c.activeDirection;
    return PageView.builder(
      controller: controller,
      scrollDirection: direction.axis,
      reverse: direction.reversed,
      onPageChanged: _c.onPageChanged,
      itemCount: _c.pages.length,
      itemBuilder: (context, i) => InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: KeyedSubtree(
            key: _pageKey(i),
            child: _Page(page: _c.pages[i], baseUrl: _c.sourceBaseUrl.value),
          ),
        ),
      ),
    );
  }

  Widget _webtoon() {
    final controller = _scroll;
    if (controller == null) return const SizedBox.shrink();
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.maxScrollExtent <= 0) return false;
        // A restore is scrolling on the reader's behalf, not the reader's.
        if (_restoring) return false;
        // Two things are recorded, because they answer different questions.
        // The pixel offset is what a resume restores; the page index is what
        // the counter shows and what decides the chapter has been finished.
        _c.onScroll(metrics.pixels, metrics.maxScrollExtent);
        final index = _webtoonPage(metrics);
        if (index != null) _c.onPageChanged(index);
        return false;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final direction = _c.activeDirection;
          final horizontal = direction.axis == Axis.horizontal;
          return ListView.builder(
            key: _webtoonKey,
            controller: controller,
            scrollDirection: direction.axis,
            reverse: direction.reversed,
            itemCount: _c.pages.length,
            itemBuilder: (context, i) {
              final page = KeyedSubtree(
                key: _pageKey(i),
                child: _Page(
                  page: _c.pages[i],
                  baseUrl: _c.sourceBaseUrl.value,
                ),
              );
              // A vertical strip constrains width and lets each page take the
              // height its aspect ratio asks for. Turned on its side that
              // reverses, and an image with an unbounded main axis falls back
              // to its *intrinsic pixel width* — which is whatever the scan was
              // encoded at, and has nothing to do with the screen. Pinning the
              // page to the viewport is what a continuous horizontal reader
              // does anyway: free scrolling, one page wide.
              return horizontal
                  ? SizedBox(width: constraints.maxWidth, child: page)
                  : page;
            },
          );
        },
      ),
    );
  }

  /// Rescales the restored webtoon position against the strip's real height.
  ///
  /// Without this, a chapter whose content is now taller resumes too early and
  /// one that is shorter resumes at the very bottom — which also *marks it
  /// read*, because reaching the bottom is what finishes a chapter.
  void _correctResume() {
    final controller = _scroll;
    if (!mounted || controller == null || !controller.hasClients) return;
    final target = _c.initialOffset;
    if (target <= 0) return;
    final max = controller.position.maxScrollExtent;
    if (max <= 0) return;

    final storedMax = _c.initialMaxOffset;
    final scaled = storedMax > 0 ? target / storedMax * max : target;
    final corrected = scaled.clamp(0.0, max);
    if ((controller.offset - corrected).abs() < 1) return;
    controller.jumpTo(corrected);
  }

  /// Which page the reader is actually on, from the laid-out children.
  ///
  /// The obvious version — `pixels / maxScrollExtent * (pages - 1)` — assumes
  /// every page is the same height. Manga pages are not: one tall spread among
  /// short pages shifts every boundary, and because [_persist] treats "on the
  /// last page" as "finished", an over-reported index marks a chapter read
  /// while the user is still several pages from the end. Measuring the children
  /// is the only thing that cannot drift.
  ///
  /// Returns null when nothing is laid out yet, which the caller reads as
  /// "leave the current page alone" rather than "page 0".
  int? _webtoonPage(ScrollMetrics metrics) {
    final total = _c.pages.length;
    if (total == 0) return null;
    // Reaching the bottom is finishing the chapter, whatever the measurement
    // says: a final page shorter than the viewport never gets its top edge
    // above the fold, so the arithmetic below would never reach it.
    if (metrics.pixels >= metrics.maxScrollExtent - 1) return total - 1;

    final viewport = _webtoonKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return null;

    final direction = _c.activeDirection;
    final horizontal = direction.axis == Axis.horizontal;
    final extent = horizontal ? viewport.size.width : viewport.size.height;

    // The page past the *leading* edge of the viewport is the one being read; a
    // page still entirely beyond it has not been reached. Only children near
    // the viewport have a context at all -- the rest are recycled, and they are
    // exactly the ones that cannot be the current page.
    //
    // "Leading" is not "top". `localToGlobal` answers in screen space, where 0
    // is always the visual left or top, while a reversed list puts page 1 at
    // the far end -- so comparing against 0 there names the page furthest from
    // the one being read. Measuring the distance from the leading edge instead
    // keeps one comparison correct for all four directions.
    int? current;
    for (final entry in _pageKeys.entries) {
      if (entry.key >= total) continue;
      final context = entry.value.currentContext;
      if (context == null) continue;
      final child = context.findRenderObject();
      if (child is! RenderBox || !child.hasSize) continue;
      final origin = child.localToGlobal(Offset.zero, ancestor: viewport);
      final start = horizontal ? origin.dx : origin.dy;
      final size = horizontal ? child.size.width : child.size.height;
      final fromLeading = direction.reversed ? extent - (start + size) : start;
      if (fromLeading <= 0 && (current == null || entry.key > current)) {
        current = entry.key;
      }
    }
    // Nothing above the fold means the strip is still at the very top.
    return current ?? 0;
  }

  /// Resolves a tap against the profile for the layout on screen.
  void _onTapUp(TapUpDetails details, Size size) {
    if (!TapZoneSettings.enabled) {
      _toggleChrome();
      return;
    }

    final direction = _c.activeDirection;
    final horizontal = direction.axis == Axis.horizontal;
    final extent = horizontal ? size.width : size.height;
    // A zero extent has no bands to land in, and dividing by it gives a
    // position that is not a number — which `clamp` would hand back unchanged,
    // because NaN sorts above every double.
    if (extent <= 0) {
      _toggleChrome();
      return;
    }

    final along = horizontal
        ? details.localPosition.dx
        : details.localPosition.dy;
    var position = (along / extent).clamp(0.0, 1.0);
    // Measured from the **leading** edge. This one line is the right-to-left
    // correction: the band authored as "the side you tap to go on" stays the
    // side you tap to go on, where AnymeX's page actions ignore `reversed`
    // entirely and fire *previous* for a tap on the leading side of every
    // right-to-left manga.
    if (direction.reversed && TapZoneSettings.mirrorWhenReversed) {
      position = 1 - position;
    }

    final action = TapZoneSettings.profileFor(_c.layout.value)
        .actionAt(position);
    // Fired for every resolved zone, `none` included. The feedback says the tap
    // was *received*, not that something moved — and an inert band is exactly
    // where a silent reader is indistinguishable from one that missed the tap.
    if (TapZoneSettings.haptics) unawaited(HapticFeedback.selectionClick());
    _perform(action);
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  void _perform(ReaderAction action) {
    switch (action) {
      case ReaderAction.toggleChrome:
        _toggleChrome();
      case ReaderAction.next:
        _step(forward: true);
      case ReaderAction.previous:
        _step(forward: false);
      case ReaderAction.nextChapter:
        unawaited(_c.next());
      case ReaderAction.previousChapter:
        unawaited(_c.previous());
      case ReaderAction.none:
        break;
    }
  }

  /// One unit of reading order: a page in paged mode, a screen in continuous.
  ///
  /// Running off either end moves to the neighbouring chapter, which is
  /// AnymeX's behaviour and the one that makes a zone worth using — a reader
  /// who taps forward at the end of a chapter means "carry on".
  void _step({required bool forward}) {
    const duration = Duration(milliseconds: 200);
    const curve = Curves.easeOutCubic;

    if (_c.layout.value == ReadingLayout.webtoon) {
      final controller = _scroll;
      if (controller == null || !controller.hasClients) return;
      final position = controller.position;
      // Content-relative, so forward is always a larger offset whichever edge
      // it is painted from — the same property the direction tests measure.
      final target = forward
          ? position.pixels + position.viewportDimension
          : position.pixels - position.viewportDimension;
      if (forward && position.pixels >= position.maxScrollExtent - 1) {
        unawaited(_c.next());
        return;
      }
      if (!forward && position.pixels <= position.minScrollExtent + 1) {
        unawaited(_c.previous());
        return;
      }
      unawaited(
        controller.animateTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: duration,
          curve: curve,
        ),
      );
      return;
    }

    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final page = _c.page.value;
    if (forward && page >= _c.pages.length - 1) {
      unawaited(_c.next());
      return;
    }
    if (!forward && page <= 0) {
      unawaited(_c.previous());
      return;
    }
    unawaited(
      forward
          ? controller.nextPage(duration: duration, curve: curve)
          : controller.previousPage(duration: duration, curve: curve),
    );
  }

  static IconData _directionIcon(ReadingDirection direction) =>
      switch (direction) {
        ReadingDirection.leftToRight => Iconsax.arrow_right_3,
        ReadingDirection.rightToLeft => Iconsax.arrow_left_2,
        ReadingDirection.topToBottom => Iconsax.arrow_down_1,
        ReadingDirection.bottomToTop => Iconsax.arrow_up_2,
      };

  Widget _chrome() {
    return Positioned.fill(
      child: Column(
        children: [
          Container(
            color: Colors.black54,
            padding: EdgeInsets.only(
              top: MediaQuery.paddingOf(context).top + 4,
              left: 4,
              right: 4,
              bottom: 4,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Iconsax.arrow_left, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _c.currentChapter?.name ?? 'Reading',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Answers "why is this instant, and why does it work on a
                      // plane" on the screen rather than in a settings page.
                      if (_c.isOffline.value) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Iconsax.tick_square,
                          size: 14,
                          color: Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Downloaded',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _c.layout.value == ReadingLayout.webtoon
                      ? 'Webtoon'
                      : 'Paged',
                  icon: Icon(
                    _c.layout.value == ReadingLayout.webtoon
                        ? Iconsax.document
                        : Iconsax.book_1,
                    color: Colors.white,
                  ),
                  onPressed: () => _c.setLayout(
                    _c.layout.value == ReadingLayout.webtoon
                        ? ReadingLayout.paged
                        : ReadingLayout.webtoon,
                  ),
                ),
                // Both layouts carry a direction now, so this is no longer
                // paged-only. It cycles rather than toggles, because there are
                // four of them; the Settings row is where one is chosen
                // deliberately.
                IconButton(
                  tooltip: _c.activeDirection.label,
                  icon: Icon(
                    _directionIcon(_c.activeDirection),
                    color: Colors.white,
                  ),
                  onPressed: () =>
                      _c.setActiveDirection(_c.activeDirection.next),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            color: Colors.black54,
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 4,
              left: 8,
              right: 8,
              top: 4,
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous chapter',
                  icon: const Icon(Iconsax.previous, color: Colors.white),
                  onPressed: _c.hasPrevious ? _c.previous : null,
                ),
                Expanded(
                  child: Text(
                    '${_c.page.value + 1} / ${_c.pages.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                IconButton(
                  tooltip: 'Next chapter',
                  icon: const Icon(Iconsax.next, color: Colors.white),
                  onPressed: _c.hasNext ? _c.next : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.page, required this.baseUrl});

  final PageUrl page;
  final String baseUrl;

  static const _broken = SizedBox(
    height: 200,
    child: Center(child: Icon(Iconsax.image, color: Colors.white24, size: 32)),
  );

  @override
  Widget build(BuildContext context) {
    // A downloaded page is a file path, not a URL. Routing it through
    // CachedNetworkImage would try to fetch "/data/.../0001.jpg" over HTTP and
    // fail — offline, which is the one situation downloads exist for.
    if (!page.url.startsWith('http')) {
      return Image.file(
        File(page.url),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _broken,
      );
    }
    return CachedNetworkImage(
      imageUrl: page.url,
      // Merged, not replaced. Most sources attach no headers at all, and
      // sending none means no User-Agent, Referer or Origin -- which is exactly
      // what hotlink-protected CDNs answer with 403. `pageImageHeaders`
      // supplies those defaults and lets anything the source set override them,
      // because a source that bothered to set a header knows something a
      // default does not.
      httpHeaders: MClient.pageImageHeaders(page.headers, baseUrl),
      fit: BoxFit.contain,
      placeholder: (_, _) => const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, _, _) => _broken,
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Iconsax.cloud_cross, size: 40, color: Colors.white38),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ],
      ),
    ),
  );
}
