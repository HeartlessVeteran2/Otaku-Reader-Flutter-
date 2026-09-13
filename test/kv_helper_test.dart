import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/key_value.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';

enum _TestKeys { aString, anInt, aDouble, aBool, aList, aMap, absent }

enum _TestDynamicKeys {
  perManga;

  T get<T>(dynamic id, [T? defaultValue]) =>
      KvHelper.get<T>('${name}_$id', defaultVal: defaultValue);
  void set<T>(dynamic id, T value) => KvHelper.set<T>('${name}_$id', value);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    dir = await Directory.systemTemp.createTemp('otaku_kv_test');
    db.isar = Isar.openSync(
      [KeyValueSchema],
      directory: dir.path,
      name: 'kvtest',
      inspector: false,
    );
  });

  tearDownAll(() async {
    await db.isar.close(deleteFromDisk: true);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  setUp(() {
    db.isar.writeTxnSync(() => db.isar.keyValues.clearSync());
  });

  test('round-trips every JSON-representable type', () {
    _TestKeys.aString.set<String>('hello');
    _TestKeys.anInt.set<int>(42);
    _TestKeys.aDouble.set<double>(1.5);
    _TestKeys.aBool.set<bool>(true);
    _TestKeys.aList.set<List<String>>(['a', 'b']);
    _TestKeys.aMap.set<Map<String, dynamic>>({'x': 1});

    expect(_TestKeys.aString.get<String>(''), 'hello');
    expect(_TestKeys.anInt.get<int>(0), 42);
    expect(_TestKeys.aDouble.get<double>(0), 1.5);
    expect(_TestKeys.aBool.get<bool>(false), true);
    expect(_TestKeys.aList.get<List<String>>(const []), ['a', 'b']);
    expect(_TestKeys.aMap.get<Map<String, dynamic>>(const {}), {'x': 1});
  });

  test('a whole-number double survives the JSON numeric collapse', () {
    // jsonEncode(3.0) is "3.0" but jsonDecode of some payloads yields an int;
    // the getter must re-widen rather than throw a cast error.
    _TestKeys.aDouble.set<double>(3.0);
    expect(_TestKeys.aDouble.get<double>(0), 3.0);
    expect(_TestKeys.aDouble.get<double>(0), isA<double>());
  });

  test('an int read as double and vice versa is coerced, not thrown', () {
    _TestKeys.anInt.set<int>(7);
    expect(_TestKeys.anInt.get<double>(0), 7.0);
    _TestKeys.aDouble.set<double>(2.9);
    expect(_TestKeys.aDouble.get<int>(0), 2);
  });

  test('an absent key yields the supplied default', () {
    expect(_TestKeys.absent.get<int>(99), 99);
    expect(_TestKeys.absent.get<String>('fallback'), 'fallback');
  });

  test('a stored null is indistinguishable from absent, by design', () {
    // The {'val': ...} envelope lets null be stored; reading it must still fall
    // back, because every call site supplies a usable default.
    _TestKeys.aString.set<String?>(null);
    expect(_TestKeys.aString.get<String>('fallback'), 'fallback');
  });

  test('a corrupt row falls back instead of throwing', () {
    db.isar.writeTxnSync(
      () => db.isar.keyValues.putSync(
        KeyValue()
          ..key = _TestKeys.aString.name
          ..value = 'not json at all',
      ),
    );
    expect(_TestKeys.aString.get<String>('fallback'), 'fallback');
  });

  test('delete removes the row', () {
    _TestKeys.anInt.set<int>(5);
    expect(_TestKeys.anInt.get<int>(0), 5);
    _TestKeys.anInt.delete();
    expect(_TestKeys.anInt.get<int>(0), 0);
  });

  test('set overwrites rather than appending a second row', () {
    _TestKeys.anInt.set<int>(1);
    _TestKeys.anInt.set<int>(2);
    expect(_TestKeys.anInt.get<int>(0), 2);
    final rows = db.isar.keyValues
        .filter()
        .keyEqualTo(_TestKeys.anInt.name)
        .findAllSync();
    expect(rows.length, 1);
  });

  test('dynamic keys namespace by id and do not collide', () {
    _TestDynamicKeys.perManga.set<String>(1, 'source-a');
    _TestDynamicKeys.perManga.set<String>(2, 'source-b');
    expect(_TestDynamicKeys.perManga.get<String>(1, ''), 'source-a');
    expect(_TestDynamicKeys.perManga.get<String>(2, ''), 'source-b');
    expect(_TestDynamicKeys.perManga.get<String>(3, 'none'), 'none');
  });
}
