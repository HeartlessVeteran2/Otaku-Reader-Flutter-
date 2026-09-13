import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/source/http/m_client.dart';

/// One library entry: cover, title, and an unread badge.
class LibraryCard extends StatelessWidget {
  const LibraryCard({
    super.key,
    required this.entry,
    required this.unread,
    this.sourceBaseUrl = '',
    this.onTap,
  });

  final MangaEntry entry;
  final int unread;

  /// For the cover request, not for display: hotlink-protected hosts answer a
  /// bare GET with 403, and a library full of fallback covers looks like the
  /// app lost them.
  final String sourceBaseUrl;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = entry.displayCover;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null && cover.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: cover,
                      httpHeaders: MClient.pageImageHeaders(
                        null,
                        sourceBaseUrl,
                      ),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const _Fallback(),
                      placeholder: (_, _) => const _Fallback(),
                    )
                  else
                    const _Fallback(),
                  if (unread > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$unread',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.2),
          ),
        ],
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Iconsax.book, color: scheme.onSurfaceVariant, size: 22),
      ),
    );
  }
}
