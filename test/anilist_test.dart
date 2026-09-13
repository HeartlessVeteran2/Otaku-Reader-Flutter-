import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/data/anilist/title_matcher.dart';
import 'package:otaku_reader/data/repository/anilist_repository_impl.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';

Map<String, dynamic> _media({
  int id = 1,
  String? userPreferred = 'Berserk',
  List<String> synonyms = const [],
  List<Map<String, dynamic>> tags = const [],
  List<Map<String, dynamic>> relationEdges = const [],
  List<Map<String, dynamic>> recommendationEdges = const [],
  List<Map<String, dynamic>> links = const [],
  List<Map<String, dynamic>> characterEdges = const [],
}) => {
  'id': id,
  'title': {'userPreferred': userPreferred, 'romaji': userPreferred},
  'synonyms': synonyms,
  'tags': tags,
  'relations': {'edges': relationEdges},
  'recommendations': {'edges': recommendationEdges},
  'externalLinks': links,
  'characters': {'edges': characterEdges},
};

String _ok(Map<String, dynamic> data) => jsonEncode({'data': data});

void main() {
  group('parsing', () {
    test('a null media yields null rather than an empty shell', () {
      expect(AniListMedia.fromJson(null), isNull);
      expect(AniListMedia.fromJson({'title': {}}), isNull);
    });

    test('both kinds of spoiler tag are hidden, and rank orders the rest', () {
      // AniList marks two *different* spoiler flags. Rendering either turns an
      // information panel into a hazard on the page someone opened to decide
      // whether to start reading.
      final media = AniListMedia.fromJson(
        _media(
          tags: [
            {'name': 'Isekai', 'rank': 87},
            {'name': 'Dies', 'rank': 99, 'isMediaSpoiler': true},
            {'name': 'Twist', 'rank': 95, 'isGeneralSpoiler': true},
            {'name': 'Adventure', 'rank': 92},
          ],
        ),
      )!;

      expect(media.safeTags.map((t) => t.name), ['Adventure', 'Isekai']);
      expect(media.safeTags.first.rank, 92);
    });

    test(
      'anime relations are excluded, because nothing here can open them',
      () {
        final media = AniListMedia.fromJson(
          _media(
            relationEdges: [
              {
                'relationType': 'ADAPTATION',
                'node': {
                  'id': 2,
                  'type': 'ANIME',
                  'title': {'userPreferred': 'Berserk (1997)'},
                },
              },
              {
                'relationType': 'SIDE_STORY',
                'node': {
                  'id': 3,
                  'type': 'MANGA',
                  'title': {'userPreferred': 'Berserk: The Prototype'},
                },
              },
            ],
          ),
        )!;

        expect(media.relations, hasLength(2), reason: 'both are parsed');
        expect(media.mangaRelations.map((r) => r.title), [
          'Berserk: The Prototype',
        ], reason: 'only the openable one is offered');
      },
    );

    test(
      'a recommendation whose media was deleted is skipped, not crashed',
      () {
        // AniList really does return edges with a null mediaRecommendation.
        final media = AniListMedia.fromJson(
          _media(
            recommendationEdges: [
              {
                'node': {'rating': 40, 'mediaRecommendation': null},
              },
              {
                'node': {
                  'rating': 120,
                  'mediaRecommendation': {
                    'id': 9,
                    'type': 'MANGA',
                    'title': {'userPreferred': 'Vagabond'},
                  },
                },
              },
            ],
          ),
        )!;

        expect(media.mangaRecommendations.map((r) => r.title), ['Vagabond']);
        expect(media.mangaRecommendations.single.rating, 120);
      },
    );

    test('external links are filtered to http(s)', () {
      final media = AniListMedia.fromJson(
        _media(
          links: [
            {'url': 'https://example.test', 'site': 'Official'},
            {'url': 'javascript:alert(1)', 'site': 'Nope'},
            {'url': 'ftp://files.test', 'site': 'Nope'},
          ],
        ),
      )!;

      expect(media.externalLinks.map((l) => l.site), ['Official']);
    });

    test('a character role is kept raw for the caller to format', () {
      // A character's role is an enum wanting prettifying; a staff member's is
      // free text kept verbatim. Normalising on the way in would make a staff
      // credit reading "Main" indistinguishable from the enum.
      final media = AniListMedia.fromJson(
        _media(
          characterEdges: [
            {
              'role': 'MAIN',
              'node': {
                'id': 5,
                'name': {'full': 'Guts'},
              },
            },
          ],
        ),
      )!;

      expect(media.characters.single.role, 'MAIN');
      expect(media.characters.single.name, 'Guts');
    });

    test('every title spelling is collected for matching, blanks dropped', () {
      final media = AniListMedia.fromJson({
        'id': 1,
        'title': {
          'userPreferred': 'Berserk',
          'romaji': 'Berserk',
          'english': null,
          'native': 'ベルセルク',
        },
        'synonyms': ['Berserk: The Black Swordsman', ''],
      })!;

      expect(
        media.titles.all,
        containsAll(['Berserk', 'ベルセルク', 'Berserk: The Black Swordsman']),
      );
      expect(media.titles.all.where((t) => t.isEmpty), isEmpty);
      expect(
        media.titles.all.where((t) => t == 'Berserk'),
        hasLength(1),
        reason: 'userPreferred and romaji are the same string',
      );
    });
  });

  group('title matching', () {
    test('an exact match scores 1 and is confident', () {
      final match = TitleMatcher.best('Berserk', [
        AniListMedia.fromJson(_media(userPreferred: 'Berserk'))!,
      ])!;

      expect(match.score, 1.0);
      expect(match.isConfident, isTrue);
    });

    test('source decoration is stripped before comparing', () {
      // These are the shapes source sites actually publish.
      for (final messy in [
        'Berserk (Official)',
        'Berserk [Colored]',
        'Berserk Manga',
        '  berserk  ',
      ]) {
        final match = TitleMatcher.best(messy, [
          AniListMedia.fromJson(_media(userPreferred: 'Berserk'))!,
        ])!;
        expect(
          match.isConfident,
          isTrue,
          reason: '"$messy" should still match Berserk (scored ${match.score})',
        );
      }
    });

    test('a synonym can win the match', () {
      final match = TitleMatcher.best('The Black Swordsman', [
        AniListMedia.fromJson(
          _media(userPreferred: 'Berserk', synonyms: ['The Black Swordsman']),
        )!,
      ])!;

      expect(match.isConfident, isTrue);
    });

    test('a different manga is not confident, however close the name', () {
      // The whole point of the threshold: a wrong synopsis and wrong tags look
      // exactly as authoritative as right ones.
      final match = TitleMatcher.best('Berserk of Gluttony', [
        AniListMedia.fromJson(_media(userPreferred: 'Berserk'))!,
      ])!;

      expect(match.isConfident, isFalse, reason: 'scored ${match.score}');
    });

    test('a title that is entirely bracketed survives normalisation', () {
      // AniList's real name for this series is "[Oshi no Ko]", brackets and
      // all. Stripping bracketed asides unconditionally left an empty string,
      // which scored 0.000 against itself.
      expect(TitleMatcher.normalise('[Oshi No Ko]'), 'oshi no ko');

      final match = TitleMatcher.best('Oshi no Ko', [
        AniListMedia.fromJson(_media(userPreferred: '[Oshi No Ko]'))!,
      ])!;
      expect(match.isConfident, isTrue);
    });

    test('a sequel sharing its parent name is NOT matched', () {
      // This is why containment is deliberately not part of the score. "Solo
      // Leveling" is wholly contained in "Solo Leveling: Ragnarok", and they
      // are different series. The cost of that rule is a few near-misses on
      // subtitled titles -- which is the safe failure, because below the
      // threshold nothing is stored and nothing renders, and the recourse is a
      // manual picker rather than a wrong synopsis presented as fact.
      final match = TitleMatcher.best('Solo Leveling', [
        AniListMedia.fromJson(
          _media(userPreferred: 'Solo Leveling: Ragnarok'),
        )!,
      ])!;

      expect(match.isConfident, isFalse, reason: 'scored ${match.score}');
    });

    test('punctuation becomes a space, so Re:Zero still matches Re: Zero', () {
      expect(TitleMatcher.normalise('Re:Zero'), 're zero');
      expect(TitleMatcher.normalise('Re: Zero'), 're zero');
    });

    test('the best of several candidates wins', () {
      final match = TitleMatcher.best('Vagabond', [
        AniListMedia.fromJson(_media(id: 1, userPreferred: 'Berserk'))!,
        AniListMedia.fromJson(_media(id: 2, userPreferred: 'Vagabond'))!,
        AniListMedia.fromJson(_media(id: 3, userPreferred: 'Vinland Saga'))!,
      ])!;

      expect(match.media.id, 2);
      expect(match.isConfident, isTrue);
    });

    test('an empty title matches nothing', () {
      expect(
        TitleMatcher.best('   ', [AniListMedia.fromJson(_media())!]),
        isNull,
      );
    });

    test('no candidates yields null, not a throw', () {
      expect(TitleMatcher.best('Berserk', const []), isNull);
    });

    test('a repeated bigram cannot be double-counted', () {
      // Dice on a multiset: without consuming matches, "aaaa" vs "aa" would
      // score far too high.
      expect(TitleMatcher.similarity('aaaa', 'aa'), lessThan(1.0));
      expect(TitleMatcher.similarity('aa', 'aa'), 1.0);
    });
  });

  group('repository', () {
    test('a GraphQL errors array is a failure, not empty metadata', () async {
      // GraphQL answers 200 with an `errors` array. A status check alone would
      // treat this as success and parse null into an empty page — metadata
      // silently missing with nothing to explain why.
      //
      // `data` is deliberately **populated**. With `data: null` this test
      // passed with the errors guard deleted, because the missing-data path
      // produced the same null: it asserted nothing. A partial response —
      // errors *and* data, which is what GraphQL actually returns when one
      // field of a query fails — is the only shape where the guard is the thing
      // being tested.
      final repo = AniListRepositoryImpl(
        post: (q, v) async => jsonEncode({
          'errors': [
            {'message': 'Not Found'},
          ],
          'data': {'Media': _media(id: 30002)},
        }),
      );

      expect(await repo.media(30002), isNull);
    });

    test('media parses a successful response', () async {
      final repo = AniListRepositoryImpl(
        post: (q, v) async => _ok({'Media': _media(id: 30002)}),
      );

      final media = await repo.media(30002);

      expect(media?.id, 30002);
      expect(media?.titles.display, 'Berserk');
    });

    test('match searches and scores', () async {
      late Map<String, dynamic> seenVariables;
      final repo = AniListRepositoryImpl(
        post: (q, v) async {
          seenVariables = v;
          return _ok({
            'Page': {
              'media': [
                _media(id: 1, userPreferred: 'Berserk of Gluttony'),
                _media(id: 2, userPreferred: 'Berserk'),
              ],
            },
          });
        },
      );

      final match = await repo.match('Berserk');

      expect(seenVariables['search'], 'Berserk');
      expect(match?.media.id, 2);
      expect(match?.isConfident, isTrue);
    });

    test('an empty search term does not hit the network', () async {
      var called = false;
      final repo = AniListRepositoryImpl(
        post: (q, v) async {
          called = true;
          return _ok({});
        },
      );

      expect(await repo.match('  '), isNull);
      expect(called, isFalse);
    });

    test('the media query asks for MANGA, not any media type', () async {
      // A great many titles name both a manga and its anime adaptation, and the
      // anime is often the more popular hit.
      late String seenQuery;
      final repo = AniListRepositoryImpl(
        post: (q, v) async {
          seenQuery = q;
          return _ok({
            'Page': {'media': []},
          });
        },
      );

      await repo.match('Berserk');

      expect(seenQuery, contains('type: MANGA'));
    });
  });
}
