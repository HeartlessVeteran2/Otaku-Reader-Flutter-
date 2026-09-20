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

class PageUrl {
  String url;
  String? fileName;
  Map<String, String>? headers;

  PageUrl(this.url, {this.fileName, this.headers});
  factory PageUrl.fromJson(Map<String, dynamic> json) {
    return PageUrl(
      json['url'].toString().trim(),
      headers: (json['headers'] as Map?)?.toMapStringString,
    );
  }
  Map<String, dynamic> toJson() => {
    'url': url,
    'headers': headers,
    'fileName': fileName,
  };

  @override
  String toString() {
    return 'PageUrl(url: $url, headers: $headers, fileName: $fileName)';
  }
}
