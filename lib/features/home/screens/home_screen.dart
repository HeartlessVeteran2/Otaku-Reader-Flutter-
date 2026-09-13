import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/data/repository/library_repository_impl.dart';
import 'package:otaku_reader/domain/model/anilist_media.dart';
import 'package:otaku_reader/features/details/screens/manga_details_screen.dart';
import 'package:otaku_reader/features/home/controllers/home_controller.dart';
import 'package:otaku_reader/features/reader/screens/reader_screen.dart';
import 'package:otaku_reader/features/search/screens/global_search_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  HomeController get _c => Get.find<HomeController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.search_normal),
            tooltip: 'Search all sources',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const GlobalSearchScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (_c.isLoading.value &&
            _c.shelves.isEmpty &&
            _c.continueReading.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = _c.error.value;
        return RefreshIndicator(
          onRefresh: _c.load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              // The banner sits above the content rather than replacing it:
              // Continue Reading is local and still works when AniList does not.
              if (error != null) _Banner(message: error, onRetry: _c.load),
              if (_c.continueReading.isNotEmpty)
                _ContinueReading(entries: _c.continueReading),
              for (final shelf in _c.shelves)
                _Shelf(title: shelf.title, items: shelf.items),
              if (_c.continueReading.isEmpty && _c.shelves.isEmpty)
                const _Empty(),
              const SizedBox(height: 24),
            ],
          ),
        );
      }),
    );
  }
}

class _ContinueReading extends StatelessWidget {
  const _ContinueReading({required this.entries});

  final List<MangaEntry> entries;

  @override
  Widget build(BuildContext context) => _SectionFrame(
    title: 'Continue reading',
    height: 214,
    itemCount: entries.length,
    itemBuilder: (context, i) {
      final entry = entries[i];
      final next = HomeController.nextChapter(entry);
      final sourceId = LibraryRepositoryImpl.sourceIdFrom(entry.sourceId);
      return _Tile(
        title: entry.displayTitle,
        coverUrl: entry.displayCover,
        // Names the chapter it will open, so the tap is predictable rather
        // than "somewhere in this manga".
        subtitle: next == null
            ? null
            : 'Ch. ${next.formattedNumber.isEmpty ? '?' : next.formattedNumber}',
        badge: '${HomeController.unreadOf(entry)}',
        onTap: sourceId == null
            ? null
            : () {
                final chapterUrl = next?.url;
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    // Straight into the reader when there is an unread
                    // chapter — that is what "continue" means. Otherwise the
                    // details page, which is the only sensible fallback.
                    builder: (_) => chapterUrl == null
                        ? MangaDetailsScreen(sourceId: sourceId, url: entry.url)
                        : ReaderScreen(
                            sourceId: sourceId,
                            mangaUrl: entry.url,
                            chapterUrl: chapterUrl,
                          ),
                  ),
                );
              },
      );
    },
  );
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.title, required this.items});

  final String title;
  final List<AniListMedia> items;

  @override
  Widget build(BuildContext context) => _SectionFrame(
    title: title,
    height: 214,
    itemCount: items.length,
    itemBuilder: (context, i) {
      final media = items[i];
      return _Tile(
        title: media.titles.display,
        coverUrl: media.coverUrl,
        subtitle: media.averageScore == null ? null : '${media.averageScore}%',
        // An AniList entry is not a local manga: there is no source, no url and
        // no chapters behind it. Tapping searches the installed sources for the
        // title, which is the only thing that can actually be done with it.
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                GlobalSearchScreen(initialQuery: media.titles.display),
          ),
        ),
      );
    },
  );
}

class _SectionFrame extends StatelessWidget {
  const _SectionFrame({
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String title;
  final double height;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: itemBuilder,
        ),
      ),
    ],
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    this.coverUrl,
    this.subtitle,
    this.badge,
    this.onTap,
  });

  final String title;
  final String? coverUrl;
  final String? subtitle;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 112,
      child: InkWell(
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
                    _Cover(url: coverUrl),
                    if (badge != null)
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
                            badge!,
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
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(height: 1.2),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.disabledColor,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Iconsax.book, size: 20, color: scheme.onSurfaceVariant),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: InkWell(
        onTap: onRetry,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Iconsax.warning_2, size: 16, color: scheme.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                'Retry',
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 120, 32, 32),
    child: Column(
      children: [
        Icon(Iconsax.home, size: 40, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Text(
          'Nothing to show yet.\nInstall a source from Browse and add a manga '
          'to your library.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}
