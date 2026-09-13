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

  /// What the browse grid already knew, shown immediately so the page is not a
  /// spinner over nothing while the detail request runs.
  MManga? get preview => _initial;

  bool get isFavorite => entry.value?.favorite ?? false;

  List<Chapter> get chapters {
    final all = entry.value?.chapters ?? const <Chapter>[];
    final visible = filter.value == ChapterFilter.unread
        ? all.where((c) => !c.read).toList()
        : all.toList();
    visible.sort((a, b) {
      // Fall back to the order the source listed them in when neither chapter
      // carries a parsable number -- many sources title one-shots and extras by
      // name, and sorting those to the top would bury the actual chapter 1.
      final an = a.number;
      final bn = b.number;
      if (an == null && bn == null) return 0;
      if (an == null) return 1;
      if (bn == null) return -1;
      return descending.value ? bn.compareTo(an) : an.compareTo(bn);
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
    isLoading.value = true;
    error.value = null;
    try {
      // Show whatever is already stored before the network call, so reopening a
      // manga you have read is instant and works offline.
      entry.value = await _library.find(sourceId, url);

      final source = await _sources.sourceById(sourceId);
      sourceBaseUrl.value = source?.baseUrl ?? '';
      final methods = await _sources.methodsFor(sourceId);
      final detail = await methods.getDetail(url);

      entry.value = await _library.upsertFromSource(
        sourceId: sourceId,
        url: url,
        manga: detail,
      );
    } catch (e) {
      // Only an error if there is nothing to show. A stored entry plus a failed
      // refresh is a usable page, not a failure.
      if (entry.value == null) {
        error.value =
            'Could not load this manga. The site may be down, moved, or '
            'blocking requests.\n\n$e';
      }
    } finally {
      isLoading.value = false;
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

  void toggleSort() => descending.value = !descending.value;

  void setFilter(ChapterFilter value) => filter.value = value;
}
