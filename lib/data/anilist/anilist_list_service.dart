import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';

/// What looking up the viewer's row found — which is not the same thing as the
/// row itself.
///
/// While the row was read-only these were deliberately collapsed into one
/// nullable entry, because every one of them rendered the same: nothing. That
/// stopped being true the moment editing arrived. "Not on your list" is now an
/// invitation to add it, and the other two are not — so they have to be told
/// apart, and the comment claiming they need not be is gone with them.
enum AniListListLookup {
  /// No account. The list is not the user's to add to.
  signedOut,

  /// Asked, and could not get an answer — offline, AniList down, a garbled
  /// reply. Offering "add to list" here would offer an action about to fail.
  unavailable,

  /// Asked, and this manga is not on their list. The one state where adding
  /// is offered.
  notOnList,

  /// On the list.
  onList,
}

/// A lookup's outcome and, when there is one, the row.
class AniListListResult {
  const AniListListResult(this.lookup, [this.entry]);

  const AniListListResult.signedOut()
    : lookup = AniListListLookup.signedOut,
      entry = null;

  const AniListListResult.unavailable()
    : lookup = AniListListLookup.unavailable,
      entry = null;

  const AniListListResult.notOnList()
    : lookup = AniListListLookup.notOnList,
      entry = null;

  final AniListListLookup lookup;
  final AniListListEntry? entry;

  /// Whether the user could act on this row at all.
  bool get isActionable =>
      lookup == AniListListLookup.onList ||
      lookup == AniListListLookup.notOnList;
}

/// Reads and writes the signed-in user's own AniList list.
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

  /// The format the viewer's own AniList profile displays scores in, or null
  /// when there is no viewer to have one.
  ///
  /// Exposed because a score input is meaningless without it: the same stored
  /// rating is "85", "8.5", "8", four stars or a smiley depending on this one
  /// setting, and an editor that guesses writes a number the user's own
  /// profile never showed them.
  ScoreFormat? get scoreFormat => _auth.viewer.value?.scoreFormat;

  /// The viewer's entry for [mediaId], and what kind of answer that is.
  Future<AniListListResult> lookUp(int mediaId) async {
    final viewer = _auth.viewer.value;
    // Covers signed out *and* a token restored offline, where `isSignedIn` is
    // true but there is no user id to query by.
    if (viewer == null) return const AniListListResult.signedOut();

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

    // A null `data` is a failed call; a null `MediaList` *inside* a successful
    // one is AniList saying "not on their list". Those are different answers
    // and only the second one may offer to add it.
    if (data == null) return const AniListListResult.unavailable();
    final raw = data['MediaList'];
    if (raw == null) return const AniListListResult.notOnList();

    final entry = AniListListEntry.fromJson(
      raw is Map ? raw.cast<String, dynamic>() : null,
    );
    return entry == null
        ? const AniListListResult.unavailable()
        : AniListListResult(AniListListLookup.onList, entry);
  }

  /// Writes any of [status], [progress] and [score] to the viewer's list.
  ///
  /// `SaveMediaListEntry` **creates** the row when there is none, so adding an
  /// untracked manga and editing a tracked one are the same call — which is
  /// why the sheet behind this needs no separate "add" path.
  ///
  /// **Only the named arguments are sent.** AniList sets exactly what it is
  /// given, so passing a field the user did not touch would write back a value
  /// read some time ago — resetting progress they advanced on another device
  /// in between. Null here means "leave it alone", not "clear it".
  ///
  /// Which is why a **zero** [score] still has to be sent: AniList's own
  /// schema says `0 => No Score`, so clearing a rating and never having set
  /// one are the same value, and treating falsy as absent would make "remove
  /// my score" silently do nothing. Same trap, same shape, as progress 0.
  ///
  /// Returns the row AniList now holds, or null if the write failed. The
  /// answer is taken from the response rather than assumed, because the server
  /// may normalise what it was sent.
  Future<AniListListEntry?> save({
    required int mediaId,
    AniListListStatus? status,
    int? progress,
    double? score,
  }) async {
    final viewer = _auth.viewer.value;
    if (viewer == null) return null;
    if (status == null && progress == null && score == null) return null;

    final data = await _auth.query(
      _mutation,
      variables: {
        'mediaId': mediaId,
        if (status != null) 'status': status.wire,
        if (progress != null) 'progress': progress,
        // Sent in the viewer's own format, which is what `score` means to
        // AniList. The mutation also offers `scoreRaw`, always 0-100, and it
        // is *not* used on purpose: converting a POINT_3 smiley to a 0-100
        // number means inventing a mapping AniList does not publish, and the
        // one format where the arithmetic is a guess is the one where a wrong
        // guess is most visible. Handing back the same units the row was read
        // in needs no arithmetic at all.
        if (score != null) 'score': score,
        'format': viewer.scoreFormat.wire,
      },
    );

    final raw = data?['SaveMediaListEntry'];
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

  /// `status` and `progress` are nullable in the schema, and a variable that
  /// is simply absent is not sent — which is what makes "leave it alone"
  /// expressible at all.
  static const _mutation = r'''
mutation ($mediaId: Int, $status: MediaListStatus, $progress: Int, $score: Float, $format: ScoreFormat) {
  SaveMediaListEntry(mediaId: $mediaId, status: $status, progress: $progress, score: $score) {
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
