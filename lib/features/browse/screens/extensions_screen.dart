import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/features/browse/controllers/extensions_controller.dart';
import 'package:otaku_reader/features/browse/screens/source_browse_screen.dart';
import 'package:otaku_reader/features/browse/widgets/source_tile.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/features/search/screens/global_search_screen.dart';

/// Install, update and remove extensions, and manage the repos they come from.
class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  final _search = TextEditingController();
  ExtensionsController get _c => Get.find<ExtensionsController>();

  @override
  void initState() {
    super.initState();
    // The segmented control is not a `TabBar`, so nothing rebuilds it when the
    // view is swiped rather than tapped. Without this the pill stays behind on
    // a swipe, which reads as the tab not having changed.
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging || _tabs.index != _lastIndex) {
      setState(() => _lastIndex = _tabs.index);
    }
  }

  int _lastIndex = 0;

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChromeScaffold(
      title: 'Extensions',
      enableSearch: true,
      searchController: _search,
      onSearchChanged: _c.setQuery,
      searchHint: 'Search extensions',
      actions: [
        IconButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const GlobalSearchScreen()),
          ),
          icon: const Icon(Iconsax.search_favorite),
          tooltip: 'Search all sources',
        ),
        IconButton(
          onPressed: _showLanguageFilter,
          icon: const Icon(Iconsax.language_square),
          tooltip: 'Languages',
        ),
        IconButton(
          onPressed: _showRepos,
          icon: const Icon(Iconsax.link, size: 20),
          tooltip: 'Repositories',
        ),
      ],
      bottom: PreferredSize(
        // The pill is the only thing in this slot, and its padding is
        // horizontal, so the slot is exactly the bar. Stated as the token
        // rather than as 46 so the header height cannot drift from the bar's.
        preferredSize: const Size.fromHeight(Chrome.tabBarHeight),
        child: Obx(
          () => SegmentedTabs(
            selectedIndex: _tabs.index,
            onSelected: (i) => _tabs.animateTo(i),
            tabs: [
              const Text('Installed'),
              const Text('Available'),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Flexible(child: Text('Updates')),
                  if (_c.updateCount > 0) ...[
                    const SizedBox(width: 6),
                    Badge(label: Text('${_c.updateCount}')),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [for (final tab in ExtensionTab.values) _list(tab)],
      ),
    );
  }

  /// The notices that sit above a tab's rows.
  ///
  /// They are list *content*, not header slots. Pinning them under the pills
  /// would mean declaring their height to the scaffold, and neither one has a
  /// height that can be declared -- an error message wraps, and a repository
  /// label is as long as the repository's name. Riding in the scroll view
  /// costs their visibility while scrolled down, and scrolling up brings them
  /// back with the header they sit under.
  List<Widget> _notices() {
    final error = _c.lastError.value;
    final filter = _c.repoFilter.value;
    return [
      if (error != null) _ErrorBanner(message: error),
      // Rendered only while a filter is on. It also has to exist: filtering
      // from inside a sheet that then closes would otherwise leave a shortened
      // list with nothing on screen saying why.
      if (!filter.isAll)
        _FilterBanner(
          label: _c.filterLabel,
          onClear: () => _c.setRepoFilter(RepoFilter.all),
        ),
    ];
  }

  Widget _list(ExtensionTab tab) {
    // A `Builder`, and not for tidiness: `ChromeHeaderScope` is published
    // *inside* `ChromeScaffold`, so reading it from this `State`'s own context
    // -- which sits above the scaffold -- finds nothing and answers 0. That
    // answer is correct for a widget with no header above it and silently
    // wrong here, and what it produces is a first row behind a translucent
    // blurred pill, which reads as a design flourish.
    return Builder(
      builder: (context) => Obx(() {
        // The body fills the screen and the pills float over it, so every
        // scrollable here starts below the header and then scrolls under it.
        final top = ChromeHeaderScope.of(context);
        if (_c.isLoading.value && _c.all.isEmpty) {
          return Padding(
            padding: EdgeInsets.only(top: top),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        final notices = _notices();
        final items = _c.visible(tab);
        if (items.isEmpty) {
          return RefreshIndicator(
            // Without this the spinner drops out from behind the title pill.
            edgeOffset: top,
            onRefresh: _c.refreshRepos,
            // A scrollable is required for pull-to-refresh to work at all, so the
            // empty state is a list rather than a bare centred column.
            child: ListView(
              padding: EdgeInsets.only(top: top),
              // Without this a short list cannot overscroll, so pull-to-refresh --
              // the only way to fetch the catalogue in the first place -- does
              // nothing on exactly the empty screen that needs it.
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ...notices,
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
                _EmptyState(
                  tab: tab,
                  // The repository filter counts as filtering too. Told only
                  // about the query, an empty result under an active repo
                  // filter claimed the *catalogue* was empty -- over a
                  // catalogue that is in fact full.
                  filtered:
                      _c.query.value.isNotEmpty || !_c.repoFilter.value.isAll,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          edgeOffset: top,
          onRefresh: _c.refreshRepos,
          child: ListView.builder(
            padding: EdgeInsets.only(top: top, bottom: Chrome.sectionGap),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: notices.length + items.length,
            itemBuilder: (context, i) {
              if (i < notices.length) return notices[i];
              final source = items[i - notices.length];
              return SourceTile(
                source: source,
                // Null for a detached source, which is what the tile renders as
                // "No repository". A url the map does not know falls back to its
                // host rather than to null, so an unknown repo is never mistaken
                // for no repo at all.
                repoLabel: source.repoUrl == null
                    ? null
                    : _c.repoLabels[source.repoUrl] ??
                          Uri.tryParse(source.repoUrl!)?.host ??
                          source.repoUrl,
                busy: _c.busy.contains(source.sourceId),
                onInstall: () => _c.install(source),
                onUpdate: () => _c.updateSource(source),
                onUninstall: () => _confirmUninstall(source),
                // Only an installed source can be browsed; an uninstalled row has
                // no code to run, and offering the tap would dead-end.
                onTap: source.isInstalled
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SourceBrowseScreen(sourceId: source.sourceId),
                        ),
                      )
                    : null,
              );
            },
          ),
        );
      }),
    );
  }

  Future<void> _confirmUninstall(Source source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Uninstall ${source.name}?'),
        content: const Text(
          'The extension is removed but stays listed, so you can install it '
          'again. Manga already in your library keep pointing at it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
    if (ok ?? false) await _c.uninstall(source);
  }

  void _showLanguageFilter() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Obx(
        () => ListView(
          shrinkWrap: true,
          children: [
            SwitchListTile(
              value: _c.showNsfw.value,
              onChanged: _c.toggleNsfw,
              title: const Text('Show 18+ sources'),
            ),
            const Divider(),
            ListTile(
              dense: true,
              title: Text(
                _c.enabledLangs.isEmpty
                    ? 'All languages'
                    : '${_c.enabledLangs.length} selected',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            for (final lang in _c.availableLangs)
              CheckboxListTile(
                dense: true,
                value: _c.enabledLangs.contains(lang),
                onChanged: (_) => _c.toggleLang(lang),
                title: Text(lang.toUpperCase()),
              ),
          ],
        ),
      ),
    );
  }

  void _showRepos() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _RepoSheet(controller: _c),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Iconsax.warning_2, size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab, required this.filtered});

  final ExtensionTab tab;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (tab) {
      // "that search" was accurate while the query was the only filter. It
      // is not once a repository can be one, and naming the wrong control
      // sends the user to clear something they never set.
      _ when filtered => (
        Iconsax.search_normal,
        'Nothing matches the current filters.',
      ),
      ExtensionTab.installed => (
        Iconsax.box,
        'No extensions installed yet.\nPull down to load the catalogue, then '
            'install one from Available.',
      ),
      ExtensionTab.available => (
        Iconsax.global,
        'Nothing to show.\nPull down to fetch the extension index.',
      ),
      ExtensionTab.updates => (
        Iconsax.tick_circle,
        'Everything is up to date.',
      ),
    };
    return Column(
      children: [
        Icon(icon, size: 40, color: Theme.of(context).disabledColor),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _RepoSheet extends StatefulWidget {
  const _RepoSheet({required this.controller});

  final ExtensionsController controller;

  @override
  State<_RepoSheet> createState() => _RepoSheetState();
}

class _RepoSheetState extends State<_RepoSheet> {
  final _url = TextEditingController();
  List<RepoStatus> _repos = const [];
  String? _error;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Asks before removing, and says what will actually happen.
  ///
  /// Installed sources are *kept* — they are detached and stop receiving
  /// updates — because deleting them would strand every library entry pointing
  /// at them. The dialog says so, because "remove, and its extensions with it"
  /// described the old behaviour and was the more frightening of the two.
  Future<void> _confirmRemove(RepoStatus status) async {
    final repo = status.repo;
    final kept = status.installedCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this repository?'),
        content: Text(
          kept == 0
              ? 'Its extensions will no longer be listed.'
              : kept == 1
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
    if (!(ok ?? false)) return;
    await widget.controller.removeRepo(repo.url);
    if (mounted) await _reload();
  }

  /// Bumped per reload, so a slower earlier one cannot publish over a newer.
  int _reloadGeneration = 0;

  /// Re-reads the repositories, and publishes only if it is still the newest.
  ///
  /// Three call sites can overlap — `initState`, adding, and removing — and each
  /// awaits before touching state. Today the repository's chain is synchronous
  /// underneath, so completions follow the microtask queue in call order and
  /// the older one cannot actually win; this guard is for the moment that stops
  /// being true, which is one disk read or one network call away, and it costs
  /// two lines. The same shape already guards the AniList write path, where the
  /// equivalent race *is* reachable.
  ///
  /// `mounted` alone is not enough: an unmounted check answers "is this widget
  /// still alive", not "is this answer still the current one". Flagged by
  /// `codeant-ai`.
  Future<void> _reload() async {
    final generation = ++_reloadGeneration;
    final repos = await widget.controller.repoStatuses();
    if (!mounted || generation != _reloadGeneration) return;
    setState(() => _repos = repos);
  }

  Future<void> _add() async {
    setState(() {
      _adding = true;
      _error = null;
    });
    final error = await widget.controller.addRepo(_url.text);
    if (!mounted) return;
    setState(() {
      _adding = false;
      _error = error;
    });
    if (error == null) {
      _url.clear();
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Repositories', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Each repository is an index.json listing extensions.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'https://…/index.json',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _adding ? null : _add,
                child: _adding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final status in _repos)
                  _RepoRow(
                    status: status,
                    onRemove: () => _confirmRemove(status),
                    // Filtering lives here rather than behind a fourth app-bar
                    // action: this sheet already lists every repository with
                    // its count, and the screen's bar is tight enough that a
                    // fourth 48px action crowds the title on a narrow phone.
                    onFilter: () {
                      widget.controller.setRepoFilter(
                        RepoFilter.of(status.repo.url),
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                if (widget.controller.hasDetached)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Iconsax.link_21,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Extensions with no repository'),
                    subtitle: const Text(
                      'Kept when their repository was removed. They still '
                      'work, and will never update.',
                    ),
                    onTap: () {
                      widget.controller.setRepoFilter(RepoFilter.detached);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One repository, with what it holds and how it last behaved.
///
/// The health line is the point of the row. A refresh that fails deliberately
/// leaves the previously known sources in place — a flaky network must not
/// empty the extension list — which also means a dead repo is indistinguishable
/// from a healthy one until you notice it never gains anything. This says so.
class _RepoRow extends StatelessWidget {
  const _RepoRow({
    required this.status,
    required this.onRemove,
    required this.onFilter,
  });

  final RepoStatus status;
  final VoidCallback onRemove;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final health = status.health;
    final failed = health != null && !health.isSuccess;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onFilter,
      title: Text(status.label, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status.repo.url, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(
                failed
                    ? Iconsax.warning_2
                    : health == null
                    ? Iconsax.clock
                    : Iconsax.tick_circle,
                size: 13,
                // The error colour is load-bearing here rather than decorative:
                // it is what makes one failing repo findable in a list of
                // healthy ones without reading every line.
                color: failed
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _healthLine(status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Iconsax.trash, size: 18),
        tooltip: 'Remove this repository',
        onPressed: onRemove,
      ),
    );
  }

  /// "12 extensions · checked 5m ago", or why not.
  ///
  /// Three states, never two: a repo that has never been refreshed says so
  /// rather than borrowing either of the others. "Never checked" is something
  /// the user can act on; reporting it as a failure would be a claim about a
  /// request that was never made.
  static String _healthLine(RepoStatus status) {
    final count = status.sourceCount == 1
        ? '1 extension'
        : '${status.sourceCount} extensions';
    final health = status.health;
    if (health == null) return '$count · never checked';
    final when = _ago(DateTime.now().difference(health.checkedAt));
    if (health.isSuccess) return '$count · checked $when';
    return '$count · failed $when';
  }

  /// A coarse "how long ago". Deliberately coarse: the exact second a repo was
  /// last read is never the question, and a ticking string would repaint the
  /// sheet forever.
  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

/// Says which repository the list is restricted to, and offers a way out.
///
/// The way out is the point: the filter is set from a sheet that closes behind
/// it, so without this the user is left with a shortened list, no explanation,
/// and no obvious route back.
class _FilterBanner extends StatelessWidget {
  const _FilterBanner({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      child: Row(
        children: [
          Icon(
            Iconsax.filter,
            size: 14,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Iconsax.close_circle, size: 18),
            tooltip: 'Show every repository',
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
