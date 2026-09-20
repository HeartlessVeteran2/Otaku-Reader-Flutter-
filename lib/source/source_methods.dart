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
import 'package:otaku_reader/source/model/page_url.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/source/model/source_preference.dart';

/// The one contract the rest of the app knows about a source.
///
/// Every backend is an implementation of this and nothing more, which is what
/// makes adding one cheap: the library, reader, downloads and migration all
/// speak this interface, not any particular runtime.
///
/// Deliberately narrower than Mangayomi's: `getVideoList` and the novel
/// accessors are gone, because this app has no video or novel surface and an
/// interface method nothing can serve is a trap for the next person.
abstract interface class SourceMethods {
  Source get source;

  /// The base URL actually in effect.
  ///
  /// Not the same as `source.baseUrl`: a source may override it from a user
  /// preference (a mirror), so this asks the extension rather than the record.
  String get sourceBaseUrl;

  bool get supportsLatest;

  /// Headers the source wants on its own requests, e.g. a Referer a CDN needs.
  Map<String, String> getHeaders();

  Future<MPages> getPopular(int page);

  Future<MPages> getLatestUpdates(int page);

  Future<MPages> search(String query, int page, FilterList filterList);

  Future<MManga> getDetail(String url);

  Future<List<PageUrl>> getPageList(String url);

  /// The filters this source offers for [search]. Shape is source-defined, so
  /// the UI renders whatever comes back rather than assuming a fixed set.
  FilterList getFilterList();

  /// The preferences this source *declares*. Values come from
  /// `SourcePreferenceStore`; this is only the shape and the defaults.
  List<SourcePreference> getSourcePreferences();

  /// Releases interpreter state. A source outlives a single request, but not
  /// the app, and the interpreter holds the parsed script.
  void dispose();
}
