// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

class MChapter {
  String? name;

  String? url;

  String? dateUpload;

  String? scanlator;

  bool? isFiller;

  String? thumbnailUrl;

  String? description;

  /// video size
  String? downloadSize;

  /// video duration
  String? duration;

  MChapter({
    this.name,
    this.url,
    this.dateUpload,
    this.scanlator,
    this.isFiller = false,
    this.thumbnailUrl,
    this.description,
    this.downloadSize,
    this.duration,
  });
  factory MChapter.fromJson(Map<String, dynamic> json) {
    return MChapter(
      name: json['name'],
      url: json['url'],
      dateUpload: json['dateUpload'],
      scanlator: json['scanlator'],
      isFiller: json['isFiller'] ?? false,
      thumbnailUrl: json['thumbnailUrl'],
      description: json['description'],
      downloadSize: json['downloadSize'],
      duration: json['duration'],
    );
  }
  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'dateUpload': dateUpload,
    'scanlator': scanlator,
    'isFiller': isFiller,
    'thumbnailUrl': thumbnailUrl,
    'description': description,
    'downloadSize': downloadSize,
    'duration': duration,
  };
}
