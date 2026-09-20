// Derived from AnymeX (https://github.com/RyanYuuki/AnymeX),
// MIT License, Copyright (c) 2024 Ryan _.
// See NOTICE and licenses/AnymeX-MIT.txt for the permission notice that
// licence requires to travel with these portions.

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
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
    this.repoLabel,
  });

  final Source source;

  /// What to call the repository this source came from.
  ///
  /// Null means **detached** — the repository was removed and the source was
  /// kept, because library rows point at it by id and deleting it would break
  /// every entry that uses it. It still works; it will never update again.
  /// That is worth saying on the row, because nothing else on screen
  /// distinguishes a frozen source from a current one.
  final String? repoLabel;
  final bool busy;
  final VoidCallback? onInstall;
  final VoidCallback? onUpdate;
  final VoidCallback? onUninstall;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A card per row rather than a flat divider-separated list: the house
    // shape, and what makes this read as AnymeX rather than as Material.
    return ChromeCard(
      margin: const EdgeInsets.fromLTRB(
        Chrome.gutter,
        0,
        Chrome.gutter,
        Chrome.gap,
      ),
      // A row with an install or uninstall in flight must not open: the source
      // it would open is the one being replaced or removed.
      onTap: busy ? null : onTap,
      child: ChromeTile(
        title: source.name,
        titleSuffix: source.isNsfw
            ? _Chip(label: '18+', color: theme.colorScheme.error)
            : null,
        leading: _Icon(url: source.iconUrl, name: source.name),
        // The card owns the tap, so the row must not offer a second one -- and
        // a chevron beside an install button reads as two actions.
        showChevron: false,
        subtitleWidget: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
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
            Row(
              children: [
                Icon(
                  repoLabel == null ? Iconsax.link_21 : Iconsax.link,
                  size: 11,
                  color: repoLabel == null
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    repoLabel ?? 'No repository — will not update',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: repoLabel == null
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: _Action(
          busy: busy,
          source: source,
          onInstall: onInstall,
          onUpdate: onUpdate,
          onUninstall: onUninstall,
        ),
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
      // Sized to the widest action it replaces ("Update"), so the title does
      // not shift sideways when a mutation starts.
      return const SizedBox(
        width: _actionWidth,
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
    // A *minimum* width, not a fixed one: the box exists so the title does not
    // shift when an action is replaced by a spinner, and at large accessibility
    // text scales a fixed 84dp clips "Update" instead.
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _actionWidth),
      child: switch (source) {
        _ when source.hasUpdate => TextButton(
          onPressed: onUpdate,
          child: const Text('Update'),
        ),
        _ when source.isInstalled => IconButton(
          onPressed: onUninstall,
          icon: const Icon(Iconsax.trash),
          tooltip: 'Uninstall',
        ),
        _ => TextButton(onPressed: onInstall, child: const Text('Install')),
      },
    );
  }
}

/// Shared by every action state, so a row does not jump when one replaces
/// another.
const double _actionWidth = 84;

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
