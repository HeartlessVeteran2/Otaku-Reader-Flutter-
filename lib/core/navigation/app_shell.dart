import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/features/browse/screens/extensions_screen.dart';
import 'package:otaku_reader/features/home/screens/home_screen.dart';
import 'package:otaku_reader/features/library/screens/library_screen.dart';
import 'package:otaku_reader/features/more/screens/more_screen.dart';
import 'package:otaku_reader/features/updates/controllers/updates_controller.dart';
import 'package:otaku_reader/features/updates/scheduling/update_schedule.dart';
import 'package:otaku_reader/features/updates/screens/updates_screen.dart';
import 'package:otaku_reader/widgets/common/lazy_indexed_stack.dart';

class _Tab {
  const _Tab(
    this.label,
    this.icon,
    this.activeIcon,
    this.builder, {
    this.badge = false,
  });
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget Function() builder;

  /// Whether this tab carries the unread-updates count.
  final bool badge;
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _breakpoint = 600.0;

  static final _tabs = <_Tab>[
    _Tab('Home', Iconsax.home, Iconsax.home5, () => const HomeScreen()),
    _Tab(
      'Library',
      Iconsax.book,
      Iconsax.book_saved,
      () => const LibraryScreen(),
    ),
    _Tab(
      'Browse',
      Iconsax.global,
      Iconsax.global,
      () => const ExtensionsScreen(),
    ),
    _Tab(
      'Updates',
      Iconsax.refresh,
      Iconsax.refresh,
      () => const UpdatesScreen(),
      badge: true,
    ),
    _Tab('More', Iconsax.category, Iconsax.category, () => const MoreScreen()),
  ];

  late int _index = General.lastOpenedTab
      .get<int>(0)
      .clamp(0, _tabs.length - 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshIfDue();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Launch and resume, which is the whole schedule. Without a background
    // worker there is no other moment to run one, and this is the honest
    // version of "automatic": the app checks whenever you come back to it,
    // rather than promising a refresh while it is closed.
    if (state == AppLifecycleState.resumed) _refreshIfDue();
  }

  /// Asks the Updates tab whether a scheduled refresh is due, and lets it run.
  ///
  /// Guarded on registration for the same reason the badge is: the shell is
  /// built by tests and by any entry point that does not run `AppBindings`,
  /// and a library refresh is not worth taking the app down for.
  ///
  /// Deliberately unawaited and silent. It is a background courtesy — the
  /// Updates tab shows its own progress and its own errors, and a snackbar on
  /// every resume would be the app talking about itself.
  void _refreshIfDue() {
    if (!Get.isRegistered<UpdatesController>()) return;
    // Caught, not merely unawaited. This fires from `initState` and from a
    // resume, so a throw has nobody above it and becomes an unhandled async
    // error at startup — the same shape as `AniListAuth.restore` being
    // launched unawaited from `AppBindings`, which is already a row in the
    // mistakes table. A refresh that cannot run is not worth a crash: the
    // Updates tab surfaces its own errors, and the next resume tries again.
    unawaited(
      Get.find<UpdatesController>().refreshIfDue().catchError(
        (_) => UpdateDecision.notDue,
      ),
    );
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    General.lastOpenedTab.set<int>(i);
  }

  /// The unread count, wrapped so a missing controller is not a crash.
  ///
  /// The shell is also built by tests and by any future entry point that does
  /// not run [AppBindings]; a navigation bar is not worth taking the app down
  /// for a badge.
  Widget _icon(_Tab tab, {required bool selected}) {
    final icon = Icon(selected ? tab.activeIcon : tab.icon);
    if (!tab.badge || !Get.isRegistered<UpdatesController>()) return icon;
    return Obx(() {
      final count = Get.find<UpdatesController>().unreadCount;
      if (count == 0) return icon;
      return Badge(
        // Three digits is where a bottom-bar badge stops fitting; past that
        // the exact number is not information anyone acts on.
        label: Text(count > 99 ? '99+' : '$count'),
        child: icon,
      );
    });
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
                    icon: _icon(t, selected: false),
                    selectedIcon: _icon(t, selected: true),
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
              icon: _icon(t, selected: false),
              selectedIcon: _icon(t, selected: true),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
