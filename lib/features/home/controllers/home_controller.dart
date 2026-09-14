// prefer_initializing_formals wants `this._anilist`, which Dart does not allow:
// a named parameter cannot be private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:get/get.dart';

import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/domain/repository/anilist_repository.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';

/// One titled row on the home page.
class HomeShelf {
  const HomeShelf({required this.title, required this.items});

  final String title;
  final List<AniListMedia> items;
}

/// The home page: what the user is reading, then AniList's shelves.
///
/// Continue Reading comes first and comes from the **library**, not AniList.
/// A home page that leads with a third-party chart is a discovery page; the
/// first question it should answer is "what was I in the middle of".
class HomeController extends GetxController {
  HomeController({
    required AniListRepository anilist,
    required LibraryRepository library,
    required NsfwPreference nsfw,
  }) : _anilist = anilist,
       _library = library,
       _nsfw = nsfw;

  final AniListRepository _anilist;
  final LibraryRepository _library;
  final NsfwPreference _nsfw;

  final continueReading = <MangaEntry>[].obs;
  final shelves = <HomeShelf>[].obs;
  final isLoading = false.obs;
  final error = RxnString();

  /// The last AniList payload, kept so the 18+ filter can be re-applied
  /// without another network call.
  ///
  /// Filtering happens when a shelf is *built*, so flipping the preference
  /// cannot change shelves that already exist — it can only rebuild them, and
  /// rebuilding needs the unfiltered data. Reloading instead would make a
  /// settings toggle hit AniList, which is a lot to charge for a switch.
  Map<String, List<AniListMedia>> _raw = const {};

  /// Whether adult titles are shown. Reads the shared preference rather than a
  /// copy — a copy is what made the Settings toggle unable to reach this
  /// screen at all.
  RxBool get showNsfw => _nsfw.shown;

  static const shelfTitles = {
    'trending': 'Trending now',
    'popular': 'All-time popular',
    'topRated': 'Top rated',
    'newReleases': 'Newly releasing',
  };

  @override
  void onInit() {
    super.onInit();
    load();
    _startWatching();
    // Rebuild rather than reload: the preference changing is not new data.
    _nsfwWatch = ever(_nsfw.shown, (_) => _rebuildShelves());
  }

  Worker? _nsfwWatch;

  @override
  void onClose() {
    _watchDebounce?.cancel();
    unawaited(_watch?.cancel());
    // The preference outlives this controller — it is a permanent singleton —
    // so a worker left running would rebuild shelves on a disposed Rx.
    _nsfwWatch?.dispose();
    super.onClose();
  }

  /// Refreshes Continue Reading when the library changes elsewhere.
  ///
  /// The tabs live in an `IndexedStack` and stay mounted, so no lifecycle hook
  /// fires when one is reselected — favouriting from Browse left this stale
  /// until the app restarted, and `didChangeDependencies` was a fix for a
  /// different case (a fresh push) that looked like a fix for this one.
  ///
  /// Only the library half: the AniList shelves are a network call and nothing
  /// local can have changed them. Debounced, because a library refresh writes
  /// once per series and this would otherwise reload once per write.
  StreamSubscription<void>? _watch;
  Timer? _watchDebounce;

  void _startWatching() {
    _watch = _library.changes.listen((_) {
      _watchDebounce?.cancel();
      _watchDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_loadContinueReading()),
      );
    });
  }

  /// Counts the loads started, so a slower earlier one cannot land last.
  ///
  /// Two callers can overlap: pull-to-refresh and the error banner's retry —
  /// and the banner is on screen precisely when a previous load failed, so
  /// tapping retry and then pulling is an ordinary thing to do. Without this
  /// the older response overwrites the newer shelves whenever it finishes
  /// second, and its `finally` clears `isLoading` while the newer one is still
  /// running.
  int _load = 0;

  Future<void> load() async {
    final load = ++_load;
    isLoading.value = true;
    error.value = null;
    try {
      // The library half first, and independently: it works offline, and a
      // failed AniList call must not empty it.
      await _loadContinueReading(load);
      await _loadShelves(load);
    } finally {
      // Only the newest load owns the spinner. An older one clearing it would
      // hide that a newer fetch is still in flight.
      if (load == _load) isLoading.value = false;
    }
  }

  Future<void> _loadContinueReading([int? load]) async {
    final favourites = await _library.favorites();
    final started =
        favourites.where((e) => e.lastRead != null && unreadOf(e) > 0).toList()
          ..sort((a, b) => b.lastRead!.compareTo(a.lastRead!));
    if (load != null && load != _load) return;
    continueReading.value = started.take(20).toList();
  }

  Future<void> _loadShelves([int? load]) async {
    try {
      final data = await _anilist.home();
      // Every write below is guarded, not just the shelves: a stale failure
      // would otherwise raise the error banner over a newer load that worked.
      if (load != null && load != _load) return;
      if (data.isEmpty) {
        // Empty is a failure here, not an empty chart: AniList always has
        // trending manga, so nothing back means the call did not work.
        error.value =
            'Could not reach AniList. Your library is still available below.';
        return;
      }
      // Filter first, then drop the empty ones. Testing the raw list would
      // leave a titled row with nothing under it whenever every entry on a
      // shelf was filtered out -- which is the whole shelf for a user who
      // hides adult titles and a chart that happens to be full of them.
      _raw = data;
      _rebuildShelves();
    } catch (_) {
      if (load != null && load != _load) return;
      error.value =
          'Could not reach AniList. Your library is still available below.';
    }
  }

  /// Rebuilds the shelves from the last payload under the current filter.
  ///
  /// Filter first, then drop the empty ones. Testing the raw list would leave
  /// a titled row with nothing under it whenever every entry on a shelf was
  /// filtered out — which is the whole shelf for a user who hides adult titles
  /// and a chart that happens to be full of them.
  void _rebuildShelves() {
    shelves.value = [
      for (final entry in shelfTitles.entries)
        if (_filtered(_raw[entry.key] ?? const []) case final items
            when items.isNotEmpty)
          HomeShelf(title: entry.value, items: items),
    ];
  }

  /// Honours the same NSFW preference as the extensions screen, so a user who
  /// hid adult sources does not meet adult covers on the home page instead.
  List<AniListMedia> _filtered(List<AniListMedia> items) =>
      showNsfw.value ? items : items.where((m) => !m.isAdult).toList();

  static int unreadOf(MangaEntry entry) =>
      entry.chapters.where((c) => !c.read).length;

  /// The chapter a Continue Reading tile should open: the first unread one, in
  /// reading order.
  static Chapter? nextChapter(MangaEntry entry) {
    final unread = entry.chapters.where((c) => !c.read).toList()
      ..sort(
        (a, b) => (a.number ?? double.infinity).compareTo(
          b.number ?? double.infinity,
        ),
      );
    return unread.isEmpty ? null : unread.first;
  }
}
