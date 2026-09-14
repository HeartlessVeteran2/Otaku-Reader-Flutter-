import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/features/settings/screens/accounts_screen.dart';

import 'helpers/anilist_fakes.dart';

/// Every branch of the Accounts screen, rendered.
///
/// This suite exists for one structural reason, and it has caught the same
/// defect in four other screens in this repo: the screen's body is a single
/// `Obx` in a `CustomScrollView`'s sliver slot, and **`flutter analyze` cannot
/// see a box widget in a sliver slot** — the declared type is `Widget` either
/// way. A branch returning, say, a bare `Center` compiles, analyses clean, and
/// throws at layout the moment that state occurs. Only rendering each branch
/// finds it.
///
/// So the assertion that matters in every test here is `takeException()`
/// being null. The text assertions are there to prove the *right* branch was
/// the one rendered.
void main() {
  tearDown(Get.reset);

  Future<void> show(WidgetTester tester, AniListAuth auth) async {
    Get.put<AniListAuth>(auth);
    await tester.pumpWidget(
      GetMaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: const AccountsScreen(),
      ),
    );
    await tester.pump();
  }

  testWidgets('while the keystore is still being read, a spinner', (
    tester,
  ) async {
    // `restore()` is deliberately not awaited at startup, so this state is
    // real and reachable — and it is not the same as signed out. Rendering
    // "Not signed in" here flashes a wrong answer at a user who is signed in.
    await show(tester, AniListAuth(storage: FakeVault(), clientId: 'abc'));

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Not signed in'), findsNothing);
  });

  testWidgets('a build with no client id renders the setup instruction', (
    tester,
  ) async {
    final auth = AniListAuth(storage: FakeVault(), clientId: '');
    await auth.restore();
    await show(tester, auth);

    expect(tester.takeException(), isNull);
    expect(find.text('Not set up in this build'), findsOneWidget);
    expect(
      find.text('Sign in to AniList'),
      findsNothing,
      reason: 'a button that cannot work is worse than no button',
    );
    expect(find.textContaining('ANILIST_CLIENT_ID'), findsOneWidget);
  });

  testWidgets('signed out renders the sign-in button', (tester) async {
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.restore();
    await show(tester, auth);

    expect(tester.takeException(), isNull);
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Sign in to AniList'), findsOneWidget);
  });

  testWidgets('signed in renders the account and its score format', (
    tester,
  ) async {
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(format: 'POINT_5', name: 'Manu')),
    );
    await auth.signIn('t');
    await show(tester, auth);

    expect(tester.takeException(), isNull);
    expect(find.text('Manu'), findsOneWidget);
    expect(
      find.text('Scores shown as stars'),
      findsOneWidget,
      reason: "the user's own AniList setting, not this app's assumption",
    );
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('an account with no avatar still renders', (tester) async {
    // AniList allows it, and `NetworkImage(null)` is not a thing — the null
    // has to be branched on. A test that only ever supplies an avatar cannot
    // tell the branch exists.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(avatar: null)),
    );
    await auth.signIn('t');
    await show(tester, auth);

    expect(tester.takeException(), isNull);
    expect(find.text('Reader'), findsOneWidget);
  });

  testWidgets('signing out returns the screen to the sign-in button', (
    tester,
  ) async {
    // The `Obx` has to re-render on `viewer` clearing. Asserting only that
    // `signOut()` emptied the vault would pass with the screen frozen on the
    // signed-in state, which is what the user would actually see.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.signIn('t');
    await show(tester, auth);
    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sign in to AniList'), findsOneWidget);
  });

  testWidgets('cancelling the sign-out dialog keeps the account', (
    tester,
  ) async {
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.signIn('t');
    await show(tester, auth);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(auth.isSignedIn, isTrue);
    expect(find.text('Reader'), findsOneWidget);
  });

  testWidgets('a sign-out that could not erase the token says so', (
    tester,
  ) async {
    // The screen must not report "signed out" and then have the app sign the
    // user back in at the next launch. `signOut()` returns whether the stored
    // token was actually erased precisely so this sentence can exist.
    final vault = FakeVault();
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.signIn('t');
    await show(tester, auth);
    vault.failDeletes = Exception('keystore locked');

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sign in to AniList'), findsOneWidget);
    expect(
      find.textContaining('could not be removed'),
      findsOneWidget,
      reason: 'silently reverting at the next launch is the worse outcome',
    );
  });

  testWidgets('dismissing the sign-out dialog keeps the account', (
    tester,
  ) async {
    // The case the Cancel test above does *not* cover, and the only one the
    // guard is for. Cancel pops an explicit `false`; tapping the barrier pops
    // **null**, and `showDialog` gives no way to tell the two apart. So
    // `ok ?? false` — writing it as `ok != false` signs the user out of
    // AniList for tapping next to a dialog, and the Cancel test passes either
    // way.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.signIn('t');
    await show(tester, auth);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out of AniList?'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8)); // the barrier, not the dialog
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Sign out of AniList?'), findsNothing);
    expect(auth.isSignedIn, isTrue);
    expect(find.text('Reader'), findsOneWidget);
  });
}
