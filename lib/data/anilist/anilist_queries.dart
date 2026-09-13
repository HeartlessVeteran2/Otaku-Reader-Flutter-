/// GraphQL against `https://graphql.anilist.co`.
///
/// Adapted from AnymeX's `detailsPrimaryQuery`, with three deliberate changes:
///
/// 1. **One query, not two.** AnymeX splits into a primary and a secondary
///    request, then `mergeSecondaryData` drops `externalLinks` and `favourites`
///    on the floor — fetched and discarded. Both are rendered here, so both are
///    asked for once.
/// 2. **Anime-only fields are gone**: `episodes`, `season`, `seasonYear`,
///    `duration`, `nextAiringEpisode`, and `voiceActors` (a manga character has
///    none). Asking for fields nothing renders is how the split above went
///    unnoticed.
/// 3. **`type: MANGA`** on the search, so a title shared with an anime cannot
///    resolve to the anime.
class AniListQueries {
  const AniListQueries._();

  static const endpoint = 'https://graphql.anilist.co';

  /// Everything the details Overview tab renders, in one round trip.
  static const media = r'''
query ($id: Int) {
  Media(id: $id, type: MANGA) {
    id
    idMal
    isAdult
    title { userPreferred romaji english native }
    synonyms
    description(asHtml: false)
    coverImage { color extraLarge large }
    bannerImage
    averageScore
    meanScore
    popularity
    favourites
    status
    chapters
    volumes
    format
    countryOfOrigin
    source
    startDate { year month day }
    endDate { year month day }
    genres
    tags { name rank isMediaSpoiler isGeneralSpoiler }
    stats {
      scoreDistribution { score amount }
      statusDistribution { status amount }
    }
    characters(sort: [ROLE, FAVOURITES_DESC], perPage: 25, page: 1) {
      edges {
        role
        node { id name { full } image { large } favourites }
      }
    }
    staff(sort: [RELEVANCE, ID], perPage: 25, page: 1) {
      edges {
        role
        node { id name { full userPreferred } image { large } }
      }
    }
    relations {
      edges {
        relationType
        node {
          id
          type
          format
          status
          averageScore
          title { userPreferred romaji english }
          coverImage { large }
        }
      }
    }
    recommendations(sort: RATING_DESC, perPage: 20) {
      edges {
        node {
          rating
          mediaRecommendation {
            id
            type
            format
            averageScore
            title { userPreferred romaji english }
            coverImage { large }
          }
        }
      }
    }
    externalLinks { url site type }
  }
}
''';

  /// Resolves a source's title to AniList media, for auto-matching.
  ///
  /// `type: MANGA` matters: a great many titles name both a manga and its anime
  /// adaptation, and the anime is often the more popular hit.
  static const search = r'''
query ($search: String, $perPage: Int) {
  Page(page: 1, perPage: $perPage) {
    media(search: $search, type: MANGA, sort: SEARCH_MATCH) {
      id
      format
      status
      averageScore
      popularity
      startDate { year }
      title { userPreferred romaji english native }
      synonyms
      coverImage { large }
    }
  }
}
''';
}
