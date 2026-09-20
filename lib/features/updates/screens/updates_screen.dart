import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/features/reader/screens/reader_screen.dart';
import 'package:otaku_reader/features/updates/controllers/updates_controller.dart';
import 'package:otaku_reader/source/http/m_client.dart';
import 'package:otaku_reader/core/ui/greeting_text.dart';
import 'package:otaku_reader/features/settings/widgets/profile_avatar.dart';

/// New chapters, newest first, grouped by the day they were found.
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  UpdatesController get _c => Get.find<UpdatesController>();

  @override
  Widget build(BuildContext context) {
    return ChromeScaffold.slivers(
      title: 'Updates',
      // The account leads the header, and the greeting sits under the
      // title -- AnymeX's shape for a tab root. Both degrade on their
      // own: the avatar has a state for every answer `AniListAuth` can
      // give, and the leading is dropped entirely on a route that can
      // pop, where the back button needs that slot.
      leading: const ProfileAvatar(),
      subtitleWidget: const GreetingText(),
      onRefresh: _c.refreshLibrary,
      actions: [
        Obx(
          () => IconButton(
            icon: const Icon(Iconsax.tick_circle),
            tooltip: 'Mark all read',
            onPressed: _c.updates.every((u) => u.chapter.read)
                ? null
                : _c.markAllRead,
          ),
        ),
        Obx(
          () => IconButton(
            icon: const Icon(Iconsax.refresh),
            tooltip: 'Check for new chapters',
            onPressed: _c.isRefreshing.value ? null : _c.refreshLibrary,
          ),
        ),
      ],
      slivers: [
        // One `Obx` over the whole body, every branch a sliver. The refresh
        // progress and the error list are box widgets, so they are adapted
        // explicitly rather than handed to the sliver slot raw.
        Obx(() {
          if (_c.isLoading.value && _c.updates.isEmpty) {
            return const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return SliverMainAxisGroup(
            slivers: [
              if (_c.isRefreshing.value)
                SliverToBoxAdapter(
                  child: _Progress(done: _c.done.value, total: _c.total.value),
                ),
              if (_c.errors.isNotEmpty)
                SliverToBoxAdapter(child: _Errors(errors: _c.errors)),
              if (_c.updates.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _Empty(lastChecked: _c.lastChecked.value),
                )
              else
                ..._grouped(context),
            ],
          );
        }),
      ],
    );
  }

  List<Widget> _grouped(BuildContext context) {
    final groups = <DateTime, List<ChapterUpdate>>{};
    for (final update in _c.updates) {
      final at = update.fetchedAt;
      final day = DateTime(at.year, at.month, at.day);
      groups.putIfAbsent(day, () => []).add(update);
    }
    return [
      for (final entry in groups.entries) ...[
        SliverToBoxAdapter(child: _DayHeader(day: entry.key)),
        SliverList.builder(
          itemCount: entry.value.length,
          itemBuilder: (context, i) => _UpdateTile(update: entry.value[i]),
        ),
      ],
    ];
  }
}

class _UpdateTile extends StatelessWidget {
  const _UpdateTile({required this.update});

  final ChapterUpdate update;

  UpdatesController get _c => Get.find<UpdatesController>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final read = update.chapter.read;
    final cover = update.entry.displayCover;
    final number = update.chapter.formattedNumber;
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: cover == null || cover.isEmpty
              ? const _CoverFallback()
              : CachedNetworkImage(
                  imageUrl: cover,
                  // A library cover is as hotlink-protected as any other, and a
                  // list of grey boxes looks like the app lost them.
                  httpHeaders: MClient.pageImageHeaders(
                    null,
                    _c.baseUrlFor(update.entry),
                  ),
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const _CoverFallback(),
                  placeholder: (_, _) => const _CoverFallback(),
                ),
        ),
      ),
      title: Text(
        update.entry.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          // Read updates stay in the list rather than disappearing, so the tab
          // is a record of what arrived and not only of what is outstanding.
          color: read ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: Text(
        number.isEmpty
            ? (update.chapter.name ?? 'New chapter')
            : 'Chapter $number',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: read ? 'Mark unread' : 'Mark read',
        icon: Icon(
          read ? Iconsax.tick_circle : Iconsax.record_circle,
          size: 20,
          color: read ? theme.colorScheme.primary : null,
        ),
        onPressed: () => _c.markRead(update, !read),
      ),
      onTap: () {
        final sourceId = LibraryRepository.sourceIdOf(update.entry);
        final chapterUrl = update.chapter.url;
        if (sourceId == null || chapterUrl == null) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(
              sourceId: sourceId,
              mangaUrl: update.entry.url,
              chapterUrl: chapterUrl,
            ),
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(day).inDays;
    final label = switch (difference) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => '${day.year}-${_two(day.month)}-${_two(day.day)}',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _Progress extends StatelessWidget {
  const _Progress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Checking $done of $total', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: total == 0 ? null : done / total),
      ],
    ),
  );
}

class _Errors extends StatelessWidget {
  const _Errors({required this.errors});

  final List<UpdateError> errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        color: theme.colorScheme.errorContainer,
        child: ExpansionTile(
          shape: const Border(),
          leading: Icon(
            Iconsax.warning_2,
            color: theme.colorScheme.onErrorContainer,
          ),
          title: Text(
            errors.length == 1
                ? '1 series could not be checked'
                : '${errors.length} series could not be checked',
            style: TextStyle(
              color: theme.colorScheme.onErrorContainer,
              fontSize: 14,
            ),
          ),
          children: [
            for (final error in errors)
              ListTile(
                dense: true,
                title: Text(
                  error.entry.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(error.message, maxLines: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.lastChecked});

  final DateTime? lastChecked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Iconsax.refresh,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No new chapters yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              // Says plainly that a first fetch is not an update, because
              // otherwise an empty tab right after adding a series reads as a
              // bug rather than as the rule.
              lastChecked == null
                  ? 'Pull down to check your library. Chapters already there '
                        'when you added a series are not counted as updates.'
                  : 'Last checked ${_ago(lastChecked!)}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime at) {
    final difference = DateTime.now().difference(at);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes} min ago';
    if (difference.inDays < 1) return '${difference.inHours} h ago';
    return '${difference.inDays} d ago';
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
        child: Icon(Iconsax.book, color: scheme.onSurfaceVariant, size: 16),
      ),
    );
  }
}
