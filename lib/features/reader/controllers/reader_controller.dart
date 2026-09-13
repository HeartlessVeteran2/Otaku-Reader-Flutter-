// prefer_initializing_formals wants `this._sources` in the constructor, which
// Dart does not allow -- a named parameter cannot be private. The fields stay
// private deliberately: public ones would invite call sites to reach through
// the controller to the repositories it exists to mediate.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/page_url.dart';

/// How pages are laid out.
enum ReadingLayout { paged, webtoon }

/// Which way paged mode advances.
enum ReadingDirection { leftToRight, rightToLeft }

/// Reads one chapter, and moves between chapters without leaving the screen.
class ReaderController extends GetxController {
  ReaderController({
    required SourceRepository sources,
    required LibraryRepository library,
    required this.sourceId,
    required this.mangaUrl,
    required String chapterUrl,
  }) : _sources = sources,
       _library = library,
       currentChapterUrl = chapterUrl.obs;

  final SourceRepository _sources;
  final LibraryRepository _library;
  final int sourceId;
  final String mangaUrl;
  final RxString currentChapterUrl;

  final pages = <PageUrl>[].obs;
  final page = 0.obs;
  final isLoading = false.obs;
  final error = RxnString();
  final layout = ReadingLayout.paged.obs;
  final direction = ReadingDirection.leftToRight.obs;
  final chaptersInOrder = <Chapter>[].obs;

  /// Needed for the page requests, not for display: hotlink-protected CDNs
  /// answer a bare GET with 403, and the fix is a Referer and Origin derived
  /// from the source's base URL.
  final sourceBaseUrl = ''.obs;

  /// The page index the reader should open at, resolved once per chapter.
  int initialPage = 0;

  /// Where a webtoon scroll should resume, in pixels, resolved with
  /// [initialPage]. A page index is not enough in continuous mode: the user
  /// stops partway down a strip, not at a page boundary.
  double initialOffset = 0;

  double _offset = 0;
  double _maxOffset = 0;

  Timer? _saveTimer;
  int _generation = 0;

  @override
  void onInit() {
    super.onInit();
    layout.value =
        ReadingLayout.values[ReaderKeys.readingLayout.get<int>(0).clamp(0, 1)];
    direction.value = ReadingDirection
        .values[ReaderKeys.readingDirection.get<int>(0).clamp(0, 1)];
    load();
  }

  @override
  void onClose() {
    // Flush rather than drop: the pending write is the user's reading position,
    // and losing it because they closed the reader inside the debounce window
    // is precisely when it matters most. `onClose` cannot be awaited, so the
    // awaitable form lives in [flush] -- which is also what tests call.
    unawaited(flush());
    super.onClose();
  }

  /// Writes any debounced progress immediately.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _persist();
  }

  Chapter? get currentChapter {
    for (final c in chaptersInOrder) {
      if (c.url == currentChapterUrl.value) return c;
    }
    return null;
  }

  int get currentIndex {
    for (var i = 0; i < chaptersInOrder.length; i++) {
      if (chaptersInOrder[i].url == currentChapterUrl.value) return i;
    }
    return -1;
  }

  bool get hasNext =>
      currentIndex >= 0 && currentIndex + 1 < chaptersInOrder.length;
  bool get hasPrevious => currentIndex > 0;

  Future<void> load() async {
    final generation = ++_generation;
    isLoading.value = true;
    error.value = null;
    pages.clear();
    try {
      final entry = await _library.find(sourceId, mangaUrl);
      if (entry != null) {
        // Ascending, so "next chapter" means the next one to read. The details
        // screen shows newest first; the reader must not inherit that or Next
        // would walk backwards.
        final ordered = [...entry.chapters]
          ..sort((a, b) => (a.number ?? 0).compareTo(b.number ?? 0));
        chaptersInOrder.value = ordered;
      }

      final source = await _sources.sourceById(sourceId);
      sourceBaseUrl.value = source?.baseUrl ?? '';
      final methods = await _sources.methodsFor(sourceId);
      final list = await methods.getPageList(currentChapterUrl.value);
      if (generation != _generation) return;

      if (list.isEmpty) {
        // An empty page list is a source failure, not an empty chapter. Showing
        // a blank reader would look like the app lost the images.
        error.value =
            'This chapter came back with no pages. The site may be down, '
            'moved, or blocking requests.';
        return;
      }

      pages.value = list;
      initialPage = _resumePage(list.length);
      page.value = initialPage;
      initialOffset = _resumeOffset();
      _offset = initialOffset;
      _maxOffset = currentChapter?.maxOffset ?? 0;
      await _persist();
    } catch (e) {
      if (generation != _generation) return;
      error.value =
          'Could not load this chapter. The site may be down, moved, or '
          'blocking requests.\n\n$e';
    } finally {
      if (generation == _generation) isLoading.value = false;
    }
  }

  /// Where to open the chapter.
  ///
  /// A finished chapter restarts at the top rather than resuming on its last
  /// page: reopening something you have read means re-reading it, and dropping
  /// the user on the final page looks broken.
  int _resumePage(int total) {
    final chapter = currentChapter;
    if (chapter == null || chapter.read) return 0;
    final last = chapter.lastPageRead;
    if (last == null || last <= 0) return 0;
    return last.clamp(0, total - 1);
  }

  /// The stored pixel offset for a continuous-mode resume.
  ///
  /// Zero for a finished chapter, for the same reason [_resumePage] returns
  /// zero: reopening something you have read means re-reading it.
  double _resumeOffset() {
    final chapter = currentChapter;
    if (chapter == null || chapter.read) return 0;
    return chapter.currentOffset ?? 0;
  }

  /// Records a continuous-mode scroll position.
  ///
  /// Called alongside [onPageChanged] from webtoon mode, which maps the strip
  /// onto a page index for the counter while this keeps the exact position.
  void onScroll(double offset, double maxOffset) {
    _offset = offset;
    _maxOffset = maxOffset;
  }

  void onPageChanged(int index) {
    if (index < 0 || index >= pages.length) return;
    page.value = index;
    // Debounced: a webtoon scroll fires this continuously, and a database write
    // per frame would stutter the scroll it is trying to record.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_persist());
    });
  }

  Future<void> _persist() async {
    final chapterUrl = currentChapterUrl.value;
    final total = pages.length;
    if (total == 0) return;
    final entry = await _library.find(sourceId, mangaUrl);
    if (entry == null) return;

    final reachedEnd = page.value >= total - 1;
    await _library.updateChapterProgress(
      sourceId: sourceId,
      url: mangaUrl,
      chapterUrl: chapterUrl,
      lastPageRead: page.value,
      totalPages: total,
      currentOffset: _offset,
      maxOffset: _maxOffset,
      // Reaching the last page is what marks a chapter read. Doing it on open
      // would mark a chapter read that was merely glanced at.
      markRead: reachedEnd,
    );
  }

  Future<void> next() async {
    if (!hasNext) return;
    await _goTo(chaptersInOrder[currentIndex + 1]);
  }

  Future<void> previous() async {
    if (!hasPrevious) return;
    await _goTo(chaptersInOrder[currentIndex - 1]);
  }

  Future<void> _goTo(Chapter chapter) async {
    final url = chapter.url;
    if (url == null) return;
    // Save where they got to in the chapter they are leaving, before the url
    // changes underneath the write.
    _saveTimer?.cancel();
    await _persist();
    currentChapterUrl.value = url;
    page.value = 0;
    _offset = 0;
    _maxOffset = 0;
    await load();
  }

  void setLayout(ReadingLayout value) {
    layout.value = value;
    ReaderKeys.readingLayout.set<int>(value.index);
  }

  void setDirection(ReadingDirection value) {
    direction.value = value;
    ReaderKeys.readingDirection.set<int>(value.index);
  }
}
