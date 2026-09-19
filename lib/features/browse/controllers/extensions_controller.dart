// prefer_initializing_formals wants `this._extensions` in the constructor,
// which Dart does not allow -- a named parameter cannot be private. The fields
// stay private deliberately: public ones would invite call sites to reach
// through the controller to the repositories it exists to mediate.
// ignore_for_file: prefer_initializing_formals

import 'package:get/get.dart';

import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/domain/repository/extension_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/source.dart';

/// Which slice of the extension list the UI is showing.
enum ExtensionTab { installed, available, updates }

/// Drives the extensions screen: the catalogue, its filters, and install state.
///
/// Holds no widgets and no `BuildContext`, so the whole thing is testable
/// without pumping a frame — which is the point of keeping GetX at the
/// controller layer rather than letting it reach into the domain.
class ExtensionsController extends GetxController {
  ExtensionsController({
    required ExtensionRepository extensions,
    required SourceRepository sources,
    required NsfwPreference nsfw,
  }) : _extensions = extensions,
       _sources = sources,
       _nsfw = nsfw;

  final ExtensionRepository _extensions;
  final SourceRepository _sources;
  final NsfwPreference _nsfw;

  final all = <Source>[].obs;
  final query = ''.obs;
  final enabledLangs = <String>{}.obs;

  /// Whether adult sources are listed. The shared preference, not a copy —
  /// Settings writes the same one, so its toggle reaches this screen too.
  RxBool get showNsfw => _nsfw.shown;

  final isLoading = false.obs;
  final isRefreshing = false.obs;

  /// Source ids with an install/update/uninstall in flight. The UI reads this
  /// to show per-row progress *and* to refuse a second tap: install is not
  /// idempotent from the user's point of view, and two concurrent fetches for
  /// one row would race on the same database write.
  final busy = <int>{}.obs;

  /// Last failure, for a snackbar. Cleared by the next successful action, so a
  /// stale error cannot outlive the thing it described.
  final lastError = RxnString();

  @override
  void onInit() {
    super.onInit();
    final stored = SourceKeys.enabledLanguages.get<List<String>?>();
    // No stored preference means "don't filter yet" rather than "no languages":
    // an empty set here would show the user an empty catalogue on first run and
    // look like the fetch failed.
    // assignAll rather than `.value =`: RxSet's `value` setter is protected,
    // and reassigning the whole set would also drop existing listeners.
    enabledLangs
      ..clear()
      ..addAll(stored ?? const <String>[]);
    load();
  }

  /// Everything matching the current filters, for [tab].
  List<Source> visible(ExtensionTab tab) {
    final q = query.value.trim().toLowerCase();
    return all.where((s) {
        switch (tab) {
          case ExtensionTab.installed:
            if (!s.isInstalled) return false;
          case ExtensionTab.available:
            if (s.isInstalled) return false;
          case ExtensionTab.updates:
            if (!s.hasUpdate) return false;
        }
        if (!showNsfw.value && s.isNsfw) return false;
        if (enabledLangs.isNotEmpty &&
            !enabledLangs.contains(s.lang) &&
            s.lang != 'all') {
          return false;
        }
        if (q.isNotEmpty && !s.name.toLowerCase().contains(q)) return false;
        return true;
      }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  int get updateCount => all.where((s) => s.hasUpdate).length;

  /// Every language present in the catalogue, plus any the user has selected.
  ///
  /// The selected ones matter: if a language disappears from the index while it
  /// is still enabled, offering only what is present hides the very checkbox
  /// needed to turn the now-empty filter off.
  List<String> get availableLangs =>
      {...all.map((s) => s.lang), ...enabledLangs}.toList()..sort();

  Future<void> load() async {
    isLoading.value = true;
    try {
      all.value = await _extensions.listAll();
    } finally {
      isLoading.value = false;
    }
  }

  /// Re-reads every configured repo index.
  ///
  /// Reports the first failure but still reloads: a refresh is per-repo, so one
  /// unreachable repo must not hide what the others returned, and a failed
  /// refresh leaves the previously known sources in place by design.
  Future<void> refreshRepos() async {
    if (isRefreshing.value) return;
    isRefreshing.value = true;
    try {
      final results = await _extensions.refreshAll();
      final failed = results.where((r) => !r.isSuccess).toList();
      lastError.value = failed.isEmpty
          ? null
          : failed.length == 1
          ? 'Could not reach ${_host(failed.single.repoUrl)}'
          : 'Could not reach ${failed.length} repositories';
      await load();
    } catch (e) {
      lastError.value = '$e';
    } finally {
      isRefreshing.value = false;
    }
  }

  Future<void> install(Source source) =>
      _mutate(source, () => _extensions.install(source));

  Future<void> updateSource(Source source) =>
      _mutate(source, () => _extensions.update(source));

  Future<void> uninstall(Source source) =>
      _mutate(source, () => _extensions.uninstall(source));

  /// Runs a catalogue mutation with the row marked busy, then reconciles.
  ///
  /// Evicting here is what makes the cache release an uninstalled source's
  /// interpreter promptly rather than waiting for something to ask again. It is
  /// only safe because [SourceRepository.evict] drops the reference without
  /// disposing: an earlier version disposed, which killed any request a browse
  /// or reader screen had in flight on that runtime the instant the user
  /// updated the source from here.
  Future<void> _mutate(Source source, Future<Source> Function() action) async {
    if (busy.contains(source.sourceId)) return;
    busy.add(source.sourceId);
    try {
      await action();
      _sources.evict(source.sourceId);
      lastError.value = null;
      await load();
    } catch (e) {
      lastError.value = 'Could not update ${source.name}: $e';
    } finally {
      busy.remove(source.sourceId);
    }
  }

  void setQuery(String value) => query.value = value;

  void toggleNsfw(bool value) => _nsfw.setShown(value);

  void toggleLang(String lang) {
    if (enabledLangs.contains(lang)) {
      enabledLangs.remove(lang);
    } else {
      enabledLangs.add(lang);
    }
    SourceKeys.enabledLanguages.set<List<String>>(enabledLangs.toList());
  }

  /// Repo management. Each returns the error to show, or null on success.
  Future<String?> addRepo(String url) async {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'That does not look like a URL';
    }
    if (uri.scheme != 'https') {
      // An index is executable code by proxy — it names the scripts the app
      // will fetch and interpret. Fetching that over plaintext lets anyone on
      // the path choose what runs.
      return 'Repository URLs must use https';
    }
    final result = await _extensions.addRepo(ExtensionRepo(url: trimmed));
    await load();
    return result.isSuccess ? null : 'Could not read that index';
  }

  /// Removes a repo, and only the sources that are safe to remove.
  ///
  /// An **installed** source is detached rather than deleted: every library
  /// entry stores its source's id, so deleting the row makes each of those
  /// entries fail with "No source with id ..." — and the user's progress,
  /// favourites and downloads all hang off that id. The enforcement is in
  /// `ExtensionRepositoryImpl.removeRepo`, not here, because this is not the
  /// only caller that could exist.
  Future<void> removeRepo(String url) async {
    // Collected first, for the same reason the count is: after the removal
    // there is no row left to say which sources belonged to this repo.
    final affected = all
        .where((s) => s.repoUrl == url)
        .map((s) => s.sourceId)
        .toList();
    await _extensions.removeRepo(url);
    // Evicted whether the row was deleted or detached: a detached row is the
    // same source, but its `repoUrl` changed, and the cache key covers it.
    for (final sourceId in affected) {
      _sources.evict(sourceId);
    }
    await load();
  }

  Future<List<ExtensionRepo>> repos() => _extensions.getRepos();

  /// The repos, each paired with how it last behaved and how much it carries.
  ///
  /// One call rather than three, because the sheet renders them on one row and
  /// three independent futures would let the count arrive before the health and
  /// repaint twice. The count is read from the **loaded catalogue** rather than
  /// stored: a persisted number goes stale the moment an install, an uninstall
  /// or another repo's refresh touches the rows, and counting what is in memory
  /// is free and always true.
  Future<List<RepoStatus>> repoStatuses() async {
    final repos = await _extensions.getRepos();
    final health = await _extensions.repoHealth();
    return [
      for (final repo in repos)
        RepoStatus(
          repo: repo,
          health: health[repo.url],
          sourceCount: all.where((s) => s.repoUrl == repo.url).length,
          installedCount: all
              .where((s) => s.repoUrl == repo.url && s.isInstalled)
              .length,
        ),
    ];
  }

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;
}

/// A repo as the sheet shows it: what it is, how it last behaved, what it holds.
class RepoStatus {
  const RepoStatus({
    required this.repo,
    required this.health,
    required this.sourceCount,
    required this.installedCount,
  });

  final ExtensionRepo repo;

  /// Null when this repo has never been refreshed by this build — which is a
  /// state of its own, not a failure. A repo added before per-repo health
  /// existed has no record, and telling the user it is broken would be a lie
  /// about a repo that may be perfectly fine.
  final RepoHealth? health;

  /// How many extensions this repo currently lists, installed or not.
  final int sourceCount;

  /// How many of those the user has installed.
  ///
  /// These are the ones that *survive* the repo being removed — they are
  /// detached, not deleted — so this is the number the removal dialog counts.
  /// It has to be read from the loaded catalogue **before** the removal:
  /// afterwards no row says which sources belonged to that repo, because the
  /// detach is precisely the clearing of `repoUrl`.
  final int installedCount;

  /// A name to show. The index may not carry one, so the host is the fallback
  /// and the raw URL is the fallback's fallback.
  String get label => repo.name ?? Uri.tryParse(repo.url)?.host ?? repo.url;
}
