import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import 'package:otaku_reader/core/database/data_keys/keys.dart';
import 'package:otaku_reader/core/database/kv_helper.dart';
import 'package:otaku_reader/core/theme/chrome_metrics.dart';
import 'package:otaku_reader/core/widgets/chrome.dart';
import 'package:otaku_reader/features/reader/controllers/reader_controller.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone.dart';
import 'package:otaku_reader/features/reader/tap_zones/tap_zone_settings.dart';

/// The smallest share of the axis a band may be given.
///
/// Not a taste number. A band of zero is unreachable — a dead zone — and that
/// is the exact failure the band geometry was chosen to make impossible, so
/// letting a slider author one would hand it back in the editor. At 360px this
/// is 18px, which is a thin strip rather than a button, but a band is a share
/// of a page the user chose rather than a control they have to hit.
const kMinBandFraction = 0.05;

/// How far a boundary moves in one step.
///
/// A **step**, not a division count, and the difference is the whole of a bug
/// `codeant-ai` caught. `Slider.divisions` divides that slider's own
/// `max - min`, not the axis — and these bounds are dynamic, because each
/// boundary is fenced in by its neighbours. So a fixed 20 divisions gave the
/// standard profile a **3%** step, and moving the second boundary to 0.5
/// changed the first slider's step to **2%**: not merely off the intended
/// grid, but not constant either, while five documents and a test all called
/// it a 5% grid.
///
/// Divisions are computed from this instead, and [_cutSlider] snaps as well,
/// so every value a boundary can take is a multiple of 5% whatever profile is
/// stored — an imported or hand-edited row is pulled onto the grid the first
/// time it is touched rather than carrying its offset forever.
///
/// With the grid real, the measurement holds: over all 171 reachable pairs,
/// 169 sum to *exactly* 1.0 with a worst error of 1.1e-16 — thirteen orders of
/// magnitude inside [TapZoneProfile.tolerance].
const kBandStep = 0.05;

/// The most of the viewport the band preview may take.
///
/// Measured rather than chosen: at 9/16 across a 390px phone an uncapped
/// preview is 636px tall, so the header, the switch and the preview fill a
/// 844px screen on their own and every boundary slider starts below the fold.
/// A preview you cannot see while dragging the boundary that moves it is the
/// one thing this screen exists to show.
const kPreviewHeightShare = 0.45;

/// Assigning actions to the reader's tap bands, and moving the boundaries
/// between them.
///
/// Ported from AnymeX's `TapZoneSettingsScreen` with three corrections, each
/// measured in its source rather than assumed:
///
/// 1. **AnymeX applies the profile the user last *looked at*, not the one they
///    are *reading* in.** The only writers of `activeTapIsWebtoon` and
///    `activeTapIsVertical` are its two segmented controls on this screen, plus
///    a read-back when the reader starts — nothing derives them from the live
///    reading mode. So reading in webtoon after last opening the "Paged" tab
///    makes the left third fire `prevPage` in a vertical reader. Here the
///    selector chooses only **which profile is being edited**; the reader picks
///    its own from `layout`, and this screen writes no reader state at all.
/// 2. **`_GridPainter.shouldRepaint` returns `false` unconditionally**, so its
///    backdrop keeps its old colour across a light/dark switch. Fixed below.
/// 3. **`_ElegantSegmentedControl` is a fourth segmented control** in an app
///    that has three. This uses [SegmentedTabs] — the one whose segments are
///    `1 / total` of the width by construction, which is the whole reason the
///    Material `TabBar` was replaced.
class TapZoneEditorScreen extends StatefulWidget {
  const TapZoneEditorScreen({super.key});

  @override
  State<TapZoneEditorScreen> createState() => _TapZoneEditorScreenState();
}

class _TapZoneEditorScreenState extends State<TapZoneEditorScreen> {
  /// Which profile is on screen — *not* which layout the reader uses.
  ReadingLayout _editing = ReadingLayout.paged;

  late TapZoneProfile _paged = TapZoneSettings.profileFor(ReadingLayout.paged);
  late TapZoneProfile _continuous = TapZoneSettings.profileFor(
    ReadingLayout.webtoon,
  );

  TapZoneProfile get _profile =>
      _editing == ReadingLayout.webtoon ? _continuous : _paged;

  /// The direction the reader will actually measure this profile along.
  ///
  /// Read from the same key the reader reads, so the preview's axis and its
  /// leading edge are the ones a tap will meet. A preview that always drew
  /// left-to-right would show the opposite of the reader's behaviour for every
  /// right-to-left manga — which is the `ReaderDefaults` defect (a switch and
  /// the thing it controls disagreeing while each file is self-consistent) in
  /// the one screen whose entire job is to show what a tap does.
  ReadingDirection get _direction {
    final key = _editing == ReadingLayout.webtoon
        ? ReaderKeys.webtoonDirection
        : ReaderKeys.readingDirection;
    final fallback = _editing == ReadingLayout.webtoon
        ? ReadingDirection.topToBottom
        : ReadingDirection.leftToRight;
    return ReadingDirection.values[key
        .get<int>(fallback.index)
        .clamp(0, ReadingDirection.values.length - 1)];
  }

  /// Whether band 0 is painted at the far edge rather than the near one.
  ///
  /// The reader measures a tap from the **leading** edge, mirroring the
  /// position when the direction is reversed and the setting allows it. The
  /// preview has to mirror with it or it is drawing a different reader.
  bool get _mirrored =>
      _direction.reversed && TapZoneSettings.mirrorWhenReversed;

  void _write(TapZoneProfile profile) {
    // Refused profiles are impossible from here — the sliders move cut points,
    // so the fractions sum to 1 by construction — but the writer reports, so
    // the screen would rather not update than show bands it failed to store.
    if (!TapZoneSettings.setProfileFor(_editing, profile)) return;
    setState(() {
      if (_editing == ReadingLayout.webtoon) {
        _continuous = profile;
      } else {
        _paged = profile;
      }
    });
  }

  void _reset() {
    TapZoneSettings.resetProfileFor(_editing);
    setState(() {
      final fresh = TapZoneSettings.profileFor(_editing);
      if (_editing == ReadingLayout.webtoon) {
        _continuous = fresh;
      } else {
        _paged = fresh;
      }
    });
  }

  Future<void> _pickAction(int index) async {
    final chosen = await showModalBottomSheet<ReaderAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ActionSheet(current: _profile.bands[index].action),
    );
    if (chosen == null || !mounted) return;
    _write(_profile.withActionAt(index, chosen));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = TapZoneSettings.enabled;
    return ChromeScaffold.slivers(
      title: 'Tap zones',
      actions: [
        IconButton(
          onPressed: _reset,
          icon: const Icon(Iconsax.refresh, size: 20),
          tooltip: 'Reset to the standard bands',
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(Chrome.tabBarHeight),
        child: SegmentedTabs(
          selectedIndex: _editing == ReadingLayout.webtoon ? 1 : 0,
          // Writes nothing but this screen's own state. See the class doc:
          // AnymeX persists the equivalent flag and the *reader* then reads it,
          // which is how looking at a tab changes how a chapter behaves.
          onSelected: (i) => setState(
            () =>
                _editing = i == 1 ? ReadingLayout.webtoon : ReadingLayout.paged,
          ),
          tabs: const [Text('Paged'), Text('Continuous')],
        ),
      ),
      slivers: [
        SliverChromeSection(
          children: [
            // The same getter and setter the Settings row uses, so the two
            // cannot disagree. A second default declared here is how a switch
            // comes to show the opposite of what the reader does.
            ChromeTile.toggle(
              icon: Iconsax.mouse_circle,
              title: 'Tap zones',
              subtitle: enabled
                  ? 'Tapping the page runs the band it lands in'
                  : 'Any tap shows or hides the controls',
              value: enabled,
              onChanged: (v) => setState(() => TapZoneSettings.setEnabled(v)),
            ),
          ],
        ),
        SliverToBoxAdapter(
          // AnymeX's shape for the disabled state, and a good one: the editor
          // stays visible and legible rather than vanishing, so the screen
          // still explains what the switch above it turns on.
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
                child: _BandPreview(
                  profile: _profile,
                  axis: _direction.axis,
                  mirrored: _mirrored,
                  onTapBand: _pickAction,
                ),
              ),
            ),
          ),
        ),
        SliverChromeSection(
          label: 'Boundaries',
          children: [
            for (var i = 0; i < _profile.cuts.length; i++)
              _cutSlider(i, enabled: enabled),
          ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: Chrome.sectionGap)),
      ],
    );
  }

  /// One slider per boundary, bounded by its neighbours.
  ///
  /// The bounds are what make the sum-to-one invariant structural: a cut can
  /// never pass the one before or after it, so no band can be squeezed below
  /// [kMinBandFraction] and none can be inverted. Three band-width sliders
  /// would each need the others rewritten after every drag, and which one gave
  /// way would be a policy nobody chose.
  Widget _cutSlider(int index, {required bool enabled}) {
    final cuts = _profile.cuts;
    final bands = _profile.bands;
    final lower = (index == 0 ? 0.0 : cuts[index - 1]) + kMinBandFraction;
    final upper =
        (index == cuts.length - 1 ? 1.0 : cuts[index + 1]) - kMinBandFraction;
    final before = bands[index].action.label;
    final after = bands[index + 1].action.label;
    return ChromeTile.slider(
      icon: Iconsax.ruler,
      title: '$before / $after',
      subtitle:
          '${_percent(bands[index].fraction)} then '
          '${_percent(bands[index + 1].fraction)}',
      valueLabel: _percent(cuts[index]),
      value: cuts[index],
      // A boundary pinned against both neighbours has nowhere to go, and a
      // Slider whose min equals its max throws. Widening the range instead
      // would let it author a band under the minimum, so the row goes inert —
      // visibly, through the same `enabled` path the switch uses.
      min: lower,
      max: upper > lower ? upper : lower + kMinBandFraction,
      // From the range, so the step is `kBandStep` rather than a share of
      // whatever room this boundary happens to have between its neighbours.
      divisions:
          (((upper > lower ? upper : lower + kMinBandFraction) - lower) /
                  kBandStep)
              .round()
              .clamp(1, 1000),
      enabled: enabled && upper > lower,
      onChanged: (v) {
        // Snapped here too, not only through `divisions`. Divisions alone put a
        // value on the grid only when the range already starts on it, so a
        // profile restored or imported off-grid would keep its offset for
        // every edit that followed.
        final snapped = (v / kBandStep).round() * kBandStep;
        final next = [...cuts]..[index] = snapped.clamp(lower, upper);
        _write(_profile.withCuts(next));
      },
    );
  }

  static String _percent(double fraction) => '${(fraction * 100).round()}%';
}

/// The bands, drawn along the axis they will be measured on.
///
/// Ported from AnymeX's `VisualZoneEditor`: a phone-shaped box, each zone a
/// translucent primary-tinted card carrying its action's name, tap to change
/// it. What changes is the geometry it draws — one axis divided into shares
/// rather than free-form rectangles — and that it mirrors when the reader will.
class _BandPreview extends StatelessWidget {
  const _BandPreview({
    required this.profile,
    required this.axis,
    required this.mirrored,
    required this.onTapBand,
  });

  final TapZoneProfile profile;
  final Axis axis;
  final bool mirrored;
  final ValueChanged<int> onTapBand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bands = [
      for (var i = 0; i < profile.bands.length; i++)
        Flexible(
          // `flex` is an int, so the shares are taken at permille — enough to
          // separate any two cuts the editor can author, which are multiples of
          // 5%. Rounding to whole percent would collapse two distinct bands
          // only below the minimum, but permille costs nothing and removes the
          // question.
          flex: (profile.bands[i].fraction * 1000).round().clamp(1, 1000),
          child: _Band(index: i, band: profile.bands[i], onTap: onTapBand),
        ),
    ];
    // Page-shaped, as AnymeX's is -- but **capped**, which AnymeX does not need
    // to do because its editor is nothing but the preview. At 9/16 across a
    // 390px phone the box alone is 636px tall, which puts every boundary slider
    // below the fold: the two halves of this screen could never be seen at
    // once, so you would be dragging a boundary with the bands it moves off
    // screen. The cap is a share of the viewport rather than a constant so it
    // holds on a tablet and on a split screen alike.
    final viewport = MediaQuery.sizeOf(context).height;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          // Guarded, because a cap of zero does not shrink the preview -- it
          // **erases** it, with no exception and nothing in a diff to say so,
          // which is the one defect class `CLAUDE.md` says a shared vocabulary
          // must not have. A viewport with no height is not reachable on a
          // device, but it is one `MediaQuery` override away in a test, and
          // that is exactly how a guard comes to be asserted against a screen
          // that was never laid out.
          maxHeight: viewport > 0
              ? viewport * kPreviewHeightShare
              : double.infinity,
        ),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              context.radius(Chrome.cardRadius),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.2),
                ),
                borderRadius: BorderRadius.circular(
                  context.radius(Chrome.cardRadius),
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _GridPainter(
                        color: scheme.outline.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  Flex(
                    direction: axis,
                    // The reader measures from the leading edge, so band 0 is
                    // painted at whichever edge that is. `reverse` on a `Flex` is
                    // spelled as a reversed child list, which is the same thing
                    // without a scroll view's baggage.
                    children: mirrored ? bands.reversed.toList() : bands,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Band extends StatelessWidget {
  const _Band({required this.index, required this.band, required this.onTap});

  final int index;
  final TapBand band;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inert = band.action == ReaderAction.none;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(
            alpha: inert ? 0.03 : 0.1,
          ),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
          borderRadius: BorderRadius.circular(
            context.radius(Chrome.leadingRadius),
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              band.action.label,
              textAlign: TextAlign.center,
              // Uncapped, per `CLAUDE.md`: the four caps that remain are layout
              // invariants, and this is a label inside a box whose size the
              // user is setting. A band squeezed narrow should wrap and stay
              // readable rather than silently lose the end of its own name.
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// AnymeX's backdrop grid, with its repaint bug fixed.
///
/// Its `shouldRepaint` returns `false` unconditionally, so the grid keeps the
/// colour it was first painted with across a light/dark switch — a dark grid
/// left on a light surface, and nothing in the diff to say so.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.color});

  final Color color;

  static const _spacing = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += _spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += _spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.color != color;
}

/// Every action, unfiltered.
///
/// AnymeX filters this list per mode — hiding `nextPage`/`prevPage` in webtoon
/// and `scrollUp`/`scrollDown` in paged — and that filter is load-bearing
/// there, because an action the layout cannot perform is a dead zone with
/// nothing to say so. Six axis-free actions leave nothing to filter, which is
/// the whole argument for collapsing the eight, and this sheet is where that
/// shows up as an absence.
class _ActionSheet extends StatelessWidget {
  const _ActionSheet({required this.current});

  final ReaderAction current;

  static IconData _icon(ReaderAction action) => switch (action) {
    ReaderAction.next => Iconsax.arrow_right_3,
    ReaderAction.previous => Iconsax.arrow_left_2,
    ReaderAction.nextChapter => Iconsax.next,
    ReaderAction.previousChapter => Iconsax.previous,
    ReaderAction.toggleChrome => Iconsax.eye,
    ReaderAction.none => Iconsax.slash,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Chrome.gap),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Chrome.gutter * 2,
              0,
              Chrome.gutter * 2,
              Chrome.gap,
            ),
            child: Text(
              'What this band does',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final action in ReaderAction.values)
            ListTile(
              leading: Icon(
                _icon(action),
                color: action == current
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(action.label),
              trailing: action == current
                  ? Icon(Iconsax.tick_circle, color: theme.colorScheme.primary)
                  : null,
              selected: action == current,
              onTap: () => Navigator.of(context).pop(action),
            ),
        ],
      ),
    );
  }
}
