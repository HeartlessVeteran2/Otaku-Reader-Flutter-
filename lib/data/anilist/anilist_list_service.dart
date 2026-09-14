import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';

/// Reads the signed-in user's own AniList list.
///
/// Distinct from `AniListMetadataService`, which serves the *public* record of
/// a series and caches it per entry against a 7-day TTL. This is per-user,
/// changes whenever the user reads a chapter on any device, and is nothing at
/// all when signed out — so it is fetched live and never cached. A cached
/// progress number is worse than none: it would sit on the screen claiming the
/// user is on chapter 12 after they read 20 elsewhere.
class AniListListService {
  const AniListListService(this._auth);

  final AniListAuth _auth;

  /// The viewer's entry for [mediaId], or null.
  ///
  /// Null covers three different things on purpose, because every one of them
  /// renders the same — nothing: signed out, not on the user's list, and
  /// AniList unreachable. A tracking row is an enhancement on a page that has
  /// to work without it, so there is no error state to show and nothing for
  /// the user to act on.
  Future<AniListListEntry?> entryFor(int mediaId) async {
    final viewer = _auth.viewer.value;
    if (viewer == null) return null;

    final data = await _auth.query(
      _query,
      variables: {
        'userId': viewer.id,
        'mediaId': mediaId,
        // Asked for explicitly rather than left to AniList's default. The
        // schema takes `score(format: ScoreFormat)`, and requesting the
        // viewer's own format is what makes a five-star user see stars
        // instead of the ten-point number their profile never shows them.
        'format': viewer.scoreFormat.wire,
      },
    );

    final raw = data?['MediaList'];
    return AniListListEntry.fromJson(
      raw is Map ? raw.cast<String, dynamic>() : null,
    );
  }

  /// `MediaList` is a root query field, and `type: MANGA` keeps a media id
  /// that exists in both halves of AniList from resolving to the anime row.
  static const _query = r'''
query ($userId: Int, $mediaId: Int, $format: ScoreFormat) {
  MediaList(userId: $userId, mediaId: $mediaId, type: MANGA) {
    id
    status
    progress
    progressVolumes
    score(format: $format)
    repeat
    private
    media { id }
  }
}
''';
}
