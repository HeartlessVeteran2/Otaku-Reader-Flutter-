import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/features/downloads/screens/downloads_screen.dart';
import 'package:otaku_reader/features/history/screens/history_screen.dart';
import 'package:otaku_reader/features/more/screens/about_screen.dart';
import 'package:otaku_reader/features/settings/screens/settings_screen.dart';

/// Everything that does not earn a tab of its own.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          _Row(
            icon: Iconsax.clock,
            title: 'History',
            subtitle: 'What you have read, newest first',
            builder: () => const HistoryScreen(),
          ),
          _Row(
            icon: Iconsax.arrow_down_2,
            title: 'Downloads',
            subtitle: 'The queue, and what it is using on disk',
            builder: () => const DownloadsScreen(),
          ),
          _Row(
            icon: Iconsax.setting_2,
            title: 'Settings',
            subtitle: 'Appearance, reader defaults, sources',
            builder: () => const SettingsScreen(),
          ),
          _Row(
            icon: Iconsax.info_circle,
            title: 'About',
            subtitle: 'Version, licences and credits',
            builder: () => const AboutScreen(),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget Function() builder;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: () =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => builder())),
  );
}
