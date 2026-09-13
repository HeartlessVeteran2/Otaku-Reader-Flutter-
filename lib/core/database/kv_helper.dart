import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:otaku_reader/core/database/database.dart';
import 'package:otaku_reader/core/database/key_value.dart';

/// Grafts typed persistence onto every enum in the app.
///
/// Declaring keys as enum members rather than string literals makes them
/// rename-safe and autocompletable, and removes the whole class of bug where a
/// read and a write disagree about a string by one character.
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
    if (val is List && T == const <String>[].runtimeType) {
      return val.cast<String>() as T;
    }
    if (val is List) return val.cast<String>() as T;
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
