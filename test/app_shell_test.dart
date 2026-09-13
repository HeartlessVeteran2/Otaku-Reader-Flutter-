import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/key_value.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/navigation/app_shell.dart';
import 'package:otaku_reader/core/theme/theme_controller.dart';

import 'helpers/isar_test_env.dart';

void main() {
  late IsarTestEnv env;

  setUpAll(() async => env = await IsarTestEnv.open('shell', [KeyValueSchema]));
  tearDownAll(() async => env.close());

  setUp(() {
    env.clear();
    Get.reset();
    Get.put<ThemeController>(ThemeController());
  });

  Widget wrap(Widget child, {Size size = const Size(400, 800)}) => MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(home: child),
  );

  testWidgets('renders a bottom bar on a narrow viewport', (tester) async {
    await tester.pumpWidget(wrap(const AppShell()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('renders a rail at or above the 600px breakpoint', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const AppShell(), size: const Size(900, 800)));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('selecting a tab persists it for the next launch', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const AppShell()));
    await tester.pumpAndSettle();

    // Library is index 1; tapping it must both switch the view and write the
    // choice, so a relaunch reopens where the user left off.
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(General.lastOpenedTab.get<int>(0), 1);
    expect(find.text('Your saved manga will appear here.'), findsOneWidget);
  });

  testWidgets('a persisted tab index out of range is clamped, not crashed', (
    tester,
  ) async {
    // A build that removes a tab must not brick the app for anyone whose stored
    // index pointed at it.
    General.lastOpenedTab.set<int>(99);

    await tester.pumpWidget(wrap(const AppShell()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
