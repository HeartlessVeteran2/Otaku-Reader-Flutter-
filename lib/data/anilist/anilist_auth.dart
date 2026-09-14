import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

/// How a user's AniList score is displayed, read from their own account.
///
/// AniList stores every score as a 0-100 double regardless; this only says how
/// to show it. Hardcoding ten-point decimal — which is AniList's own default —
/// would show a five-star user "8.0" for what their web profile calls four
/// stars, which reads as the app having the wrong number rather than the wrong
/// unit.
enum ScoreFormat {
  point100('POINT_100'),
  point10Decimal('POINT_10_DECIMAL'),
  point10('POINT_10'),
  point5('POINT_5'),
  point3('POINT_3');

  const ScoreFormat(this.wire);

  /// The value AniList's API uses.
  final String wire;

  static ScoreFormat parse(String? value) => ScoreFormat.values.firstWhere(
    (f) => f.wire == value,
    orElse: () => ScoreFormat.point10Decimal,
  );
}

/// The signed-in AniList account.
class AniListViewer {
  const AniListViewer({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.scoreFormat = ScoreFormat.point10Decimal,
  });

  final int id;
  final String name;
  final String? avatarUrl;
  final ScoreFormat scoreFormat;
}

/// Signs in to AniList and holds the token.
///
/// **The token lives in `flutter_secure_storage`, never in the KV tier.** That
/// table is an ordinary Isar collection: a backup, a debug dump or anything
/// that can read the database file would carry the token off in clear text,
/// and an AniList token can rewrite the user's whole list. AnymeX keeps its
/// auth tokens in its KV table; this is one of the things `CLAUDE.md` says not
/// to copy.
///
/// ## Why PIN, not a redirect
///
/// AniList's implicit grant can redirect to `…/oauth/pin`, which shows the
/// token on screen for the user to paste back. The alternative — a real
/// redirect URI — needs either a WebView to intercept it or an intent filter
/// and deep-link plumbing, which is two more Android plugins and a manifest
/// entry for a flow the user runs approximately once. Pasting a token is
/// slightly clumsier and very much simpler, and it keeps the token out of a
/// WebView this app would then own.
class AniListAuth {
  AniListAuth({
    FlutterSecureStorage? storage,
    http.Client? client,
    String? clientId,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _client = client ?? http.Client(),
       clientId = clientId ?? _configuredClientId;

  static const _tokenKey = 'anilist_access_token';
  static const _endpoint = 'https://graphql.anilist.co';

  /// Supplied at build time, because it identifies *this build* of the app to
  /// AniList and is the developer's to register, not something that can be
  /// committed usefully.
  ///
  /// Empty is a first-class state, not a failure: a fresh clone has no client
  /// id and must render a setup instruction rather than a broken sign-in
  /// button. See [isConfigured].
  static const _configuredClientId = String.fromEnvironment(
    'ANILIST_CLIENT_ID',
  );

  final FlutterSecureStorage _storage;
  final http.Client _client;

  /// The AniList application id this build authenticates as.
  final String clientId;

  /// Whether this build can sign in at all.
  ///
  /// False on any build that was not given a client id, which includes every
  /// fresh clone. The UI must say so and explain how to fix it; a sign-in
  /// button that fails on tap is worse than one that is not offered.
  bool get isConfigured => clientId.isNotEmpty;

  /// The signed-in account, or null. Null while it is still being read.
  final viewer = Rxn<AniListViewer>();

  /// True once there is an answer to render, whatever that answer is.
  ///
  /// Distinct from `viewer == null`: "not signed in" and "not looked yet" are
  /// different screens, and conflating them flashes a signed-out state at a
  /// user who is signed in.
  ///
  /// Set by [restore] whatever it finds, **and** by a successful [signIn].
  /// Both establish an answer, and tying it to [restore] alone would make the
  /// flag mean "startup ran" rather than what every screen actually gates on —
  /// a difference invisible in the app, where [restore] always runs first, and
  /// a spinner that never ends anywhere it does not.
  final isReady = false.obs;

  String? _token;

  /// Whether a token is held. Says nothing about whether AniList still accepts
  /// it — [loadViewer] is what establishes that.
  bool get isSignedIn => _token != null;

  /// The URL that grants a token, for the user to open.
  ///
  /// `response_type=token` is the implicit grant: AniList shows the token on
  /// its pin page rather than redirecting anywhere this app has to catch.
  Uri get authorizeUrl => Uri.https('anilist.co', '/api/v2/oauth/authorize', {
    'client_id': clientId,
    'response_type': 'token',
  });

  /// Reads the stored token and, if there is one, who it belongs to.
  Future<void> restore() async {
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      // A device whose keystore is unavailable — a restored backup, a broken
      // secure element. Treated as signed out rather than fatal: the user can
      // sign in again, and nothing else in the app depends on this.
      _token = null;
    }
    if (_token != null) await loadViewer();
    isReady.value = true;
  }

  /// Stores [token] and confirms it by fetching the account it belongs to.
  ///
  /// Returns false and stores nothing when AniList rejects it, so a mistyped
  /// paste cannot leave the app believing it is signed in.
  Future<bool> signIn(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return false;
    _token = trimmed;
    final ok = await loadViewer();
    if (!ok) {
      _token = null;
      return false;
    }
    await _storage.write(key: _tokenKey, value: trimmed);
    isReady.value = true;
    return true;
  }

  /// Forgets the token and the account.
  Future<void> signOut() async {
    _token = null;
    viewer.value = null;
    await _storage.delete(key: _tokenKey);
  }

  /// Fetches the signed-in account. False if AniList refused the token.
  Future<bool> loadViewer() async {
    final data = await query(_viewerQuery);
    final me = (data?['Viewer'] as Map?)?.cast<String, dynamic>();
    if (me == null) {
      viewer.value = null;
      return false;
    }
    viewer.value = AniListViewer(
      id: me['id'] as int,
      name: (me['name'] as String?) ?? 'AniList',
      avatarUrl: (me['avatar'] as Map?)?['large'] as String?,
      scoreFormat: ScoreFormat.parse(
        (me['mediaListOptions'] as Map?)?['scoreFormat'] as String?,
      ),
    );
    return true;
  }

  /// Runs an **authenticated** GraphQL call. Null on any failure.
  ///
  /// Deliberately swallows the error rather than throwing: every caller here
  /// treats AniList as a disposable upstream, and a tracker that is down must
  /// not take a screen with it.
  Future<Map<String, dynamic>?> query(
    String document, {
    Map<String, dynamic> variables = const {},
  }) async {
    if (_token == null) return null;
    try {
      final response = await _client.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({'query': document, 'variables': variables}),
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      // GraphQL answers 200 with an `errors` array, so the status code alone
      // is not success — an expired token arrives this way.
      if (body['errors'] != null) return null;
      return (body['data'] as Map?)?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  static const _viewerQuery = '''
query {
  Viewer {
    id
    name
    avatar { large }
    mediaListOptions { scoreFormat }
  }
}
''';
}
