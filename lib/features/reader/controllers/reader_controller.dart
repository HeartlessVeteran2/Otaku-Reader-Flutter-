// prefer_initializing_formals wants `this._sources` in the constructor, which
// Dart does not allow -- a named parameter cannot be private. The fields stay
// private deliberately: public ones would invite call sites to reach through
// the controller to the repositories it exists to mediate.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:io';

// `Axis` only. The reader's direction carries the axis it flows along, and
// that pair belongs with the enum rather than being re-derived at each of the
// four call sites that need it.
import 'package:flutter/painting.dart' show Axis;
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'package:otaku_reader/data/anilist/anilist_progress_sync.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/reader/screen_wakelock.dart';
import 'package:otaku_reader/source/model/page_url.dart';

/// How pages are laid out.
enum ReadingLayout { paged, webtoon }

/// Which way a reader advances: an axis, and a sign along it.
///
/// Ported from AnymeX's `MangaPageViewDirection`, which carries exactly this
/// pair of getters — **but not its member order**. AnymeX's is
/// `{up, down, left, right}`; adopting that here would silently re-point every
/// stored index, because the value is persisted as `index` and this app already
/// has users whose `0` means left-to-right. New members are therefore
/// *appended*, and the spelling differs from the reference on purpose.
enum ReadingDirection {
  leftToRight,
  rightToLeft,
  topToBottom,
  bottomToTop;

  /// The axis pages flow along.
  Axis get axis => switch (this) {
    ReadingDirection.leftToRight => Axis.horizontal,
    ReadingDirection.rightToLeft => Axis.horizontal,
    ReadingDirection.topToBottom => Axis.vertical,
    ReadingDirection.bottomToTop => Axis.vertical,
  };

  /// Whether the first page sits at the far end of that axis.
  bool get reversed => switch (this) {
    ReadingDirection.leftToRight => false,
    ReadingDirection.rightToLeft => true,
    ReadingDirection.topToBottom => false,
    ReadingDirection.bottomToTop => true,
  };

  /// What this direction is called, everywhere it is named.
  ///
  /// On the enum rather than in either screen, for the reason `ReaderDefaults`
  /// exists: the reader's own control and the Settings row both render this,
  /// and a pair that disagrees puts a tooltip on screen contradicting the row
  /// that set it — with each file perfectly self-consistent on its own. It also
  /// means a member added later cannot be labelled in one place and left blank
  /// in the other.
  String get label => switch (this) {
    ReadingDirection.leftToRight => 'Left to right',
    ReadingDirection.rightToLeft => 'Right to left',
    ReadingDirection.topToBottom => 'Top to bottom',
    ReadingDirection.bottomToTop => 'Bottom to top',
  };

  /// The short form, for a segmented row where a full label would be squeezed
  /// to a stub. `CLAUDE.md` records why a `FittedBox` is not the fix there: it
  /// hands its child unbounded width, so the ellipsis never fires and a long
  /// label scales toward nothing.
  String get shortLabel => switch (this) {
    ReadingDirection.leftToRight => 'L → R',
    ReadingDirection.rightToLeft => 'R → L',
    ReadingDirection.topToBottom => 'T → B',
    ReadingDirection.bottomToTop => 'B → T',
  };

  /// The next one in the reader's quick cycle, wrapping at the end.
  ReadingDirection get next =>
      ReadingDirection.values[(index + 1) % ReadingDirection.values.length];

  /// The default for [layout].
  ///
  /// The two layouts do **not** share a stored direction, and that is a
  /// deliberate departure. AnymeX keeps one value for both and then
  /// force-overrides it to `down` whenever its auto-webtoon detector fires
  /// (`_applyAutoWebtoonMode`) — a special case that exists precisely because a
  /// shared value is wrong for a long strip. Sharing here would be worse still:
  /// this app's stored default is `leftToRight`, so every existing webtoon
  /// reader would have come back from an upgrade scrolling sideways.
  static ReadingDirection defaultFor(ReadingLayout layout) =>
      layout == ReadingLayout.webtoon
      ? ReadingDirection.topToBottom
      : ReadingDirection.leftToRight;
}

/// Reads one chapter, and moves between chapters without leaving the screen.
class ReaderController extends GetxController {
  ReaderController({
    required SourceRepository sources,
    required LibraryRepository library,
    required AniListProgressReporter anilistProgress,
    required ScreenWakelock wakelock,
    required this.sourceId,
    required this.mangaUrl,
    required String chapterUrl,
  }) : _sources = sources,
       _library = library,
       _anilistProgress = anilistProgress,
       _wakelock = wakelock,
       currentChapterUrl = chapterUrl.obs;

  final SourceRepository _sources;
  final LibraryRepository _library;

  /// Required rather than optional. An optional collaborator that the screen
  /// forgets to pass is how this app already shipped live UI wired to
  /// nothing; making it required means the wiring cannot be missing quietly.
  final AniListProgressReporter _anilistProgress;

  /// Required for the same reason, and it is the same defect twice: "Keep the
  /// screen on" shipped as a switch the user could press with nothing behind
  /// it. An optional wakelock would let that happen again silently.
  final ScreenWakelock _wakelock;
  final int sourceId;
  final String mangaUrl;
  final RxString currentChapterUrl;

  final pages = <PageUrl>[].obs;

  /// True when the pages on screen came off disk. The reader shows a small
  /// marker, because "why is this instant and working on a plane" is a
  /// question worth answering on the screen rather than in a settings page.
  final isOffline = false.obs;
  final page = 0.obs;
  final isLoading = false.obs;
  final error = RxnString();
  final layout = ReadingLayout.paged.obs;

  /// The direction paged mode advances in.
  final direction = ReadingDirection.leftToRight.obs;

  /// The direction continuous mode scrolls in, stored separately — see
  /// [ReadingDirection.defaultFor] for why the two are not one value.
  final webtoonDirection = ReadingDirection.topToBottom.obs;

  /// The direction actually in force, which is the one the screen renders and
  /// the only one a tap zone can be measured against.
  ReadingDirection get activeDirection => layout.value == ReadingLayout.webtoon
      ? webtoonDirection.value
      : direction.value;

  /// Whether a page counter stays on screen once the chrome is hidden.
  ///
  /// Seeded from [ReaderDefaults] rather than a literal, so the value the
  /// reader holds before `onInit` runs cannot disagree with the one the
  /// Settings switch renders.
  final showPageIndicator = ReaderDefaults.showPageIndicator.obs;
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
    // The bounds come from the enums, never from a literal. `clamp(0, 1)` was
    // what stood here, and it is the `int status = 5` row of the mistakes
    // table wearing a different hat: appending a `ReadingDirection` member
    // would have left the Settings row offering it -- that row already clamps
    // against `values.length` -- while the reader silently pinned it back to
    // left-to-right, with nothing failing anywhere. Seventh instance of a rule
    // holding in one file and not in its neighbour.
    layout.value =
        ReadingLayout.values[ReaderKeys.readingLayout
            .get<int>(0)
            .clamp(0, ReadingLayout.values.length - 1)];
    direction.value =
        ReadingDirection.values[ReaderKeys.readingDirection
            .get<int>(ReadingDirection.leftToRight.index)
            .clamp(0, ReadingDirection.values.length - 1)];
    webtoonDirection.value =
        ReadingDirection.values[ReaderKeys.webtoonDirection
            .get<int>(ReadingDirection.topToBottom.index)
            .clamp(0, ReadingDirection.values.length - 1)];
    showPageIndicator.value = ReaderKeys.showPageIndicator.get<bool>(
      ReaderDefaults.showPageIndicator,
    );
    // Read the setting *first*. AnymeX enables unconditionally here and then
    // corrects itself once preferences load, which holds the screen awake
    // against the user's own choice for the width of that window.
    if (ReaderKeys.keepScreenOn.get<bool>(ReaderDefaults.keepScreenOn)) {
      unawaited(_wakelock.enable());
    }
    load();
  }

  @override
  void onClose() {
    // Flush rather than drop: the pending write is the user's reading position,
    // and losing it because they closed the reader inside the debounce window
    // is precisely when it matters most. `onClose` cannot be awaited, so the
    // awaitable form lives in [flush] -- which is also what tests call.
    unawaited(flush());
    // Unconditional, deliberately. Keying the release on `keepScreenOn` reads
    // as the tidy version and strands the lock whenever the switch is turned
    // off while a chapter is open: the enable already happened, and the
    // release would then be skipped on the way out.
    unawaited(_wakelock.disable());
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
        // `?? 0` would sort every unnumbered extra *before* chapter 1, so the
        // reader's Next button would walk through the extras first. Nulls go
        // last, keeping their source order.
        final ordered = [...entry.chapters];
        final sourceOrder = Map<Chapter, int>.identity();
        for (var i = 0; i < ordered.length; i++) {
          sourceOrder[ordered[i]] = i;
        }
        ordered.sort((a, b) {
          final an = a.number;
          final bn = b.number;
          if (an == null && bn == null) {
            return (sourceOrder[a] ?? 0).compareTo(sourceOrder[b] ?? 0);
          }
          if (an == null) return 1;
          if (bn == null) return -1;
          final byNumber = an.compareTo(bn);
          return byNumber != 0
              ? byNumber
              : (sourceOrder[a] ?? 0).compareTo(sourceOrder[b] ?? 0);
        });
        chaptersInOrder.value = ordered;
      }

      final source = await _sources.sourceById(sourceId);
      // Downloaded pages first, and without touching the source at all — that
      // is what "offline" has to mean. A stored path whose directory has since
      // gone (the user cleared storage, or moved the download folder) falls
      // through to the network rather than showing an empty chapter, because a
      // reader that renders nothing looks like the app lost the images.
      final local = await _localPages();
      if (generation != _generation) return;
      if (local != null) {
        pages.value = local;
        isOffline.value = true;
        _afterPagesLoaded(local.length);
        await _persist(markRead: false);
        return;
      }
      isOffline.value = false;

      final methods = await _sources.methodsFor(sourceId);
      // The runtime's effective base URL, not the stored one: a mirror
      // preference changes where the images actually come from, and this value
      // becomes the Referer/Origin on every page request.
      final effective = methods.sourceBaseUrl;
      sourceBaseUrl.value = effective.isNotEmpty
          ? effective
          : source?.baseUrl ?? '';
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
      _afterPagesLoaded(list.length);
      // `markRead: false` explicitly. Opening a one-page chapter puts page 0 at
      // the last page, so an unguarded save here would mark it read before the
      // user has done anything. Only a page turn or a scroll finishes a
      // chapter.
      await _persist(markRead: false);
    } catch (e) {
      if (generation != _generation) return;
      error.value =
          'Could not load this chapter. The site may be down, moved, or '
          'blocking requests.\n\n$e';
    } finally {
      if (generation == _generation) isLoading.value = false;
    }
  }

  /// Resolves the resume position once the page list is known, whichever
  /// source it came from.
  void _afterPagesLoaded(int total) {
    initialPage = _resumePage(total);
    page.value = initialPage;
    initialOffset = _resumeOffset();
    _offset = initialOffset;
    _maxOffset = currentChapter?.maxOffset ?? 0;
    initialMaxOffset = _maxOffset;
  }

  /// The downloaded pages for this chapter, or null if there are none.
  ///
  /// Sorted by filename, which the downloader zero-pads for exactly this
  /// reason: "10" sorts before "2" otherwise, and a shuffled chapter is worse
  /// than one that did not download.
  Future<List<PageUrl>?> _localPages() async {
    final path = currentChapter?.localPath;
    if (path == null || path.isEmpty) return null;

    final dir = Directory(path);
    // Filtered to the extensions the downloader itself writes. Anything else
    // in here was put there by something else — a `.nomedia`, a thumbnail from
    // a gallery app that scanned the folder — and it would sort ahead of
    // `0001.jpg` and render as a broken first page.
    final files = await dir.exists()
        ? (await dir.list().toList())
              .whereType<File>()
              .where(
                (f) => kDownloadedPageExtensions.contains(
                  p.extension(f.path).toLowerCase(),
                ),
              )
              .toList()
        : <File>[];
    if (files.isEmpty) {
      // The pointer is stale — storage was cleared, or the download folder was
      // moved. Falling back to the network is only half an answer: the details
      // screen reads the same field and would go on offering "delete" for a
      // download that is not there, with no way to fetch it again. The reader
      // is where the staleness is *discovered*, so it is where it is cleared.
      await _library.setChapterLocalPath(
        sourceId: sourceId,
        url: mangaUrl,
        chapterUrl: currentChapterUrl.value,
        localPath: null,
      );
      return null;
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return [for (final file in files) PageUrl(file.path)];
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

  /// The scroll extent the stored offset was measured against.
  ///
  /// A raw pixel offset only means anything relative to the strip it came from,
  /// and the strip changes height: images load at a different resolution, the
  /// device rotates, the source republishes the chapter with more pages. The
  /// screen corrects for that after the first layout — see `initialOffset`.
  double initialMaxOffset = 0;

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

  Future<void> _persist({bool? markRead}) async {
    final chapterUrl = currentChapterUrl.value;
    final total = pages.length;
    if (total == 0) return;
    final entry = await _library.find(sourceId, mangaUrl);
    if (entry == null) return;

    final reachedEnd = page.value >= total - 1;
    final nowRead = markRead ?? reachedEnd;

    // Read *before* the write, because the write is what changes it. This is a
    // transition detector rather than a state check, and it has to be:
    // `onPageChanged` fires on every scroll, so a chapter already sitting at
    // its last page would otherwise report itself to AniList again on every
    // twitch of the finger.
    // Written out rather than `firstWhereOrNull`: that extension reaches this
    // file only through somebody else's re-export, and a loop needs nothing.
    Chapter? before;
    for (final chapter in entry.chapters) {
      if (chapter.url == chapterUrl) {
        before = chapter;
        break;
      }
    }
    final becameRead = nowRead && !(before?.read ?? false);

    await _library.updateChapterProgress(
      sourceId: sourceId,
      url: mangaUrl,
      chapterUrl: chapterUrl,
      lastPageRead: page.value,
      totalPages: total,
      currentOffset: _offset,
      maxOffset: _maxOffset,
      // Reaching the last page is what marks a chapter read. Doing it on open
      // would mark a chapter read that was merely glanced at -- see the
      // explicit `markRead: false` on the initial save.
      markRead: nowRead,
    );

    if (!becameRead) return;
    // Unawaited on purpose. This is a network round trip sitting behind a page
    // turn, and the reader must not wait on a tracker to record where the user
    // got to. It reports nothing to the screen for the same reason: the user
    // did not ask for this write, so a snackbar over the last page of a
    // chapter would interrupt them about something they did not do.
    unawaited(
      _anilistProgress.reportChapter(
        entryId: entry.id,
        chapterNumber: before?.number,
      ),
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

  void setWebtoonDirection(ReadingDirection value) {
    webtoonDirection.value = value;
    ReaderKeys.webtoonDirection.set<int>(value.index);
  }

  /// Writes [value] to whichever direction the current layout is reading.
  ///
  /// The reader's own control should not have to know which of the two keys it
  /// is editing — that is the knowledge [activeDirection] already holds, and
  /// splitting it across the control and the controller is how the two come to
  /// disagree.
  void setActiveDirection(ReadingDirection value) =>
      layout.value == ReadingLayout.webtoon
      ? setWebtoonDirection(value)
      : setDirection(value);
}
