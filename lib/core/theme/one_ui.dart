import 'package:flutter/material.dart';

/// The house style: One UI's shapes and rhythm over AnymeX's layout.
///
/// AnymeX decides what is on a screen and in what order; this decides how it
/// looks and where the user's thumb goes. Every number here is a decision, not
/// a default — see `CLAUDE.md`, "The visual language".
abstract final class OneUi {
  /// The corner radius shared by cards, sheets and grouped lists.
  ///
  /// Large enough to read as One UI rather than as Material's default 12. It is
  /// the most recognisable tell after the collapsing header, so it is one
  /// number used everywhere rather than a per-widget choice.
  static const radius = 26.0;

  /// The radius for something small enough that [radius] would swallow it —
  /// a chip, a thumbnail, a progress bar.
  static const radiusSmall = 14.0;

  /// Space between rows inside a group.
  static const gap = 8.0;

  /// Space between one group and the next.
  ///
  /// One UI breathes: this is deliberately more than Material's 8-12. A
  /// screen that looks slightly too airy on a desk looks right in a hand.
  static const sectionGap = 24.0;

  /// The side gutter. Groups inset from the screen edge rather than running
  /// to it, which is what makes them read as cards.
  static const gutter = 16.0;

  /// How tall a large header stands before it collapses.
  ///
  /// Not decoration: it pushes the first row of content into the lower half of
  /// a tall phone, which is the part a thumb reaches without a regrip.
  static const headerHeight = 152.0;

  /// Motion. Short and eased, never bouncy — a spring reads as playful, and
  /// this is a reading app.
  static const duration = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;
}

/// A screen with One UI's collapsing header.
///
/// The title starts oversized in the top half and shrinks into the app bar as
/// the content scrolls — **when there is content to scroll**. A screen whose
/// rows fit the viewport keeps its large title: `maxScrollExtent` is content
/// minus viewport, so on a four-row screen it is 0 and nothing moves. That is
/// One UI's own behaviour rather than a shortfall, and `test/one_ui_test.dart`
/// pins both halves — a long screen collapses, a short one does not. Asserting
/// only that a drag throws nothing passes on a screen that cannot move at all.
///
/// [slivers] is a sliver slot, so **every entry must produce a `RenderSliver`**
/// — use [SliverOneUiGroup] for grouped rows, `SliverList`/`SliverGrid` for
/// anything long, and wrap a plain widget in a `SliverToBoxAdapter`. Putting a
/// box widget here — [OneUiGroup] itself, a `Column`, a `Padding` — compiles
/// and analyses clean, because the declared type is `Widget` either way, and
/// throws during layout on the device. `test/one_ui_test.dart` renders every
/// screen that uses this for exactly that reason.
class OneUiScaffold extends StatelessWidget {
  const OneUiScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.bottom,
    this.onRefresh,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;

  /// A search field or a tab bar pinned under the title.
  final PreferredSizeWidget? bottom;

  /// When set, the body is wrapped in a [RefreshIndicator].
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final view = CustomScrollView(
      // The documented pairing for `RefreshIndicator`: its child has to accept
      // the drag, and a list that fits the screen otherwise need not.
      //
      // Stated precisely, because the obvious experiment does not settle it:
      // `pull-to-refresh fires on a Downloads list that fits` passes with this
      // line deleted, so the widget tester accepts the fling either way. That
      // is not evidence the line is dead — it is evidence this environment
      // cannot tell, and device physics (iOS bouncing in particular) differ.
      // Kept as the idiom, scoped to the refresh path because off it there is
      // nothing it could do: with clamping physics a short screen's `pixels`
      // stays pinned at 0 through a drag regardless, and it does **not** make
      // a short header collapse.
      physics: onRefresh == null ? null : const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar.large(
          title: Text(title),
          leading: leading,
          actions: actions,
          bottom: bottom,
          expandedHeight: OneUi.headerHeight,
          // Elevation as a colour step, not a shadow. The bar has to differ
          // from the body once content slides under it, and a drop shadow
          // under a rounded group reads as grime.
          backgroundColor: scheme.surface,
          surfaceTintColor: scheme.surfaceTint,
        ),
        ...slivers,
        // Clears the gesture bar, so the last row is not the thing a
        // back-swipe grabs.
        const SliverToBoxAdapter(child: SizedBox(height: OneUi.sectionGap * 2)),
      ],
    );
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: onRefresh == null
          ? view
          : RefreshIndicator(onRefresh: onRefresh!, child: view),
    );
  }
}

/// A labelled, rounded group of rows — One UI's replacement for a flat
/// divider-separated list.
///
/// The label sits *above* the container in the accent colour rather than
/// inside it as a header row, which is what separates this from a Material
/// `ListTile` section.
///
/// This is a **box** widget. Inside an [OneUiScaffold] use [SliverOneUiGroup];
/// this one is for an ordinary `ListView` or `Column`.
class OneUiGroup extends StatelessWidget {
  const OneUiGroup({
    super.key,
    this.label,
    required this.children,
    this.padding,
  });

  final String? label;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            OneUi.gutter,
            OneUi.sectionGap,
            OneUi.gutter,
            0,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                OneUi.gutter,
                0,
                OneUi.gutter,
                OneUi.gap,
              ),
              child: Text(
                label!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          // Clipped rather than given a shape on each child: a row can then be
          // any widget — a switch, a slider, a whole sub-list — and still get
          // the group's corners without knowing it is in a group.
          ClipRRect(
            borderRadius: BorderRadius.circular(OneUi.radius),
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// [OneUiGroup] as a sliver — the form to use inside [OneUiScaffold.slivers].
class SliverOneUiGroup extends StatelessWidget {
  const SliverOneUiGroup({super.key, this.label, required this.children});

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: OneUiGroup(label: label, children: children),
  );
}
