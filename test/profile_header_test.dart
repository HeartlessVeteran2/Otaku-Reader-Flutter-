import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/data/anilist/anilist_auth.dart';
import 'package:otaku_reader/features/settings/widgets/profile_avatar.dart';

import 'helpers/anilist_fakes.dart';

/// The account at the head of a tab root.
///
/// Two separate things are guarded here, and the second is the one that a
/// review would otherwise find:
///
/// 1. the avatar answers with **four** states, not two — collapsing them is a
///    mistake `CLAUDE.md` already records twice;
/// 2. a leading costs one **action slot**, and the header overflows a real
///    phone without it being obvious. That budget is measured rather than
///    asserted from the shape of the row.
void main() {
  tearDown(Get.reset);

  Future<void> show(WidgetTester tester, {Size? surface}) async {
    if (surface != null) {
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: ProfileAvatar())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the avatar has an answer for every state of the account', () {
    testWidgets('startup has not answered yet', (tester) async {
      // Deliberately distinct from "signed out": claiming the user is not
      // signed in before anyone has looked is a sentence about a question
      // that was never asked. The Settings row already honours this and a
      // previous version of it did not -- that is in the mistakes table.
      Get.put<AniListAuth>(
        AniListAuth(storage: FakeVault(), clientId: 'abc'),
        permanent: true,
      );
      await show(tester);

      expect(find.byTooltip('Checking your account'), findsOneWidget);
    });

    testWidgets('this build has no client id', (tester) async {
      final auth = AniListAuth(storage: FakeVault(), clientId: '');
      await auth.restore();
      Get.put<AniListAuth>(auth, permanent: true);
      await show(tester);

      expect(
        find.byTooltip('AniList is not set up in this build'),
        findsOneWidget,
        reason: 'a fresh clone is supposed to look like this',
      );
    });

    testWidgets('configured but signed out invites a sign-in', (tester) async {
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: FakeClient(viewerBody()),
      );
      await auth.restore();
      Get.put<AniListAuth>(auth, permanent: true);
      await show(tester);

      expect(find.byTooltip('Sign in to AniList'), findsOneWidget);
    });

    testWidgets('signed in names the account', (tester) async {
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: FakeClient(viewerBody(name: 'Manu')),
      );
      await auth.signIn('t');
      Get.put<AniListAuth>(auth, permanent: true);
      await show(tester);

      expect(find.byTooltip('Manu'), findsOneWidget);
    });

    testWidgets('no controller registered renders rather than throwing', (
      tester,
    ) async {
      // The tolerated case, and the reason it is tolerated: a library-grid or
      // extension-list test should not have to stand up an AniList account to
      // render the screen it is actually about. It is not silent -- the
      // bindings test below asserts the app itself registers one.
      await show(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ProfileAvatar), findsOneWidget);
    });
  });

  group('a leading costs one action slot', () {
    // Measured, not reasoned about. With a leading, three actions plus search
    // overflows by 22px at 320 and **1.5px at 360** -- a Pixel-class width,
    // exactly like the `TabBar` overflow this repo already shipped. Without
    // one, the same row is clean at every width.
    //
    // This is what keeps four tab roots leading with the account while Browse
    // does not. If someone gives Browse a leading again, or adds a third
    // action to a screen that has one, this fails instead of an overflow
    // stripe appearing on a phone nobody tested.
    Widget header({required bool leading, required int actions}) => MaterialApp(
      home: ChromeScaffold.slivers(
        title: 'Extensions',
        leading: leading ? const SizedBox.square(dimension: 36) : null,
        subtitleWidget: const Text('Good evening'),
        enableSearch: true,
        actions: [
          for (var i = 0; i < actions; i++)
            IconButton(icon: const Icon(Icons.star), onPressed: () {}),
        ],
        slivers: [
          SliverList.builder(
            itemCount: 3,
            itemBuilder: (_, i) => SizedBox(height: 56, child: Text('$i')),
          ),
        ],
      ),
    );

    Future<Object?> render(
      WidgetTester tester,
      Widget widget,
      double width,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      return tester.takeException();
    }

    for (final width in [320.0, 360.0, 384.0]) {
      testWidgets('two actions and search fit beside a leading at $width', (
        tester,
      ) async {
        expect(
          await render(tester, header(leading: true, actions: 2), width),
          isNull,
        );
      });

      testWidgets('three actions and search fit without one at $width', (
        tester,
      ) async {
        expect(
          await render(tester, header(leading: false, actions: 3), width),
          isNull,
        );
      });
    }

    testWidgets('three actions plus a leading is over the budget at 360', (
      tester,
    ) async {
      // The assertion that makes the two above mean something. Without it,
      // deleting the leading from every screen would satisfy them, and so
      // would a header that silently dropped whatever did not fit.
      expect(
        await render(tester, header(leading: true, actions: 3), 360),
        isNotNull,
        reason: 'the budget is real, and this is where it is spent',
      );
    });
  });
}
