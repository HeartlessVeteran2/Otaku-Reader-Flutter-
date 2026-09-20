// Derived from AnymeX (https://github.com/RyanYuuki/AnymeX),
// MIT License, Copyright (c) 2024 Ryan _.
// See NOTICE and licenses/AnymeX-MIT.txt for the permission notice that
// licence requires to travel with these portions.

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:otaku_reader/core/util/open_link.dart';
import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';

/// Version, licences and credits.
///
/// AnymeX's equivalent (`settings_about.dart`) leads with a hero **card**
/// rather than a bare centred icon, which is the shape taken here. What is
/// deliberately not taken is its `Stack(clipBehavior: Clip.none)` overlapping
/// the logo across the card's top edge: that hangs a fixed 40px offset off a
/// card whose height is entirely text, and this app has already recorded two
/// separate defects from a parent forcing a size onto a child that could not
/// meet it. The logo sits inside the card.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  /// Read from the built package rather than from a constant, so a release
  /// build cannot report a version the source tree merely used to have.
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ChromeScaffold.slivers(
      title: 'About',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Chrome.gutter,
              Chrome.gap,
              Chrome.gutter,
              0,
            ),
            child: ChromeCard(
              padding: const EdgeInsets.symmetric(
                horizontal: Chrome.gutter,
                vertical: Chrome.sectionGap,
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        context.radius(Chrome.cardRadius),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Icon(
                        Iconsax.book_saved,
                        size: 40,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Otaku Reader',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  FutureBuilder<PackageInfo>(
                    future: _info,
                    builder: (context, snapshot) {
                      final info = snapshot.data;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          // Blank rather than "unknown" while it resolves: a
                          // version that flickers from a wrong value to a
                          // right one is worse than one that appears a frame
                          // late.
                          info == null
                              ? ''
                              : 'Version ${info.version} (${info.buildNumber})',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverChromeSection(
          label: 'This app',
          children: [
            ChromeTile(
              icon: Iconsax.code,
              title: 'Source code',
              subtitle: 'github.com/HeartlessVeteran2/Otaku-Reader-Flutter-',
              onTap: () => openLink(
                context,
                'https://github.com/HeartlessVeteran2/Otaku-Reader-Flutter-',
              ),
            ),
            ChromeTile(
              icon: Iconsax.message_question,
              title: 'Report a problem',
              subtitle: 'Open an issue',
              onTap: () => openLink(
                context,
                'https://github.com/HeartlessVeteran2/Otaku-Reader-Flutter-/issues/new/choose',
              ),
            ),
            ChromeTile(
              icon: Iconsax.document_text,
              title: 'Open-source licences',
              onTap: () async {
                final info = await _info;
                if (!context.mounted) return;
                showLicensePage(
                  context: context,
                  applicationName: 'Otaku Reader',
                  applicationVersion: info.version,
                );
              },
            ),
          ],
        ),
        SliverChromeSection(
          label: 'Built on',
          children: [
            ChromeTile(
              icon: Iconsax.hierarchy,
              title: 'Mangayomi extensions',
              subtitle:
                  'Sources are published by the Mangayomi ecosystem and run '
                  'unmodified. Apache-2.0.',
              onTap: () =>
                  openLink(context, 'https://github.com/kodjodevf/mangayomi'),
            ),
            ChromeTile(
              icon: Iconsax.star,
              title: 'AniList',
              subtitle: 'Metadata, recommendations and the home page shelves.',
              onTap: () => openLink(context, 'https://anilist.co'),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Chrome.gutter * 2,
              Chrome.sectionGap,
              Chrome.gutter * 2,
              Chrome.sectionGap,
            ),
            child: Text(
              'Otaku Reader does not host any manga. Everything it shows '
              'comes from the sources you choose to install.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
