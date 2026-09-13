/// AniList metadata for one manga.
///
/// Deliberately a **separate model from `MangaEntry`**, never folded into it.
/// The Kotlin app's own note explains why: AniList data is a disposable cache
/// with a re-fetchable upstream, while a library row owns the user's data. A
/// failed refresh must not be able to damage the second.
class AniListMedia {
  const AniListMedia({
    required this.id,
    required this.titles,
    this.raw = const {},
    this.malId,
    this.isAdult = false,
    this.description,
    this.coverUrl,
    this.bannerUrl,
    this.coverColor,
    this.averageScore,
    this.meanScore,
    this.popularity,
    this.favourites,
    this.status,
    this.chapters,
    this.volumes,
    this.format,
    this.countryOfOrigin,
    this.source,
    this.startYear,
    this.endYear,
    this.genres = const [],
    this.tags = const [],
    this.characters = const [],
    this.staff = const [],
    this.relations = const [],
    this.recommendations = const [],
    this.externalLinks = const [],
  });

  final int id;

  /// The payload this was parsed from, so the cache stores one representation
  /// rather than needing a hand-written `toJson` that can drift from
  /// [fromJson].
  final Map<String, dynamic> raw;

  final int? malId;
  final bool isAdult;
  final AniListTitles titles;
  final String? description;
  final String? coverUrl;
  final String? bannerUrl;
  final String? coverColor;
  final int? averageScore;
  final int? meanScore;
  final int? popularity;
  final int? favourites;
  final String? status;
  final int? chapters;
  final int? volumes;
  final String? format;
  final String? countryOfOrigin;
  final String? source;
  final int? startYear;
  final int? endYear;
  final List<String> genres;
  final List<AniListTag> tags;
  final List<AniListPerson> characters;
  final List<AniListPerson> staff;
  final List<AniListRelation> relations;
  final List<AniListRecommendation> recommendations;
  final List<AniListLink> externalLinks;

  static AniListMedia? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = (json['id'] as num?)?.toInt();
    if (id == null) return null;

    return AniListMedia(
      id: id,
      raw: json,
      malId: (json['idMal'] as num?)?.toInt(),
      isAdult: json['isAdult'] as bool? ?? false,
      titles: AniListTitles.fromJson(
        json['title'] as Map<String, dynamic>?,
        (json['synonyms'] as List?)?.map((e) => '$e').toList() ?? const [],
      ),
      description: _text(json['description']),
      coverUrl: _cover(json['coverImage'] as Map<String, dynamic>?),
      bannerUrl: _text(json['bannerImage']),
      coverColor: _text((json['coverImage'] as Map?)?['color']),
      averageScore: (json['averageScore'] as num?)?.toInt(),
      meanScore: (json['meanScore'] as num?)?.toInt(),
      popularity: (json['popularity'] as num?)?.toInt(),
      favourites: (json['favourites'] as num?)?.toInt(),
      status: _text(json['status']),
      chapters: (json['chapters'] as num?)?.toInt(),
      volumes: (json['volumes'] as num?)?.toInt(),
      format: _text(json['format']),
      countryOfOrigin: _text(json['countryOfOrigin']),
      source: _text(json['source']),
      startYear: ((json['startDate'] as Map?)?['year'] as num?)?.toInt(),
      endYear: ((json['endDate'] as Map?)?['year'] as num?)?.toInt(),
      genres: (json['genres'] as List?)?.map((e) => '$e').toList() ?? const [],
      tags: AniListTag.listFrom(json['tags'] as List?),
      characters: AniListPerson.listFrom(
        (json['characters'] as Map?)?['edges'] as List?,
      ),
      staff: AniListPerson.listFrom((json['staff'] as Map?)?['edges'] as List?),
      relations: AniListRelation.listFrom(
        (json['relations'] as Map?)?['edges'] as List?,
      ),
      recommendations: AniListRecommendation.listFrom(
        (json['recommendations'] as Map?)?['edges'] as List?,
      ),
      externalLinks: AniListLink.listFrom(json['externalLinks'] as List?),
    );
  }

  /// Tags worth showing, spoilers removed and strongest first.
  ///
  /// AniList marks two *different* kinds of spoiler and both have to go: a
  /// media-specific one and a general one. Rendering either turns an
  /// information panel into a hazard on a page the user opened to decide
  /// whether to start reading.
  List<AniListTag> get safeTags {
    final safe = tags
        .where((t) => !t.isMediaSpoiler && !t.isGeneralSpoiler)
        .toList();
    safe.sort((a, b) => b.rank.compareTo(a.rank));
    return safe;
  }

  /// Relations this app can actually open.
  ///
  /// AniList returns anime adaptations among a manga's relations, and this app
  /// has no anime surface — so such a tile could only do nothing when tapped.
  /// The sibling Kotlin app shipped that tile and had to filter it out later.
  List<AniListRelation> get mangaRelations =>
      relations.where((r) => r.type == 'MANGA').toList();

  /// Recommendations this app can open, for the same reason.
  List<AniListRecommendation> get mangaRecommendations =>
      recommendations.where((r) => r.type == 'MANGA').toList();

  static String? _cover(Map<String, dynamic>? image) {
    if (image == null) return null;
    return _text(image['extraLarge']) ?? _text(image['large']);
  }

  static String? _text(Object? value) {
    if (value == null) return null;
    final s = '$value'.trim();
    return s.isEmpty ? null : s;
  }
}

class AniListTitles {
  const AniListTitles({
    this.userPreferred,
    this.romaji,
    this.english,
    this.native,
    this.synonyms = const [],
  });

  final String? userPreferred;
  final String? romaji;
  final String? english;
  final String? native;
  final List<String> synonyms;

  /// Every spelling AniList knows, for title matching. Deduplicated and
  /// blank-free, because a null-heavy title block is the norm.
  List<String> get all => {
    ?userPreferred,
    ?romaji,
    ?english,
    ?native,
    ...synonyms,
  }.where((t) => t.trim().isNotEmpty).toList();

  String get display => userPreferred ?? romaji ?? english ?? native ?? '';

  static AniListTitles fromJson(
    Map<String, dynamic>? json,
    List<String> synonyms,
  ) => AniListTitles(
    userPreferred: AniListMedia._text(json?['userPreferred']),
    romaji: AniListMedia._text(json?['romaji']),
    english: AniListMedia._text(json?['english']),
    native: AniListMedia._text(json?['native']),
    synonyms: synonyms,
  );
}

class AniListTag {
  const AniListTag({
    required this.name,
    required this.rank,
    this.isMediaSpoiler = false,
    this.isGeneralSpoiler = false,
  });

  final String name;

  /// How strongly the community associates this tag, 0-100. Rendered as
  /// "Isekai 87%", which is the detail that makes AniList tags worth showing
  /// at all — an unranked tag list is just noise.
  final int rank;
  final bool isMediaSpoiler;
  final bool isGeneralSpoiler;

  static List<AniListTag> listFrom(List? json) => [
    for (final raw in json ?? const [])
      if (raw is Map && raw['name'] != null)
        AniListTag(
          name: '${raw['name']}',
          rank: (raw['rank'] as num?)?.toInt() ?? 0,
          isMediaSpoiler: raw['isMediaSpoiler'] as bool? ?? false,
          isGeneralSpoiler: raw['isGeneralSpoiler'] as bool? ?? false,
        ),
  ];
}

/// A character or a staff member. One model, because they render identically.
class AniListPerson {
  const AniListPerson({
    required this.id,
    required this.name,
    this.role,
    this.imageUrl,
  });

  final int id;
  final String name;

  /// Stored **raw** and formatted by the caller. A character's role is an
  /// AniList enum (`MAIN`) that wants prettifying; a staff member's is free
  /// text kept verbatim ("Story & Art"). Normalising on the way in would make a
  /// staff credit reading "Main" indistinguishable from the enum.
  final String? role;
  final String? imageUrl;

  static List<AniListPerson> listFrom(List? edges) => [
    for (final edge in edges ?? const [])
      if (edge is Map && edge['node'] is Map)
        if (((edge['node'] as Map)['id'] as num?) != null)
          AniListPerson(
            id: ((edge['node'] as Map)['id'] as num).toInt(),
            name:
                AniListMedia._text(
                  ((edge['node'] as Map)['name'] as Map?)?['full'],
                ) ??
                AniListMedia._text(
                  ((edge['node'] as Map)['name'] as Map?)?['userPreferred'],
                ) ??
                '',
            role: AniListMedia._text(edge['role']),
            imageUrl: AniListMedia._text(
              ((edge['node'] as Map)['image'] as Map?)?['large'],
            ),
          ),
  ];
}

class AniListRelation {
  const AniListRelation({
    required this.id,
    required this.title,
    required this.type,
    this.relationType,
    this.format,
    this.status,
    this.averageScore,
    this.coverUrl,
  });

  final int id;
  final String title;
  final String type;
  final String? relationType;
  final String? format;
  final String? status;
  final int? averageScore;
  final String? coverUrl;

  static List<AniListRelation> listFrom(List? edges) => [
    for (final edge in edges ?? const [])
      if (edge is Map && edge['node'] is Map)
        if (((edge['node'] as Map)['id'] as num?) != null)
          AniListRelation(
            id: ((edge['node'] as Map)['id'] as num).toInt(),
            title: _titleOf((edge['node'] as Map)['title'] as Map?),
            type: '${(edge['node'] as Map)['type'] ?? ''}',
            relationType: AniListMedia._text(edge['relationType']),
            format: AniListMedia._text((edge['node'] as Map)['format']),
            status: AniListMedia._text((edge['node'] as Map)['status']),
            averageScore: ((edge['node'] as Map)['averageScore'] as num?)
                ?.toInt(),
            coverUrl: AniListMedia._text(
              ((edge['node'] as Map)['coverImage'] as Map?)?['large'],
            ),
          ),
  ];
}

class AniListRecommendation {
  const AniListRecommendation({
    required this.id,
    required this.title,
    required this.type,
    this.rating,
    this.format,
    this.averageScore,
    this.coverUrl,
  });

  final int id;
  final String title;
  final String type;

  /// The community's net vote for this recommendation. Sorting by it is what
  /// separates "people actually recommend this" from an incidental link.
  final int? rating;
  final String? format;
  final int? averageScore;
  final String? coverUrl;

  static List<AniListRecommendation> listFrom(List? edges) {
    final out = <AniListRecommendation>[];
    for (final edge in edges ?? const []) {
      if (edge is! Map) continue;
      final node = edge['node'];
      if (node is! Map) continue;
      // A recommendation edge whose media has been deleted comes back with a
      // null mediaRecommendation. AniList does return these.
      final media = node['mediaRecommendation'];
      if (media is! Map) continue;
      final id = (media['id'] as num?)?.toInt();
      if (id == null) continue;
      out.add(
        AniListRecommendation(
          id: id,
          title: _titleOf(media['title'] as Map?),
          type: '${media['type'] ?? ''}',
          rating: (node['rating'] as num?)?.toInt(),
          format: AniListMedia._text(media['format']),
          averageScore: (media['averageScore'] as num?)?.toInt(),
          coverUrl: AniListMedia._text((media['coverImage'] as Map?)?['large']),
        ),
      );
    }
    return out;
  }
}

class AniListLink {
  const AniListLink({required this.url, required this.site, this.type});

  final String url;
  final String site;
  final String? type;

  static List<AniListLink> listFrom(List? json) => [
    for (final raw in json ?? const [])
      if (raw is Map && raw['url'] != null)
        // Filtered to http(s) here, and again before a URL becomes an Intent.
        // The sibling app filters twice for a reason: a row cached by an older
        // build never passed through today's mapper.
        if (_isWeb('${raw['url']}'))
          AniListLink(
            url: '${raw['url']}',
            site: '${raw['site'] ?? ''}',
            type: AniListMedia._text(raw['type']),
          ),
  ];

  static bool _isWeb(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }
}

String _titleOf(Map? title) =>
    AniListMedia._text(title?['userPreferred']) ??
    AniListMedia._text(title?['romaji']) ??
    AniListMedia._text(title?['english']) ??
    '';
