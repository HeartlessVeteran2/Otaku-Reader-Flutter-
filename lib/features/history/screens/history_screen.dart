import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/domain/repository/library_repository.dart';
import 'package:otaku_reader/domain/repository/source_repository.dart';
import 'package:otaku_reader/features/history/controllers/history_controller.dart';
import 'package:otaku_reader/features/reader/screens/reader_screen.dart';
import 'package:otaku_reader/source/http/m_client.dart';

/// What was read, newest first, with swipe-to-remove and an undo.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const _tag = 'history';

  late final HistoryController _c = Get.put(
    HistoryController(
      library: Get.find<LibraryRepository>(),
      sources: Get.find<SourceRepository>(),
    ),
    tag: _tag,
  );

  @override
  void dispose() {
    Get.delete<HistoryController>(tag: _tag);
    super.dispose();
  }

  void _remove(List<HistoryEntry> rows) {
    _c.remove(rows);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: HistoryController.undoWindow,
        content: Text(
          rows.length == 1
              ? 'Removed from history'
              : '${rows.length} removed from history',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // A snackbar can outlive its batch — the window closes on a timer
            // and the action stays tappable until the bar is dismissed. The
            // controller decides whether there is still anything to undo.
            if (!_c.undo() && mounted) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Too late to undo that one')),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This forgets when you read things. Which chapters are marked read '
          'is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok ?? false) await _c.clearAll();
  }

  @override
  Widget build(BuildContext context) {
    return ChromeScaffold.slivers(
      title: 'History',
      // The search field used to sit permanently under the title, costing 56px
      // on every screenful whether or not anyone was searching. The header
      // swaps its split row for a search row instead -- AnymeX's shape, and
      // the thing that buys back the height the old collapsing header spent.
      enableSearch: true,
      searchHint: 'Search history',
      // No `onSearchClear`: the header already calls `onSearchChanged('')`
      // when search closes, precisely so a filter cannot stay in force with
      // nothing on screen naming it. Passing both would call `setQuery('')`
      // twice under a comment claiming the second call was load-bearing.
      onSearchChanged: _c.setQuery,
      actions: [
        Obx(
          () => IconButton(
            icon: const Icon(Iconsax.trash),
            tooltip: 'Clear history',
            onPressed: _c.entries.isEmpty ? null : _confirmClear,
          ),
        ),
      ],
      slivers: [
        // One `Obx`, and every branch returns a sliver — the loading spinner
        // and the empty state are `SliverFillRemaining`, not bare widgets.
        Obx(() {
          if (_c.isLoading.value && _c.entries.isEmpty) {
            return const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final rows = _c.visible;
          if (rows.isEmpty) {
            return SliverFillRemaining(
              hasScrollBody: false,
              child: _Empty(searching: _c.query.value.isNotEmpty),
            );
          }
          return SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => Dismissible(
              key: ValueKey(rows[i].key),
              background: const _SwipeBackground(),
              secondaryBackground: const _SwipeBackground(trailing: true),
              onDismissed: (_) => _remove([rows[i]]),
              child: _HistoryTile(
                row: rows[i],
                baseUrl: _c.baseUrlFor(rows[i].entry),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.row, required this.baseUrl});

  final HistoryEntry row;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final cover = row.entry.displayCover;
    final number = row.chapter.formattedNumber;
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
                  httpHeaders: MClient.pageImageHeaders(null, baseUrl),
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const _CoverFallback(),
                  placeholder: (_, _) => const _CoverFallback(),
                ),
        ),
      ),
      title: Text(
        row.entry.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${number.isEmpty ? (row.chapter.name ?? 'Chapter') : 'Chapter $number'}'
        ' · ${_when(row.readAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        final sourceId = LibraryRepository.sourceIdOf(row.entry);
        final chapterUrl = row.chapter.url;
        if (sourceId == null || chapterUrl == null) return;
        // Straight back into the chapter, at the stored position — resuming is
        // the only reason to tap a history row.
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(
              sourceId: sourceId,
              mangaUrl: row.entry.url,
              chapterUrl: chapterUrl,
            ),
          ),
        );
      },
    );
  }

  static String _when(DateTime at) {
    final difference = DateTime.now().difference(at);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes} min ago';
    if (difference.inDays < 1) return '${difference.inHours} h ago';
    if (difference.inDays < 7) return '${difference.inDays} d ago';
    return '${at.year}-${_two(at.month)}-${_two(at.day)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({this.trailing = false});

  final bool trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.errorContainer,
      alignment: trailing ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(Iconsax.trash, color: scheme.onErrorContainer),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

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
              Iconsax.clock,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              searching
                  ? 'Nothing in your history matches that.'
                  : 'Nothing read yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
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
        child: Icon(Iconsax.book, color: scheme.onSurfaceVariant, size: 16),
      ),
    );
  }
}
