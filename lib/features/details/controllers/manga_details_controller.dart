// prefer_initializing_formals wants `this._sources` in the constructor, which
// Dart does not allow -- a named parameter cannot be private. The fields stay
// private deliberately: public ones would invite call sites to reach through
// the controller to the repositories it exists to mediate.
// ignore_for_file: prefer_initializing_formals

import 'package:get/get.dart';

import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/m_manga.dart';

/// Which chapters the list is showing.
enum ChapterFilter { all, unread }

/// One manga's detail page: metadata, chapter list, and library membership.
class MangaDetailsController extends GetxController {
  MangaDetailsController({
    required SourceRepository sources,
    required LibraryRepository library,
    required this.sourceId,
    required this.url,
    MManga? initial,
  }) : _sources = sources,
       _library = library,
       _initial = initial;

  final SourceRepository _sources;
  final LibraryRepository _library;
  final int sourceId;
  final String url;
  final MManga? _initial;

  final entry = Rxn<MangaEntry>();
  final isLoading = false.obs;
  final error = RxnString();
  final descending = true.obs;
  final filter = ChapterFilter.all.obs;
  final sourceBaseUrl = ''.obs;

  /// Incremented on every [load]. A response carrying a stale token is dropped.
  ///
  /// Without it, a pull-to-refresh started before the first load returns lets
  /// the older response land last and overwrite the newer metadata and chapter
  /// list. The browse and reader controllers already guard this way.
  int _generation = 0;

  /// What the browse grid already knew, shown immediately so the page is not a
  /// spinner over nothing while the detail request runs.
  MManga? get preview => _initial;

  bool get isFavorite => entry.value?.favorite ?? false;

  List<Chapter> get chapters {
    final all = entry.value?.chapters ?? const <Chapter>[];
    final visible = filter.value == ChapterFilter.unread
        ? all.where((c) => !c.read).toList()
        : all.toList();
    // Dart's List.sort is *not* stable above 32 elements (below that it uses
    // insertion sort), so returning 0 for two unnumbered chapters lets their
    // order shuffle. Their position in the source's own listing is the only
    // order they have, so it is captured here as the tie-break.
    //
    // Keyed by **identity**, not by url: a source can return several chapters
    // with no url at all, and a url-keyed map collapses them onto one entry —
    // which puts the tie-break back to returning 0 for exactly the rows it was
    // added to protect.
    final sourceOrder = Map<Chapter, int>.identity();
    for (var i = 0; i < all.length; i++) {
      sourceOrder[all[i]] = i;
    }

    visible.sort((a, b) {
      // Unnumbered chapters sort last either way -- many sources title
      // one-shots and extras by name, and sorting those to the top would bury
      // the actual chapter 1.
      final an = a.number;
      final bn = b.number;
      if (an == null && bn == null) {
        return (sourceOrder[a] ?? 0).compareTo(sourceOrder[b] ?? 0);
      }
      if (an == null) return 1;
      if (bn == null) return -1;
      final byNumber = descending.value ? bn.compareTo(an) : an.compareTo(bn);
      if (byNumber != 0) return byNumber;
      return (sourceOrder[a] ?? 0).compareTo(sourceOrder[b] ?? 0);
    });
    return visible;
  }

  int get unreadCount =>
      (entry.value?.chapters ?? const <Chapter>[]).where((c) => !c.read).length;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final generation = ++_generation;
    isLoading.value = true;
    error.value = null;
    try {
      // Show whatever is already stored before the network call, so reopening a
      // manga you have read is instant and works offline.
      final stored = await _library.find(sourceId, url);
      if (generation != _generation) return;
      entry.value = stored;

      final source = await _sources.sourceById(sourceId);
      final methods = await _sources.methodsFor(sourceId);
      // The runtime's effective base URL, not the stored one: a source can
      // override it from a mirror preference, and this value becomes the
      // Referer/Origin on every cover request.
      final effective = methods.sourceBaseUrl;
      sourceBaseUrl.value = effective.isNotEmpty
          ? effective
          : source?.baseUrl ?? '';
      final detail = await methods.getDetail(url);
      if (generation != _generation) return;

      entry.value = await _library.upsertFromSource(
        sourceId: sourceId,
        url: url,
        manga: detail,
      );
    } catch (e) {
      if (generation != _generation) return;
      // Only an error if there is nothing to show. A stored entry plus a failed
      // refresh is a usable page, not a failure.
      if (entry.value == null) {
        error.value =
            'Could not load this manga. The site may be down, moved, or '
            'blocking requests.\n\n$e';
      }
    } finally {
      if (generation == _generation) isLoading.value = false;
    }
  }

  Future<void> toggleFavorite() async {
    // The row has to exist before it can be favourited, and it will not if the
    // detail fetch failed on a manga never opened before.
    if (entry.value == null) return;
    await _library.toggleFavorite(sourceId, url);
    entry.value = await _library.find(sourceId, url);
    entry.refresh();
  }

  Future<void> setRead(Chapter chapter, bool read) async {
    final chapterUrl = chapter.url;
    if (chapterUrl == null) return;
    await _library.setChapterRead(sourceId, url, chapterUrl, read);
    entry.value = await _library.find(sourceId, url);
    entry.refresh();
  }

  /// Marks every chapter up to and including [chapter] as read.
  ///
  /// Ordinary reader behaviour: people come back having read ahead elsewhere,
  /// and ticking forty boxes by hand is not a feature.
  Future<void> markReadUpTo(Chapter chapter) async {
    final target = chapter.number;
    if (target == null) return;
    for (final c in entry.value?.chapters ?? const <Chapter>[]) {
      final n = c.number;
      if (n == null || n > target || c.read) continue;
      final chapterUrl = c.url;
      if (chapterUrl == null) continue;
      await _library.setChapterRead(sourceId, url, chapterUrl, true);
    }
    entry.value = await _library.find(sourceId, url);
    entry.refresh();
  }

  /// Re-reads the stored row without hitting the network.
  ///
  /// The reader writes progress straight to the library, so returning from it
  /// has to pick that up — otherwise a chapter just read still shows unread
  /// until the page is reopened.
  Future<void> refreshEntry() async {
    entry.value = await _library.find(sourceId, url);
    entry.refresh();
  }

  void toggleSort() => descending.value = !descending.value;

  void setFilter(ChapterFilter value) => filter.value = value;
}
