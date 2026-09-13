import 'package:isar_community/isar.dart';

part 'manga_entry.g.dart';

/// One library entry.
///
/// `sourceId` is the source's **string id**, stored verbatim. The Kotlin app
/// keyed rows by `sourceStringId.hashCode()` and calls the resulting inability
/// to go back from key to source its highest-impact bug ever. Isar has no reason
/// to need an integer key, so the whole class of bug is designed out here.
@collection
class MangaEntry {
  Id id = Isar.autoIncrement;

  @Index(composite: [CompositeIndex('url')])
  late String sourceId;

  late String url;

  @Index(type: IndexType.value, caseSensitive: false)
  late String title;

  String? thumbnailUrl;
  String? author;
  String? artist;
  String? description;
  List<String> genres = const [];

  /// Mangayomi `MStatus` index.
  int status = 5;

  @Index()
  bool favorite = false;

  /// Set when the user overrides a source-provided field. Kept separate so a
  /// chapter refresh can overwrite source data without clobbering user edits.
  String? userTitle;
  String? userCoverUrl;
  String? notes;

  DateTime? dateAdded;
  DateTime? lastUpdate;
  DateTime? lastRead;

  List<Chapter> chapters = const [];

  List<int> categoryIds = const [];

  @ignore
  String get displayTitle => userTitle?.isNotEmpty == true ? userTitle! : title;

  @ignore
  String? get displayCover =>
      userCoverUrl?.isNotEmpty == true ? userCoverUrl : thumbnailUrl;
}

@embedded
class Chapter {
  String? url;
  String? name;
  String? scanlator;
  String? dateUpload;

  /// Fractional chapters are real (12.5), so this is a double, not an int.
  double? number;

  bool read = false;

  /// 0-based index of the last page viewed.
  int? lastPageRead;
  int? totalPages;

  /// Webtoon resume. A page index is not enough in continuous mode — the user
  /// stops partway down a strip, not at a page boundary.
  double? currentOffset;
  double? maxOffset;

  int? lastReadTime;

  /// Set when the chapter is downloaded; the reader then lists this directory
  /// instead of calling the source.
  String? localPath;

  /// Isar cannot store a Map, so headers are two parallel lists. They are
  /// written and read only through [headers], which keeps the lengths in step.
  List<String> headerKeys = const [];
  List<String> headerValues = const [];

  @ignore
  Map<String, String> get headers {
    final n = headerKeys.length < headerValues.length
        ? headerKeys.length
        : headerValues.length;
    return {for (var i = 0; i < n; i++) headerKeys[i]: headerValues[i]};
  }

  set headers(Map<String, String> value) {
    headerKeys = value.keys.toList();
    headerValues = value.values.toList();
  }

  @ignore
  String get formattedNumber {
    final n = number;
    if (n == null) return '';
    return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
  }
}
