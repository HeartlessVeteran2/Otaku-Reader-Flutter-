import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/theme/one_ui.dart';
import 'package:otaku_reader/data/isar/manga_entry.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/data/anilist/anilist_list_service.dart';
import 'package:otaku_reader/data/anilist/anilist_metadata_service.dart';
import 'package:otaku_reader/features/details/controllers/manga_details_controller.dart';
import 'package:otaku_reader/features/details/widgets/anilist_edit_sheet.dart';
import 'package:otaku_reader/features/details/widgets/anilist_sections.dart';
import 'package:otaku_reader/features/reader/screens/reader_screen.dart';
import 'package:otaku_reader/source/http/m_client.dart';
import 'package:otaku_reader/source/model/m_manga.dart';
import 'package:otaku_reader/source/model/m_status.dart';
import 'package:otaku_reader/core/util/open_link.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';

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
      anilist: Get.find<AniListMetadataService>(),
      anilistList: Get.find<AniListListService>(),
      downloads: Get.find<DownloadRepository>(),
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
              SliverToBoxAdapter(child: _AniList(controller: _c)),
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
                    // Its own Obx: `itemBuilder` runs during layout, after the
                    // enclosing Obx's build closure has finished, so a read of
                    // `downloadTasks` in here would register no dependency and
                    // the row would never show a download progressing.
                    return Obx(
                      () => _ChapterTile(
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
                        download: _c.downloadFor(chapter),
                        onDownload: () => _c.download(chapter),
                        onDeleteDownload: () => _c.deleteDownload(chapter),
                      ),
                    );
                  },
                ),
              // Clears the gesture bar, the same way `OneUiScaffold` does — the
              // last chapter row must not be what a back-swipe grabs.
              const SliverToBoxAdapter(
                child: SizedBox(height: OneUi.sectionGap * 2),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Everything AniList contributes, or nothing at all.
///
/// Opens the list sheet and writes whatever came back.
///
/// The snackbar is not optional. A write that fails silently leaves the row
/// showing the old values with no hint that AniList refused, and the user's
/// next move would be to change it again and wonder why nothing sticks.
Future<void> _editAniList(
  BuildContext context,
  MangaDetailsController controller,
  int? totalChapters,
) async {
  final edit = await showAniListEditSheet(
    context,
    result: controller.anilistList.value,
    scoreFormat: controller.anilistScoreFormat,
    totalChapters: totalChapters,
  );
  if (edit == null || edit.isEmpty || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  final result = await controller.saveAniList(
    status: edit.status,
    progress: edit.progress,
    score: edit.score,
  );
  // `busy` says nothing, deliberately. The write already in flight will
  // report its own outcome, and this one was never offered to AniList — so
  // there is nothing true to say about it that the other snackbar will not
  // say a moment later.
  if (result == AniListSaveResult.busy) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result == AniListSaveResult.ok
            ? 'Saved to AniList'
            : 'AniList did not save that. Your list is unchanged.',
      ),
    ),
  );
}

/// Rendering nothing is the correct outcome for an unmatched title, not a
/// failure state: below the confidence threshold no match is stored, because a
/// wrong synopsis and wrong tags look exactly as authoritative as right ones.
class _AniList extends StatelessWidget {
  const _AniList({required this.controller});

  final MangaDetailsController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final media = controller.anilist.value;
    if (media == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // First, because it is the only line on this page about *this reader*
        // rather than about the series. Renders nothing when there is no row,
        // so the spacing below is unchanged for everyone signed out.
        AniListListRow(
          result: controller.anilistList.value,
          totalChapters: media.chapters,
          isSaving: controller.isSavingAniList.value,
          // Null while a write is in flight, so the row cannot open a second
          // sheet over the first. The controller refuses the concurrent write
          // anyway — this stops the user reaching a refusal they would have
          // no way to understand.
          onEdit: controller.isSavingAniList.value
              ? null
              : () => _editAniList(context, controller, media.chapters),
        ),
        const SizedBox(height: 20),
        AniListStats(media: media),
        const SizedBox(height: 16),
        AniListTags(media: media),
        PersonCarousel(
          title: 'Characters',
          people: media.characters,
          prettifyRole: true,
        ),
        PersonCarousel(
          title: 'Staff',
          people: media.staff,
          // Staff roles are free text ("Story & Art"); prettifying would make a
          // credit reading "Main" indistinguishable from the character enum.
          prettifyRole: false,
        ),
        MediaCarousel(
          title: 'Related',
          items: [
            for (final r in media.mangaRelations)
              (
                id: r.id,
                title: r.title,
                coverUrl: r.coverUrl,
                subtitle: r.relationType?.toLowerCase().replaceAll('_', ' '),
              ),
          ],
        ),
        MediaCarousel(
          title: 'Recommended',
          items: [
            for (final r in media.mangaRecommendations)
              (
                id: r.id,
                title: r.title,
                coverUrl: r.coverUrl,
                subtitle: r.averageScore == null ? null : '${r.averageScore}%',
              ),
          ],
        ),
        AlternativeTitles(media: media),
        ExternalLinkChips(
          links: media.externalLinks,
          onOpen: (url) => openLink(context, url),
        ),
      ],
    );
  });
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
      padding: const EdgeInsets.fromLTRB(OneUi.gutter, 12, OneUi.gutter, 0),
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
    padding: const EdgeInsets.fromLTRB(OneUi.gutter, OneUi.sectionGap, 8, 4),
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
    required this.download,
    required this.onDownload,
    required this.onDeleteDownload,
    this.onOpen,
  });

  final Chapter chapter;
  final VoidCallback onToggleRead;
  final VoidCallback onMarkUpTo;

  /// This chapter's queue entry, or null if it has none.
  final DownloadTask? download;

  final VoidCallback onDownload;
  final VoidCallback onDeleteDownload;
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DownloadButton(
            downloaded: chapter.localPath != null,
            task: download,
            onDownload: onDownload,
            onDelete: onDeleteDownload,
          ),
          IconButton(
            tooltip: read ? 'Mark unread' : 'Mark read',
            onPressed: onToggleRead,
            icon: Icon(
              read ? Iconsax.tick_circle : Iconsax.record_circle,
              size: 18,
              color: read ? theme.colorScheme.primary : theme.disabledColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// One chapter's download control: start, progress, or delete.
///
/// Every state occupies the same 40dp box, so a row does not shift sideways
/// the moment a download starts — the same reason the extensions list pins its
/// action width.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.downloaded,
    required this.task,
    required this.onDownload,
    required this.onDelete,
  });

  final bool downloaded;
  final DownloadTask? task;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = task?.state;

    Widget content;
    if (downloaded) {
      content = IconButton(
        tooltip: 'Delete download',
        onPressed: onDelete,
        icon: Icon(
          Iconsax.tick_square,
          size: 18,
          color: theme.colorScheme.primary,
        ),
      );
    } else if (state == DownloadState.queued ||
        state == DownloadState.running) {
      content = Center(
        child: SizedBox(
          width: 18,
          height: 18,
          // Indeterminate until the page count is known — a bar that sits at
          // zero looks stuck, and the page list is a network call of its own.
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: task?.progress,
          ),
        ),
      );
    } else if (state == DownloadState.failed) {
      content = IconButton(
        tooltip: task?.error ?? 'Download failed — tap to retry',
        onPressed: onDownload,
        icon: Icon(Iconsax.warning_2, size: 18, color: theme.colorScheme.error),
      );
    } else {
      content = IconButton(
        tooltip: 'Download',
        onPressed: onDownload,
        icon: Icon(Iconsax.arrow_down_2, size: 18, color: theme.disabledColor),
      );
    }
    return SizedBox(width: 40, height: 40, child: content);
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
