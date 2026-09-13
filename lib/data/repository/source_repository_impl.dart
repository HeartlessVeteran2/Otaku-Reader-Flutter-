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
      cached.runtime.dispose();
      _cache.remove(sourceId);
    }

    final runtime = _runtimeFactory(source);
    _cache[sourceId] = _CachedRuntime(runtime, fingerprint);
    return runtime;
  }

  /// Identifies the exact code a runtime was built from.
  ///
  /// Version alone is not enough — a reinstall of the same version, or a source
  /// republished without a version bump, would keep the stale runtime. The code
  /// hash is what actually decides; version and length are cheap extra signal.
  static String _fingerprint(Source source) {
    final code = source.sourceCode ?? '';
    return '${source.version}:${code.length}:${code.hashCode}';
  }

  @override
  void evict(int sourceId) {
    // Dispose before dropping the reference: the runtime holds interpreter
    // state and a preference-resolver registration keyed by source id, and a
    // leaked registration would answer for the *next* runtime of the same id.
    _cache.remove(sourceId)?.runtime.dispose();
  }

  @override
  void evictAll() {
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
