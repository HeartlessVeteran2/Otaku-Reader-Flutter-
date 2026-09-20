import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
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

  /// url_launcher's own channel. Mocking it is what makes the paste sheet
  /// reachable at all: `openLink` returns false when no browser answers, and
  /// `_start` deliberately does not open the sheet in that case — so without
  /// this the entire token-paste path is unreachable live UI.
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');

  List<String> mockBrowser(WidgetTester tester, {bool opens = true}) {
    final launched = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(launcher, (call) async {
      launched.add('${call.arguments}');
      return opens;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launcher, null));
    return launched;
  }

  testWidgets('pasting a token signs in, and the sheet owns no leak', (
    tester,
  ) async {
    final launched = mockBrowser(tester);
    final vault = FakeVault();
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.restore();
    await show(tester, auth);

    await tester.tap(find.text('Sign in to AniList'));
    await tester.pumpAndSettle();

    expect(launched.single, contains('response_type=token'));
    expect(find.text('Paste the token'), findsOneWidget);

    // Held onto so disposal can be asserted once the sheet is gone — the
    // screen owns this controller privately, so there is no other way to
    // reach it, and "it is disposed" is not observable from the rendered
    // tree at all.
    final field = tester.widget<TextField>(find.byType(TextField)).controller!;

    await tester.enterText(find.byType(TextField), '  pasted-token  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(vault.store['anilist_access_token'], 'pasted-token');
    expect(find.text('Signed in to AniList'), findsOneWidget);
    expect(find.text('Reader'), findsOneWidget);
    expect(
      () => field.addListener(() {}),
      throwsFlutterError,
      reason: 'one controller per sheet-open is an unbounded leak',
    );
  });

  testWidgets('dismissing the paste sheet disposes its controller too', (
    tester,
  ) async {
    // The branch a careless fix misses. Disposing after the "user cancelled"
    // early return leaks exactly the case where the user opened the sheet and
    // changed their mind, which is the likeliest way to open it repeatedly.
    mockBrowser(tester);
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.restore();
    await show(tester, auth);

    await tester.tap(find.text('Sign in to AniList'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byType(TextField)).controller!;

    await tester.tapAt(const Offset(8, 8)); // the barrier
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Paste the token'), findsNothing);
    expect(() => field.addListener(() {}), throwsFlutterError);
  });

  testWidgets('no browser means no sheet to paste into', (tester) async {
    // `openLink` already tells the user; opening a sheet asking them to paste
    // a token from a page that never opened would be the second, confusing
    // half of one failure.
    mockBrowser(tester, opens: false);
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.restore();
    await show(tester, auth);

    await tester.tap(find.text('Sign in to AniList'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Paste the token'), findsNothing);
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

  group('the chrome contract holds on every branch', () {
    // Converted from `OneUiScaffold` to `ChromeScaffold`, which floats its
    // header over the body instead of reserving a bar for it. That swaps one
    // failure mode for another: a body that starts too high is not an
    // exception, it is a row rendered behind a translucent blurred pill --
    // which reads as a design flourish rather than as a control nobody can
    // press, and `flutter analyze` is clean throughout.
    for (final width in <double>[320, 360, 384]) {
      testWidgets('the sign-in row clears the pill at ${width.toInt()}px', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 720));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final auth = AniListAuth(
          storage: FakeVault(),
          clientId: 'abc',
          client: FakeClient(viewerBody()),
        );
        await auth.restore();
        await show(tester, auth);
        await tester.pumpAndSettle();

        final header = tester.getRect(find.byType(PillHeader));
        final row = tester.getRect(find.text('Not signed in'));
        expect(row.top, greaterThanOrEqualTo(header.bottom));
      });
    }

    testWidgets('the setup instruction is not truncated at a doubled font', (
      tester,
    ) async {
      // The longest prose in the app: a four-step shell recipe in a build
      // with no client id, which is what a fresh clone renders. An ellipsis
      // throws nothing, so `takeException()` is blind to it and
      // `didExceedMaxLines` is the question actually being asked.
      await tester.binding.setSurfaceSize(const Size(320, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Restored, or `isReady` stays false and the screen renders its
      // spinner -- which never settles, so `pumpAndSettle` times out on an
      // animation rather than failing on anything this test is about.
      final auth = AniListAuth(storage: FakeVault(), clientId: '');
      await auth.restore();
      Get.put<AniListAuth>(auth);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: const GetMaterialApp(home: AccountsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      var checked = 0;
      for (final element in find.byType(RichText).evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        if (paragraph.maxLines == 1) continue;
        checked++;
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'hidden text: "${paragraph.text.toPlainText()}"',
        );
      }
      // A filter that matches nothing passes every assertion it never makes.
      expect(checked, greaterThan(0), reason: 'no uncapped text was examined');
    });
  });
}
