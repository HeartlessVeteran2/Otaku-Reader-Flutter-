import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
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
  late final String _tag = 'reader-${widget.sourceId}-${widget.mangaUrl}';
  late final ReaderController _c = Get.put(
    ReaderController(
      sources: Get.find<SourceRepository>(),
      library: Get.find<LibraryRepository>(),
      sourceId: widget.sourceId,
      mangaUrl: widget.mangaUrl,
      chapterUrl: widget.chapterUrl,
    ),
    tag: _tag,
  );

  PageController? _pageController;
  final _scroll = ScrollController();
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    // Immersive by default: a reader is the one screen where the system bars
    // are pure obstruction.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    // Rebuild the PageView at the resume position once the pages arrive.
    ever<List<PageUrl>>(_c.pages, (list) {
      if (list.isEmpty) return;
      _pageController?.dispose();
      _pageController = PageController(initialPage: _c.initialPage);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController?.dispose();
    _scroll.dispose();
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
        child: Center(child: _Page(page: _c.pages[i])),
      ),
    );
  }

  Widget _webtoon() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.maxScrollExtent <= 0) return false;
        // Continuous mode has no page boundaries, so position is reported as a
        // fraction of the strip mapped onto the page count. That is what makes
        // "resume where I was" mean anything in webtoon mode.
        final fraction = metrics.pixels / metrics.maxScrollExtent;
        final index = (fraction * (_c.pages.length - 1)).round();
        _c.onPageChanged(index.clamp(0, _c.pages.length - 1));
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemCount: _c.pages.length,
        itemBuilder: (context, i) => _Page(page: _c.pages[i]),
      ),
    );
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
                  child: Text(
                    _c.currentChapter?.name ?? 'Reading',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
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
  const _Page({required this.page});

  final PageUrl page;

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    imageUrl: page.url,
    // Headers the source attached to this specific page win: a source that
    // bothered to set one knows something a generic default does not.
    httpHeaders: page.headers,
    fit: BoxFit.contain,
    placeholder: (_, _) => const SizedBox(
      height: 400,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    ),
    errorWidget: (_, _, _) => const SizedBox(
      height: 200,
      child: Center(
        child: Icon(Iconsax.image, color: Colors.white24, size: 32),
      ),
    ),
  );
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
