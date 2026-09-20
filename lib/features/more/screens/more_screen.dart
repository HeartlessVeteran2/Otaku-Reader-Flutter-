// Derived from AnymeX (https://github.com/RyanYuuki/AnymeX),
// MIT License, Copyright (c) 2024 Ryan _.
// See NOTICE and licenses/AnymeX-MIT.txt for the permission notice that
// licence requires to travel with these portions.

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/features/downloads/screens/downloads_screen.dart';
import 'package:otaku_reader/features/history/screens/history_screen.dart';
import 'package:otaku_reader/features/more/screens/about_screen.dart';
import 'package:otaku_reader/features/settings/screens/settings_screen.dart';

/// Everything that does not earn a tab of its own.
///
/// A *hub*, not a settings list, so it takes AnymeX's shape for one
/// (`lib/screens/other_features.dart`): cards with a tinted icon tile over a
/// title and a sentence, two to a row. Four destinations each worth a sentence
/// is the case the row idiom serves worst — a `ListTile` subtitle has to
/// compete with the title on one line.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChromeScaffold(
      title: 'More',
      body: Builder(
        builder: (context) {
          // From a Builder inside the body, never from the State's context:
          // that sits above the ChromeScaffold this build returns, so the
          // lookup finds nothing and silently takes the zero fallback, which
          // renders the first row behind the blurred pill.
          final headerHeight = ChromeHeaderScope.of(context);
          return ListView(
            padding: EdgeInsets.fromLTRB(
              Chrome.gutter,
              headerHeight + Chrome.gap,
              Chrome.gutter,
              Chrome.sectionGap * 2,
            ),
            children: const [
              _HubRow(
                left: _Destination.history,
                right: _Destination.downloads,
              ),
              SizedBox(height: Chrome.gap + 4),
              _HubRow(left: _Destination.settings, right: _Destination.about),
            ],
          );
        },
      ),
    );
  }
}

/// Two cards of equal height, side by side.
///
/// `IntrinsicHeight` rather than a fixed height, and the measurement matters
/// more than the reasoning: at the **default** text scale a hardcoded 150px
/// fits the tallest card even at 320px, so every width test here passes with
/// one. What it cannot survive is a doubled system font, where the card's
/// height is entirely text — that overflows, and it is an ordinary
/// accessibility setting rather than an edge case. The suite asserts that
/// state specifically, because it is the only one that tells the two versions
/// apart.
class _HubRow extends StatelessWidget {
  const _HubRow({required this.left, required this.right});

  final _Destination left;
  final _Destination right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _Card(destination: left)),
        const SizedBox(width: Chrome.gap + 4),
        Expanded(child: _Card(destination: right)),
      ],
    ),
  );
}

enum _Destination {
  history(
    icon: Iconsax.clock,
    title: 'History',
    description: 'What you have read, newest first',
  ),
  downloads(
    icon: Iconsax.arrow_down_2,
    title: 'Downloads',
    description: 'The queue, and what it is using on disk',
  ),
  settings(
    icon: Iconsax.setting_2,
    title: 'Settings',
    description: 'Appearance, reader defaults, sources',
  ),
  about(
    icon: Iconsax.info_circle,
    title: 'About',
    description: 'Version, licences and credits',
  );

  const _Destination({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  Widget build() => switch (this) {
    _Destination.history => const HistoryScreen(),
    _Destination.downloads => const DownloadsScreen(),
    _Destination.settings => const SettingsScreen(),
    _Destination.about => const AboutScreen(),
  };
}

class _Card extends StatelessWidget {
  const _Card({required this.destination});

  final _Destination destination;

  @override
  Widget build(BuildContext context) => ChromeFeatureCard(
    icon: destination.icon,
    title: destination.title,
    description: destination.description,
    onTap: () =>
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => destination.build())),
  );
}
