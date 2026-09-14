import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:otaku_reader/data/anilist/anilist_auth.dart';

import 'helpers/anilist_fakes.dart';

void main() {
  test('a build with no client id cannot sign in, and says so', () {
    // The state of every fresh clone. It has to be distinguishable from
    // "signed out", because the fix is completely different: one is a sign-in
    // button, the other is a setup instruction.
    final auth = AniListAuth(storage: FakeVault(), clientId: '');
    expect(auth.isConfigured, isFalse);
  });

  test('the authorize url asks for a token, not a code', () {
    // `response_type=token` is the implicit grant, which is what makes the pin
    // page show a token the user can paste. `code` would hand back something
    // that needs a second call *and* the client secret, which an app shipping
    // its own binary cannot keep.
    final auth = AniListAuth(storage: FakeVault(), clientId: 'abc');
    expect(auth.authorizeUrl.queryParameters['response_type'], 'token');
    expect(auth.authorizeUrl.queryParameters['client_id'], 'abc');
  });

  test('signing in stores the token only once AniList accepts it', () async {
    final vault = FakeVault();
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );

    expect(await auth.signIn('  good-token  '), SignInResult.ok);
    expect(
      vault.store['anilist_access_token'],
      'good-token',
      reason: 'trimmed, because a paste carries whitespace',
    );
    expect(auth.viewer.value?.name, 'Reader');
  });

  test('a rejected token is not stored and leaves the app signed out', () async {
    // The likeliest failure is a truncated paste. Storing it anyway would mean
    // the app believes it is signed in and every later call fails instead.
    final vault = FakeVault();
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(jsonEncode({'errors': <Object>[]})),
    );

    expect(await auth.signIn('bad-token'), SignInResult.rejected);
    expect(vault.store, isEmpty);
    expect(auth.isSignedIn, isFalse);
    expect(auth.viewer.value, isNull);
  });

  test('a GraphQL error is a failure even when data came back too', () async {
    // The case that actually needs the check, and the one an obvious test
    // misses. A 200 carrying *only* `errors` already fails on the absent
    // `data`, so a test shaped that way passes with the check deleted — it
    // proves nothing. GraphQL's partial-failure shape is a 200 carrying
    // **both**, and there the status code and the payload both look like
    // success.
    //
    // It matters beyond sign-in: `query` is the one authenticated call the
    // rest of AniList goes through, and a mutation that half-failed answers
    // exactly this way. Reporting it as success would tell the user their
    // score saved when it did not.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(
        jsonEncode({
          'data': {
            'Viewer': {
              'id': 7,
              'name': 'Reader',
              'mediaListOptions': {'scoreFormat': 'POINT_10'},
            },
          },
          'errors': [
            {'message': 'Internal server error'},
          ],
        }),
      ),
    );

    expect(await auth.signIn('partial'), SignInResult.rejected);
    expect(
      auth.viewer.value,
      isNull,
      reason: 'the half-answer is discarded, not shown as an account',
    );
  });

  test('a successful sign-in leaves the screens with an answer', () async {
    // `isReady` is what every screen gates its spinner on. Tying it to
    // `restore` alone makes it mean "startup ran", which is true in the app
    // and false anywhere else — a spinner with nothing behind it.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    expect(auth.isReady.value, isFalse);

    await auth.signIn('t');

    expect(auth.isReady.value, isTrue);
  });

  test('a transport failure is a refusal, not a crash', () async {
    // AniList being down must not throw out of a sign-in tap.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient('<html>502</html>', status: 502),
    );
    expect(await auth.signIn('t'), SignInResult.rejected);
  });

  test('the score format comes from the account, not a default', () async {
    // AniList stores every score as 0-100 whatever this says. A five-star user
    // shown "8.0" reads as the wrong number rather than the wrong unit, and
    // ten-point-decimal is AniList's own default — so hardcoding it looks
    // right for most users and wrong for the rest.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(format: 'POINT_5')),
    );
    await auth.signIn('t');
    expect(auth.viewer.value?.scoreFormat, ScoreFormat.point5);
  });

  test('an unknown score format falls back rather than throwing', () async {
    // AniList could add one. A tracker adding an enum value must not stop the
    // user signing in.
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(format: 'POINT_42')),
    );
    await auth.signIn('t');
    expect(auth.viewer.value?.scoreFormat, ScoreFormat.point10Decimal);
  });

  test('restore reads the stored token and sends it', () async {
    final sent = <http.Request>[];
    final vault = FakeVault()..store['anilist_access_token'] = 'stored';
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(viewerBody(), sent: sent),
    );

    await auth.restore();

    expect(auth.isSignedIn, isTrue);
    expect(auth.viewer.value?.name, 'Reader');
    expect(auth.isReady.value, isTrue);
    expect(sent.single.headers['Authorization'], 'Bearer stored');
  });

  test('restore with no stored token asks AniList nothing', () async {
    // A first launch. An anonymous `Viewer` query would answer with an error
    // the app has no use for, on every cold start.
    final sent = <http.Request>[];
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(), sent: sent),
    );

    await auth.restore();

    expect(sent, isEmpty);
    expect(auth.isReady.value, isTrue);
    expect(auth.viewer.value, isNull);
  });

  test('an unreadable keystore is signed out, not a crash', () async {
    // A restored backup or a broken secure element. Nothing else in the app
    // depends on this, so the honest answer is "signed out" — the user can
    // sign in again, which they cannot do if the app fails to start.
    final vault = FakeVault()..failWith = Exception('keystore unavailable');
    final auth = AniListAuth(storage: vault, clientId: 'abc');

    await auth.restore();

    expect(auth.isSignedIn, isFalse);
    expect(
      auth.isReady.value,
      isTrue,
      reason: 'ready with an answer, rather than stuck on the spinner',
    );
  });

  test('signing out forgets the token and the account', () async {
    final vault = FakeVault();
    final auth = AniListAuth(
      storage: vault,
      clientId: 'abc',
      client: FakeClient(viewerBody()),
    );
    await auth.signIn('t');
    expect(vault.store, isNotEmpty);

    await auth.signOut();

    expect(vault.store, isEmpty);
    expect(auth.isSignedIn, isFalse);
    expect(auth.viewer.value, isNull);
  });

  test('an unauthenticated query is refused before it is sent', () async {
    // Not merely "returns null": a call with no token must not reach AniList
    // at all, because an anonymous request to a mutation would be a confusing
    // failure rather than an obvious one.
    final sent = <http.Request>[];
    final auth = AniListAuth(
      storage: FakeVault(),
      clientId: 'abc',
      client: FakeClient(viewerBody(), sent: sent),
    );

    expect(await auth.query('query { Viewer { id } }'), isNull);
    expect(sent, isEmpty);
  });

  group('the keystore can fail without lying about it', () {
    // CodeAnt's four Major findings on #36, all one shape: a storage or
    // payload failure escaped as an exception, from methods whose documented
    // contract is a returned value — and `restore()` is launched unawaited
    // from `AppBindings`, so a throw there has nobody at all to catch it.

    test('a token that works but cannot be saved says exactly that', () async {
      // Rolling back to "rejected" would be a lie that costs the user the
      // session they just earned, and send them to re-paste a token that
      // works. Reporting plain success would promise a persistence that is
      // not there.
      final vault = FakeVault()..failWrites = Exception('keystore is full');
      final auth = AniListAuth(
        storage: vault,
        clientId: 'abc',
        client: FakeClient(viewerBody()),
      );

      expect(await auth.signIn('good'), SignInResult.notPersisted);
      expect(auth.viewer.value?.name, 'Reader', reason: 'the session is live');
      expect(auth.isSignedIn, isTrue);
      expect(vault.store, isEmpty);
    });

    test('signing out reports a token it could not erase', () async {
      // The session ends either way, but a token left on disk signs the user
      // back in at the next launch — so "signed out" would be a promise the
      // app goes on to break by itself.
      final vault = FakeVault()..failDeletes = Exception('keystore locked');
      final auth = AniListAuth(
        storage: vault,
        clientId: 'abc',
        client: FakeClient(viewerBody()),
      );
      await auth.signIn('t');
      vault.store['anilist_access_token'] = 't';

      expect(await auth.signOut(), isFalse);
      expect(auth.isSignedIn, isFalse, reason: 'the session still ends');
      expect(auth.viewer.value, isNull);
    });

    test('a malformed 200 is handled, not thrown', () async {
      // A captive portal's login page, a gateway error, a shape change. The
      // casts this replaced would throw straight out of an unawaited
      // `restore`.
      final auth = AniListAuth(
        storage: FakeVault()..store['anilist_access_token'] = 'stored',
        clientId: 'abc',
        client: FakeClient(
          jsonEncode({
            'data': {
              'Viewer': {'id': 'seven', 'avatar': 'not-a-map'},
            },
          }),
        ),
      );

      await auth.restore();

      expect(auth.viewer.value, isNull);
      expect(auth.isReady.value, isTrue);
    });

    test('a viewer with no name still renders as an account', () async {
      final auth = AniListAuth(
        storage: FakeVault(),
        clientId: 'abc',
        client: FakeClient(viewerBody(name: '')),
      );
      await auth.signIn('t');
      expect(auth.viewer.value?.name, 'AniList');
    });
  });

  group('only a refusal forgets the token', () {
    // The correction CodeAnt's finding did not make. "Drop the token when the
    // check fails" is wrong, because the check also fails for a device with
    // no signal — and signing someone out for being on a train is far worse
    // than one wasted request, with the pin flow as the only way back.

    test('a token AniList refuses is dropped, not retried forever', () async {
      final vault = FakeVault()..store['anilist_access_token'] = 'expired';
      final auth = AniListAuth(
        storage: vault,
        clientId: 'abc',
        client: FakeClient(invalidTokenBody(), status: 400),
      );

      await auth.restore();

      expect(auth.isSignedIn, isFalse);
      expect(vault.store, isEmpty, reason: 'and gone from disk, not just RAM');
      expect(auth.isReady.value, isTrue);
    });

    test('an offline launch keeps the token', () async {
      final vault = FakeVault()..store['anilist_access_token'] = 'good';
      final auth = AniListAuth(
        storage: vault,
        clientId: 'abc',
        client: FakeClient.offline(),
      );

      await auth.restore();

      expect(
        vault.store['anilist_access_token'],
        'good',
        reason: 'no signal is not a rejection',
      );
      expect(auth.isReady.value, isTrue);
    });

    test('AniList being down keeps the token', () async {
      final vault = FakeVault()..store['anilist_access_token'] = 'good';
      final auth = AniListAuth(
        storage: vault,
        clientId: 'abc',
        client: FakeClient('<html>502 Bad Gateway</html>', status: 502),
      );

      await auth.restore();

      expect(vault.store['anilist_access_token'], 'good');
    });

    test(
      'our own malformed query does not cost the user their token',
      () async {
        // AniList answers 400 for a bad *query* as well as a bad token, so the
        // status alone cannot decide. Deciding on it would delete a working
        // token because of a bug in this app.
        final vault = FakeVault()..store['anilist_access_token'] = 'good';
        final auth = AniListAuth(
          storage: vault,
          clientId: 'abc',
          client: FakeClient(
            jsonEncode({
              'errors': [
                {'message': 'Cannot query field "nope" on type "Query".'},
              ],
            }),
            status: 400,
          ),
        );

        await auth.restore();

        expect(vault.store['anilist_access_token'], 'good');
      },
    );
  });
}
