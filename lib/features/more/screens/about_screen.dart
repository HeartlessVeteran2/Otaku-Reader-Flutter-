import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:otaku_reader/core/theme/one_ui.dart';
import 'package:otaku_reader/core/util/open_link.dart';

/// Version, licences and credits.
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
    return OneUiScaffold(
      title: 'About',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: OneUi.gap, bottom: OneUi.gap),
            child: Column(
              children: [
                Icon(
                  Iconsax.book_saved,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text('Otaku Reader', style: theme.textTheme.titleLarge),
                FutureBuilder<PackageInfo>(
                  future: _info,
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        // Blank rather than "unknown" while it resolves: a
                        // version that flickers from a wrong value to a right
                        // one is worse than one that appears a frame late.
                        info == null
                            ? ''
                            : 'Version ${info.version} (${info.buildNumber})',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        SliverOneUiGroup(
          label: 'This app',
          children: [
            ListTile(
              leading: const Icon(Iconsax.code),
              title: const Text('Source code'),
              subtitle: const Text(
                'github.com/HeartlessVeteran2/Otaku-Reader-Flutter-',
              ),
              onTap: () => openLink(
                context,
                'https://github.com/HeartlessVeteran2/Otaku-Reader-Flutter-',
              ),
            ),
            ListTile(
              leading: const Icon(Iconsax.message_question),
              title: const Text('Report a problem'),
              subtitle: const Text('Open an issue'),
              onTap: () => openLink(
                context,
                'https://github.com/HeartlessVeteran2/Otaku-Reader-Flutter-/issues/new/choose',
              ),
            ),
            ListTile(
              leading: const Icon(Iconsax.document_text),
              title: const Text('Open-source licences'),
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
        SliverOneUiGroup(
          label: 'Built on',
          children: [
            ListTile(
              leading: const Icon(Iconsax.hierarchy),
              title: const Text('Mangayomi extensions'),
              subtitle: const Text(
                'Sources are published by the Mangayomi ecosystem and run '
                'unmodified. Apache-2.0.',
              ),
              onTap: () =>
                  openLink(context, 'https://github.com/kodjodevf/mangayomi'),
            ),
            ListTile(
              leading: const Icon(Iconsax.star),
              title: const Text('AniList'),
              subtitle: const Text(
                'Metadata, recommendations and the home page shelves.',
              ),
              onTap: () => openLink(context, 'https://anilist.co'),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              OneUi.gutter * 2,
              OneUi.sectionGap,
              OneUi.gutter * 2,
              0,
            ),
            child: Text(
              'Otaku Reader does not host any manga. Everything it shows '
              'comes from the sources you choose to install.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
