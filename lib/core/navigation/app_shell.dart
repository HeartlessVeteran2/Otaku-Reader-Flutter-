import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/widgets/common/lazy_indexed_stack.dart';
import 'package:otaku_reader/widgets/common/placeholder_screen.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.activeIcon, this.builder);
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget Function() builder;
}

/// The app's root. Tabs live in a [LazyIndexedStack] so each keeps its state.
///
/// Below 600px this is a bottom navigation bar; at or above it a side rail, so
/// the same tab set serves phone, tablet and (later) desktop without a second
/// widget tree.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _breakpoint = 600.0;

  static final _tabs = <_Tab>[
    _Tab(
      'Home',
      Iconsax.home,
      Iconsax.home5,
      () => const PlaceholderScreen(
        title: 'Home',
        icon: Iconsax.home,
        note: 'Local and AniList home feeds land in phase 2.',
      ),
    ),
    _Tab(
      'Library',
      Iconsax.book,
      Iconsax.book_saved,
      () => const PlaceholderScreen(
        title: 'Library',
        icon: Iconsax.book,
        note: 'Your saved manga will appear here.',
      ),
    ),
    _Tab(
      'Browse',
      Iconsax.global,
      Iconsax.global,
      () => const PlaceholderScreen(
        title: 'Browse',
        icon: Iconsax.global,
        note: 'Install a source to start browsing.',
      ),
    ),
    _Tab(
      'Updates',
      Iconsax.refresh,
      Iconsax.refresh,
      () => const PlaceholderScreen(
        title: 'Updates',
        icon: Iconsax.refresh,
        note: 'New chapters from your library.',
      ),
    ),
    _Tab(
      'More',
      Iconsax.category,
      Iconsax.category,
      () => const PlaceholderScreen(
        title: 'More',
        icon: Iconsax.category,
        note: 'History, statistics, downloads and settings.',
      ),
    ),
  ];

  late int _index = General.lastOpenedTab
      .get<int>(0)
      .clamp(0, _tabs.length - 1);

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    General.lastOpenedTab.set<int>(i);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _breakpoint;
    final body = LazyIndexedStack(
      index: _index,
      children: [for (final t in _tabs) t.builder()],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final t in _tabs)
                  NavigationRailDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.activeIcon),
                    label: Text(t.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.activeIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
