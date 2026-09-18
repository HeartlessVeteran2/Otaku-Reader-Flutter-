import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';
import 'package:otaku_reader/features/details/widgets/anilist_edit_sheet.dart';

/// A row carrying a rating, for the score control's own tests.
const _scored = AniListListResult(
  AniListListLookup.onList,
  AniListListEntry(
    id: 1,
    mediaId: 7,
    status: AniListListStatus.current,
    statusRaw: 'CURRENT',
    progress: 12,
    score: 8.5,
  ),
);

const _onList = AniListListResult(
  AniListListLookup.onList,
  AniListListEntry(
    id: 1,
    mediaId: 7,
    status: AniListListStatus.current,
    statusRaw: 'CURRENT',
    progress: 12,
  ),
);

void main() {
  /// Opens the sheet and hands back **the sheet's own future**, which
  /// completes when it pops.
  ///
  /// Not the result directly: the sheet is still open when this returns, so a
  /// helper that awaited the result would deadlock, and one that returned
  /// early would hand back a null the test then asserts on. Awaiting the outer
  /// future pumps the sheet open; awaiting the inner one reads what it popped.
  Future<Future<AniListEdit?>> open(
    WidgetTester tester,
    AniListListResult result, {
    int? totalChapters = 24,
    ScoreFormat? scoreFormat = ScoreFormat.point10Decimal,
  }) async {
    late Future<AniListEdit?> pending;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => pending = showAniListEditSheet(
                context,
                result: result,
                scoreFormat: scoreFormat,
                totalChapters: totalChapters,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return pending;
  }

  testWidgets('an untouched sheet cannot be saved', (tester) async {
    // Nothing changed means nothing to write. Leaving Save enabled would fire
    // a mutation that only re-sends what AniList already holds.
    await open(tester, _onList);

    expect(find.text('Edit your AniList'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('changing status sends status and nothing else', (tester) async {
    // The rule the whole `AniListEdit` type exists for: progress was never
    // touched, so it must not be written back.
    final pending = await open(tester, _onList);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final edit = await pending;
    expect(edit?.status, AniListListStatus.completed);
    expect(
      edit?.progress,
      isNull,
      reason: 'untouched is null, which the service then omits',
    );
  });

  testWidgets('changing progress sends progress and nothing else', (
    tester,
  ) async {
    final pending = await open(tester, _onList);

    await tester.tap(find.byTooltip('One more chapter'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final edit = await pending;
    expect(edit?.progress, 13);
    expect(edit?.status, isNull);
  });

  testWidgets('returning a value to what it was is not a change', (
    tester,
  ) async {
    // Step forward and back. The sheet's state is identical to the row's, so
    // there is nothing to write — and a naive "the user touched it" flag
    // would send it anyway.
    await open(tester, _onList);

    await tester.tap(find.byTooltip('One more chapter'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('One fewer chapter'));
    await tester.pumpAndSettle();

    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('progress cannot go below zero', (tester) async {
    // AniList rejects it, and the failure would land as a snackbar long after
    // the tap that caused it.
    await open(
      tester,
      const AniListListResult(
        AniListListLookup.onList,
        AniListListEntry(id: 1, mediaId: 7, progress: 0),
      ),
    );

    final minus = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('One fewer chapter'),
        matching: find.byType(IconButton),
      ),
    );
    expect(minus.onPressed, isNull);
  });

  testWidgets('progress cannot pass the known chapter count', (tester) async {
    await open(
      tester,
      const AniListListResult(
        AniListListLookup.onList,
        AniListListEntry(id: 1, mediaId: 7, progress: 24),
      ),
    );

    final plus = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('One more chapter'),
        matching: find.byType(IconButton),
      ),
    );
    expect(plus.onPressed, isNull);
  });

  testWidgets('an unknown chapter count does not cap progress', (tester) async {
    // A running series. Capping at a total AniList does not know would stop
    // the user recording chapters they have actually read.
    await open(
      tester,
      const AniListListResult(
        AniListListLookup.onList,
        AniListListEntry(id: 1, mediaId: 7, progress: 400),
      ),
      totalChapters: null,
    );

    final plus = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('One more chapter'),
        matching: find.byType(IconButton),
      ),
    );
    expect(plus.onPressed, isNotNull);
  });

  testWidgets('adding an untracked manga starts it as Reading', (tester) async {
    // Somebody opening this on a series they do not track is almost always
    // starting it, and "Planning" would be a silent wrong answer they have to
    // notice and correct.
    final pending = await open(tester, const AniListListResult.notOnList());

    expect(find.text('Add to your AniList'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    final edit = await pending;
    expect(edit?.status, AniListListStatus.current);
  });

  testWidgets('an unrecognised status preselects nothing', (tester) async {
    // AniList adding a status must not make the sheet preselect "Reading" and
    // enable Save the instant it opens — that overwrites a status the user
    // never chose and this build has never heard of. The model already
    // refuses that fallback; this is the same rule in the sheet.
    await open(
      tester,
      const AniListListResult(
        AniListListLookup.onList,
        AniListListEntry(
          id: 1,
          mediaId: 7,
          statusRaw: 'ARCHIVED',
          progress: 12,
        ),
      ),
    );

    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(chip.selected, isFalse, reason: 'nothing the user did not choose');
    }
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(save.onPressed, isNull, reason: 'opening a sheet is not an edit');
    expect(find.textContaining('does not know'), findsOneWidget);
  });

  testWidgets('an unrecognised status can still be changed deliberately', (
    tester,
  ) async {
    // Refusing the silent overwrite must not make the status uneditable —
    // picking one explicitly is exactly how a user gets out of a state this
    // build cannot name.
    final pending = await open(
      tester,
      const AniListListResult(
        AniListListLookup.onList,
        AniListListEntry(id: 1, mediaId: 7, statusRaw: 'ARCHIVED'),
      ),
    );

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect((await pending)?.status, AniListListStatus.completed);
  });

  testWidgets('dismissing the sheet writes nothing', (tester) async {
    final pending = await open(tester, _onList);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8)); // the barrier
    await tester.pumpAndSettle();

    expect(await pending, isNull, reason: 'a dismiss is not a save');
  });

  group('the score control takes the shape the viewer\'s format asks for', () {
    // Three rendered tests rather than one, because `flutter analyze` is
    // structurally blind to which branch a switch took — and this repo has a
    // row in its own mistake list for a screen that analysed clean and could
    // not lay out. A branch with no rendered test is a branch nobody has seen.

    testWidgets('POINT_5 is stars, as the schema asks', (tester) async {
      await open(tester, _scored, scoreFormat: ScoreFormat.point5);

      expect(find.byTooltip('1 star'), findsOneWidget);
      expect(find.byTooltip('5 stars'), findsOneWidget);
      expect(
        find.byType(Slider),
        findsNothing,
        reason: 'a five-star user has never seen a ten-point number',
      );
    });

    testWidgets('POINT_3 is smileys, in AniList\'s own order', (tester) async {
      // Quoted from the schema: 1 => :(, 2 => :|, 3 => :). Not reordered, and
      // not relabelled.
      await open(tester, _scored, scoreFormat: ScoreFormat.point3);

      expect(find.byTooltip('Bad'), findsOneWidget);
      expect(find.byTooltip('Okay'), findsOneWidget);
      expect(find.byTooltip('Good'), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('a numeric format gets a slider and a stepper', (tester) async {
      await open(tester, _scored, scoreFormat: ScoreFormat.point10Decimal);

      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('8.5 / 10'), findsOneWidget);
    });

    testWidgets('no format means no score control at all', (tester) async {
      // Reachable: a sign-out landing between the lookup and this sheet. There
      // is no neutral default to fall back on — the same stored rating is 85,
      // 8.5, 8, four stars or a smiley depending on this one setting — so the
      // control is left out rather than guessed at.
      await open(tester, _scored, scoreFormat: null);

      expect(find.text('Score'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      // The rest of the sheet still works.
      expect(find.text('Chapters read'), findsOneWidget);
    });

    testWidgets('zero reads as "No score", not as a rating of zero', (
      tester,
    ) async {
      // AniList's schema says `0 => No Score`. Rendering "0 / 10" would put a
      // rating of zero on every entry the user never rated, which is most of
      // them.
      await open(tester, _onList, scoreFormat: ScoreFormat.point10Decimal);

      expect(find.text('No score'), findsOneWidget);
      expect(find.text('0 / 10'), findsNothing);
    });
  });

  group('what a score edit sends', () {
    testWidgets('touching only the score sends only the score', (tester) async {
      final pending = await open(
        tester,
        _scored,
        scoreFormat: ScoreFormat.point5,
      );

      await tester.tap(find.byTooltip('4 stars'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final edit = await pending;
      expect(edit!.score, 4);
      expect(
        edit.status,
        isNull,
        reason: 'rating something says nothing about its status',
      );
      expect(edit.progress, isNull);
    });

    testWidgets('clearing a rating sends zero, not nothing', (tester) async {
      // "Remove my score" is a real edit. Treating falsy as absent would make
      // it silently do nothing — the same trap as stepping progress to 0.
      final pending = await open(
        tester,
        _scored,
        scoreFormat: ScoreFormat.point5,
      );

      await tester.tap(find.widgetWithText(TextButton, 'No score'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final edit = await pending;
      expect(edit!.score, 0);
    });

    testWidgets('a score clamped on open does not arm Save', (tester) async {
      // The mutation this guard exists for. The row was fetched while the
      // profile said POINT_100 and the sheet opens saying POINT_5, so the 8.5
      // seed is clamped to fit the five-star input. Comparing the working
      // value against the seed would read that clamp as an edit and enable
      // Save with a rating the user never chose — the same defect the
      // unknown-status rule prevents one field up.
      //
      // Replacing `_scoreTouched` with a value compare fails exactly here.
      await open(tester, _scored, scoreFormat: ScoreFormat.point3);

      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(save.onPressed, isNull);
      // And it rendered at a position the input actually has.
      expect(find.byTooltip('Good'), findsOneWidget);
    });
  });
}
