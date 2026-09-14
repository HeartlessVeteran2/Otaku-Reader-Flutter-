import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/domain/model/anilist_list_entry.dart';
import 'package:otaku_reader/features/details/widgets/anilist_edit_sheet.dart';

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

    await tester.tap(find.byIcon(Icons.add));
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

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove));
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
        of: find.byIcon(Icons.remove),
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
        of: find.byIcon(Icons.add),
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
        of: find.byIcon(Icons.add),
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

  testWidgets('dismissing the sheet writes nothing', (tester) async {
    final pending = await open(tester, _onList);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8)); // the barrier
    await tester.pumpAndSettle();

    expect(await pending, isNull, reason: 'a dismiss is not a save');
  });
}
