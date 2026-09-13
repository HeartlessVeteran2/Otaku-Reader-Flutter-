import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/domain/repository/extension_repository.dart';
import 'package:otaku_reader/features/browse/controllers/extensions_controller.dart';
import 'package:otaku_reader/features/browse/screens/source_browse_screen.dart';
import 'package:otaku_reader/features/browse/widgets/source_tile.dart';
import 'package:otaku_reader/source/model/source.dart';

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
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        actions: [
          IconButton(
            onPressed: _showLanguageFilter,
            icon: const Icon(Iconsax.language_square),
            tooltip: 'Languages',
          ),
          IconButton(
            onPressed: _showRepos,
            icon: const Icon(Iconsax.link),
            tooltip: 'Repositories',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _search,
                  onChanged: _c.setQuery,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search extensions',
                    prefixIcon: const Icon(Iconsax.search_normal, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              Obx(
                () => TabBar(
                  controller: _tabs,
                  tabs: [
                    const Tab(text: 'Installed'),
                    const Tab(text: 'Available'),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Updates'),
                          if (_c.updateCount > 0) ...[
                            const SizedBox(width: 6),
                            Badge(label: Text('${_c.updateCount}')),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Obx(() {
        final error = _c.lastError.value;
        return Column(
          children: [
            if (error != null) _ErrorBanner(message: error),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [for (final tab in ExtensionTab.values) _list(tab)],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _list(ExtensionTab tab) {
    return Obx(() {
      if (_c.isLoading.value && _c.all.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = _c.visible(tab);
      if (items.isEmpty) {
        return RefreshIndicator(
          onRefresh: _c.refreshRepos,
          // A scrollable is required for pull-to-refresh to work at all, so the
          // empty state is a list rather than a bare centred column.
          child: ListView(
            // Without this a short list cannot overscroll, so pull-to-refresh --
            // the only way to fetch the catalogue in the first place -- does
            // nothing on exactly the empty screen that needs it.
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
              _EmptyState(tab: tab, filtered: _c.query.value.isNotEmpty),
            ],
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _c.refreshRepos,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final source = items[i];
            return SourceTile(
              source: source,
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
    });
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
      _ when filtered => (
        Iconsax.search_normal,
        'Nothing matches that search.',
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
  List<ExtensionRepo> _repos = const [];
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

  Future<void> _reload() async {
    final repos = await widget.controller.repos();
    if (mounted) setState(() => _repos = repos);
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
                for (final repo in _repos)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      repo.name ?? Uri.tryParse(repo.url)?.host ?? repo.url,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      repo.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Iconsax.trash, size: 18),
                      tooltip: 'Remove, and its extensions with it',
                      onPressed: () async {
                        await widget.controller.removeRepo(repo.url);
                        await _reload();
                      },
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
