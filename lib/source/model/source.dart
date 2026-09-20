// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:isar_community/isar.dart';

import 'package:otaku_reader/source/model/m_source.dart';
import 'package:otaku_reader/source/model/m_status.dart';

part 'source.g.dart';

/// Which engine runs a source's code.
///
/// The index tags every entry with this, and picking the wrong one feeds a Dart
/// file to a JavaScript engine. The ordinals are the index's own encoding.
enum SourceCodeLanguage { dart, javascript }

/// An extension, whether merely listed in a repo index or installed.
///
/// This is both the index row and the installed record: `sourceCode` is null
/// until installed, which is the only difference between the two states, and
/// keeping them in one collection means "is this installed, and is it stale?"
/// is a field comparison rather than a join.
@collection
class Source {
  Id id = Isar.autoIncrement;

  /// The id the index assigns. It is also what the interpreter passes to
  /// `getPreferenceValue`, so it must survive round-trips unchanged.
  @Index(unique: true, replace: true)
  late int sourceId;

  late String name;
  String? baseUrl;
  String? apiUrl;
  late String lang;

  String? iconUrl;
  String? sourceCodeUrl;

  /// Null until installed. Presence is the installed flag.
  String? sourceCode;

  String version = '0.0.1';

  /// The version the index currently advertises. Differing from [version] is
  /// what makes an update available.
  String versionLast = '0.0.1';

  bool isNsfw = false;
  bool hasCloudflare = false;
  bool isFullData = false;
  bool isActive = true;
  bool isPinned = false;

  String? dateFormat;
  String? dateFormatLocale;

  /// Extra per-entry configuration. The multisrc Dart templates are one script
  /// shared by many sites, and this is what tells an instance which site it is —
  /// so dropping it collapses 151 Madara sources into one broken one.
  String? additionalParams;

  String? notes;

  /// Which repo index this came from, so a repo removal can take its sources.
  String? repoUrl;

  @enumerated
  SourceCodeLanguage sourceCodeLanguage = SourceCodeLanguage.dart;

  @enumerated
  ItemType itemType = ItemType.manga;

  DateTime? lastUsed;

  @ignore
  bool get isInstalled => sourceCode != null && sourceCode!.isNotEmpty;

  @ignore
  bool get hasUpdate => isInstalled && version != versionLast;

  /// The subset the interpreter sees. Extensions read `source.baseUrl`,
  /// `source.apiUrl` and `source.additionalParams` off this.
  MSource toMSource() => MSource(
    id: sourceId,
    name: name,
    baseUrl: baseUrl,
    lang: lang,
    isFullData: isFullData,
    hasCloudflare: hasCloudflare,
    dateFormat: dateFormat,
    dateFormatLocale: dateFormatLocale,
    apiUrl: apiUrl,
    additionalParams: additionalParams,
    notes: notes,
  );

  /// Decodes one entry of a repo `index.json`.
  ///
  /// The field *types* here are load-bearing and easy to get wrong from memory:
  /// `id` and `itemType` arrive as **numbers**, not strings, and
  /// `sourceCodeLanguage` selects the engine. The Kotlin app shipped a DTO that
  /// declared them as strings; the index decoded to nothing, and what did decode
  /// fed Dart files to a JavaScript engine.
  static Source fromIndexJson(Map<String, dynamic> json, {String? repoUrl}) {
    final source = Source()
      ..sourceId = (json['id'] as num).toInt()
      ..name = json['name'] as String? ?? ''
      ..baseUrl = json['baseUrl'] as String?
      ..apiUrl = json['apiUrl'] as String?
      ..lang = json['lang'] as String? ?? 'en'
      ..iconUrl = json['iconUrl'] as String?
      ..sourceCodeUrl = json['sourceCodeUrl'] as String?
      ..versionLast = json['version']?.toString() ?? '0.0.1'
      ..isNsfw = json['isNsfw'] as bool? ?? false
      ..hasCloudflare = json['hasCloudflare'] as bool? ?? false
      ..isFullData = json['isFullData'] as bool? ?? false
      ..dateFormat = json['dateFormat'] as String?
      ..dateFormatLocale = json['dateFormatLocale'] as String?
      ..additionalParams = json['additionalParams'] as String?
      ..notes = json['notes'] as String?
      ..repoUrl = repoUrl
      ..sourceCodeLanguage = SourceCodeLanguage
          .values[(json['sourceCodeLanguage'] as num?)?.toInt() ?? 0]
      ..itemType = ItemType.values[(json['itemType'] as num?)?.toInt() ?? 0];
    return source;
  }
}
