// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:otaku_reader/source/model/m_manga.dart';

class MPages {
  List<MManga> list;
  bool hasNextPage;
  MPages({required this.list, this.hasNextPage = false});

  factory MPages.fromJson(Map<String, dynamic> json) {
    return MPages(
      list: json['list'] != null
          ? (json['list'] as List).map((e) => MManga.fromJson(e)).toList()
          : [],
      hasNextPage: json['hasNextPage'],
    );
  }

  Map<String, dynamic> toJson() => {
    'list': list.map((v) => v.toJson()).toList(),
    'hasNextPage': hasNextPage,
  };
}
