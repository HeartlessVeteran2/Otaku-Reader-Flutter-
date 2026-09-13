import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/domain/model/anilist_media.dart';

/// The AniList stats strip: score, popularity, favourites.
class AniListStats extends StatelessWidget {
  const AniListStats({super.key, required this.media});

  final AniListMedia media;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      if (media.averageScore != null)
        (Iconsax.star1, '${media.averageScore}%', 'Average'),
      if (media.meanScore != null && media.meanScore != media.averageScore)
        (Iconsax.chart_2, '${media.meanScore}%', 'Mean'),
      if (media.popularity != null)
        (Iconsax.people, _compact(media.popularity!), 'Popularity'),
      if (media.favourites != null)
        (Iconsax.heart, _compact(media.favourites!), 'Favourites'),
      if (media.chapters != null)
        (Iconsax.book, '${media.chapters}', 'Chapters'),
      if (media.volumes != null)
        (Iconsax.book_1, '${media.volumes}', 'Volumes'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (icon, value, label) in items)
            Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(height: 4),
                  Text(value, style: theme.textTheme.titleSmall),
                  Text(label, style: theme.textTheme.labelSmall),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 12400 → "12.4k". A raw popularity count is noise at full precision.
  static String _compact(int value) {
    if (value < 1000) return '$value';
    if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}k';
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
}

/// Community-ranked tags, rendered as "Isekai 87%".
///
/// The rank is the point: an unranked tag list is indistinguishable from
/// genres, while the percentage says how strongly the community associates it.
class AniListTags extends StatelessWidget {
  const AniListTags({super.key, required this.media, this.onTap});

  final AniListMedia media;
  final void Function(String tag)? onTap;

  @override
  Widget build(BuildContext context) {
    final tags = media.safeTags;
    if (tags.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tag in tags.take(20))
            ActionChip(
              onPressed: onTap == null ? null : () => onTap!(tag.name),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              label: Text(
                '${tag.name} ${tag.rank}%',
                style: theme.textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Characters or staff. One widget, because they render identically.
class PersonCarousel extends StatelessWidget {
  const PersonCarousel({
    super.key,
    required this.title,
    required this.people,
    required this.prettifyRole,
  });

  final String title;
  final List<AniListPerson> people;

  /// A character's role is an AniList enum (`MAIN`) wanting prettifying; a
  /// staff member's is free text kept verbatim ("Story & Art"). The caller
  /// decides, because normalising on the way in would make a staff credit
  /// reading "Main" indistinguishable from the enum.
  final bool prettifyRole;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: title,
      child: SizedBox(
        height: 168,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: people.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final person = people[i];
            return SizedBox(
              width: 84,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: _Portrait(url: person.imageUrl),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    person.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (person.role != null)
                    Text(
                      prettifyRole ? _pretty(person.role!) : person.role!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: Theme.of(context).disabledColor),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// `SUPPORTING` → `Supporting`.
  static String _pretty(String role) {
    final lower = role.toLowerCase().replaceAll('_', ' ');
    return lower.isEmpty ? lower : lower[0].toUpperCase() + lower.substring(1);
  }
}

/// Relations and recommendations, which render the same way.
class MediaCarousel extends StatelessWidget {
  const MediaCarousel({
    super.key,
    required this.title,
    required this.items,
    this.onTap,
  });

  final String title;
  final List<({int id, String title, String? coverUrl, String? subtitle})>
  items;
  final void Function(String title)? onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: title,
      child: SizedBox(
        height: 200,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) {
            final item = items[i];
            return SizedBox(
              width: 104,
              child: InkWell(
                // A relation is an AniList media id with no local record, so
                // tapping searches sources for the title rather than opening
                // something that does not exist here.
                onTap: onTap == null ? null : () => onTap!(item.title),
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: _Portrait(url: item.coverUrl),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: Theme.of(context).disabledColor),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Alternative titles, which are genuinely useful for finding the same manga on
/// another source.
class AlternativeTitles extends StatelessWidget {
  const AlternativeTitles({super.key, required this.media});

  final AniListMedia media;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (media.titles.romaji != null) ('Romaji', media.titles.romaji!),
      if (media.titles.english != null) ('English', media.titles.english!),
      if (media.titles.native != null) ('Native', media.titles.native!),
      if (media.titles.synonyms.isNotEmpty)
        ('Synonyms', media.titles.synonyms.join(' · ')),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return _Section(
      title: 'Alternative titles',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(label, style: theme.textTheme.labelSmall),
                    ),
                    Expanded(
                      child: Text(value, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ExternalLinkChips extends StatelessWidget {
  const ExternalLinkChips({
    super.key,
    required this.links,
    required this.onOpen,
  });

  final List<AniListLink> links;
  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: 'Links',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final link in links)
              ActionChip(
                // Filtered to http(s) at the mapper *and* here: a payload
                // cached by an older build never passed through today's mapper.
                onPressed: _isWeb(link.url) ? () => onOpen(link.url) : null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(
                  link.site.isEmpty ? link.url : link.site,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _isWeb(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      const SizedBox(height: 10),
      child,
    ],
  );
}

class _Portrait extends StatelessWidget {
  const _Portrait({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Iconsax.user, size: 18, color: scheme.onSurfaceVariant),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      placeholder: (_, _) => fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}
