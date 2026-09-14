// prefer_initializing_formals wants `this._sources` in the constructor, which
// Dart does not allow -- a named parameter cannot be private. The fields stay
// private deliberately: public ones would invite call sites to reach through
// the controller to the repositories it exists to mediate.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:get/get.dart';

import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/data/anilist/anilist_metadata_service.dart';
import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';

/// Which chapters the list is showing.
enum ChapterFilter { all, unread }

/// One manga's detail page: metadata, chapter list, and library membership.
/// What came of writing the user's AniList row.
///
/// Three outcomes rather than a bool, for the same reason `SignInResult` has
/// three: "AniList refused this" and "this app never sent it" are different
/// events and need different words. Collapsing them made a write dropped by
/// the in-flight guard report itself as a refusal by AniList — a sentence
/// about a server that was never asked.
enum AniListSaveResult {
  /// AniList took it, and the row on screen is what it now holds.
  ok,

  /// Offered and declined, or there was nothing to offer it to.
  refused,

  /// Never offered: another write was already in flight. The write that *is*
  /// in flight will report itself, so this needs no word of its own.
  busy,
}

class MangaDetailsController extends GetxController {
  MangaDetailsController({
    required SourceRepository sources,
    required LibraryRepository library,
    required AniListMetadataService anilist,
    required AniListListService anilistList,
    required DownloadRepository downloads,
    required this.sourceId,
    required this.url,
    MManga? initial,
  }) : _sources = sources,
       _library = library,
       _anilist = anilist,
       _anilistList = anilistList,
       _downloads = downloads,
       _initial = initial;

  final SourceRepository _sources;
  final LibraryRepository _library;
  final AniListMetadataService _anilist;
  final AniListListService _anilistList;
  final DownloadRepository _downloads;
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

  /// AniList metadata, when a **confident** match exists.
  ///
  /// Null is the ordinary case for an obscure title, not an error, and renders
  /// nothing: a wrong synopsis and wrong tags look exactly as authoritative as
  /// right ones. The recourse is [linkTo], not a lower threshold.
  final anilist = Rxn<AniListMedia>();
  final isLoadingAniList = false.obs;

  /// The signed-in user's own list row for this manga, and what kind of
  /// answer that is.
  ///
  /// Tri-state rather than a nullable row, because "not on your list" is an
  /// invitation to add it while "signed out" and "AniList unreachable" are
  /// not. Never cached: progress changes whenever the user reads a chapter on
  /// another device, and a stale number claiming they are on chapter 12 after
  /// they read 20 is worse than no number.
  final anilistList = const AniListListResult.signedOut().obs;

  /// True while a list edit is in flight, so the sheet can refuse a second
  /// tap rather than race itself.
  final isSavingAniList = false.obs;

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
    // The reader writes the user's position on a debounce and flushes it from
    // its own `onClose`, which cannot be awaited — so the `await refreshEntry()`
    // the chapter list does when the reader pops can win that race and leave
    // the list showing stale progress. Watching the repository closes it by
    // reacting to the write itself rather than by guessing the ordering.
    _readDownloads();
    _downloadWatch = _downloads.changes.listen((_) => _readDownloads());
    _watch = _library.changes.listen((_) {
      _watchDebounce?.cancel();
      _watchDebounce = Timer(
        const Duration(milliseconds: 200),
        () => unawaited(refreshEntry()),
      );
    });
  }

  StreamSubscription<void>? _watch;
  Timer? _watchDebounce;
  StreamSubscription<void>? _downloadWatch;

  /// Rebuilt on every queue change so the chapter list's per-row control can
  /// be read synchronously while the list is scrolling.
  final downloadTasks = <String, DownloadTask>{}.obs;

  DownloadTask? downloadFor(Chapter chapter) =>
      downloadTasks['$sourceId $url ${chapter.url}'];

  void _readDownloads() {
    downloadTasks.value = {
      for (final task in _downloads.tasks)
        if (task.sourceId == sourceId && task.mangaUrl == url) task.key: task,
    };
  }

  /// Queues a chapter, or retries one that failed.
  Future<void> download(Chapter chapter) => _downloads.enqueue(
    sourceId: sourceId,
    mangaUrl: url,
    chapter: chapter,
    mangaTitle: entry.value?.displayTitle ?? preview?.name ?? 'Manga',
  );

  /// Deletes a chapter's downloaded pages. Read state is untouched.
  Future<void> deleteDownload(Chapter chapter) async {
    final chapterUrl = chapter.url;
    if (chapterUrl == null) return;
    await _downloads.deleteChapter(
      sourceId: sourceId,
      mangaUrl: url,
      chapterUrl: chapterUrl,
    );
  }

  @override
  void onClose() {
    _watchDebounce?.cancel();
    unawaited(_watch?.cancel());
    unawaited(_downloadWatch?.cancel());
    super.onClose();
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
      // Guarded like every other write in this method. An older load resuming
      // here would put its source's base URL on the *current* manga, and this
      // value is the Referer/Origin on every cover request — so the cover would
      // 403 for a reason nothing on screen could explain.
      if (generation != _generation) return;
      // The runtime's effective base URL, not the stored one: a source can
      // override it from a mirror preference.
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
      // Deliberately not awaited: AniList is supplementary, and the chapter
      // list must not wait on a third-party API to render.
      unawaited(_loadAniList(generation));
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

  /// Fetches AniList metadata for the current entry, if one is stored.
  Future<void> _loadAniList(int generation, {bool force = false}) async {
    final id = entry.value?.id;
    final title = entry.value?.title;
    if (id == null || title == null || title.isEmpty) return;
    isLoadingAniList.value = true;
    try {
      final media = await _anilist.metadataFor(
        entryId: id,
        title: title,
        forceRefresh: force,
      );
      if (generation != _generation) return;
      anilist.value = media;
      // Sequential, not parallel: the list row is keyed by the AniList media
      // id, which only exists once the match above resolved.
      await _loadAniListEntry(generation, media?.id);
    } catch (_) {
      // Swallowed on purpose. A page that works without AniList must not show
      // an error because AniList was unreachable — the chapter list, the cover
      // and the reader are all unaffected.
    } finally {
      if (generation == _generation) isLoadingAniList.value = false;
    }
  }

  Future<void> _loadAniListEntry(int generation, int? mediaId) async {
    if (mediaId == null) {
      anilistList.value = const AniListListResult.signedOut();
      return;
    }
    final result = await _anilistList.lookUp(mediaId);
    if (generation != _generation) return;
    anilistList.value = result;
  }

  /// Writes the user's list row.
  ///
  /// Only what the caller passes is sent — see `AniListListService.save`. The
  /// row is replaced with what AniList returns rather than with what was
  /// asked for, because the server may normalise it.
  ///
  /// [AniListSaveResult.busy] is **not** a refusal, and the distinction is the
  /// whole reason this is not a bool: a write dropped because another was
  /// already in flight was never offered to AniList, so reporting it as
  /// "AniList did not save that" states something untrue about a server that
  /// was never asked.
  Future<AniListSaveResult> saveAniList({
    AniListListStatus? status,
    int? progress,
  }) async {
    final mediaId = anilist.value?.id;
    if (mediaId == null) return AniListSaveResult.refused;
    if (isSavingAniList.value) return AniListSaveResult.busy;
    isSavingAniList.value = true;
    try {
      final saved = await _anilistList.save(
        mediaId: mediaId,
        status: status,
        progress: progress,
      );
      if (saved == null) return AniListSaveResult.refused;
      // Publish only if this page is still about the media the write went to.
      // Unlinking or re-linking while it was in flight leaves the response
      // describing a series the page no longer claims to be, and restoring a
      // row the user just removed is worse than dropping a display update.
      //
      // Deliberately *not* the `_generation` check the load path uses:
      // `unlinkAniList` does not bump it, so a generation compare alone would
      // miss the very case that matters. The media id is what actually
      // identifies what was written.
      if (anilist.value?.id == mediaId) {
        anilistList.value = AniListListResult(AniListListLookup.onList, saved);
      }
      // Still `ok`: AniList did take the write. Only the display was dropped.
      return AniListSaveResult.ok;
    } finally {
      isSavingAniList.value = false;
    }
  }

  /// Candidates for the manual picker, best first.
  Future<List<TitleMatch>> anilistCandidates() async {
    final title = entry.value?.title ?? _initial?.name ?? '';
    return _anilist.candidates(title);
  }

  /// Records the user's pick. It outlives the metadata cache, and
  /// auto-matching never overwrites it.
  Future<void> linkTo(int anilistId) async {
    final id = entry.value?.id;
    if (id == null) return;
    _anilist.setLink(id, anilistId);
    await _loadAniList(_generation, force: true);
  }

  Future<void> unlinkAniList() async {
    final id = entry.value?.id;
    if (id == null) return;
    _anilist.clearLink(id);
    anilist.value = null;
    // The list row belongs to the media that was just unlinked. Leaving it
    // would show the user's progress on a series this page no longer claims
    // to be.
    anilistList.value = const AniListListResult.signedOut();
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
