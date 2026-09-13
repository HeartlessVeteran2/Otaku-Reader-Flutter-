// prefer_initializing_formals wants `this._anilist`, which Dart does not allow:
// a named parameter cannot be private.
// ignore_for_file: prefer_initializing_formals

import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
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
  }) : _anilist = anilist,
       _library = library;

  final AniListRepository _anilist;
  final LibraryRepository _library;

  final continueReading = <MangaEntry>[].obs;
  final shelves = <HomeShelf>[].obs;
  final isLoading = false.obs;
  final error = RxnString();
  final showNsfw = false.obs;

  static const shelfTitles = {
    'trending': 'Trending now',
    'popular': 'All-time popular',
    'topRated': 'Top rated',
    'newReleases': 'Newly releasing',
  };

  @override
  void onInit() {
    super.onInit();
    showNsfw.value = SourceKeys.showNsfwSources.get<bool>(false);
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      // The library half first, and independently: it works offline, and a
      // failed AniList call must not empty it.
      await _loadContinueReading();
      await _loadShelves();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loadContinueReading() async {
    final favourites = await _library.favorites();
    final started =
        favourites.where((e) => e.lastRead != null && unreadOf(e) > 0).toList()
          ..sort((a, b) => b.lastRead!.compareTo(a.lastRead!));
    continueReading.value = started.take(20).toList();
  }

  Future<void> _loadShelves() async {
    try {
      final data = await _anilist.home();
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
      shelves.value = [
        for (final entry in shelfTitles.entries)
          if (_filtered(data[entry.key] ?? const []) case final items
              when items.isNotEmpty)
            HomeShelf(title: entry.value, items: items),
      ];
    } catch (_) {
      error.value =
          'Could not reach AniList. Your library is still available below.';
    }
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
