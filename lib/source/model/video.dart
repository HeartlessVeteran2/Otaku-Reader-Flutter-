// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:otaku_reader/source/http/http_extensions.dart';

class Video {
  String url;
  String quality;
  String originalUrl;
  Map<String, String>? headers;
  List<Track>? subtitles;
  List<Track>? audios;

  Video(
    this.url,
    this.quality,
    this.originalUrl, {
    this.headers,
    this.subtitles,
    this.audios,
  });
  factory Video.fromJson(Map<String, dynamic> json) {
    return Video(
      json['url'].toString().trim(),
      json['quality'].toString().trim(),
      json['originalUrl'].toString().trim(),
      headers: (json['headers'] as Map?)?.toMapStringString,
      subtitles: json['subtitles'] != null
          ? (json['subtitles'] as List).map((e) => Track.fromJson(e)).toList()
          : [],
      audios: json['audios'] != null
          ? (json['audios'] as List).map((e) => Track.fromJson(e)).toList()
          : [],
    );
  }
  Map<String, dynamic> toJson() => {
    'url': url,
    'quality': quality,
    'originalUrl': originalUrl,
    'headers': headers,
    'subtitles': subtitles?.map((e) => e.toJson()).toList(),
    'audios': audios?.map((e) => e.toJson()).toList(),
  };
}

class Track {
  String? file;
  String? label;

  Track({this.file, this.label});
  Track.fromJson(Map<String, dynamic> json) {
    file = json['file']?.toString().trim();
    label = json['label']?.toString().trim();
  }
  Map<String, dynamic> toJson() => {'file': file, 'label': label};
}
