import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/features/reader/display/reader_display.dart';
import 'package:otaku_reader/features/reader/display/reader_display_layer.dart';
import 'package:otaku_reader/features/reader/display/reader_display_settings.dart';

/// Picking the tint and the blend mode the reader lays over a page.
///
/// Ported from AnymeX's `color_filter_settings_page.dart`: four 0-255 channel
/// sliders, and its sixteen blend modes. What is added is a **preview**, which
/// AnymeX has none of — sixteen blend modes against an arbitrary ARGB colour is
/// not something anyone can hold in their head, and without a preview the
/// screen is a set of numbers whose only feedback loop is leaving, opening a
/// chapter, and coming back.
class ColourFilterScreen extends StatefulWidget {
  const ColourFilterScreen({super.key});

  @override
  State<ColourFilterScreen> createState() => _ColourFilterScreenState();
}

class _ColourFilterScreenState extends State<ColourFilterScreen> {
  late int _argb = ReaderDisplaySettings.filterColor;
  late ReaderBlend _blend = ReaderDisplaySettings.filterBlend;

  Color get _colour => Color(_argb);

  void _setChannel(int shift, double value) {
    final byte = value.round().clamp(0, 255);
    setState(() {
      _argb = (_argb & ~(0xFF << shift)) | (byte << shift);
      ReaderDisplaySettings.setFilterColor(_argb);
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ReaderDisplaySettings.filterEnabled;
    return ChromeScaffold.slivers(
      title: 'Colour filter',
      slivers: [
        SliverChromeSection(
          children: [
            // The same getter the reader and the Settings row read. A second
            // default declared here is how a switch comes to show the opposite
            // of what the reader does.
            ChromeTile.toggle(
              icon: Iconsax.colorfilter,
              title: 'Colour filter',
              subtitle: enabled
                  ? 'The tint below is laid over every page'
                  : 'Pages render untinted',
              value: enabled,
              onChanged: (v) =>
                  setState(() => ReaderDisplaySettings.setFilterEnabled(v)),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: IgnorePointer(
            ignoring: !enabled,
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.4,
              duration: Chrome.duration,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Chrome.gutter,
                  Chrome.sectionGap,
                  Chrome.gutter,
                  0,
                ),
                child: _Preview(colour: _colour, blend: _blend),
              ),
            ),
          ),
        ),
        SliverChromeSection(
          label: 'Tint',
          children: [
            for (final (shift, name, icon) in const [
              (16, 'Red', Iconsax.record),
              (8, 'Green', Iconsax.record),
              (0, 'Blue', Iconsax.record),
              (24, 'Strength', Iconsax.drop),
            ])
              ChromeTile.slider(
                icon: icon,
                // "Strength" rather than "Alpha", which names the
                // implementation. It is how much of the tint reaches the page,
                // and that is what the reader is choosing.
                title: name,
                value: ((_argb >> shift) & 0xFF).toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                valueLabel: '${(_argb >> shift) & 0xFF}',
                enabled: enabled,
                onChanged: (v) => _setChannel(shift, v),
              ),
          ],
        ),
        SliverChromeSection(
          label: 'How it mixes',
          children: [
            for (final blend in ReaderBlend.values)
              ChromeTile(
                icon: blend == _blend ? Iconsax.tick_circle : Iconsax.record,
                title: blend.label,
                showChevron: false,
                enabled: enabled,
                iconColor: blend == _blend
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onTap: () => setState(() {
                  _blend = blend;
                  ReaderDisplaySettings.setFilterBlend(blend);
                }),
              ),
          ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Chrome.sectionGap)),
      ],
    );
  }
}

/// A stand-in page, under the live filter.
///
/// Deliberately not a real page: a preview that loads artwork is a preview that
/// can fail, and the thing being judged is what the tint does to light and dark
/// areas rather than to any particular panel. Three bands plus text cover what
/// a reader actually looks at.
class _Preview extends StatelessWidget {
  const _Preview({required this.colour, required this.blend});

  final Color colour;
  final ReaderBlend blend;

  @override
  Widget build(BuildContext context) {
    final radius = context.radius(Chrome.cardRadius);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: 120,
        child: ReaderDisplayLayer(
          greyscale: ReaderDisplaySettings.greyscale,
          invert: ReaderDisplaySettings.invert,
          filter: colour,
          blend: blend,
          child: Row(
            children: [
              for (final shade in const [
                Colors.white,
                Color(0xFF9E9E9E),
                Colors.black,
              ])
                Expanded(
                  child: ColoredBox(
                    color: shade,
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
