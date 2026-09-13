// prefer_initializing_formals wants `this._extensions` in the constructor,
// which Dart does not allow -- a named parameter cannot be private. The fields
// stay private deliberately: public ones would invite call sites to reach
// through the controller to the repositories it exists to mediate.
// ignore_for_file: prefer_initializing_formals

import 'package:get/get.dart';

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
  }) : _extensions = extensions,
       _sources = sources;

  final ExtensionRepository _extensions;
  final SourceRepository _sources;

  final all = <Source>[].obs;
  final query = ''.obs;
  final enabledLangs = <String>{}.obs;
  final showNsfw = false.obs;

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
    showNsfw.value = SourceKeys.showNsfwSources.get<bool>(false);
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

  /// Every language present in the catalogue, so the filter offers exactly the
  /// ones that can actually match rather than a hardcoded list that drifts.
  List<String> get availableLangs =>
      all.map((s) => s.lang).toSet().toList()..sort();

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
  /// The eviction is belt and braces rather than load-bearing — the runtime
  /// cache fingerprints the stored code and rebuilds on its own — but an
  /// uninstalled source should not keep an interpreter alive until something
  /// happens to ask for it again.
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

  void toggleNsfw(bool value) {
    showNsfw.value = value;
    SourceKeys.showNsfwSources.set<bool>(value);
  }

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

  Future<void> removeRepo(String url) async {
    await _extensions.removeRepo(url);
    await load();
  }

  Future<List<ExtensionRepo>> repos() => _extensions.getRepos();

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;
}
