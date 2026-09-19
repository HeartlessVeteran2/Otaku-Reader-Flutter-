import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/data/anilist/anilist_metadata_service.dart';
import 'package:otaku_reader/data/anilist/anilist_progress_sync.dart';
import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/domain/repository/anilist_repository.dart';

import 'helpers/anilist_fakes.dart';

/// Never called: `linkFor` reads a stored link and touches no network, and
/// these tests never go down the matching path — which is itself one of the
/// rules under test.
class _UnusedRepo implements AniListRepository {
  @override
  Future<AniListMedia?> media(int id) => throw UnimplementedError();
  @override
  Future<TitleMatch?> match(String title) => throw UnimplementedError();
  @override
  Future<List<TitleMatch>> searchCandidates(String title) =>
      throw UnimplementedError();
  @override
  Future<Map<String, List<AniListMedia>>> home({int perPage = 20}) =>
      throw UnimplementedError();
}

class _Metadata extends AniListMetadataService {
  _Metadata(this.link) : super(anilist: _UnusedRepo());

  final int? link;

  @override
  int? linkFor(int entryId) => link;
}

class _List extends AniListListService {
  _List(this.lookupResult, {this.saveAnswers = true})
    : super(AniListAuth(storage: FakeVault(), clientId: 'x'));

  final AniListListResult lookupResult;
  final bool saveAnswers;
  final writes = <int?>[];

  @override
  Future<AniListListResult> lookUp(int mediaId) async => lookupResult;

  @override
  Future<AniListListEntry?> save({
    required int mediaId,
    AniListListStatus? status,
    int? progress,
    double? score,
  }) async {
    writes.add(progress);
    return saveAnswers
        ? AniListListEntry(id: 1, mediaId: mediaId, progress: progress ?? 0)
        : null;
  }
}

AniListListResult _onList(int progress) => AniListListResult(
  AniListListLookup.onList,
  AniListListEntry(id: 1, mediaId: 7, progress: progress),
);

void main() {
  group('rule 1: it never lowers the number', () {
    test('a chapter behind AniList is not written', () async {
      // Re-reading chapter 3 of something the user is 40 chapters into is not
      // a claim that they unread 37 of them.
      final list = _List(_onList(40));
      final sync = AniListProgressSync(_Metadata(7), list);

      final outcome = await sync.reportChapter(entryId: 1, chapterNumber: 3);

      expect(outcome, AniListProgressOutcome.alreadyAhead);
      expect(list.writes, isEmpty);
    });

    test('the chapter AniList already holds is not rewritten', () async {
      final list = _List(_onList(12));
      final sync = AniListProgressSync(_Metadata(7), list);

      final outcome = await sync.reportChapter(entryId: 1, chapterNumber: 12);

      expect(outcome, AniListProgressOutcome.alreadyAhead);
      expect(list.writes, isEmpty);
    });

    test('forward progress is written', () async {
      final list = _List(_onList(12));
      final sync = AniListProgressSync(_Metadata(7), list);

      final outcome = await sync.reportChapter(entryId: 1, chapterNumber: 13);

      expect(outcome, AniListProgressOutcome.written);
      expect(list.writes, [13]);
    });

    test('a progress set by hand is only ever moved forward', () async {
      // This is also what stops automatic reporting fighting the edit sheet.
      // The user set 40 deliberately; reading an early chapter must not undo
      // it, and there is no separate "is this manual?" flag to consult.
      final list = _List(_onList(40));
      final sync = AniListProgressSync(_Metadata(7), list);

      await sync.reportChapter(entryId: 1, chapterNumber: 1);
      await sync.reportChapter(entryId: 1, chapterNumber: 39);
      await sync.reportChapter(entryId: 1, chapterNumber: 41);

      expect(list.writes, [41]);
    });
  });

  group('rule 2: it only updates a row that already exists', () {
    test('a manga not on the list is skipped, not added', () async {
      // `SaveMediaListEntry` would happily create the row. Reading one chapter
      // of an untracked series would then silently put it on the user's
      // AniList list — adding something to a list is a thing people do on
      // purpose, and finishing a chapter is not a request to do it for them.
      final list = _List(const AniListListResult.notOnList());
      final sync = AniListProgressSync(_Metadata(7), list);

      final outcome = await sync.reportChapter(entryId: 1, chapterNumber: 5);

      expect(outcome, AniListProgressOutcome.skipped);
      expect(list.writes, isEmpty);
    });

    test('an unreachable AniList writes nothing', () async {
      final list = _List(const AniListListResult.unavailable());
      final sync = AniListProgressSync(_Metadata(7), list);

      expect(
        await sync.reportChapter(entryId: 1, chapterNumber: 5),
        AniListProgressOutcome.skipped,
      );
      expect(list.writes, isEmpty);
    });

    test('a signed-out reader writes nothing', () async {
      final list = _List(const AniListListResult.signedOut());
      final sync = AniListProgressSync(_Metadata(7), list);

      expect(
        await sync.reportChapter(entryId: 1, chapterNumber: 5),
        AniListProgressOutcome.skipped,
      );
      expect(list.writes, isEmpty);
    });
  });

  group('rule 3: it never matches', () {
    test('an unlinked manga is skipped without asking AniList', () async {
      // The media id comes from a link already stored — set by the user, or by
      // a confident auto-match on the details page. Matching from the reader
      // would be a network guess fired by a page turn, and a wrong guess
      // writes progress onto somebody else's series.
      //
      // `_UnusedRepo` throws on every matching call, so a lookup here fails
      // the test rather than passing quietly.
      final list = _List(_onList(0));
      final sync = AniListProgressSync(_Metadata(null), list);

      final outcome = await sync.reportChapter(entryId: 1, chapterNumber: 5);

      expect(outcome, AniListProgressOutcome.skipped);
      expect(list.writes, isEmpty);
    });
  });

  group('what counts as a chapter number', () {
    test('a fractional chapter floors', () async {
      // Reading 12.5 means twelve whole chapters are behind them. Reporting 13
      // would claim one they have not read.
      final list = _List(_onList(0));
      final sync = AniListProgressSync(_Metadata(7), list);

      await sync.reportChapter(entryId: 1, chapterNumber: 12.5);

      expect(list.writes, [12]);
    });

    test('an unnumbered chapter is skipped', () async {
      // An extra, a one-shot, a source that does not number them. There is no
      // position in the series to report, and inventing one writes a number
      // the user never read to.
      final list = _List(_onList(0));
      final sync = AniListProgressSync(_Metadata(7), list);

      expect(
        await sync.reportChapter(entryId: 1, chapterNumber: null),
        AniListProgressOutcome.skipped,
      );
      expect(list.writes, isEmpty);
    });

    test('a negative chapter number is skipped', () async {
      final list = _List(_onList(0));
      final sync = AniListProgressSync(_Metadata(7), list);

      expect(
        await sync.reportChapter(entryId: 1, chapterNumber: -1),
        AniListProgressOutcome.skipped,
      );
      expect(list.writes, isEmpty);
    });
  });

  test('a refused write is reported as failed, not as written', () async {
    // Nothing surfaces this to the reader, deliberately — but "AniList did not
    // take it" and "AniList now holds it" must not be the same answer to the
    // caller, or a future surface that does report it would report a lie.
    final list = _List(_onList(0), saveAnswers: false);
    final sync = AniListProgressSync(_Metadata(7), list);

    expect(
      await sync.reportChapter(entryId: 1, chapterNumber: 5),
      AniListProgressOutcome.failed,
    );
    expect(list.writes, [5]);
  });
}
