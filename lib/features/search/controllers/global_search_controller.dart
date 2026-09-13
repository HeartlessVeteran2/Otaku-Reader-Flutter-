// prefer_initializing_formals wants `this._sources`, which Dart does not allow:
// a named parameter cannot be private.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/source.dart';

/// One source's slice of a global search.
///
/// Every source gets a row whatever happens to it, so a site that is down shows
/// as a named failure rather than silently vanishing from the results — which
/// otherwise reads as "this manga is not on that source".
class SourceSearchResult {
  const SourceSearchResult({
    required this.source,
    required this.baseUrl,
    this.items = const [],
    this.isLoading = true,
    this.error,
  });

  final Source source;

  /// The base URL actually in effect, for cover Referer/Origin headers. A
  /// mirror preference can move it, so `Source.baseUrl` is not necessarily it.
  final String baseUrl;

  final List<MManga> items;
  final bool isLoading;
  final String? error;

  SourceSearchResult copyWith({
    String? baseUrl,
    List<MManga>? items,
    bool? isLoading,
    String? error,
  }) => SourceSearchResult(
    source: source,
    baseUrl: baseUrl ?? this.baseUrl,
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

/// Searches every installed source at once.
///
/// This is the only screen that answers "where can I read this?", so it is also
/// where an AniList tile lands: an AniList entry is a title and nothing else,
/// and the installed sources are the only things that can turn it into pages.
class GlobalSearchController extends GetxController {
  GlobalSearchController({required SourceRepository sources})
    : _sources = sources;

  final SourceRepository _sources;

  /// How many sources are queried at once.
  ///
  /// Unbounded would fire one request per installed source the instant the user
  /// stops typing — with a Madara repo installed that is 150 connections, which
  /// gets an IP rate-limited faster than it gets results.
  static const _concurrency = 4;

  /// How many hits to keep per source. A global search is for picking a source,
  /// not for browsing one; the row links through to the source's own screen.
  static const perSourceLimit = 10;

  final results = <SourceSearchResult>[].obs;
  final query = ''.obs;
  final isSearching = false.obs;
  final error = RxnString();

  /// Incremented on every new search. A response carrying a stale token is
  /// dropped, so a slow source from the previous query cannot append its hits
  /// under the current one.
  int _generation = 0;

  Timer? _debounce;

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }

  /// Types into the search box. The request is debounced; [search] runs it now.
  void onQueryChanged(String value) {
    query.value = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => search(value));
  }

  Future<void> search(String raw) async {
    _debounce?.cancel();
    final q = raw.trim();
    query.value = raw;
    final token = ++_generation;

    if (q.isEmpty) {
      results.clear();
      isSearching.value = false;
      error.value = null;
      return;
    }

    isSearching.value = true;
    error.value = null;

    final langs = SourceKeys.enabledLanguages.get<List<String>?>(null);
    final installed = await _sources.installedSources(
      // An empty stored set means "the user turned every language off", but no
      // stored value at all means they never chose — and filtering to nothing
      // would give a first-run user an empty result that looks like a failure.
      langs: (langs == null || langs.isEmpty) ? null : langs.toSet(),
      includeNsfw: SourceKeys.showNsfwSources.get<bool>(false),
    );
    if (token != _generation) return;

    final pinned = SourceKeys.pinnedSourceIds.get<List<String>?>(null)?.toSet();
    final ordered = [...installed]
      ..sort((a, b) {
        final ap = pinned?.contains('${a.sourceId}') ?? false;
        final bp = pinned?.contains('${b.sourceId}') ?? false;
        if (ap != bp) return ap ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    if (ordered.isEmpty) {
      results.clear();
      isSearching.value = false;
      error.value =
          'No sources installed. Add an extension from the Browse tab first.';
      return;
    }

    // Every row is laid out up front, in final order, so rows do not jump
    // around as slow sources land.
    results.value = [
      for (final s in ordered)
        SourceSearchResult(source: s, baseUrl: s.baseUrl ?? ''),
    ];

    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (token != _generation) return;
        final i = next++;
        if (i >= ordered.length) return;
        await _searchOne(i, ordered[i], q, token);
      }
    }

    await Future.wait([
      for (var i = 0; i < _concurrency && i < ordered.length; i++) worker(),
    ]);
    if (token != _generation) return;
    isSearching.value = false;
  }

  Future<void> _searchOne(int index, Source source, String q, int token) async {
    try {
      final methods = await _sources.methodsFor(source.sourceId);
      if (token != _generation) return;
      final page = await methods.search(q, 1, FilterList([]));
      if (token != _generation) return;

      final base = methods.sourceBaseUrl.isNotEmpty
          ? methods.sourceBaseUrl
          : (source.baseUrl ?? '');
      _update(
        index,
        token,
        (r) => r.copyWith(
          isLoading: false,
          items: page.list.take(perSourceLimit).toList(),
          baseUrl: base,
        ),
      );
    } catch (e) {
      if (token != _generation) return;
      _update(index, token, (r) => r.copyWith(isLoading: false, error: '$e'));
    }
  }

  /// Rebuilds one row in place.
  ///
  /// Guarded by the index still being in range as well as by the token: a
  /// search that resets `results` between the await and this write would
  /// otherwise index past the end of the new, shorter list.
  void _update(
    int index,
    int token,
    SourceSearchResult Function(SourceSearchResult) change,
  ) {
    if (token != _generation || index >= results.length) return;
    results[index] = change(results[index]);
  }
}
