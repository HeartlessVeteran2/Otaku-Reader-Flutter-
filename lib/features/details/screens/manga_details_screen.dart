import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/details/controllers/manga_details_controller.dart';
import 'package:otaku_reader/features/reader/screens/reader_screen.dart';
import 'package:otaku_reader/source/http/m_client.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_status.dart';

class MangaDetailsScreen extends StatefulWidget {
  const MangaDetailsScreen({
    super.key,
    required this.sourceId,
    required this.url,
    this.initial,
  });

  final int sourceId;
  final String url;
  final MManga? initial;

  @override
  State<MangaDetailsScreen> createState() => _MangaDetailsScreenState();
}

class _MangaDetailsScreenState extends State<MangaDetailsScreen> {
  late final String _tag = 'details-${widget.sourceId}-${widget.url}';
  late final MangaDetailsController _c = Get.put(
    MangaDetailsController(
      sources: Get.find<SourceRepository>(),
      library: Get.find<LibraryRepository>(),
      sourceId: widget.sourceId,
      url: widget.url,
      initial: widget.initial,
    ),
    tag: _tag,
  );

  @override
  void dispose() {
    Get.delete<MangaDetailsController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Obx(() {
        final error = _c.error.value;
        if (error != null) return _Error(message: error, onRetry: _c.load);

        final entry = _c.entry.value;
        final title = entry?.displayTitle ?? _c.preview?.name ?? '';
        final cover = entry?.displayCover ?? _c.preview?.imageUrl;

        return RefreshIndicator(
          onRefresh: _c.load,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                  background: _Header(
                    cover: cover,
                    baseUrl: _c.sourceBaseUrl.value,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _Meta(
                  entry: entry,
                  isLoading: _c.isLoading.value,
                  isFavorite: _c.isFavorite,
                  onToggleFavorite: entry == null ? null : _c.toggleFavorite,
                ),
              ),
              SliverToBoxAdapter(
                child: _ChapterHeader(
                  count: _c.chapters.length,
                  unread: _c.unreadCount,
                  descending: _c.descending.value,
                  filter: _c.filter.value,
                  onToggleSort: _c.toggleSort,
                  onFilter: _c.setFilter,
                ),
              ),
              if (_c.isLoading.value && (entry?.chapters.isEmpty ?? true))
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: _c.chapters.length,
                  itemBuilder: (context, i) {
                    final chapter = _c.chapters[i];
                    return _ChapterTile(
                      chapter: chapter,
                      // Tapping a chapter reads it. The read/unread toggle is
                      // the trailing icon: a list where tapping a row marks it
                      // read instead of opening it is the wrong default for a
                      // reader.
                      onOpen: chapter.url == null
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ReaderScreen(
                                    sourceId: widget.sourceId,
                                    mangaUrl: widget.url,
                                    chapterUrl: chapter.url!,
                                  ),
                                ),
                              );
                              // Progress is written by the reader, so the list
                              // has to re-read it on the way back.
                              await _c.refreshEntry();
                            },
                      onToggleRead: () => _c.setRead(chapter, !chapter.read),
                      onMarkUpTo: () => _c.markReadUpTo(chapter),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        );
      }),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.cover, required this.baseUrl});

  final String? cover;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null && cover!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: cover!,
            httpHeaders: MClient.pageImageHeaders(null, baseUrl),
            fit: BoxFit.cover,
            errorWidget: (_, _, _) =>
                ColoredBox(color: scheme.surfaceContainerHighest),
          )
        else
          ColoredBox(color: scheme.surfaceContainerHighest),
        // The title sits on top of the cover, so it needs a scrim to stay
        // legible over a light one.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
        ),
      ],
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.entry,
    required this.isLoading,
    required this.isFavorite,
    this.onToggleFavorite,
  });

  final MangaEntry? entry;
  final bool isLoading;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = entry == null
        ? null
        : Status.values[entry!.status.clamp(0, Status.values.length - 1)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: onToggleFavorite,
                icon: Icon(isFavorite ? Iconsax.heart5 : Iconsax.heart),
                label: Text(isFavorite ? 'In library' : 'Add to library'),
              ),
              const Spacer(),
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (entry?.author?.isNotEmpty ?? false)
            Text(entry!.author!, style: theme.textTheme.bodyMedium),
          if ((entry?.artist?.isNotEmpty ?? false) &&
              entry!.artist != entry!.author)
            Text(entry!.artist!, style: theme.textTheme.bodySmall),
          if (status != null && status != Status.unknown)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _statusLabel(status),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (entry?.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            _Description(text: entry!.description!),
          ],
          if (entry?.genres.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final genre in entry!.genres)
                  Chip(
                    label: Text(genre, style: theme.textTheme.labelSmall),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(Status status) => switch (status) {
    Status.ongoing => 'Ongoing',
    Status.completed => 'Completed',
    Status.canceled => 'Cancelled',
    Status.onHiatus => 'On hiatus',
    Status.publishingFinished => 'Publishing finished',
    Status.unknown => '',
  };
}

class _Description extends StatefulWidget {
  const _Description({required this.text});

  final String text;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _expanded = !_expanded),
    child: AnimatedSize(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.topCenter,
      child: Text(
        widget.text,
        maxLines: _expanded ? null : 4,
        overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({
    required this.count,
    required this.unread,
    required this.descending,
    required this.filter,
    required this.onToggleSort,
    required this.onFilter,
  });

  final int count;
  final int unread;
  final bool descending;
  final ChapterFilter filter;
  final VoidCallback onToggleSort;
  final ValueChanged<ChapterFilter> onFilter;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
    child: Row(
      children: [
        Text(
          '$count chapters'
          '${unread > 0 ? ' · $unread unread' : ''}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const Spacer(),
        IconButton(
          tooltip: filter == ChapterFilter.unread
              ? 'Showing unread only'
              : 'Showing all',
          icon: Icon(
            filter == ChapterFilter.unread ? Iconsax.filter5 : Iconsax.filter,
          ),
          onPressed: () => onFilter(
            filter == ChapterFilter.unread
                ? ChapterFilter.all
                : ChapterFilter.unread,
          ),
        ),
        IconButton(
          tooltip: descending ? 'Newest first' : 'Oldest first',
          icon: Icon(descending ? Iconsax.arrow_down : Iconsax.arrow_up_2),
          onPressed: onToggleSort,
        ),
      ],
    ),
  );
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({
    required this.chapter,
    required this.onToggleRead,
    required this.onMarkUpTo,
    this.onOpen,
  });

  final Chapter chapter;
  final VoidCallback onToggleRead;
  final VoidCallback onMarkUpTo;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final read = chapter.read;
    return ListTile(
      dense: true,
      onTap: onOpen,
      onLongPress: onMarkUpTo,
      title: Text(
        chapter.name ?? 'Chapter ${chapter.formattedNumber}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: read ? theme.disabledColor : null,
        ),
      ),
      subtitle: chapter.scanlator?.isNotEmpty ?? false
          ? Text(chapter.scanlator!, style: theme.textTheme.bodySmall)
          : null,
      trailing: IconButton(
        tooltip: read ? 'Mark unread' : 'Mark read',
        onPressed: onToggleRead,
        icon: Icon(
          read ? Iconsax.tick_circle : Iconsax.record_circle,
          size: 18,
          color: read ? theme.colorScheme.primary : theme.disabledColor,
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Iconsax.cloud_cross,
              size: 40,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}
