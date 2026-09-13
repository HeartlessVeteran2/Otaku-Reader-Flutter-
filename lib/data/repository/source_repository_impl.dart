import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/runtime/dart_source_runtime.dart';
import 'package:otaku_reader/source/source_methods.dart';

/// Builds a runtime for a source. Injected so tests can substitute a fake
/// without an interpreter, and so a JavaScript backend can be added later
/// without this class knowing about either engine.
typedef SourceRuntimeFactory = SourceMethods Function(Source source);

SourceMethods _defaultFactory(Source source) {
  // The index carries both languages and this app has only a Dart interpreter,
  // so a JavaScript entry handed to `DartSourceRuntime` fails at evaluation with
  // a parse error that reads like a broken extension. Refuse it here, where the
  // message can say what is actually wrong.
  //
  // This is not a gap worth papering over: the Dart half *is* the ecosystem —
  // 249 index entries across ~245 sites, against 18 distinct JavaScript
  // scripts. See CLAUDE.md.
  if (source.sourceCodeLanguage == SourceCodeLanguage.javascript) {
    throw UnsupportedError(
      '${source.name} is a JavaScript extension, and this app runs the Dart '
      'half of the Mangayomi ecosystem. Nothing can open it.',
    );
  }
  return DartSourceRuntime(source);
}

class SourceRepositoryImpl implements SourceRepository {
  SourceRepositoryImpl({
    SourceRuntimeFactory? runtimeFactory,
    Duration? retirementGrace,
  }) : _runtimeFactory = runtimeFactory ?? _defaultFactory,
       retirementGrace = retirementGrace ?? defaultRetirementGrace;

  final SourceRuntimeFactory _runtimeFactory;
  final Map<int, _CachedRuntime> _cache = {};

  /// Runtimes dropped from the cache but not yet disposed.
  ///
  /// They are kept because a browse or reader screen may still be awaiting a
  /// call on one, and `dispose()` nulls the interpreter out from under it.
  ///
  /// This is a **bounded, deliberate** hold rather than a solved problem: a
  /// retired runtime stays reachable through `SourcePreferenceResolver`, whose
  /// entry is a bound method on it. A replacement runtime for the same id
  /// overwrites that entry, so the ordinary update path releases it; an
  /// uninstall with no replacement holds one runtime until [evictAll].
  /// Releasing it sooner needs the runtime to know whether a call is in
  /// flight, which `SourceMethods` deliberately does not expose.
  final Map<SourceMethods, Timer> _retired = {};

  /// How long a superseded runtime is kept alive before it is disposed.
  ///
  /// It cannot be disposed immediately — `dispose()` nulls the interpreter, and
  /// a browse or reader screen may still be awaiting a call on it. It cannot be
  /// kept forever either: the repository is permanent and nothing in production
  /// calls [evictAll], so an unbounded list meant every update and uninstall
  /// leaked an interpreter for the life of the process.
  ///
  /// Two minutes is well past `MClient`'s own request timeout, so anything
  /// still holding this runtime has already failed. Overridable only so a test
  /// can assert the disposal actually happens without waiting for it.
  static const defaultRetirementGrace = Duration(minutes: 2);

  final Duration retirementGrace;

  /// Holds [runtime] alive for [retirementGrace], then disposes it.
  void _retire(SourceMethods runtime) {
    if (_retired.containsKey(runtime)) return;
    _retired[runtime] = Timer(retirementGrace, () {
      _retired.remove(runtime);
      runtime.dispose();
    });
  }

  @override
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  }) async {
    final all = db.isar.sources.where().findAllSync();
    return all.where((s) {
      if (!s.isInstalled) return false;
      if (!includeNsfw && s.isNsfw) return false;
      // 'all' is the index's wildcard language and belongs in every filter --
      // dropping it hides the multi-language sources from a user who picked a
      // specific language, which is most users.
      if (langs != null && !langs.contains(s.lang) && s.lang != 'all') {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<Source?> sourceById(int sourceId) async =>
      db.isar.sources.filter().sourceIdEqualTo(sourceId).findFirstSync();

  @override
  Future<SourceMethods> methodsFor(int sourceId) async {
    final source = await sourceById(sourceId);
    if (source == null) {
      throw StateError('No source with id $sourceId');
    }
    if (!source.isInstalled) {
      throw StateError('${source.name} is not installed');
    }

    // The cache validates itself against the row it just read rather than
    // waiting to be told the code changed. A notification-based cache is only
    // as good as every call site that has to remember to fire it, and the
    // failure mode -- an updated extension still running its old code, with the
    // update button showing "up to date" -- is silent and would be blamed on
    // the source.
    //
    // This costs nothing: [sourceById] has already read the row, so the
    // fingerprint is computed from a string that is in hand either way.
    final fingerprint = _fingerprint(source);
    final cached = _cache[sourceId];
    if (cached != null) {
      if (cached.fingerprint == fingerprint) return cached.runtime;
      // Superseded, not disposed — see [evict]. A call already in flight on the
      // old runtime must be allowed to finish.
      _retire(cached.runtime);
      _cache.remove(sourceId);
    }

    final runtime = _runtimeFactory(source);
    _cache[sourceId] = _CachedRuntime(runtime, fingerprint);
    return runtime;
  }

  /// Identifies the exact runtime a cached interpreter was built from.
  ///
  /// Version alone is not enough — a reinstall of the same version, or a source
  /// republished without a version bump, would keep the stale runtime.
  ///
  /// Two refinements over the obvious "version + code hash":
  ///
  /// * **SHA-256, not `String.hashCode`.** A 32-bit hash colliding with the
  ///   same length is unlikely but not negligible, and the consequence is
  ///   running obsolete third-party code indefinitely. `crypto` is already a
  ///   dependency for the extension runtime.
  /// * **The source fields the interpreter is constructed with** are part of
  ///   the identity, not just the script. `toMSource()` hands `baseUrl`,
  ///   `apiUrl` and `additionalParams` to the extension at construction, and
  ///   `additionalParams` is precisely what distinguishes one Madara site from
  ///   the other 150 sharing that script. A repo re-added with a corrected
  ///   base URL but the same code must not keep serving the old one.
  static String _fingerprint(Source source) {
    final code = source.sourceCode ?? '';
    final digest = sha256.convert(utf8.encode(code));
    return [
      source.version,
      code.length,
      digest,
      // Every field `toMSource()` hands the extension at construction. Listing
      // a subset is how this went wrong the first time: a refresh that changed
      // only `hasCloudflare` or `notes` kept the old runtime.
      source.name,
      source.baseUrl,
      source.apiUrl,
      source.lang,
      source.isFullData,
      source.hasCloudflare,
      source.dateFormat,
      source.dateFormatLocale,
      source.additionalParams,
      source.notes,
    ].join('\u0000');
  }

  @override
  void evict(int sourceId) {
    // Drops the reference **without disposing**. Disposing nulls the
    // interpreter, so a browse or reader controller sitting in an `await` on
    // that runtime fails its request the moment the user updates or uninstalls
    // the source from another screen. The dropped instance finishes whatever it
    // was doing and is then collected.
    //
    // The preference resolver is keyed by source id, so a replacement runtime
    // overwrites the old entry; with no replacement the runtime is held for
    // [retirementGrace] rather than being disposed under a live call.
    final cached = _cache.remove(sourceId);
    if (cached != null) _retire(cached.runtime);
  }

  @override
  void evictAll() {
    // Teardown, where nothing is in flight and releasing interpreter state
    // promptly is the point.
    for (final entry in _cache.values) {
      entry.runtime.dispose();
    }
    for (final entry in _retired.entries) {
      entry.value.cancel();
      entry.key.dispose();
    }
    _retired.clear();
    _cache.clear();
  }

  @override
  Future<void> markUsed(int sourceId) async {
    db.isar.writeTxnSync(() {
      final row = db.isar.sources
          .filter()
          .sourceIdEqualTo(sourceId)
          .findFirstSync();
      if (row == null) return;
      row.lastUsed = DateTime.now();
      db.isar.sources.putSync(row);
    });
  }
}

class _CachedRuntime {
  const _CachedRuntime(this.runtime, this.fingerprint);

  final SourceMethods runtime;
  final String fingerprint;
}
