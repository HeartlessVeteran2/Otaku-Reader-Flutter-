import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/theme/one_ui.dart';
import 'package:otaku_reader/domain/repository/download_repository.dart';
import 'package:otaku_reader/features/downloads/controllers/downloads_controller.dart';

/// The download queue and what it is using on disk.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  static const _tag = 'downloads';

  late final DownloadsController _c = Get.put(
    DownloadsController(downloads: Get.find<DownloadRepository>()),
    tag: _tag,
  );

  @override
  void dispose() {
    Get.delete<DownloadsController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OneUiScaffold(
      title: 'Downloads',
      onRefresh: _c.refreshUsage,
      actions: [
        Obx(
          () => IconButton(
            icon: const Icon(Iconsax.broom),
            tooltip: 'Clear finished',
            // Clears the *list*, not the files — which the tooltip on the
            // empty state says, because "clear downloads" could plausibly
            // mean either and one of them is destructive.
            onPressed: _c.tasks.length == _c.activeCount
                ? null
                : _c.clearFinished,
          ),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Obx(
            () =>
                _UsageHeader(bytes: _c.usedBytes.value, active: _c.activeCount),
          ),
        ),
        // Its own `Obx`, and its own sliver: `itemBuilder` runs during layout,
        // after an enclosing build closure has already finished, so a read of
        // `tasks` there would register no dependency and the queue would never
        // visibly progress.
        Obx(() {
          final tasks = _c.tasks;
          if (tasks.isEmpty) {
            return const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 48, 24, 24),
                child: _Empty(),
              ),
            );
          }
          return SliverList.builder(
            itemCount: tasks.length,
            itemBuilder: (context, i) =>
                _TaskTile(task: tasks[i], onCancel: () => _c.cancel(tasks[i])),
          );
        }),
      ],
    );
  }
}

class _UsageHeader extends StatelessWidget {
  const _UsageHeader({required this.bytes, required this.active});

  final int bytes;
  final int active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(Iconsax.folder_open, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DownloadsController.formatBytes(bytes),
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  active == 0
                      ? 'Stored on this device'
                      : active == 1
                      ? '1 chapter downloading'
                      : '$active chapters downloading',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onCancel});

  final DownloadTask task;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running =
        task.state == DownloadState.queued ||
        task.state == DownloadState.running;
    return ListTile(
      title: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch (task.state) {
              DownloadState.done => '${task.chapterLabel} · saved',
              DownloadState.failed =>
                '${task.chapterLabel} · ${task.error ?? 'failed'}',
              DownloadState.queued => '${task.chapterLabel} · waiting',
              _ =>
                task.total == 0
                    ? '${task.chapterLabel} · starting'
                    : '${task.chapterLabel} · '
                          '${task.downloaded} of ${task.total} pages',
            },
            maxLines: 2,
            style: theme.textTheme.bodySmall?.copyWith(
              color: task.state == DownloadState.failed
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
          if (running) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: task.progress),
          ],
        ],
      ),
      trailing: running
          ? IconButton(
              icon: const Icon(Iconsax.close_circle, size: 20),
              tooltip: 'Cancel',
              onPressed: onCancel,
            )
          : Icon(
              switch (task.state) {
                DownloadState.done => Iconsax.tick_circle,
                DownloadState.failed => Iconsax.warning_2,
                _ => Iconsax.clock,
              },
              size: 20,
              color: switch (task.state) {
                DownloadState.done => theme.colorScheme.primary,
                DownloadState.failed => theme.colorScheme.error,
                _ => theme.disabledColor,
              },
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(
          Iconsax.arrow_down_2,
          size: 40,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          'Nothing downloading.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Download a chapter from its manga page to read it offline. '
          'Downloaded chapters are deleted from there too.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
