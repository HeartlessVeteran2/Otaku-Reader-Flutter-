import 'package:cached_network_image/cached_network_image.dart';

import 'dart:io';

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
import 'package:otaku_reader/source/http/m_client.dart';
import 'package:otaku_reader/source/model/page_url.dart';

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
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Before deleting the controller, so the worker cannot fire against a
    // disposed Rx or a dead State.
    _pagesWorker?.dispose();
    _pageController?.dispose();
    _scroll?.dispose();
    Get.delete<ReaderController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Obx(() {
        if (_c.isLoading.value && _c.pages.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = _c.error.value;
        if (error != null) return _Error(message: error, onRetry: _c.load);

        return Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => setState(() => _chromeVisible = !_chromeVisible),
              child: _c.layout.value == ReadingLayout.webtoon
                  ? _webtoon()
                  : _paged(),
            ),
            if (_chromeVisible) _chrome(),
          ],
        );
      }),
    );
  }

  Widget _paged() {
    final controller = _pageController;
    if (controller == null) return const SizedBox.shrink();
    return PageView.builder(
      controller: controller,
      // Right-to-left is the default for a great deal of manga, and flipping
      // the scroll direction is what makes the swipe gesture match the page
      // order rather than fighting it.
      reverse: _c.direction.value == ReadingDirection.rightToLeft,
      onPageChanged: _c.onPageChanged,
      itemCount: _c.pages.length,
      itemBuilder: (context, i) => InteractiveViewer(
        minScale: 1,
        maxScale: 4,
        child: Center(
          child: _Page(page: _c.pages[i], baseUrl: _c.sourceBaseUrl.value),
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
        // Two things are recorded, because they answer different questions.
        // The pixel offset is what a resume restores; the page index is what
        // the counter shows and what decides the chapter has been finished.
        _c.onScroll(metrics.pixels, metrics.maxScrollExtent);
        final index = _webtoonPage(metrics);
        if (index != null) _c.onPageChanged(index);
        return false;
      },
      child: ListView.builder(
        key: _webtoonKey,
        controller: controller,
        itemCount: _c.pages.length,
        itemBuilder: (context, i) => KeyedSubtree(
          key: _pageKey(i),
          child: _Page(page: _c.pages[i], baseUrl: _c.sourceBaseUrl.value),
        ),
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

    // The page under the top edge of the viewport is the one being read; a page
    // still entirely below it has not been reached. Only children near the
    // viewport have a context at all -- the rest are recycled, and they are
    // exactly the ones that cannot be the current page.
    int? current;
    for (final entry in _pageKeys.entries) {
      if (entry.key >= total) continue;
      final context = entry.value.currentContext;
      if (context == null) continue;
      final child = context.findRenderObject();
      if (child is! RenderBox || !child.hasSize) continue;
      final top = child.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (top <= 0 && (current == null || entry.key > current)) {
        current = entry.key;
      }
    }
    // Nothing above the fold means the strip is still at the very top.
    return current ?? 0;
  }

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
                if (_c.layout.value == ReadingLayout.paged)
                  IconButton(
                    tooltip: _c.direction.value == ReadingDirection.rightToLeft
                        ? 'Right to left'
                        : 'Left to right',
                    icon: Icon(
                      _c.direction.value == ReadingDirection.rightToLeft
                          ? Iconsax.arrow_left_2
                          : Iconsax.arrow_right_3,
                      color: Colors.white,
                    ),
                    onPressed: () => _c.setDirection(
                      _c.direction.value == ReadingDirection.rightToLeft
                          ? ReadingDirection.leftToRight
                          : ReadingDirection.rightToLeft,
                    ),
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
