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

SourceMethods _defaultFactory(Source source) => DartSourceRuntime(source);

class SourceRepositoryImpl implements SourceRepository {
  SourceRepositoryImpl({SourceRuntimeFactory? runtimeFactory})
    : _runtimeFactory = runtimeFactory ?? _defaultFactory;

  final SourceRuntimeFactory _runtimeFactory;
  final Map<int, _CachedRuntime> _cache = {};

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
      source.baseUrl,
      source.apiUrl,
      source.additionalParams,
      source.lang,
      source.dateFormat,
      source.dateFormatLocale,
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
    // Nothing leaks by not disposing: the preference resolver is keyed by
    // source id, so the replacement runtime registers over the old entry.
    _cache.remove(sourceId);
  }

  @override
  void evictAll() {
    // Teardown, where nothing is in flight and releasing interpreter state
    // promptly is the point.
    for (final entry in _cache.values) {
      entry.runtime.dispose();
    }
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
