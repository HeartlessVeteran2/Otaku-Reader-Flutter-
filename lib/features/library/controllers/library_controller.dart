// prefer_initializing_formals wants `this._library` in the constructor, which
// Dart does not allow -- a named parameter cannot be private. The field stays
// private deliberately: a public one would invite call sites to reach through
// the controller to the repository it exists to mediate.
// ignore_for_file: prefer_initializing_formals

import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';

enum LibrarySort { title, lastRead, dateAdded, unread }

/// The user's saved manga.
class LibraryController extends GetxController {
  LibraryController({
    required LibraryRepository library,
    required SourceRepository sources,
  }) : _library = library,
       _sources = sources;

  final LibraryRepository _library;
  final SourceRepository _sources;

  /// Base URL per source id, for cover Referer/Origin headers. Resolved once
  /// per load rather than per card, because every card in the grid rebuilds
  /// constantly while scrolling.
  final _baseUrls = <int, String>{};

  String baseUrlFor(MangaEntry entry) {
    final id = LibraryRepository.sourceIdOf(entry);
    return id == null ? '' : _baseUrls[id] ?? '';
  }

  final entries = <MangaEntry>[].obs;
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
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      final favourites = await _library.favorites();
      entries.value = favourites;

      // Hotlink-protected hosts answer a bare GET with 403, so a library of
      // fallback covers looks like the app lost them.
      for (final entry in favourites) {
        final id = LibraryRepository.sourceIdOf(entry);
        if (id == null || _baseUrls.containsKey(id)) continue;
        _baseUrls[id] = (await _sources.sourceById(id))?.baseUrl ?? '';
      }
    } finally {
      isLoading.value = false;
    }
  }

  static int unreadOf(MangaEntry entry) =>
      entry.chapters.where((c) => !c.read).length;

  List<MangaEntry> get visible {
    final q = query.value.trim().toLowerCase();
    final list = entries
        .where((e) => q.isEmpty || e.displayTitle.toLowerCase().contains(q))
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
