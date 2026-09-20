// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'dart:convert';

import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/source/model/source_preference.dart';

/// Per-source preference storage.
///
/// **The stored value wins; the declared default is the fallback, read lazily.**
/// Sources near-universally ship a working mirror or base-URL override as that
/// preference's declared default in `getSourcePreferences()`. Seeding a copy of
/// the default at install (or, as upstream does, on first read) freezes it: when
/// the source later ships a new mirror because the old domain died, a user who
/// never touched the setting keeps the dead one. Falling through to the declared
/// default on every read means an updated default reaches them for free, and a
/// row is written only when the user actually changes something.
class SourcePreferenceStore {
  const SourcePreferenceStore._();

  static String _key(int sourceId, String key) => 'srcpref_${sourceId}_$key';
  static String _stringKey(int sourceId, String key) =>
      'srcprefstr_${sourceId}_$key';

  /// The value the extension should see for [key].
  ///
  /// [declared] is the source's own `getSourcePreferences()` list, consulted
  /// only when the user has stored nothing.
  static dynamic value(
    int sourceId,
    String key,
    List<SourcePreference> declared,
  ) {
    final stored = KvHelper.get<String?>(_key(sourceId, key));
    if (stored != null) {
      try {
        return jsonDecode(stored)['v'];
      } catch (_) {
        // A row from an older encoding. The declared default is a better answer
        // than propagating a decode failure into the extension.
      }
    }
    for (final pref in declared) {
      if (pref.key != key) continue;
      return _declaredValue(pref);
    }
    return null;
  }

  static void setValue(int sourceId, String key, dynamic value) {
    KvHelper.set<String>(_key(sourceId, key), jsonEncode({'v': value}));
  }

  /// The `getPrefStringValue` accessor extensions use for free-form strings.
  ///
  /// Unlike [value] this has no declared list to fall back to, so the caller's
  /// [defaultValue] is the fallback — and it is deliberately **not** written
  /// back, for the same reason: a later default change must still take effect.
  static String stringValue(int sourceId, String key, String defaultValue) =>
      KvHelper.get<String>(_stringKey(sourceId, key), defaultVal: defaultValue);

  static void setStringValue(int sourceId, String key, String value) {
    KvHelper.set<String>(_stringKey(sourceId, key), value);
  }

  static void clearForSource(int sourceId, List<SourcePreference> declared) {
    for (final pref in declared) {
      final key = pref.key;
      if (key == null) continue;
      KvHelper.remove(_key(sourceId, key));
      KvHelper.remove(_stringKey(sourceId, key));
    }
  }

  /// Reads the value a preference declares as its default.
  ///
  /// A list preference stores an *index*, so the entry value has to be looked up
  /// through it; an index past the end of `entryValues` means the source changed
  /// its options, and falling back to the first entry beats throwing.
  static dynamic _declaredValue(SourcePreference pref) {
    final list = pref.listPreference;
    if (list != null) {
      final values = list.entryValues;
      final index = list.valueIndex;
      if (values == null || values.isEmpty) return null;
      if (index == null || index < 0 || index >= values.length) {
        return values.first;
      }
      return values[index];
    }
    if (pref.checkBoxPreference != null) return pref.checkBoxPreference!.value;
    if (pref.switchPreferenceCompat != null) {
      return pref.switchPreferenceCompat!.value;
    }
    if (pref.editTextPreference != null) return pref.editTextPreference!.value;
    if (pref.multiSelectListPreference != null) {
      return pref.multiSelectListPreference!.values;
    }
    return null;
  }
}
