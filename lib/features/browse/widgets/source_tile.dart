import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/source/model/source.dart';

/// One extension row: icon, name, language and version, and the action that
/// applies to its current state.
class SourceTile extends StatelessWidget {
  const SourceTile({
    super.key,
    required this.source,
    required this.busy,
    this.onInstall,
    this.onUpdate,
    this.onUninstall,
    this.onTap,
  });

  final Source source;
  final bool busy;
  final VoidCallback? onInstall;
  final VoidCallback? onUpdate;
  final VoidCallback? onUninstall;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: _Icon(url: source.iconUrl, name: source.name),
      title: Row(
        children: [
          Flexible(child: Text(source.name, overflow: TextOverflow.ellipsis)),
          if (source.isNsfw) ...[
            const SizedBox(width: 6),
            _Chip(label: '18+', color: theme.colorScheme.error),
          ],
        ],
      ),
      subtitle: Text(
        [
          source.lang.toUpperCase(),
          if (source.isInstalled)
            'v${source.version}'
          else
            'v${source.versionLast}',
          if (source.hasUpdate) '→ v${source.versionLast}',
        ].join(' · '),
        style: theme.textTheme.bodySmall,
      ),
      trailing: _Action(
        busy: busy,
        source: source,
        onInstall: onInstall,
        onUpdate: onUpdate,
        onUninstall: onUninstall,
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.busy,
    required this.source,
    this.onInstall,
    this.onUpdate,
    this.onUninstall,
  });

  final bool busy;
  final Source source;
  final VoidCallback? onInstall;
  final VoidCallback? onUpdate;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      // Same footprint as the buttons it replaces, so a row does not jump when
      // an install starts.
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (source.hasUpdate) {
      return TextButton(onPressed: onUpdate, child: const Text('Update'));
    }
    if (source.isInstalled) {
      return IconButton(
        onPressed: onUninstall,
        icon: const Icon(Iconsax.trash),
        tooltip: 'Uninstall',
      );
    }
    return TextButton(onPressed: onInstall, child: const Text('Install'));
  }
}

class _Icon extends StatelessWidget {
  const _Icon({this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = _Fallback(name: name);
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url!,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        // A source icon is decoration. A dead icon host is common — the domains
        // in the index go stale faster than the scripts do — and must never
        // look like the source itself is broken.
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(letter, style: TextStyle(color: scheme.onSurfaceVariant)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: color, fontWeight: FontWeight.w600),
    ),
  );
}
