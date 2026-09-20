// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

class MSource {
  int? id;

  String? name;

  String? baseUrl;

  String? lang;

  bool? isFullData;

  bool? hasCloudflare;

  String? dateFormat;

  String? dateFormatLocale;

  String? apiUrl;

  String? additionalParams;

  String? notes;

  MSource({
    this.id,
    this.name,
    this.baseUrl,
    this.lang,
    this.isFullData,
    this.hasCloudflare,
    this.dateFormat,
    this.dateFormatLocale,
    this.apiUrl,
    this.additionalParams,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'apiUrl': apiUrl,
    'baseUrl': baseUrl,
    'dateFormat': dateFormat,
    'dateFormatLocale': dateFormatLocale,
    'hasCloudflare': hasCloudflare,
    'id': id,
    'isFullData': isFullData,
    'lang': lang,
    'name': name,
    'additionalParams': additionalParams,
    'notes': notes,
  };
}
