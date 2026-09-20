// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:otaku_reader/source/model/source_preference.dart';
import 'package:otaku_reader/source/preference/source_preference_store.dart';
import 'package:otaku_reader/source/util/log.dart';

/// Resolves `getPreferenceValue` calls made from inside an extension.
///
/// There is a circularity here worth naming: the value a source reads for a
/// preference falls back to the default the source *declares*, and reading that
/// declaration means calling `getSourcePreferences()` on the extension — so the
/// preference lookup needs the very runtime that is calling it. Rather than
/// hand every bridge a runtime reference, each runtime registers a callback for
/// its own source id while it is alive, and the bridge asks by id.
class SourcePreferenceResolver {
  const SourcePreferenceResolver._();

  static final Map<int, List<SourcePreference> Function()> _declared = {};

  /// Guards against an extension whose `getSourcePreferences()` itself calls
  /// `getPreferenceValue`. Without this the two would call each other until the
  /// stack ran out; with it the inner call sees no declaration and returns null,
  /// which is the same answer it would get for an unknown key.
  static final Set<int> _resolving = {};

  static void register(
    int sourceId,
    List<SourcePreference> Function() declared,
  ) {
    _declared[sourceId] = declared;
  }

  static void unregister(int sourceId) {
    _declared.remove(sourceId);
    _resolving.remove(sourceId);
  }

  static List<SourcePreference> declaredFor(int sourceId) {
    final fn = _declared[sourceId];
    if (fn == null || _resolving.contains(sourceId)) return const [];
    _resolving.add(sourceId);
    try {
      return fn();
    } catch (e, st) {
      // A source that throws while describing its own settings must not take
      // down the request that merely wanted to read one.
      Log.error(e, st);
      return const [];
    } finally {
      _resolving.remove(sourceId);
    }
  }

  /// The `getPreferenceValue(sourceId, key)` an extension calls.
  static dynamic value(int sourceId, String key) =>
      SourcePreferenceStore.value(sourceId, key, declaredFor(sourceId));

  /// The `getPrefStringValue(sourceId, key, default)` an extension calls.
  static String stringValue(int sourceId, String key, String defaultValue) =>
      SourcePreferenceStore.stringValue(sourceId, key, defaultValue);
}
