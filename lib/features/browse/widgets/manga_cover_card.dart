import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/source/http/m_client.dart';
import 'package:otaku_reader/source/model/m_manga.dart';

/// One cover in the browse grid.
class MangaCoverCard extends StatelessWidget {
  const MangaCoverCard({
    super.key,
    required this.manga,
    required this.sourceBaseUrl,
    this.onTap,
  });

  final MManga manga;

  /// Needed for the cover request, not for display: hotlink-protected CDNs
  /// answer a bare GET with 403, and the fix is a Referer and Origin derived
  /// from the source's base URL.
  final String sourceBaseUrl;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AspectRatio is the direct child, not wrapped in Expanded: Expanded
          // forces its child to fill the leftover grid height, which overrides
          // the ratio and stretches every cover vertically.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: _Cover(url: manga.imageUrl, sourceBaseUrl: sourceBaseUrl),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            manga.name ?? 'Untitled',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.2),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({this.url, required this.sourceBaseUrl});

  final String? url;
  final String sourceBaseUrl;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return const _CoverFallback();
    return CachedNetworkImage(
      imageUrl: url!,
      httpHeaders: MClient.pageImageHeaders(null, sourceBaseUrl),
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, _) => const _CoverFallback(),
      // A missing cover is ordinary — image hosts in this ecosystem go stale
      // faster than the scripts do — so it must not read as an error.
      errorWidget: (_, _, _) => const _CoverFallback(),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Iconsax.image, color: scheme.onSurfaceVariant, size: 22),
      ),
    );
  }
}
