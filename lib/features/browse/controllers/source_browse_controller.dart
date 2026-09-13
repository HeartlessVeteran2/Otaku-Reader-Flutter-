// prefer_initializing_formals wants `this._sources` in the constructor, which
// Dart does not allow -- a named parameter cannot be private. The field stays
// private deliberately: a public one would invite call sites to reach through
// the controller to the repository it exists to mediate.
// ignore_for_file: prefer_initializing_formals

import 'package:get/get.dart';

import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/source_methods.dart';

/// Which listing the browse screen is showing.
enum BrowseMode { popular, latest, search }

/// Pages one source's catalogue: popular, latest, or a search.
///
/// One controller per source, constructed with the source id so the screen can
/// be opened for any installed extension.
class SourceBrowseController extends GetxController {
  SourceBrowseController({
    required SourceRepository sources,
    required this.sourceId,
    String? initialQuery,
  }) : _sources = sources {
    // Applied here rather than by the screen calling setQuery after
    // construction: setQuery calls reload(), and _start() has not yet resolved
    // the source's methods at that point, so that reload fails with "Source is
    // not ready" and the arriving search is the *second* load, racing the
    // first.
    final q = initialQuery?.trim() ?? '';
    if (q.isNotEmpty) {
      query.value = q;
      mode.value = BrowseMode.search;
    }
  }

  final SourceRepository _sources;
  final int sourceId;

  final items = <MManga>[].obs;
  final mode = BrowseMode.popular.obs;
  final query = ''.obs;

  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final hasNextPage = true.obs;

  /// A failed *reload*. The grid keeps its previous results, so this is what
  /// the "could not refresh" banner reads.
  final error = RxnString();

  /// A failed *next page*. Kept apart from [error] because the two want
  /// different words and a different retry: a banner saying the refresh failed,
  /// whose button reloads page 1, is wrong on both counts when what actually
  /// failed was page 4.
  final pagingError = RxnString();

  final source = Rxn<Source>();
  final supportsLatest = true.obs;

  /// The base URL actually in effect, which is what cover requests need for
  /// their Referer and Origin. A source can override it from a mirror
  /// preference, so the stored `Source.baseUrl` is not necessarily right.
  final effectiveBaseUrl = ''.obs;

  int _page = 1;
  SourceMethods? _methods;

  /// Incremented on every reset. A response carrying a stale token is dropped.
  ///
  /// Without this, typing a second search while page 2 of the first is still in
  /// flight appends the old source's results underneath the new ones — a bug
  /// that only appears on a slow network, which is exactly where it is hardest
  /// to notice and most likely to happen.
  int _generation = 0;

  /// Identifies which `loadMore` currently owns [isLoadingMore].
  ///
  /// Clearing the flag unconditionally in `finally` fixed the stuck-forever
  /// case but introduced a narrower one: a superseded page finishing after a
  /// *newer* loadMore had started would clear the newer request's guard, and
  /// the next scroll would fetch and append the same page twice. Only the
  /// owning operation clears it.
  int _loadMoreToken = 0;

  @override
  void onInit() {
    super.onInit();
    _start();
  }

  Future<void> _start() async {
    try {
      source.value = await _sources.sourceById(sourceId);
      _methods = await _sources.methodsFor(sourceId);
      supportsLatest.value = _methods!.supportsLatest;
      final effective = _methods!.sourceBaseUrl;
      effectiveBaseUrl.value = effective.isNotEmpty
          ? effective
          : source.value?.baseUrl ?? '';
      await _sources.markUsed(sourceId);
      await reload();
    } catch (e) {
      error.value = '$e';
      isLoading.value = false;
    }
  }

  void setMode(BrowseMode value) {
    if (mode.value == value) return;
    mode.value = value;
    reload();
  }

  void setQuery(String value) {
    query.value = value;
    mode.value = value.trim().isEmpty ? BrowseMode.popular : BrowseMode.search;
    reload();
  }

  /// Starts the current listing again from page 1.
  Future<void> reload() async {
    final generation = ++_generation;
    // A reload invalidates any in-flight paging: disown it and release the
    // guard now, rather than waiting for a response that will be discarded.
    _loadMoreToken++;
    isLoadingMore.value = false;
    error.value = null;
    pagingError.value = null;
    isLoading.value = true;
    try {
      final page = await _fetch(1);
      if (generation != _generation) return;
      // Committed only on success. Resetting the cursor up front and then
      // failing leaves the old pages on screen with `_page` back at 1, so the
      // next scroll re-fetches page 2 and appends a duplicate of what is
      // already there.
      _page = 1;
      items.value = page.list;
      hasNextPage.value = page.hasNextPage;
    } catch (e) {
      if (generation != _generation) return;
      // Deliberately does not clear `items`: a failure on a refresh should
      // leave what the user was already looking at on screen. Paging stops
      // until a reload succeeds, though -- the listing on screen and the
      // cursor pointing into it no longer necessarily describe the same
      // request, because a failed reload may also have been a mode change.
      hasNextPage.value = false;
      error.value = _describe(e);
    } finally {
      if (generation == _generation) isLoading.value = false;
    }
  }

  /// Appends the next page, if there is one.
  Future<void> loadMore() async {
    if (isLoading.value || isLoadingMore.value || !hasNextPage.value) return;
    final generation = _generation;
    final token = ++_loadMoreToken;
    isLoadingMore.value = true;
    pagingError.value = null;
    try {
      final page = await _fetch(_page + 1);
      if (generation != _generation) return;
      _page++;
      items.addAll(page.list);
      hasNextPage.value = page.hasNextPage;
    } catch (e) {
      if (generation != _generation) return;
      pagingError.value = _describe(e);
      // Stop paging on a failure rather than retrying the same page every time
      // the user reaches the bottom.
      hasNextPage.value = false;
    } finally {
      // Only the owning operation releases the guard. Guarding on the
      // *generation* left it stuck true forever after a reload; clearing it
      // unconditionally let a superseded page release a newer request's guard
      // and duplicate a page. The token distinguishes the two.
      if (token == _loadMoreToken) isLoadingMore.value = false;
    }
  }

  /// Tries the failed page again, without discarding what is already listed.
  ///
  /// `reload()` is the wrong recovery here: it throws away pages 1..n to
  /// re-fetch page 1, which is not what the user asked for when page n+1 timed
  /// out.
  Future<void> retryPaging() async {
    if (pagingError.value == null) return;
    pagingError.value = null;
    hasNextPage.value = true;
    await loadMore();
  }

  Future<MPagesLike> _fetch(int page) async {
    final methods = _methods;
    if (methods == null) throw StateError('Source is not ready');
    final result = switch (mode.value) {
      BrowseMode.popular => await methods.getPopular(page),
      BrowseMode.latest => await methods.getLatestUpdates(page),
      BrowseMode.search => await methods.search(
        query.value.trim(),
        page,
        FilterList([]),
      ),
    };
    return MPagesLike(result.list, result.hasNextPage);
  }

  /// Turns an extension failure into something a user can act on.
  ///
  /// Every hard failure in this project's own live sweep was external — a dead
  /// domain, a redirect to a moved site, a Cloudflare interstitial — so the
  /// message points at the site rather than implying the app is broken.
  String _describe(Object error) {
    final name = source.value?.name ?? 'This source';
    return '$name did not respond as expected. The site may be down, moved, '
        'or blocking requests.\n\n$error';
  }
}

/// Decouples the controller from `MPages`, which the runtime owns.
class MPagesLike {
  const MPagesLike(this.list, this.hasNextPage);
  final List<MManga> list;
  final bool hasNextPage;
}
