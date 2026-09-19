import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:otaku_reader/core/database/database.dart';
import 'package:otaku_reader/core/database/key_value.dart';

/// Grafts typed persistence onto every enum in the app.
///
/// Declaring keys as enum members rather than string literals makes them
/// autocompletable and removes the whole class of bug where a read and a write
/// disagree about a string by one character.
///
/// It does **not** make them rename-safe, which an earlier version of this
/// comment claimed. The stored key is the member's `name`, so renaming a member
/// silently orphans every value already written under the old name — the code
/// still compiles, every call site is updated by the rename, and the user's
/// data is simply gone. Renaming a key is a migration, not a refactor.
/// Reordering members, on the other hand, is free: nothing depends on `index`.
extension KvExtensions on Enum {
  T get<T>([T? defaultValue]) =>
      KvHelper.get<T>(name, defaultVal: defaultValue);
  void set<T>(T value) => KvHelper.set<T>(name, value);
  void delete() => KvHelper.remove(name);
}

class KvHelper {
  const KvHelper._();

  static T get<T>(String key, {T? defaultVal}) {
    final row = isar.keyValues.filter().keyEqualTo(key).findFirstSync();
    final raw = row?.value;
    if (raw == null) return defaultVal as T;

    final dynamic val;
    try {
      val = (jsonDecode(raw) as Map<String, dynamic>)['val'];
    } catch (_) {
      // A row written by an older build, or corrupted. The default is always a
      // better answer than throwing out of a synchronous read inside build().
      return defaultVal as T;
    }
    if (val == null) return defaultVal as T;

    // jsonDecode collapses the numeric tower, so a double written as 3.0 reads
    // back as int. Re-widen against the requested type rather than letting the
    // cast below throw.
    if (val is num && T == double) return val.toDouble() as T;
    if (val is num && T == int) return val.toInt() as T;
    // A list's element type lives only in T, and jsonDecode erases it to
    // List<dynamic>. This used to cast *every* list to List<String>, which
    // succeeds at the cast and then throws on first element access for any list
    // that is not strings -- so every list of maps this app stores (repo URLs,
    // home-page cards) round-tripped in name only. Deciding from the data's own
    // element type rather than from T also gets the nullable spellings right,
    // because List<String> satisfies List<String>? for free.
    if (val is List) {
      if (val is T) return val as T;
      if (val.every((e) => e is String)) {
        return val.cast<String>().toList() as T;
      }
      if (val.every((e) => e is num)) {
        final ints = val.map((e) => (e as num).toInt()).toList();
        if (ints is T) return ints as T;
        return val.map((e) => (e as num).toDouble()).toList() as T;
      }
      if (val.every((e) => e is Map)) {
        return val.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            as T;
      }
      return val as T;
    }
    if (val is Map) return Map<String, dynamic>.from(val) as T;
    return val as T;
  }

  static void set<T>(String key, T value) {
    final row = KeyValue()
      ..key = key
      ..value = jsonEncode({'val': value});
    isar.writeTxnSync(() => isar.keyValues.putSync(row));
  }

  static void remove(String key) {
    isar.writeTxnSync(
      () => isar.keyValues.filter().keyEqualTo(key).deleteAllSync(),
    );
  }
}
