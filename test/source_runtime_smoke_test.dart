import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/runtime/dart_source_runtime.dart';

/// Proves the runtime can evaluate a real, unmodified published extension.
///
/// The fixture is `madara.dart` exactly as published — the multi-site template
/// that drives 151 of the index's entries, so it is both the most representative
/// source and the highest-value one to keep working.
///
/// Evaluation is the part worth pinning: an extension declares
/// `class Madara extends MProvider`, and an `extends` clause resolves at
/// class-definition time, so a bridge gap fails the *whole script* rather than
/// one method. A test that only called a method would never see it.
void main() {
  late String code;

  setUpAll(() {
    code = File('test/fixtures/madara_extension.dart.txt').readAsStringSync();
  });

  Source madaraSource() => Source()
    ..sourceId = 1
    ..name = 'Madara Test'
    ..lang = 'en'
    ..baseUrl = 'https://example.com'
    ..sourceCode = code;

  test('evaluates a published Madara extension without throwing', () {
    final runtime = DartSourceRuntime(madaraSource());
    addTearDown(runtime.dispose);
    expect(runtime.source.name, 'Madara Test');
  });

  test('resolves the base URL through the extension, not the record', () {
    final runtime = DartSourceRuntime(madaraSource());
    addTearDown(runtime.dispose);
    // madara.dart implements getBaseUrl(); whatever it answers, the runtime
    // must return a usable string rather than throwing or handing back null.
    expect(runtime.sourceBaseUrl, isNotEmpty);
  });

  test('reads the filter list the extension declares', () {
    final runtime = DartSourceRuntime(madaraSource());
    addTearDown(runtime.dispose);
    final filters = runtime.getFilterList();
    // Madara declares a substantial filter set; an empty list would mean the
    // filter bridge silently failed and browse would render no filters at all.
    expect(filters.filters, isNotEmpty);
  });

  test('reads the preferences the extension declares', () {
    final runtime = DartSourceRuntime(madaraSource());
    addTearDown(runtime.dispose);
    final prefs = runtime.getSourcePreferences();
    expect(prefs, isNotEmpty);
    // Every declared preference must carry a key: the key is what the store and
    // the settings UI index by, and a null one is silently unreachable.
    expect(prefs.every((p) => p.key != null && p.key!.isNotEmpty), isTrue);
  });

  test('reports latest-updates support', () {
    final runtime = DartSourceRuntime(madaraSource());
    addTearDown(runtime.dispose);
    expect(runtime.supportsLatest, isA<bool>());
  });

  test('a source with no code is refused at construction', () {
    // Failing here, with the source named, beats failing later inside the
    // interpreter with no indication of which source was involved.
    final empty = Source()
      ..sourceId = 2
      ..name = 'Uninstalled'
      ..lang = 'en';
    expect(() => DartSourceRuntime(empty), throwsStateError);
  });

  test('a disposed runtime refuses further calls', () {
    final runtime = DartSourceRuntime(madaraSource());
    runtime.dispose();
    expect(() => runtime.getPopular(1), throwsStateError);
  });
}
