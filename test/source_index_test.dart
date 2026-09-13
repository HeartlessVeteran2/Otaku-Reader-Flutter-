import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otaku_reader/source/model/m_status.dart';
import 'package:otaku_reader/source/model/source.dart';

/// Decoding the repo index is where a plausible-looking DTO goes wrong quietly.
///
/// The Kotlin app shipped one that declared `id` and `itemType` as strings when
/// the index emits numbers, and never read `sourceCodeLanguage` at all: the
/// index decoded to nothing, and what did decode fed Dart files to a JavaScript
/// engine. These cases pin the actual wire types.
void main() {
  Map<String, dynamic> entry(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  test('decodes numeric id and itemType, and picks the engine by language', () {
    final source = Source.fromIndexJson(
      entry('''
      {"name":"Madara Site","id":123456,"baseUrl":"https://example.com",
       "lang":"en","itemType":0,"sourceCodeLanguage":0,"version":"0.0.5",
       "sourceCodeUrl":"https://example.com/madara.dart"}
    '''),
    );

    expect(source.sourceId, 123456);
    expect(source.itemType, ItemType.manga);
    expect(source.sourceCodeLanguage, SourceCodeLanguage.dart);
    expect(source.versionLast, '0.0.5');
  });

  test('language 1 selects the JavaScript engine', () {
    final source = Source.fromIndexJson(
      entry('{"name":"JS Site","id":1,"lang":"en","sourceCodeLanguage":1}'),
    );
    expect(source.sourceCodeLanguage, SourceCodeLanguage.javascript);
  });

  test(
    'keeps additionalParams, which is what distinguishes multisrc sites',
    () {
      // One script drives 151 Madara sites; additionalParams is the only thing
      // telling an instance which site it is. Dropping it collapses them all.
      final source = Source.fromIndexJson(
        entry(
          '{"name":"Site","id":2,"lang":"en","additionalParams":"?lang=en"}',
        ),
      );
      expect(source.additionalParams, '?lang=en');
      expect(source.toMSource().additionalParams, '?lang=en');
    },
  );

  test('an entry missing optional fields still decodes', () {
    final source = Source.fromIndexJson(
      entry('{"name":"Bare","id":3,"lang":"en"}'),
    );
    expect(source.sourceCodeLanguage, SourceCodeLanguage.dart);
    expect(source.itemType, ItemType.manga);
    expect(source.isNsfw, isFalse);
  });

  test('a version arriving as a number is still read as a string', () {
    // Some entries quote the version and some do not; toString() covers both,
    // where a cast would throw on the unquoted form.
    final source = Source.fromIndexJson(
      entry('{"name":"N","id":4,"lang":"en","version":3}'),
    );
    expect(source.versionLast, '3');
  });

  test('installed state and update availability are derived, not stored', () {
    final source = Source.fromIndexJson(
      entry('{"name":"N","id":5,"lang":"en","version":"2.0"}'),
    );
    expect(source.isInstalled, isFalse);
    expect(
      source.hasUpdate,
      isFalse,
      reason: 'not installed cannot need update',
    );

    source.sourceCode = 'class X {}';
    source.version = '1.0';
    expect(source.isInstalled, isTrue);
    expect(source.hasUpdate, isTrue);

    source.version = '2.0';
    expect(source.hasUpdate, isFalse);
  });
}
