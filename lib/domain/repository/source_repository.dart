import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/source_methods.dart';

/// How the app gets from a stored [Source] row to something it can call.
///
/// Separate from `ExtensionRepository`, which manages the *catalogue*. This one
/// owns live interpreter state: constructing a runtime parses the extension
/// script, so instances are cached and have to be evicted when the code behind
/// them changes.
abstract interface class SourceRepository {
  /// Installed sources only — an uninstalled row has no code to run.
  ///
  /// [langs] filters by language; null means every language. [includeNsfw]
  /// defaults to false so an accidental omission is the conservative answer.
  Future<List<Source>> installedSources({
    Set<String>? langs,
    bool includeNsfw = false,
  });

  Future<Source?> sourceById(int sourceId);

  /// A live runtime for [sourceId], reused across calls.
  ///
  /// Throws if the source is absent or not installed, rather than returning
  /// null: every call site would otherwise have to invent a failure mode for a
  /// state the UI should never route into.
  Future<SourceMethods> methodsFor(int sourceId);

  /// Drops the cached runtime for [sourceId]. Called whenever the stored code
  /// changes, so the next call re-parses.
  void evict(int sourceId);

  void evictAll();

  /// Records that a source was used, for recency ordering in the UI.
  Future<void> markUsed(int sourceId);
}
