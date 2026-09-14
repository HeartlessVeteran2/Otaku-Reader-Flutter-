/// Where a manga sits on the signed-in user's own AniList list.
///
/// Separate from [AniListMedia], which is the *public* record of a series and
/// is cached per entry. This is per-user and per-media, it changes whenever the
/// user reads a chapter anywhere, and it is meaningless when signed out — so it
/// is fetched live and never cached.
library;

/// AniList's `MediaListStatus`.
///
/// The wire values are shared with anime, which is why the labels are not just
/// the enum name title-cased: `CURRENT` is "Watching" on an anime and
/// **"Reading"** here, and `REPEATING` likewise. Showing "Current" would be
/// technically faithful to the API and wrong to every reader.
enum AniListListStatus {
  current('CURRENT', 'Reading'),
  planning('PLANNING', 'Planning'),
  completed('COMPLETED', 'Completed'),
  dropped('DROPPED', 'Dropped'),
  paused('PAUSED', 'Paused'),
  repeating('REPEATING', 'Rereading');

  const AniListListStatus(this.wire, this.label);

  /// The value AniList's API uses.
  final String wire;

  /// What a manga reader calls it.
  final String label;

  /// Null for a value this build does not know.
  ///
  /// Deliberately not a fallback to [current]: AniList adding a status must
  /// leave the row *unlabelled* rather than silently claim the user is reading
  /// something they are not. The caller shows the raw value instead.
  static AniListListStatus? parse(String? value) {
    for (final status in AniListListStatus.values) {
      if (status.wire == value) return status;
    }
    return null;
  }
}

/// One row of the user's AniList list.
class AniListListEntry {
  const AniListListEntry({
    required this.id,
    required this.mediaId,
    this.status,
    this.statusRaw,
    this.progress = 0,
    this.progressVolumes,
    this.score,
    this.repeat = 0,
    this.private = false,
  });

  /// Builds from AniList's `MediaList` shape. Every field is checked rather
  /// than cast — this is third-party JSON on a screen that must render without
  /// it.
  static AniListListEntry? fromJson(Map<String, dynamic>? json) {
    final id = json?['id'];
    final mediaId = (json?['media'] as Map?)?['id'] ?? json?['mediaId'];
    if (id is! int || mediaId is! int) return null;

    final rawScore = json?['score'];
    final score = rawScore is num ? rawScore.toDouble() : null;
    final rawStatus = json?['status'];
    final statusRaw = rawStatus is String ? rawStatus : null;

    return AniListListEntry(
      id: id,
      mediaId: mediaId,
      status: AniListListStatus.parse(statusRaw),
      statusRaw: statusRaw,
      progress: json?['progress'] is int ? json!['progress'] as int : 0,
      progressVolumes: json?['progressVolumes'] is int
          ? json!['progressVolumes'] as int
          : null,
      // **Zero means unscored, not a score of zero.** AniList stores no
      // "unset" — every format bottoms out at 0 — so rendering it as a rating
      // would put "0.0" on every entry the user has never rated, which is most
      // of them.
      score: score == null || score == 0 ? null : score,
      repeat: json?['repeat'] is int ? json!['repeat'] as int : 0,
      private: json?['private'] == true,
    );
  }

  /// AniList's id for this list row, not the media's.
  final int id;
  final int mediaId;

  /// Null when AniList reported a status this build does not know.
  final AniListListStatus? status;

  /// The wire value as received, so an unknown status can still be shown.
  final String? statusRaw;

  final int progress;
  final int? progressVolumes;

  /// Already in the viewer's own display format, and null when unscored.
  final double? score;

  final int repeat;
  final bool private;

  /// What to call this status, whatever AniList sent.
  String get statusLabel {
    final known = status;
    if (known != null) return known.label;
    final raw = statusRaw;
    if (raw == null || raw.isEmpty) return 'On list';
    // An unrecognised value, shown rather than hidden: "REPEATING" →
    // "Repeating" reads as a status even when this build has never heard of it.
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }
}
