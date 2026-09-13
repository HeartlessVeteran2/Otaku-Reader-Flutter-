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
  }) : _sources = sources;

  final SourceRepository _sources;
  final int sourceId;

  final items = <MManga>[].obs;
  final mode = BrowseMode.popular.obs;
  final query = ''.obs;

  final isLoading = false.obs;
  final isLoadingMore = false.obs;
  final hasNextPage = true.obs;
  final error = RxnString();

  final source = Rxn<Source>();
  final supportsLatest = true.obs;

  int _page = 1;
  SourceMethods? _methods;

  /// Incremented on every reset. A response carrying a stale token is dropped.
  ///
  /// Without this, typing a second search while page 2 of the first is still in
  /// flight appends the old source's results underneath the new ones — a bug
  /// that only appears on a slow network, which is exactly where it is hardest
  /// to notice and most likely to happen.
  int _generation = 0;

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
    _page = 1;
    hasNextPage.value = true;
    error.value = null;
    isLoading.value = true;
    try {
      final page = await _fetch(1);
      if (generation != _generation) return;
      items.value = page.list;
      hasNextPage.value = page.hasNextPage;
    } catch (e) {
      if (generation != _generation) return;
      // Deliberately does not clear `items`: a failure on a refresh should
      // leave what the user was already looking at on screen.
      error.value = _describe(e);
    } finally {
      if (generation == _generation) isLoading.value = false;
    }
  }

  /// Appends the next page, if there is one.
  Future<void> loadMore() async {
    if (isLoading.value || isLoadingMore.value || !hasNextPage.value) return;
    final generation = _generation;
    isLoadingMore.value = true;
    try {
      final page = await _fetch(_page + 1);
      if (generation != _generation) return;
      _page++;
      items.addAll(page.list);
      hasNextPage.value = page.hasNextPage;
    } catch (e) {
      if (generation != _generation) return;
      error.value = _describe(e);
      // Stop paging on a failure rather than retrying the same page every time
      // the user reaches the bottom.
      hasNextPage.value = false;
    } finally {
      if (generation == _generation) isLoadingMore.value = false;
    }
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
