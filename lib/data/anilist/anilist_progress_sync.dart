import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/data/anilist/anilist_metadata_service.dart';

/// What reporting a finished chapter to AniList came to.
///
/// Four answers rather than a bool, for the same reason the rest of this
/// layer has them: "AniList refused it", "AniList was already ahead" and
/// "there was nothing to report to" are different events, and only one of
/// them is a failure.
enum AniListProgressOutcome {
  /// AniList now holds this chapter.
  written,

  /// AniList was already at or past it, so nothing was sent.
  alreadyAhead,

  /// Not attempted: signed out, unreachable, not linked to an AniList media,
  /// not on the user's list, or a chapter with no usable number.
  skipped,

  /// Sent and AniList did not take it.
  failed,
}

/// Reports finished chapters to AniList.
///
/// An interface, not because a second implementation is planned, but because
/// the reader is the caller: a concrete collaborator here drags a metadata
/// service, a list service, an auth and an HTTP client into every reader
/// test, and a test that expensive to set up is a test that does not get
/// written.
abstract interface class AniListProgressReporter {
  /// Reports [chapterNumber] of the library entry [entryId] as read.
  Future<AniListProgressOutcome> reportChapter({
    required int entryId,
    required double? chapterNumber,
  });
}

/// Reports chapters to AniList as the reader finishes them.
///
/// Deliberately narrow. Three rules decide everything it does, and each one
/// exists because the obvious version is worse:
///
/// 1. **It never lowers the number.** Re-reading chapter 3 of something the
///    user is 40 chapters into is not a claim that they have unread 37 of
///    them. This is also what stops automatic reporting from fighting the
///    edit sheet: a progress the user set by hand is only ever moved
///    *forward* by reading.
/// 2. **It only updates a row that already exists.** `SaveMediaListEntry`
///    would happily create one, and then reading a single chapter of an
///    untracked series would silently put it on the user's AniList list.
///    Adding something to a list is a thing people do on purpose; finishing a
///    chapter is not a request to do it for them.
/// 3. **It never matches.** The media id comes from a link that is already
///    stored — set by the user or by a confident auto-match on the details
///    page. Asking the metadata service to go and find one would mean a
///    network guess fired from the reader, and a wrong guess writes progress
///    onto somebody else's series.
class AniListProgressSync implements AniListProgressReporter {
  const AniListProgressSync(this._metadata, this._list);

  final AniListMetadataService _metadata;
  final AniListListService _list;

  /// Never throws: this runs behind a page turn, and a tracker being down is
  /// not a reason for the reader to fail.
  @override
  Future<AniListProgressOutcome> reportChapter({
    required int entryId,
    required double? chapterNumber,
  }) async {
    // An unnumbered chapter — an extra, a one-shot, a source that does not
    // number them — cannot be a position in a series, and inventing one would
    // write a number the user never read to.
    if (chapterNumber == null || !chapterNumber.isFinite || chapterNumber < 0) {
      return AniListProgressOutcome.skipped;
    }

    // Rule 3: only an existing link, never a fresh match.
    final mediaId = _metadata.linkFor(entryId);
    if (mediaId == null) return AniListProgressOutcome.skipped;

    // Floored, because a fractional chapter is *between* two counts. Reading
    // 12.5 means twelve whole chapters are behind them; reporting 13 would
    // claim one they have not read.
    final progress = chapterNumber.floor();

    final current = await _list.lookUp(mediaId);
    // Rule 2: `notOnList` is a deliberate skip, not an opportunity.
    if (current.lookup != AniListListLookup.onList) {
      return AniListProgressOutcome.skipped;
    }

    // Rule 1.
    final held = current.entry?.progress ?? 0;
    if (progress <= held) return AniListProgressOutcome.alreadyAhead;

    final saved = await _list.save(mediaId: mediaId, progress: progress);
    return saved == null
        ? AniListProgressOutcome.failed
        : AniListProgressOutcome.written;
  }
}
