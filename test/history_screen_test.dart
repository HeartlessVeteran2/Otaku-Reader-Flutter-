import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/history/screens/history_screen.dart';
import 'package:otaku_reader/source/model/m_chapter.dart';
import 'package:otaku_reader/source/model/m_manga.dart';

import 'helpers/fake_source_repository.dart';
import 'helpers/isar_test_env.dart';

/// History's search, which changed shape in the chrome conversion.
///
/// It used to be a `TextField` pinned permanently under the title, costing
/// 56px of every screenful whether or not anyone was searching. It is now the
/// header's own search row, reached by tapping the search action — AnymeX's
/// shape, and what buys back the height the old collapsing header spent.
///
/// That is a behaviour change, not a restyle: the field a user typed into no
/// longer exists until they ask for it, and a toggle that opens a field the
/// list ignores would look identical to one that works.
void main() {
  IsarTestEnv? env;

  setUpAll(
    () async => env = await IsarTestEnv.open(
      'history-screen',
      db.AppDatabaseSchemas.all,
    ),
  );
  tearDownAll(() async => env?.close());

  late LibraryRepositoryImpl library;

  setUp(() async {
    env!.clear();
    Get.reset();
    library = LibraryRepositoryImpl();
    Get.put<LibraryRepository>(library);
    Get.put<SourceRepository>(const NoSources());

    for (final name in ['Berserk', 'Vinland Saga']) {
      final url = '/${name.toLowerCase().replaceAll(' ', '-')}';
      await library.upsertFromSource(
        sourceId: 7,
        url: url,
        manga: MManga(
          name: name,
          chapters: [MChapter(url: '/c-1')],
        ),
      );
      await library.setChapterRead(7, url, '/c-1', true);
    }
  });

  tearDown(Get.reset);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('there is no search field until it is asked for', (tester) async {
    await open(tester);

    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'the height it used to cost is the point of the change',
    );
    expect(find.text('Berserk'), findsOneWidget);
    expect(find.text('Vinland Saga'), findsOneWidget);
  });

  testWidgets('the header search filters the list', (tester) async {
    await open(tester);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'vinland');
    await tester.pumpAndSettle();

    expect(find.text('Vinland Saga'), findsOneWidget);
    expect(
      find.text('Berserk'),
      findsNothing,
      reason: 'the field is wired to the controller, not merely rendered',
    );
  });

  testWidgets('closing search puts every row back', (tester) async {
    // The header clears the query when search closes, precisely so a filter
    // cannot stay in force with nothing on screen naming it. Without that,
    // closing the field leaves History looking like it lost rows.
    await open(tester);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'vinland');
    await tester.pumpAndSettle();
    expect(find.text('Berserk'), findsNothing);

    // The header's own close, not the field's clear button: closing search is
    // the path that has to put the query back, and the two are different
    // controls with different handlers.
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();

    expect(find.text('Berserk'), findsOneWidget);
    expect(find.text('Vinland Saga'), findsOneWidget);
  });

  group('the first row clears the pill', () {
    for (final width in <double>[320, 360, 384]) {
      testWidgets('at ${width.toInt()}px', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await open(tester);

        final header = tester.getRect(find.byType(PillHeader));
        final firstRow = tester.getRect(find.text('Berserk'));
        expect(firstRow.top, greaterThanOrEqualTo(header.bottom));
      });
    }
  });
}
