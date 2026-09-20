// Part of this app's port of the Mangayomi extension runtime
// (https://github.com/kodjodevf/mangayomi), Apache License 2.0.
// See NOTICE and licenses/Mangayomi-Apache-2.0.txt.
//
// Files in this tree are either ported from that project -- some byte for
// byte, some modified -- or written against its contracts. NOTICE lists every
// intended difference, as Apache-2.0 section 4(b) requires. A finding here
// usually describes upstream behaviour that published extensions are written
// against, so diff against upstream before "fixing" it.

import 'package:otaku_reader/source/model/filter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_pages.dart';
import 'package:otaku_reader/source/model/video.dart';

abstract class MProvider {
  MProvider();

  bool get supportsLatest => true;

  String? get baseUrl;

  Map<String, String> get headers;

  Future<MPages> getLatestUpdates(int page);

  Future<MPages> getPopular(int page);

  Future<MPages> search(String query, int page, FilterList filterList);

  Future<MManga> getDetail(String url);

  Future<List<dynamic>> getPageList(String url);

  Future<List<Video>> getVideoList(String url);

  Future<String> getHtmlContent(String name, String url);

  Future<String> cleanHtmlContent(String html);

  List<dynamic> getFilterList();

  List<dynamic> getSourcePreferences();
}
