import 'dart:convert';

import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/domain/repository/extension_repository.dart';
import 'package:otaku_reader/source/http/m_client.dart';
import 'package:otaku_reader/source/model/m_status.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/util/log.dart';

/// Fetches a URL as text. Injected so the repository can be tested without the
/// open internet — the index and the extension bodies are the only two things
/// this layer ever downloads.
typedef TextFetcher = Future<String> Function(Uri url);

Future<String> _httpGet(Uri url) async {
  final client = MClient.init();
  try {
    final response = await client.get(url);
    if (response.statusCode != 200) {
      throw HttpStatusException(url, response.statusCode);
    }
    return response.body;
  } finally {
    client.close();
  }
}

/// A non-200 from a repo or extension URL.
///
/// A distinct type rather than a bare string because "the index 404s" and "the
/// index is not JSON" want different messages, and both are ordinary.
class HttpStatusException implements Exception {
  const HttpStatusException(this.url, this.statusCode);

  final Uri url;
  final int statusCode;

  @override
  String toString() => 'HTTP $statusCode for $url';
}

class ExtensionRepositoryImpl implements ExtensionRepository {
  ExtensionRepositoryImpl({TextFetcher? fetch}) : _fetch = fetch ?? _httpGet;

  final TextFetcher _fetch;

  /// Serialises the repo list's read-modify-write cycles.
  ///
  /// Both [addRepo] and [removeRepo] read the stored list, change it, and write
  /// the whole thing back. Two of those interleaving -- two quick taps on two
  /// remove buttons is enough -- means the second read happened before the
  /// first write, so the second write puts the first's removal back and the
  /// repository the user deleted reappears. The lock has to span *both* steps;
  /// making each one individually atomic changes nothing.
  Future<void> _repoLock = Future<void>.value();

  Future<T> _withRepoLock<T>(Future<T> Function() body) {
    final result = _repoLock.then((_) => body());
    // The chain must survive a failed body, or one error wedges every later
    // caller on a future that never completes.
    _repoLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// The index every Mangayomi client reads. Seeded so a fresh install has
  /// something to browse before the user has added anything.
  static const defaultRepoUrl =
      'https://raw.githubusercontent.com/kodjodevf/mangayomi-extensions/main/index.json';

  @override
  Future<List<ExtensionRepo>> getRepos() async {
    // Nullable T deliberately: with a non-nullable T and nothing stored,
    // KvHelper returns `null as T` and throws. Absent has to be distinguishable
    // from empty here, because absent means "seed the default repo" and empty
    // means "the user removed every repo", and seeding over the second would
    // resurrect a repo they deleted on every launch.
    final stored = SourceKeys.repoUrls.get<List<dynamic>?>();
    if (stored == null) return const [ExtensionRepo(url: defaultRepoUrl)];
    return stored
        .whereType<Map>()
        .map((e) => ExtensionRepo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _saveRepos(List<ExtensionRepo> repos) async {
    SourceKeys.repoUrls.set<List<dynamic>>(
      repos.map((r) => r.toJson()).toList(),
    );
  }

  @override
  Future<RefreshResult> addRepo(ExtensionRepo repo) async {
    await _withRepoLock(() async {
      // [getRepos] returns the seeded default when nothing is stored, and
      // writing that list back materialises the seed. That is deliberate: the
      // default is visible in the UI before any write, so saving only the newly
      // added repo would make it disappear the moment the user adds their
      // first one.
      final repos = await getRepos();
      if (!repos.any((r) => r.url == repo.url)) {
        await _saveRepos([...repos, repo]);
      }
    });
    // Outside the lock: fetching an index is slow and network-bound, and it
    // does not touch the repo list.
    return refresh(repo.url);
  }

  @override
  Future<void> removeRepo(String url) => _withRepoLock(() => _removeRepo(url));

  Future<void> _removeRepo(String url) async {
    final repos = await getRepos();
    await _saveRepos(repos.where((r) => r.url != url).toList());
    db.isar.writeTxnSync(() {
      final rows = db.isar.sources.filter().repoUrlEqualTo(url).findAllSync();

      // An **installed** source is detached, not deleted. Every library entry
      // stores its source's id, so deleting the row makes each of those entries
      // fail with "No source with id ..." -- the exact failure the Kotlin app
      // calls its highest-impact bug ever, and there is no way back from it
      // because the user's chapters, progress and favourites all hang off that
      // id. Clearing `repoUrl` means the source keeps working and simply stops
      // receiving updates, which is what removing its repo should mean.
      //
      // Checking the library instead of the install state would be the wrong
      // test: opening a manga stores an entry before it is favourited, so a
      // favourites-only check misses read progress, and an entry can be added
      // after the removal anyway.
      final detach = <Source>[];
      final delete = <int>[];
      for (final row in rows) {
        if (row.isInstalled) {
          row.repoUrl = null;
          detach.add(row);
        } else {
          delete.add(row.id);
        }
      }
      db.isar.sources.deleteAllSync(delete);
      if (detach.isNotEmpty) db.isar.sources.putAllSync(detach);
    });
  }

  @override
  Future<List<RefreshResult>> refreshAll() async {
    final repos = await getRepos();
    final results = <RefreshResult>[];
    for (final repo in repos) {
      results.add(await refresh(repo.url));
    }
    SourceKeys.lastRepoRefresh.set<int>(DateTime.now().millisecondsSinceEpoch);
    return results;
  }

  @override
  Future<RefreshResult> refresh(String repoUrl) async {
    final List<dynamic> entries;
    try {
      final body = await _fetch(Uri.parse(repoUrl));
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        return RefreshResult(
          repoUrl: repoUrl,
          error: 'Index is not a JSON list',
        );
      }
      entries = decoded;
    } catch (e) {
      // A failed refresh deliberately changes nothing. The previously known
      // sources stay exactly as they were, so a flaky network or a repo that is
      // briefly down cannot empty the user's extension list.
      Log.error('Refreshing $repoUrl failed: $e');
      return RefreshResult(repoUrl: repoUrl, error: '$e');
    }

    final incoming = <int, Source>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final Source parsed;
      try {
        parsed = Source.fromIndexJson(
          Map<String, dynamic>.from(entry),
          repoUrl: repoUrl,
        );
      } catch (e) {
        // One malformed entry must not cost the whole index. The Kotlin app's
        // DTO mismatch made every entry fail at once and the list came back
        // empty with no error anywhere.
        Log.error('Skipping malformed index entry in $repoUrl: $e');
        continue;
      }
      // This app has no anime or novel surface, so an entry it could never open
      // is noise in the browse list rather than a feature.
      if (parsed.itemType != ItemType.manga) continue;
      // Same reasoning for JavaScript entries: there is no JS interpreter here,
      // so listing one only offers an install that leads to a source which
      // cannot open. The Dart half is the ecosystem -- 249 entries across ~245
      // sites, against 18 distinct JS scripts (CLAUDE.md).
      if (parsed.sourceCodeLanguage != SourceCodeLanguage.dart) continue;
      incoming[parsed.sourceId] = parsed;
    }

    var added = 0;
    var updated = 0;
    var removed = 0;

    // One transaction for the whole reconcile. Read-then-merge-then-write is a
    // read-then-act sequence, and the two halves have to be inside the same
    // transaction or a concurrent refresh can land between them and lose a
    // write. Deliberately *not* `putBySourceId`: Isar's unique-index replace
    // deletes the conflicting row first, which would silently drop an installed
    // source's code and every user-owned field with it.
    db.isar.writeTxnSync(() {
      final existing = db.isar.sources
          .filter()
          .repoUrlEqualTo(repoUrl)
          .findAllSync();
      final byId = {for (final s in existing) s.sourceId: s};

      for (final entry in incoming.values) {
        final current = byId[entry.sourceId];
        if (current == null) {
          db.isar.sources.putSync(entry);
          added++;
        } else {
          final changed = _merge(current, entry);
          db.isar.sources.putSync(current);
          if (changed) updated++;
        }
      }

      // A source the index no longer lists is dropped only if it is not
      // installed. An installed one stays: library rows point at it by id, and
      // deleting it under them reproduces the "source not found" failure the
      // Kotlin app calls its highest-impact bug. Uninstalling is the user's
      // call, not a side effect of the upstream index being edited.
      for (final stale in existing) {
        if (incoming.containsKey(stale.sourceId)) continue;
        if (stale.isInstalled) continue;
        db.isar.sources.deleteSync(stale.id);
        removed++;
      }
    });

    return RefreshResult(
      repoUrl: repoUrl,
      added: added,
      updated: updated,
      removed: removed,
    );
  }

  /// Copies the fields the **index** owns onto [current], leaving the fields the
  /// **user** owns alone. Returns whether anything actually changed.
  ///
  /// Getting this split wrong is the whole risk in a refresh. `sourceCode`,
  /// `version`, `isActive`, `isPinned` and `lastUsed` are user state: wiping
  /// `sourceCode` uninstalls a working extension, and overwriting `version` with
  /// the index's number makes [Source.hasUpdate] false while the installed code
  /// is still the old one — an update the user can never be offered.
  static bool _merge(Source current, Source incoming) {
    var changed = false;
    void set<T>(T now, T next, void Function(T) assign) {
      if (now == next) return;
      assign(next);
      changed = true;
    }

    set(current.name, incoming.name, (v) => current.name = v);
    set(current.baseUrl, incoming.baseUrl, (v) => current.baseUrl = v);
    set(current.apiUrl, incoming.apiUrl, (v) => current.apiUrl = v);
    set(current.lang, incoming.lang, (v) => current.lang = v);
    set(current.iconUrl, incoming.iconUrl, (v) => current.iconUrl = v);
    set(
      current.sourceCodeUrl,
      incoming.sourceCodeUrl,
      (v) => current.sourceCodeUrl = v,
    );
    set(
      current.versionLast,
      incoming.versionLast,
      (v) => current.versionLast = v,
    );
    set(current.isNsfw, incoming.isNsfw, (v) => current.isNsfw = v);
    set(
      current.hasCloudflare,
      incoming.hasCloudflare,
      (v) => current.hasCloudflare = v,
    );
    set(current.isFullData, incoming.isFullData, (v) => current.isFullData = v);
    set(current.dateFormat, incoming.dateFormat, (v) => current.dateFormat = v);
    set(
      current.dateFormatLocale,
      incoming.dateFormatLocale,
      (v) => current.dateFormatLocale = v,
    );
    set(
      current.additionalParams,
      incoming.additionalParams,
      (v) => current.additionalParams = v,
    );
    set(current.notes, incoming.notes, (v) => current.notes = v);
    set(
      current.sourceCodeLanguage,
      incoming.sourceCodeLanguage,
      (v) => current.sourceCodeLanguage = v,
    );
    return changed;
  }

  @override
  Future<List<Source>> listAll() async => db.isar.sources.where().findAllSync();

  @override
  Future<Source> install(Source source) => _fetchCodeInto(source);

  @override
  Future<Source> update(Source source) => _fetchCodeInto(source);

  Future<Source> _fetchCodeInto(Source source) async {
    final url = source.sourceCodeUrl;
    if (url == null || url.isEmpty) {
      throw StateError('${source.name} lists no sourceCodeUrl');
    }
    final code = await _fetch(Uri.parse(url));
    if (code.trim().isEmpty) {
      throw StateError('${source.name} returned an empty script');
    }
    db.isar.writeTxnSync(() {
      // Re-read inside the transaction: the caller's copy may be stale, and the
      // fetch above is a long await during which a refresh can have run.
      final row = db.isar.sources.getSync(source.id) ?? source;
      row.sourceCode = code;
      // Only now does the installed version become the advertised one. Writing
      // this at index time instead would hide every future update.
      row.version = row.versionLast;
      db.isar.sources.putSync(row);
      source.sourceCode = row.sourceCode;
      source.version = row.version;
      source.id = row.id;
    });
    return source;
  }

  @override
  Future<Source> uninstall(Source source) async {
    db.isar.writeTxnSync(() {
      final row = db.isar.sources.getSync(source.id) ?? source;
      row.sourceCode = null;
      // Back to the floor, so a reinstall is not mistaken for an up-to-date
      // install when the index advertises the same number.
      row.version = '0.0.1';
      db.isar.sources.putSync(row);
      source.sourceCode = null;
      source.version = row.version;
    });
    return source;
  }
}
