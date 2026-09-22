import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/database.dart' as db;
import 'package:otaku_reader/core/preferences/nsfw_preference.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/core/widgets/chrome_pills.dart';
import 'package:otaku_reader/data/repository/category_repository_impl.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/repository/category_repository.dart';
import 'package:otaku_reader/features/details/widgets/category_sheet.dart';
import 'package:otaku_reader/features/library/controllers/library_controller.dart';
import 'package:otaku_reader/features/library/screens/categories_screen.dart';
import 'package:otaku_reader/features/library/screens/library_screen.dart';
import 'package:otaku_reader/features/library/widgets/category_filter_bar.dart';
import 'package:otaku_reader/source/model/m_manga.dart';

import 'helpers/fake_source_repository.dart';
import 'helpers/isar_test_env.dart';

/// The category UI: the library's filter bar, the management screen and the
/// assignment sheet.
///
/// The load-bearing test in this file is **"the Library screen renders the
/// filter bar"** — it builds the real screen exactly as the shell does and
/// never constructs a `CategoryFilterBar` by hand. Every other test here
/// constructs the feature's enabled state, which proves the mechanism and is
/// structurally unable to notice that nothing asks for it. This repo has
/// shipped that defect three times (the AniList link chips' `onOpen: (_) {}`,
/// two dead reader switches, a glow multiplier with no caller), and the third
/// one had eight passing tests over it.
void main() {
  IsarTestEnv? env;

  setUpAll(
    () async =>
        env = await IsarTestEnv.open('catui', db.AppDatabaseSchemas.all),
  );
  tearDownAll(() async => env?.close());

  late CategoryRepositoryImpl repo;
  late LibraryRepositoryImpl library;

  setUp(() {
    env!.clear();
    Get.reset();
    repo = CategoryRepositoryImpl();
    // One instance, shared — two would share the database and not the change
    // stream, which is a harness structurally unable to fail when the
    // notification path breaks.
    library = LibraryRepositoryImpl();
    Get.put<ThemeController>(ThemeController());
    Get.put<NsfwPreference>(NsfwPreference());
    Get.put<CategoryRepository>(repo);
  });

  tearDown(() {
    Get.reset();
    repo.dispose();
  });

  Future<void> addManga(
    String url,
    String title, {
    bool favorite = true,
  }) async {
    await library.upsertFromSource(
      sourceId: 5,
      url: url,
      manga: MManga(name: title),
    );
    if (favorite) await library.toggleFavorite(5, url);
  }

  /// Registers the controller and lets **GetX** initialise it.
  ///
  /// Deliberately without a hand-written init call. `Get.put` runs the
  /// lifecycle already, so calling it again runs `_startWatching` twice — and
  /// that method assigns its subscriptions to fields, so the first pair is
  /// overwritten, never cancelled, and outlives the test.
  /// `screen_chrome_test.dart` gets this right for the same screen;
  /// `library_controller_test.dart` drives the lifecycle by hand because it
  /// never registers the controller at all.
  void putController() {
    Get.put<LibraryController>(
      LibraryController(
        library: library,
        sources: const NoSources(),
        categories: repo,
      ),
    );
  }

  /// Copies the real `MediaQueryData` rather than building a fresh one.
  ///
  /// `MediaQueryData()` carries `size: Size.zero`, which makes every
  /// `MediaQuery.sizeOf` under it read zero — and this feature has two
  /// viewport-share caps that a zero would erase rather than shrink. That is
  /// already in `CLAUDE.md`, from four width tests that passed against a
  /// widget which was never on screen.
  Widget wrap(
    Widget child, {
    Size size = const Size(400, 800),
    double scale = 1,
  }) => MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(size: size, textScaler: TextScaler.linear(scale)),
        child: child,
      ),
    ),
  );

  group('the filter bar is wired into the real Library screen', () {
    testWidgets('no categories renders no bar and no pills', (tester) async {
      await addManga('/a', 'Berserk');
      putController();
      await tester.pumpWidget(wrap(const LibraryScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(CategoryFilterBar), findsOneWidget);
      // The widget is in the tree and deliberately renders nothing: a lone
      // "All" chip filters against no alternative.
      expect(find.byType(ChromePills), findsNothing);
      expect(find.text('All'), findsNothing);
    });

    testWidgets('a category reaches the real screen as a pill', (tester) async {
      await addManga('/a', 'Berserk');
      repo.create('Seinen');

      putController();
      await tester.pumpWidget(wrap(const LibraryScreen()));
      await tester.pumpAndSettle();

      // Built by the screen itself, not by this test. Deleting the `bottom:`
      // argument in `library_screen.dart` fails here and nowhere else.
      expect(find.byType(ChromePills), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Seinen'), findsOneWidget);
    });

    testWidgets('tapping a pill filters the grid', (tester) async {
      await addManga('/a', 'Berserk');
      await addManga('/b', 'Solo Levelling');
      final seinen = repo.create('Seinen');
      repo.setCategoriesFor(5, '/a', [seinen!.id]);

      putController();
      await tester.pumpWidget(wrap(const LibraryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Berserk'), findsOneWidget);
      expect(find.text('Solo Levelling'), findsOneWidget);

      await tester.tap(find.text('Seinen'));
      await tester.pumpAndSettle();

      expect(find.text('Berserk'), findsOneWidget);
      expect(
        find.text('Solo Levelling'),
        findsNothing,
        reason: 'it is in no category, so the Seinen filter excludes it',
      );
    });

    testWidgets('the count beside a pill is the filtered count', (
      tester,
    ) async {
      await addManga('/a', 'Berserk');
      await addManga('/b', 'Vagabond');
      await addManga('/c', 'Solo Levelling');
      final seinen = repo.create('Seinen');
      repo.setCategoriesFor(5, '/a', [seinen!.id]);
      repo.setCategoriesFor(5, '/b', [seinen.id]);

      putController();
      await tester.pumpWidget(wrap(const LibraryScreen()));
      await tester.pumpAndSettle();

      // Asserted as text beside the pill rather than baked into the label,
      // which is what keeps the ellipsis from eating the number.
      expect(find.text('3'), findsOneWidget, reason: 'All');
      expect(find.text('2'), findsOneWidget, reason: 'Seinen');
    });

    testWidgets('an empty category still gets a pill, showing 0', (
      tester,
    ) async {
      // AnymeX hides an empty list unless it is selected, which means making
      // a category and not finding it. The count is what makes it legible.
      await addManga('/a', 'Berserk');
      repo.create('Isekai');

      putController();
      await tester.pumpWidget(wrap(const LibraryScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Isekai'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    for (final width in [320.0, 360.0, 384.0]) {
      testWidgets('the bar fits at ${width.toInt()}px', (tester) async {
        await addManga('/a', 'Berserk');
        for (final name in ['Seinen', 'Isekai', 'Shounen', 'On hold']) {
          repo.create(name);
        }

        putController();
        await tester.pumpWidget(
          wrap(const LibraryScreen(), size: Size(width, 800)),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the bar survives a doubled system font', (tester) async {
      await addManga('/a', 'Berserk');
      repo.create('Seinen');

      putController();
      await tester.pumpWidget(
        wrap(const LibraryScreen(), size: const Size(320, 800), scale: 2),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('ChromePills', () {
    testWidgets('a long label ellipsises instead of running off', (
      tester,
    ) async {
      // A horizontal scroll view hands its child unbounded width, so this
      // produces no overflow and no exception — it produces one pill several
      // screens wide. The cap is the only thing that stops it.
      await tester.pumpWidget(
        wrap(
          Align(
            alignment: Alignment.topCenter,
            child: ChromePills(
              pills: [
                ChromePill(label: 'A' * 200, selected: false, onTap: () {}),
              ],
            ),
          ),
          size: const Size(400, 800),
        ),
      );
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('A' * 200));
      expect(text.overflow, TextOverflow.ellipsis);
      // 60% of 400, and the pill's own padding and border sit inside that.
      expect(tester.getSize(find.byType(ChromePills)).width, lessThan(400));
    });

    testWidgets('tapping the live pill does not fire its callback', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          Align(
            alignment: Alignment.topCenter,
            child: ChromePills(
              pills: [
                ChromePill(label: 'All', selected: true, onTap: () => taps++),
                ChromePill(
                  label: 'Seinen',
                  selected: false,
                  onTap: () => taps++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(taps, 0, reason: 're-selecting what is showing is not a change');

      await tester.tap(find.text('Seinen'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('the management screen', () {
    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(400, 800),
    }) async {
      putController();
      await tester.pumpWidget(wrap(const CategoriesScreen(), size: size));
      await tester.pumpAndSettle();
    }

    testWidgets('creates a category through the dialog', (tester) async {
      await open(tester);
      expect(find.textContaining('No categories yet'), findsOneWidget);

      await tester.tap(find.text('New category'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Seinen');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(find.text('Seinen'), findsOneWidget);
      expect(repo.all(), hasLength(1));
    });

    testWidgets('Create is disabled until the name has content', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('New category'));
      await tester.pumpAndSettle();

      FilledButton create() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create'),
      );
      expect(create().onPressed, isNull);

      // Whitespace only. The repository refuses it too, but a button that
      // looks live and then does nothing reads as broken.
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(create().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'Seinen');
      await tester.pumpAndSettle();
      expect(create().onPressed, isNotNull);
    });

    testWidgets('renames through the row', (tester) async {
      repo.create('Sienen');
      await open(tester);

      await tester.tap(find.text('Sienen'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Seinen');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Seinen'), findsOneWidget);
      expect(find.text('Sienen'), findsNothing);
    });

    testWidgets('a delete confirms, and says what happens to the manga', (
      tester,
    ) async {
      await addManga('/a', 'Berserk');
      final seinen = repo.create('Seinen');
      repo.setCategoriesFor(5, '/a', [seinen!.id]);
      await open(tester);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      // The warning, not the reassurance. Collapsing the two into one line
      // loses whichever the user needed.
      expect(find.textContaining('stays in your library'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(repo.all(), hasLength(1), reason: 'Cancel cancels');

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repo.all(), isEmpty);
      expect(
        repo.categoriesOf(5, '/a'),
        isEmpty,
        reason: 'the delete scrubbed the id off the library row',
      );
    });

    testWidgets('an empty category gets the reassurance, not the warning', (
      tester,
    ) async {
      repo.create('Isekai');
      await open(tester);

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing is filed'), findsOneWidget);
      expect(find.textContaining('stays in your library'), findsNothing);
    });

    testWidgets('a drag moves a row to where it was dropped', (tester) async {
      // The guard for the `onReorder` → `onReorderItem` migration. The old
      // callback reports the destination as an index into the list *before*
      // the dragged item is removed, so it needs a `newIndex -= 1` correction
      // on a downward move; the new one has already applied it. Carrying that
      // line across — the obvious thing to do, since it was already written —
      // lands every downward drag one row short, with no error and nothing
      // else to fail.
      for (final name in ['A', 'B', 'C']) {
        repo.create(name);
      }
      await open(tester);

      // Measured off the laid-out rows rather than computed from a row
      // height: the drop index turns on where the dragged row *overlaps* its
      // neighbours, so an offset that looks like "two rows down" arithmetically
      // can still sit inside row one.
      final rows = find.byType(ChromeTile);
      final start = tester.getCenter(
        find.byIcon(Icons.drag_handle_rounded).first,
      );
      final distance =
          tester.getCenter(rows.at(2)).dy - tester.getCenter(rows.at(0)).dy;

      final drag = await tester.startGesture(start);
      await tester.pump(kLongPressTimeout);
      // Stepped, with a frame between each. A reorderable list works out the
      // drop index as the dragged row *passes* its neighbours, so one large
      // `moveTo` registers a single swap and lands the row one slot down --
      // measured, the callback reported `new=1` for a jump spanning two rows.
      // That reads exactly like an off-by-one in the code under test, and is
      // not one.
      for (var step = 0; step < 10; step++) {
        await drag.moveBy(Offset(0, distance / 10));
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();

      expect(repo.all().map((c) => c.name), ['B', 'C', 'A']);
    });

    for (final width in [320.0, 360.0, 384.0]) {
      testWidgets('fits at ${width.toInt()}px', (tester) async {
        for (final name in ['Seinen', 'Isekai', 'Currently reading']) {
          repo.create(name);
        }
        await open(tester, size: Size(width, 800));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the assignment sheet', () {
    /// Opens the sheet over a host that records what it returned.
    Future<List<bool>> openSheet(
      WidgetTester tester, {
      Size size = const Size(400, 800),
    }) async {
      final results = <bool>[];
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async => results.add(
                    await showCategorySheet(
                      context: context,
                      repository: repo,
                      sourceId: 5,
                      url: '/a',
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          size: size,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('ticks what the row already holds', (tester) async {
      await addManga('/a', 'Berserk');
      final seinen = repo.create('Seinen');
      repo.create('Isekai');
      repo.setCategoriesFor(5, '/a', [seinen!.id]);

      await openSheet(tester);

      final tiles = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect(tiles, hasLength(2));
      expect(tiles[0].value, isTrue, reason: 'Seinen');
      expect(tiles[1].value, isFalse, reason: 'Isekai');
    });

    testWidgets('Save writes the ticks; Cancel writes nothing', (tester) async {
      await addManga('/a', 'Berserk');
      repo.create('Seinen');

      await openSheet(tester);
      await tester.tap(find.text('Seinen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(repo.categoriesOf(5, '/a'), isEmpty);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seinen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.categoriesOf(5, '/a'), hasLength(1));
    });

    testWidgets('a category made inside the sheet is ticked already', (
      tester,
    ) async {
      // The first category in the app is made here, so this is also the only
      // route out of the no-categories state for a fresh install.
      await addManga('/a', 'Berserk');
      await openSheet(tester);
      expect(find.textContaining('No categories yet'), findsOneWidget);

      await tester.tap(find.text('New category'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Seinen');
      // A pump between typing and tapping, because Create is gated on the
      // field through a `ValueListenableBuilder`: without a frame in between
      // the button is still disabled when the tap lands, the dialog stays
      // open, and the failure reads as the sheet not rendering a row.
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      final tile = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(
        tile.value,
        isTrue,
        reason: 'making a category here is an action about this manga',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.categoriesOf(5, '/a'), hasLength(1));
    });

    testWidgets('the search field appears only past three categories', (
      tester,
    ) async {
      await addManga('/a', 'Berserk');
      for (final name in ['A', 'B', 'C']) {
        repo.create(name);
      }
      await openSheet(tester);
      expect(
        find.widgetWithText(TextField, 'Find a category'),
        findsNothing,
        reason: 'a search box over three rows costs more height than it saves',
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      repo.create('D');

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    for (final width in [320.0, 360.0, 384.0]) {
      testWidgets('fits at ${width.toInt()}px', (tester) async {
        await addManga('/a', 'Berserk');
        for (final name in ['Seinen', 'Isekai', 'Currently reading', 'Done']) {
          repo.create(name);
        }
        await openSheet(tester, size: Size(width, 800));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
