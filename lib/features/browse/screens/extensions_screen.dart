// Derived from AnymeX (https://github.com/RyanYuuki/AnymeX),
// MIT License, Copyright (c) 2024 Ryan _.
// See NOTICE and licenses/AnymeX-MIT.txt for the permission notice that
// licence requires to travel with these portions.

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/features/browse/controllers/extensions_controller.dart';
import 'package:otaku_reader/features/browse/screens/repositories_screen.dart';
import 'package:otaku_reader/features/browse/screens/source_browse_screen.dart';
import 'package:otaku_reader/features/browse/widgets/source_tile.dart';
import 'package:otaku_reader/source/model/source.dart';
import 'package:otaku_reader/features/search/screens/global_search_screen.dart';
import 'package:otaku_reader/core/ui/greeting_text.dart';

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
      // The greeting, but **no** `leading: ProfileAvatar()`, and that is
      // measured rather than preferred.
      //
      // A leading costs one action slot. This screen carries three actions
      // plus search, and `chrome_test`'s own probe puts that combination
      // over the edge by **22px at 320 and 1.5px at 360** with a leading,
      // and clean at every width without one — the same shape as the
      // `TabBar` overflow this repo already shipped, which was also not
      // confined to tiny phones.
      //
      // AnymeX arrives at the same place from the other direction: it only
      // leads with the avatar on screens carrying a single action, and its
      // one busy root (home) puts the avatar in the *actions* pill instead.
      // So four tab roots lead with the account and this one does not,
      // which is a width budget rather than an oversight.
      subtitleWidget: const GreetingText(),
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

  /// A screen, not a sheet.
  ///
  /// AnymeX's equivalent is a screen and this app's was a sheet, invented
  /// while that one sat on disk — its own row in `CLAUDE.md`. A sheet also
  /// caps what the feature can grow into: a per-row deleting state and a
  /// multi-URL add both want room the sheet does not have.
  Future<void> _showRepos() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RepositoriesScreen(controller: _c),
      ),
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
