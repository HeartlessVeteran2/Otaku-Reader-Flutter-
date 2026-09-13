import 'dart:convert';

import 'package:otaku_reader/data/anilist/anilist_queries.dart';
import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/domain/repository/anilist_repository.dart';
import 'package:otaku_reader/source/http/m_client.dart';
import 'package:otaku_reader/source/util/log.dart';

/// Posts a GraphQL document and returns the raw response body. Injected so the
/// repository is testable without the network.
typedef GraphQlPoster = Future<String> Function(
  String query,
  Map<String, dynamic> variables,
);

Future<String> _defaultPost(
  String query,
  Map<String, dynamic> variables,
) async {
  final client = MClient.init();
  try {
    final response = await client.post(
      Uri.parse(AniListQueries.endpoint),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'query': query, 'variables': variables}),
    );
    if (response.statusCode != 200) {
      throw StateError('AniList returned HTTP ${response.statusCode}');
    }
    return response.body;
  } finally {
    client.close();
  }
}

class AniListRepositoryImpl implements AniListRepository {
  AniListRepositoryImpl({GraphQlPoster? post}) : _post = post ?? _defaultPost;

  final GraphQlPoster _post;

  /// How many candidates to score. More is not better: AniList's SEARCH_MATCH
  /// ordering already puts the plausible ones first, and a long tail only gives
  /// a spurious high scorer more chances to win.
  static const _searchLimit = 10;

  @override
  Future<AniListMedia?> media(int id) async {
    final data = await _query(AniListQueries.media, {'id': id});
    if (data == null) return null;
    return AniListMedia.fromJson(data['Media'] as Map<String, dynamic>?);
  }

  @override
  Future<TitleMatch?> match(String title) async {
    final scored = await searchCandidates(title);
    return scored.isEmpty ? null : scored.first;
  }

  @override
  Future<List<TitleMatch>> searchCandidates(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return const [];

    final data = await _query(AniListQueries.search, {
      'search': trimmed,
      'perPage': _searchLimit,
    });
    if (data == null) return const [];

    final list = (data['Page'] as Map?)?['media'] as List?;
    final candidates = [
      for (final raw in list ?? const [])
        if (raw is Map) ?AniListMedia.fromJson(Map<String, dynamic>.from(raw)),
    ];
    // Scored individually rather than via `best`, because the picker shows the
    // runners-up: the whole point of it is the case where the top hit is wrong.
    final scored = [
      for (final media in candidates) ?TitleMatcher.best(trimmed, [media]),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  @override
  Future<Map<String, List<AniListMedia>>> home({int perPage = 20}) async {
    final data = await _query(AniListQueries.home, {'perPage': perPage});
    if (data == null) return const {};
    return {
      for (final shelf in const [
        'trending',
        'popular',
        'topRated',
        'newReleases',
      ])
        shelf: [
          for (final raw
              in ((data[shelf] as Map?)?['media'] as List?) ?? const [])
            if (raw is Map)
              ?AniListMedia.fromJson(Map<String, dynamic>.from(raw)),
        ],
    };
  }

  /// Runs a query and unwraps `data`, or returns null.
  ///
  /// GraphQL answers **200 with an `errors` array** rather than an HTTP error,
  /// so a status check alone would treat a failed query as success and then
  /// parse null into an empty page — metadata silently missing with nothing to
  /// explain why.
  Future<Map<String, dynamic>?> _query(
    String query,
    Map<String, dynamic> variables,
  ) async {
    final body = await _post(query, variables);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;

    final errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      Log.error('AniList query failed: ${jsonEncode(errors)}');
      return null;
    }
    return decoded['data'] as Map<String, dynamic>?;
  }
}
