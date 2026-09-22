// prefer_initializing_formals wants `this._library` in the constructor, which
// Dart does not allow -- a named parameter cannot be private. The field stays
// private deliberately: a public one would invite call sites to reach through
// the controller to the repository it exists to mediate.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/data/isar/category_entry.dart';
import 'package:otaku_reader/domain/repository/category_repository.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/data/source_base_urls.dart';

enum LibrarySort { title, lastRead, dateAdded, unread }

/// The user's saved manga.
class LibraryController extends GetxController {
  LibraryController({
    required LibraryRepository library,
    required SourceRepository sources,
    required CategoryRepository categories,
  }) : _library = library,
       _sources = sources,
       _categories = categories;

  final LibraryRepository _library;
  final SourceRepository _sources;
  final CategoryRepository _categories;

  /// Base URL per source id, for cover Referer/Origin headers. Resolved once
  /// per load rather than per card, because every card in the grid rebuilds
  /// constantly while scrolling.
  late final _baseUrls = SourceBaseUrls(_sources);

  String baseUrlFor(MangaEntry entry) => _baseUrls.forEntry(entry);

  final entries = <MangaEntry>[].obs;

  /// The categories, in their stored order. Empty until one is created, and an
  /// empty list is a **first-class state**: the filter bar renders nothing
  /// rather than a lone "All" chip that filters against no alternative.
  final categories = <CategoryEntry>[].obs;

  /// The category being shown, or null for all of them.
  ///
  /// Deliberately not persisted. A filter is a thing you do, not a thing you
  /// configure — coming back to the app and finding two thirds of the library
  /// missing, because of a chip tapped yesterday, reads as data loss.
  final selectedCategory = Rxn<int>();

  final query = ''.obs;
  final sort = LibrarySort.title.obs;
  final ascending = true.obs;
  final isLoading = false.obs;

  @override
  void onInit() {
    super.onInit();
    sort.value =
        LibrarySort.values[LibraryKeys.sortType
            .get<int>(0)
            .clamp(0, LibrarySort.values.length - 1)];
    ascending.value = LibraryKeys.sortAscending.get<bool>(true);
    load();
    unawaited(loadCategories());
    _startWatching();
  }

  @override
  void onClose() {
    _watchDebounce?.cancel();
    unawaited(_watch?.cancel());
    unawaited(_categoryWatch?.cancel());
    super.onClose();
  }

  /// Reloads when the library changes anywhere else in the app.
  ///
  /// The tabs live in an `IndexedStack` and stay mounted, so no lifecycle hook
  /// fires when one is reselected — favouriting from Browse left this stale
  /// until the app restarted, and `didChangeDependencies` was a fix for a
  /// different case (a fresh push) that looked like a fix for this one.
  ///
  /// Debounced, because a library refresh writes once per series and this would
  /// otherwise reload once per write.
  StreamSubscription<void>? _watch;
  StreamSubscription<void>? _categoryWatch;
  Timer? _watchDebounce;

  void _startWatching() {
    _watch = _library.changes.listen((_) {
      _watchDebounce?.cancel();
      _watchDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(load()),
      );
    });
    // A second subscription rather than one merged stream, and **undebounced**.
    // The library's debounce exists because a refresh writes a row per series;
    // a category write is one deliberate tap, and delaying it by 300ms after
    // the user renames a chip is a visible lag for no benefit.
    _categoryWatch = _categories.changes.listen(
      (_) => unawaited(loadCategories()),
    );
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      final favourites = await _library.favorites();
      entries.value = favourites;

      // Hotlink-protected hosts answer a bare GET with 403, so a library of
      // fallback covers looks like the app lost them.
      await _baseUrls.refresh(favourites);
    } finally {
      isLoading.value = false;
    }
  }

  static int unreadOf(MangaEntry entry) =>
      entry.chapters.where((c) => !c.read).length;

  List<MangaEntry> get visible {
    final q = query.value.trim().toLowerCase();
    final category = selectedCategory.value;
    final list = entries
        .where((e) => q.isEmpty || e.displayTitle.toLowerCase().contains(q))
        // Filtered here rather than by re-querying: the grid already holds
        // every favourite, and a category is a handful of ids on each row.
        // Round-tripping the database on a chip tap would also drop the
        // search, which is a second filter the user is still holding.
        .where((e) => category == null || e.categoryIds.contains(category))
        .toList();

    list.sort((a, b) {
      // Nulls are resolved *before* the direction flip below, not inside the
      // comparison. An entry never read has no position on a "last read" axis,
      // and if null-handling rode along with the flip, reversing the sort would
      // move every never-opened entry to the top -- burying exactly what the
      // user wanted to get back to. An earlier version did precisely that, with
      // a comment claiming otherwise; the test caught it.
      final nulls = switch (sort.value) {
        LibrarySort.lastRead => _nullsLast(a.lastRead, b.lastRead),
        LibrarySort.dateAdded => _nullsLast(a.dateAdded, b.dateAdded),
        _ => null,
      };
      if (nulls != null) return nulls;

      final result = switch (sort.value) {
        LibrarySort.title => a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        ),
        LibrarySort.lastRead => a.lastRead!.compareTo(b.lastRead!),
        LibrarySort.dateAdded => a.dateAdded!.compareTo(b.dateAdded!),
        LibrarySort.unread => unreadOf(a).compareTo(unreadOf(b)),
      };
      return ascending.value ? result : -result;
    });
    return list;
  }

  /// Decides the order when either side is null, or null when both are set.
  ///
  /// A null always loses, so it lands at the end regardless of direction.
  static int? _nullsLast(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return null;
  }

  /// Reloads the category list, and drops a selection that no longer exists.
  ///
  /// That second half is the one that matters. A category deleted from the
  /// management screen while the grid is filtered by it leaves the selection
  /// naming nothing — and `visible` would then answer **empty**, which is a
  /// library that looks wiped. The repository scrubs the ids off the rows;
  /// this scrubs the one held in memory.
  Future<void> loadCategories() async {
    categories.value = await _categories.all();
    final selected = selectedCategory.value;
    if (selected != null && !categories.any((c) => c.id == selected)) {
      selectedCategory.value = null;
    }
  }

  void selectCategory(int? id) => selectedCategory.value = id;

  void setQuery(String value) => query.value = value;

  void setSort(LibrarySort value) {
    if (sort.value == value) {
      ascending.value = !ascending.value;
    } else {
      sort.value = value;
    }
    LibraryKeys.sortType.set<int>(sort.value.index);
    LibraryKeys.sortAscending.set<bool>(ascending.value);
  }
}
