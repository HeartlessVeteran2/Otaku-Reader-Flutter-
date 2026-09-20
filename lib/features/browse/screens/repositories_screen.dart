// Derived from AnymeX (https://github.com/RyanYuuki/AnymeX),
// MIT License, Copyright (c) 2024 Ryan _.
// See NOTICE and licenses/AnymeX-MIT.txt for the permission notice that
// licence requires to travel with these portions.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/features/browse/controllers/extensions_controller.dart';

/// Manage the repositories extensions are listed from.
///
/// A **screen**, not a sheet, and built on AnymeX's
/// `lib/screens/settings/sub_settings/settings_extensions.dart` rather than
/// from scratch — the sheet this replaces was invented while that 911-line
/// equivalent sat on disk, which is its own row in `CLAUDE.md`. What comes
/// from there: the URL split into a monospace *path* over a muted *host*, a
/// copy button, a per-row deleting state instead of a blocking dialog, and an
/// add dialog that takes several URLs at once.
///
/// What does not: per-repo health and source counts are this app's own, and
/// AnymeX has nothing like them — so they keep the shape they already had,
/// inside AnymeX's shell rather than beside it.
class RepositoriesScreen extends StatefulWidget {
  const RepositoriesScreen({super.key, required this.controller});

  final ExtensionsController controller;

  @override
  State<RepositoriesScreen> createState() => _RepositoriesScreenState();
}

class _RepositoriesScreenState extends State<RepositoriesScreen> {
  List<RepoStatus> _repos = const [];
  bool _loaded = false;

  /// The URLs with a removal in flight.
  ///
  /// Keyed by URL rather than by index: the list is rebuilt under the removal,
  /// so an index would follow whichever row slid into that position.
  final _removing = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Bumped per reload, so a slower earlier one cannot publish over a newer.
  int _reloadGeneration = 0;

  /// Re-reads the repositories, and publishes only if it is still the newest.
  ///
  /// `mounted` alone is not enough: it answers "is this widget still alive",
  /// not "is this answer still the current one". Carried over from the sheet,
  /// where `codeant-ai` flagged its absence.
  Future<void> _reload() async {
    final generation = ++_reloadGeneration;
    final repos = await widget.controller.repoStatuses();
    if (!mounted || generation != _reloadGeneration) return;
    setState(() {
      _repos = repos;
      _loaded = true;
    });
  }

  /// Re-reads every index, which is what refreshes the health line.
  Future<void> _refresh() async {
    await widget.controller.refreshRepos();
    await _reload();
  }

  /// Restricts the extensions list to one repository and goes back to it.
  void _filterBy(RepoFilter filter) {
    widget.controller.setRepoFilter(filter);
    Navigator.of(context).pop();
  }

  /// Removes a repository, asking first **only when there is something to
  /// warn about**.
  ///
  /// AnymeX asks nothing, because its removal has no consequence worth
  /// stating. This app's does: an installed source is *detached* rather than
  /// deleted — it keeps working and silently stops updating — and that is a
  /// surprise the user should meet before it happens, not after.
  ///
  /// But a repository with nothing installed costs one dialog to say
  /// "its extensions will no longer be listed", which is what the user just
  /// asked for. Confirming that trains people to dismiss the dialog that
  /// matters. So the question is asked exactly when it has an answer.
  Future<void> _remove(RepoStatus status) async {
    final kept = status.installedCount;
    if (kept > 0 && !await _confirm(kept)) return;

    setState(() => _removing.add(status.repo.url));
    try {
      await widget.controller.removeRepo(status.repo.url);
      if (mounted) await _reload();
    } catch (error) {
      // The row un-dims either way, so without this the user sees a spinner
      // stop, the repository still sitting there, and nothing said — which
      // reads as the app being broken rather than as the removal having
      // failed. It is the rule `open_link.dart` exists for, and the removal
      // really can throw: it writes the KV tier and an Isar transaction, and
      // a database failure escaping an untried block is already a row in
      // CLAUDE.md. Found by `codeant-ai`.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove that repository: $error')),
        );
      }
    } finally {
      // Removed from the set whatever happened: a row left dimmed with a
      // spinner after a failure reads as a removal still in progress, and the
      // retry is the same tap the user can no longer see a target for.
      if (mounted) setState(() => _removing.remove(status.repo.url));
    }
  }

  Future<bool> _confirm(int kept) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this repository?'),
        content: Text(
          kept == 1
              ? '1 installed extension stays and keeps working, but stops '
                    'receiving updates. The rest are no longer listed.'
              : '$kept installed extensions stay and keep working, but stop '
                    'receiving updates. The rest are no longer listed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    // The barrier pops null, and Cancel pops false. Both mean no.
    return ok ?? false;
  }

  Future<void> _openAddDialog() async {
    final added = await showDialog<int>(
      context: context,
      builder: (context) => _AddRepoDialog(controller: widget.controller),
    );
    if (added != null && added > 0 && mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final detached = widget.controller.hasDetached;
    return ChromeScaffold.slivers(
      title: 'Repositories',
      subtitle: _loaded ? _subtitle(_repos.length) : null,
      onRefresh: _refresh,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        icon: const Icon(Iconsax.add),
        label: const Text('Add'),
      ),
      slivers: [
        if (!_loaded)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(Chrome.sectionGap),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_repos.isEmpty && !detached)
          const SliverToBoxAdapter(child: _Empty())
        else ...[
          SliverList.builder(
            itemCount: _repos.length,
            itemBuilder: (context, i) {
              final status = _repos[i];
              return _RepoCard(
                status: status,
                removing: _removing.contains(status.repo.url),
                onTap: () => _filterBy(RepoFilter.of(status.repo.url)),
                onRemove: () => _remove(status),
              );
            },
          ),
          if (detached)
            SliverToBoxAdapter(
              child: _DetachedCard(onTap: () => _filterBy(RepoFilter.detached)),
            ),
        ],
        // Clears the extended FAB, which floats over the last row.
        const SliverToBoxAdapter(child: SizedBox(height: 72)),
      ],
    );
  }

  static String _subtitle(int count) =>
      count == 1 ? '1 repository' : '$count repositories';
}

/// One repository: what it is, how it last behaved, what it holds.
///
/// The URL is split the way AnymeX splits it — the *path* in monospace, which
/// is the part that differs between two indexes on the same host, over the
/// host in a muted line. A single ellipsised URL hides exactly the end that
/// tells two repositories apart.
class _RepoCard extends StatelessWidget {
  const _RepoCard({
    required this.status,
    required this.removing,
    required this.onTap,
    required this.onRemove,
  });

  final RepoStatus status;
  final bool removing;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final health = status.health;
    final failed = health != null && !health.isSuccess;

    return ChromeCard(
      margin: const EdgeInsets.fromLTRB(
        Chrome.gutter,
        0,
        Chrome.gutter,
        Chrome.gap,
      ),
      // A row being removed must not also be a row that filters the catalogue
      // by the repository it is removing.
      onTap: removing ? null : onTap,
      child: AnimatedOpacity(
        opacity: removing ? 0.4 : 1,
        duration: const Duration(milliseconds: 200),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: Chrome.leadingSize,
                height: Chrome.leadingSize,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Chrome.leadingRadius),
                ),
                child: Icon(Iconsax.link, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _path(status.repo.url),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Name-or-host, and deliberately the *same* string the
                      // extension rows use: a repository called one thing here
                      // and another there is worse than either name.
                      status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          failed
                              ? Iconsax.warning_2
                              : health == null
                              ? Iconsax.clock
                              : Iconsax.tick_circle,
                          size: 13,
                          // Load-bearing rather than decorative: it is what
                          // makes one failing repository findable in a list of
                          // healthy ones without reading every line.
                          color: failed
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            healthLine(status),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: failed
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _Action(
                icon: Iconsax.copy,
                tooltip: 'Copy URL',
                onPressed: removing
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: status.repo.url),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('URL copied')),
                        );
                      },
              ),
              if (removing)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                _Action(
                  icon: Iconsax.trash,
                  tooltip: 'Remove this repository',
                  color: scheme.error,
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _path(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.path.isEmpty) return url;
    return uri.path + (uri.hasQuery ? '?${uri.query}' : '');
  }

  /// "12 extensions · checked 5m ago", or why not.
  ///
  /// Three states, never two: a repo that has never been refreshed says so
  /// rather than borrowing either of the others. "Never checked" is something
  /// the user can act on; reporting it as a failure would be a claim about a
  /// request that was never made.
  static String healthLine(RepoStatus status) {
    final count = status.sourceCount == 1
        ? '1 extension'
        : '${status.sourceCount} extensions';
    final health = status.health;
    if (health == null) return '$count · never checked';
    final verb = health.isSuccess ? 'checked' : 'failed';
    final when = ago(DateTime.now().difference(health.checkedAt));
    // The outcome is always said; only its age can be unsayable.
    return when == null ? '$count · $verb' : '$count · $verb $when';
  }

  /// A coarse "how long ago", or **null** when the record is ahead of the
  /// clock.
  ///
  /// Deliberately coarse: the exact second a repo was last read is never the
  /// question, and a ticking string would repaint the list forever.
  ///
  /// `checkedAt` is persisted, so a clock correction — a timezone change, an
  /// NTP step, a user setting the date back — can leave a stored record dated
  /// in the future. The difference is then negative, and every bound below is
  /// "less than", so it would render as *"just now"*: a confident claim about
  /// when the check happened, made from a number that cannot say. Dropping the
  /// clause says less and nothing false. Found by `codeant-ai`.
  static String? ago(Duration d) {
    if (d.isNegative) return null;
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// The extensions whose repository was removed.
///
/// Its own row rather than a repository, because it is not one: these sources
/// still work and will never update again, and nothing else on the extensions
/// list distinguishes a frozen source from a current one.
class _DetachedCard extends StatelessWidget {
  const _DetachedCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChromeCard(
      margin: const EdgeInsets.fromLTRB(
        Chrome.gutter,
        0,
        Chrome.gutter,
        Chrome.gap,
      ),
      onTap: onTap,
      child: ChromeTile(
        title: 'Extensions with no repository',
        subtitle:
            'Kept when their repository was removed. They still work, '
            'and will never update.',
        icon: Iconsax.link_21,
        iconColor: scheme.error,
        iconBackground: scheme.error.withValues(alpha: 0.12),
        onTap: onTap,
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon, size: 18, color: color),
    tooltip: tooltip,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Chrome.gutter * 2,
        Chrome.sectionGap * 2,
        Chrome.gutter * 2,
        0,
      ),
      child: Column(
        children: [
          Icon(Iconsax.link, size: 40, color: theme.disabledColor),
          const SizedBox(height: 12),
          Text(
            'No repositories.\nAdd one to list extensions from it.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Adds one repository, or several at once.
///
/// The several-at-once is AnymeX's, and it is the difference between pasting a
/// list someone shared and pasting one line eleven times. Each URL is still
/// validated and fetched on its own, so one bad entry in a paste reports
/// itself without discarding the others.
class _AddRepoDialog extends StatefulWidget {
  const _AddRepoDialog({required this.controller});

  final ExtensionsController controller;

  @override
  State<_AddRepoDialog> createState() => _AddRepoDialogState();
}

class _AddRepoDialogState extends State<_AddRepoDialog> {
  // Owned by this `State` rather than disposed after `await showDialog`: that
  // future completes when the route is popped, while the exit animation is
  // still running and the field is still mounted, so disposing there throws
  // part-way through the close. Recorded in CLAUDE.md.
  final _urls = TextEditingController();
  bool _adding = false;

  /// What went wrong, per URL, from the last attempt.
  List<(String url, String error)> _failures = const [];

  /// How many landed, so a partly successful paste says so rather than only
  /// listing what did not.
  int _added = 0;

  @override
  void dispose() {
    _urls.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final urls = _urls.text
        .split(RegExp(r'[\n,]'))
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;

    setState(() {
      _adding = true;
      _failures = const [];
      _added = 0;
    });

    final failures = <(String, String)>[];
    var added = 0;
    // Sequential on purpose. Each add fetches an index, and firing a pasted
    // list at one host in parallel is how an IP gets rate-limited — the same
    // rule that bounds global search and the library refresh.
    for (final url in urls) {
      final error = await widget.controller.addRepo(url);
      if (error == null) {
        added++;
      } else {
        failures.add((url, error));
      }
    }
    if (!mounted) return;

    if (failures.isEmpty) {
      Navigator.of(context).pop(added);
      return;
    }
    // Held open on a partial failure, with the ones that failed left in the
    // field: closing would report the successes and silently drop the rest.
    setState(() {
      _adding = false;
      _added = added;
      _failures = failures;
      _urls.text = failures.map((f) => f.$1).join('\n');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add repository'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A repository is an index.json listing extensions. Paste several, '
            'one per line.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urls,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enabled: !_adding,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'https://…/index.json',
              border: OutlineInputBorder(),
            ),
          ),
          if (_added > 0) ...[
            const SizedBox(height: 12),
            Text(
              _added == 1
                  ? '1 repository added. The rest did not:'
                  : '$_added repositories added. The rest did not:',
              style: theme.textTheme.bodySmall,
            ),
          ],
          for (final (url, error) in _failures) ...[
            const SizedBox(height: 8),
            Text(
              '$error\n$url',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _adding ? null : () => Navigator.pop(context, _added),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _adding ? null : _submit,
          child: _adding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
