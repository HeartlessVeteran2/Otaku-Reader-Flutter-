import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/database/key_value.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';

import 'helpers/isar_test_env.dart';

enum _TestKeys {
  aString,
  anInt,
  aDouble,
  aBool,
  aList,
  aMap,
  listOfMaps,
  listOfInts,
  listOfDoubles,
  emptyList,
  absent,
}

enum _TestDynamicKeys {
  perManga;

  T get<T>(dynamic id, [T? defaultValue]) =>
      KvHelper.get<T>('${name}_$id', defaultVal: defaultValue);
  void set<T>(dynamic id, T value) => KvHelper.set<T>('${name}_$id', value);
}

void main() {
  // Nullable, not `late`: when open() throws -- a missing native library is
  // the realistic case -- a `late` field makes tearDownAll throw
  // LateInitializationError on top, and that cascade is what the reader sees
  // instead of the actual cause.
  IsarTestEnv? env;

  setUpAll(() async => env = await IsarTestEnv.open('kv', [KeyValueSchema]));
  tearDownAll(() async => env?.close());
  setUp(() => env!.clear());

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

  // The list cases below are separate because the suite above only ever stored
  // a List<String>, and that is exactly the one element type the old
  // implementation handled -- it cast every list to List<String>, which
  // succeeds at the cast and throws on first element access for anything else.
  // A green test that covers only the working case is how the defect survived.
  test('a list of maps round-trips with its elements intact', () {
    _TestKeys.listOfMaps.set<List<dynamic>>([
      {'url': 'https://example.com/index.json', 'name': 'default'},
      {'url': 'https://example.org/index.json'},
    ]);

    final back = _TestKeys.listOfMaps.get<List<dynamic>?>();

    // Reading the elements is the assertion. The broken version returned a
    // CastList that compared fine until something touched an element.
    expect(back, hasLength(2));
    expect(back!.first, isA<Map>());
    expect((back.first as Map)['url'], 'https://example.com/index.json');
    expect((back.last as Map)['name'], isNull);
  });

  test('a list of ints round-trips as ints, not strings', () {
    _TestKeys.listOfInts.set<List<int>>([1, 2, 3]);
    expect(_TestKeys.listOfInts.get<List<int>>(const []), [1, 2, 3]);
  });

  test('a list of whole-number doubles re-widens', () {
    // Same numeric collapse as the scalar case: [1.0, 2.0] encodes to [1.0,2.0]
    // but a list written as [1, 2] must still read back as doubles when asked.
    _TestKeys.listOfDoubles.set<List<double>>([1.5, 2.0]);
    expect(_TestKeys.listOfDoubles.get<List<double>>(const []), [1.5, 2.0]);
  });

  test('an empty list keeps the requested element type', () {
    // `every` is vacuously true on an empty list, so this is the case where a
    // type decided from the data alone has no data to decide from.
    _TestKeys.emptyList.set<List<String>>(const []);
    expect(_TestKeys.emptyList.get<List<String>>(const ['x']), isEmpty);
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
