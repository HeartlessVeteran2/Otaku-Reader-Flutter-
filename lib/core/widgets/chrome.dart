import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// AnymeX's chrome: floating pills, segmented tabs and card rows.
///
/// Ported from `/home/user/AnymeX-HV`, which is checked out in every session
/// and now decides both halves of the house style — see `CLAUDE.md`, "The
/// visual language". It replaces the collapsing `SliverAppBar.large` that
/// phase 7 put on eight screens; the developer reversed that decision, and the
/// reversal is recorded there with its history so this is not re-litigated per
/// screen.
///
/// The shapes, and the file each came from:
///
/// | here | AnymeX |
/// |---|---|
/// | [ChromeScaffold] | `widgets/common/anymex_scaffold.dart` (`_HeaderBodyShell`) |
/// | [PillHeader] | `widgets/anymex_widgets/anymex_header.dart` |
/// | [SegmentedTabs] | `widgets/anymex_widgets/anymex_tabbar.dart` |
/// | [ChromeCard] | `widgets/anymex_widgets/anymex_container.dart` |
/// | [ChromeTile] | `widgets/anymex_widgets/anymex_tile.dart` |
abstract final class Chrome {
  /// The header pills. Large enough to read as a capsule rather than a
  /// rounded rectangle, which is the difference between this and a bar.
  static const pillRadius = 30.0;

  /// Cards and sheets.
  static const cardRadius = 18.0;

  /// The 36x36 tinted square behind a row's leading icon, and anything else
  /// small enough that [cardRadius] would swallow it.
  static const leadingRadius = 10.0;

  static const leadingSize = 36.0;

  /// The selected segment inside [SegmentedTabs], and the track around it.
  static const segmentRadius = 12.0;
  static const tabBarRadius = 16.0;

  /// How hard the pills blur what scrolls under them.
  static const blur = 16.0;

  /// Side gutter, row-to-row gap, section-to-section gap.
  ///
  /// The rhythm is the one thing phase 7 got right that survived the
  /// reversal: generous, because a screen that looks slightly too airy on a
  /// desk looks right in a hand.
  static const gutter = 16.0;
  static const gap = 8.0;
  static const sectionGap = 20.0;

  /// A header action, and **Material's 48px minimum** rather than the 40 the
  /// pill would look tidier at.
  ///
  /// The pill gives each action a fixed box, so this is the whole touch
  /// target: two actions sit flush against each other and the pill's 4px
  /// padding is outside their hit areas, so it adds nothing to the one in the
  /// middle. An earlier 40 here shrank every header action below the platform
  /// minimum, under a comment claiming the padding made up the difference —
  /// which it does not. Found by `codeant-ai`.
  static const actionSize = 48.0;

  static const tabBarHeight = 46.0;

  /// Motion: short and eased, never bouncy. [headerSlide] is longer because it
  /// moves the whole header off screen, where the shorter curve reads as a
  /// flicker.
  static const duration = Duration(milliseconds: 300);
  static const curve = Curves.easeOutCubic;
  static const headerSlide = Duration(milliseconds: 450);

  /// The pill's own padding and hairline. The estimate below has to account
  /// for both, and nothing else should hardcode either.
  static const pillPadding = 4.0;
  static const pillBorder = 0.5;

  /// A **first-frame estimate** of the height [PillHeader] will occupy,
  /// including the status bar it sits under.
  ///
  /// [ChromeScaffold] measures the header it actually built and uses that
  /// from the next frame on, so this only has to be close, not right. That
  /// split is the point: every version of this that was arithmetic alone
  /// turned out to be wrong about something it could not see — a caller
  /// passing an `IconButton` at Material's 48px minimum rather than
  /// [actionSize], a `TextField`'s own metrics in the search row, the line
  /// height the engine rounds a scaled font to. CLAUDE.md already carries one
  /// of these: the webtoon page index was arithmetic where it should have been
  /// measurement, and it marked chapters read several pages early.
  ///
  /// AnymeX hardcodes 64 (80 with a subtitle), which is right at the default
  /// text scale and wrong at every other.
  static double headerHeight(
    BuildContext context, {
    bool hasSubtitle = false,
    bool hasActions = false,
    double bottomHeight = 0,
  }) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = bottomHeight > 0 ? gap + bottomHeight : 0.0;
    final pill = pillHeight(
      context,
      hasSubtitle: hasSubtitle,
      hasActions: hasActions,
    );
    return top + gap + pill + bottom + gap;
  }

  /// The estimated height of one header pill.
  static double pillHeight(
    BuildContext context, {
    bool hasSubtitle = false,
    bool hasActions = false,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    // 1.3 is the line height these two styles are rendered at below, rounded
    // the way the engine rounds a laid-out line box.
    final title = (scaler.scale(16) * 1.3).roundToDouble();
    final subtitle = hasSubtitle
        ? 2 + (scaler.scale(11) * 1.3).roundToDouble()
        : 0.0;
    // The actions pill is the taller of the two at ordinary font sizes, and
    // the shorter one once the title has been scaled up.
    final content = hasActions
        ? math.max(actionSize, title + subtitle)
        : title + subtitle;
    return content + pillPadding * 2 + pillBorder * 2;
  }
}

/// Reports its child's height once the frame that laid it out is done.
///
/// Reporting *during* layout would re-enter it, so the callback is deferred to
/// the end of the frame and lands as an ordinary rebuild.
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onChange, required Widget super.child});

  final ValueChanged<double> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureHeight(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasureHeight renderObject,
  ) => renderObject.onChange = onChange;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onChange);

  ValueChanged<double> onChange;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onChange(height));
  }
}

class ChromeHeaderScope extends InheritedWidget {
  const ChromeHeaderScope({
    super.key,
    required this.height,
    required super.child,
  });

  final double height;

  /// Zero when there is no header above, so a converted row dropped into a
  /// sheet or a dialog still lays out.
  ///
  /// That fallback is also the trap, and it has already caught this repo once:
  /// a `State`'s own `context` sits *above* the [ChromeScaffold] it builds, so
  /// reading the scope from it finds nothing and gets 0 — correct for a widget
  /// with no header and silently wrong for a body that has one. Read it from a
  /// `Builder` inside the body, never from `State.context`.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChromeHeaderScope>()?.height ??
      0;

  /// [of] as padding, for a scroll view's `padding:`.
  static EdgeInsets padding(BuildContext context) =>
      EdgeInsets.only(top: of(context));

  @override
  bool updateShouldNotify(ChromeHeaderScope oldWidget) =>
      height != oldWidget.height;
}

/// A screen whose header is two floating pills over the content.
///
/// The header hides as the content scrolls down and comes back on the way up,
/// which is what buys back the height the collapsing header used to spend
/// permanently.
class ChromeScaffold extends StatefulWidget {
  const ChromeScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions,
    this.bottom,
    this.floatingActionButton,
    this.enableSearch = false,
    this.searchController,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onSearchClear,
    this.searchHint = 'Search',
  });

  /// The form to use for a screen that is one scroll view.
  ///
  /// The header gap is inserted as the first sliver, so the caller cannot
  /// leave its first row under the pills. [onRefresh] wraps the view in a
  /// `RefreshIndicator` with the physics that make a short list pullable.
  factory ChromeScaffold.slivers({
    Key? key,
    required String title,
    required List<Widget> slivers,
    String? subtitle,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
    Widget? floatingActionButton,
    Future<void> Function()? onRefresh,
    bool enableSearch = false,
    TextEditingController? searchController,
    ValueChanged<String>? onSearchChanged,
    ValueChanged<String>? onSearchSubmitted,
    VoidCallback? onSearchClear,
    String searchHint = 'Search',
  }) {
    return ChromeScaffold(
      key: key,
      title: title,
      subtitle: subtitle,
      actions: actions,
      bottom: bottom,
      floatingActionButton: floatingActionButton,
      enableSearch: enableSearch,
      searchController: searchController,
      onSearchChanged: onSearchChanged,
      onSearchSubmitted: onSearchSubmitted,
      onSearchClear: onSearchClear,
      searchHint: searchHint,
      // Built under the scope rather than here, because the gap's size is only
      // known below the header this scaffold is about to create.
      body: _SliverBody(slivers: slivers, onRefresh: onRefresh),
    );
  }

  final String title;
  final String? subtitle;
  final Widget body;

  /// Icon-sized controls for the actions pill.
  ///
  /// Each is given a [Chrome.actionSize] square — the contract, so the
  /// header's height is its own property rather than the call site's. One
  /// that does not fit is scaled down to the slot rather than clipped, but it
  /// will look scaled: pass an icon, not a composite.
  final List<Widget>? actions;

  /// Pinned under the pills and hidden with them — a [SegmentedTabs], a filter
  /// row. It declares its own height, so the header cannot be told the wrong
  /// one.
  final PreferredSizeWidget? bottom;

  final Widget? floatingActionButton;

  final bool enableSearch;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchClear;
  final String searchHint;

  @override
  State<ChromeScaffold> createState() => _ChromeScaffoldState();
}

class _ChromeScaffoldState extends State<ChromeScaffold> {
  final _visible = ValueNotifier<bool>(true);

  /// Where the current measurement started, not where the header last moved.
  ///
  /// Those are different once the user keeps scrolling the same way past a
  /// crossing, and the difference is the bug below.
  double _anchor = 0;

  /// The header's measured height, once there has been a header to measure.
  ///
  /// Null on the first frame, where [Chrome.headerHeight]'s estimate stands
  /// in. Everything after that is what the header really is — including while
  /// searching, where the pill holds a `TextField` whose height is the
  /// framework's business rather than ours.
  double? _measured;

  /// How far the finger has to travel before the header moves.
  ///
  /// Without it the header flickers on every small scroll correction, which is
  /// worse than a header that never hides.
  static const _threshold = 50.0;

  @override
  void dispose() {
    _visible.dispose();
    super.dispose();
  }

  void _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return;

    final offset = metrics.pixels;
    if (offset <= 0) {
      // At the top the header is always available, whichever way the last
      // gesture went. Anything else means a screen can open with its own title
      // hidden.
      _visible.value = true;
      _anchor = offset;
      return;
    }
    // An overscroll at the bottom is a bounce, not a direction: acting on it
    // hides the header when the user hits the end of a list.
    if (offset >= metrics.maxScrollExtent) return;

    // Carrying on in the direction the header is already answering moves the
    // anchor with the finger, so the next reversal is measured from where it
    // happened.
    //
    // Anchoring on the last *crossing* instead — which is what AnymeX does,
    // and what this was ported as — leaves the baseline behind as the scroll
    // continues, so the reversal needed to bring the header back grows with
    // however far past the crossing the user went. Scroll down 300 and back
    // up 60 and nothing happens, which reads as a header that has stopped
    // working. Found by `codeant-ai`.
    if (_visible.value ? offset < _anchor : offset > _anchor) {
      _anchor = offset;
      return;
    }
    if ((offset - _anchor).abs() > _threshold) {
      _visible.value = offset < _anchor;
      _anchor = offset;
    }
  }

  void _onMeasured(double height) {
    if (!mounted || height == _measured) return;
    setState(() => _measured = height);
  }

  @override
  Widget build(BuildContext context) {
    final bottomHeight = widget.bottom?.preferredSize.height ?? 0;
    final height =
        _measured ??
        Chrome.headerHeight(
          context,
          hasSubtitle: widget.subtitle != null && widget.subtitle!.isNotEmpty,
          hasActions:
              widget.enableSearch || (widget.actions?.isNotEmpty ?? false),
          bottomHeight: bottomHeight,
        );

    return Scaffold(
      floatingActionButton: widget.floatingActionButton,
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          _onScroll(n);
          return false;
        },
        child: ValueListenableBuilder<bool>(
          valueListenable: _visible,
          builder: (context, visible, _) => Stack(
            children: [
              Positioned.fill(
                child: ChromeHeaderScope(height: height, child: widget.body),
              ),
              AnimatedPositioned(
                duration: Chrome.headerSlide,
                curve: Curves.easeInOut,
                // Past the top edge by a margin, so the pill's shadow goes with
                // it rather than hanging below the status bar.
                top: visible ? 0 : -(height + 20),
                left: 0,
                right: 0,
                child: _MeasureHeight(
                  onChange: _onMeasured,
                  child: PillHeader(
                    title: widget.title,
                    subtitle: widget.subtitle,
                    actions: widget.actions,
                    bottom: widget.bottom,
                    enableSearch: widget.enableSearch,
                    searchController: widget.searchController,
                    onSearchChanged: widget.onSearchChanged,
                    onSearchSubmitted: widget.onSearchSubmitted,
                    onSearchClear: widget.onSearchClear,
                    searchHint: widget.searchHint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliverBody extends StatelessWidget {
  const _SliverBody({required this.slivers, this.onRefresh});

  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final view = CustomScrollView(
      // `RefreshIndicator` needs a child that accepts the drag, and a list
      // that fits the screen otherwise need not.
      physics: onRefresh == null ? null : const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(height: ChromeHeaderScope.of(context)),
        ),
        ...slivers,
        // Clears the gesture bar, so the last row is not the thing a
        // back-swipe grabs.
        const SliverToBoxAdapter(
          child: SizedBox(height: Chrome.sectionGap * 2),
        ),
      ],
    );
    if (onRefresh == null) return view;
    return RefreshIndicator(
      // Otherwise the spinner appears behind the title pill.
      edgeOffset: ChromeHeaderScope.of(context),
      onRefresh: onRefresh!,
      child: view,
    );
  }
}

/// The header itself: a title pill on the left, an actions pill on the right,
/// and the content scrolling under both.
///
/// Search toggles the whole row in place rather than sitting under the title
/// permanently. That is the trade the reversal makes: the collapsing header
/// spent ~150px of every screenful on a title, and this spends none.
class PillHeader extends StatefulWidget {
  const PillHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.bottom,
    this.enableSearch = false,
    this.searchController,
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onSearchClear,
    this.searchHint = 'Search',
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool enableSearch;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchClear;
  final String searchHint;

  @override
  State<PillHeader> createState() => PillHeaderState();
}

class PillHeaderState extends State<PillHeader> {
  bool _searching = false;

  bool get isSearching => _searching;

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        widget.searchController?.clear();
        // Closing search has to clear the *query*, not just the field: leaving
        // a filter in force with nothing on screen naming it is the stale
        // filter this repo already shipped once.
        widget.onSearchChanged?.call('');
        widget.onSearchClear?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Chrome.gap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Chrome.gutter),
              child: AnimatedSwitcher(
                duration: Chrome.duration,
                switchInCurve: Chrome.curve,
                switchOutCurve: Curves.easeInCubic,
                child: _searching ? _searchRow(context) : _splitRow(context),
              ),
            ),
            if (widget.bottom != null) ...[
              const SizedBox(height: Chrome.gap),
              widget.bottom!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context, {
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? padding,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(Chrome.pillRadius);
    return ClipRRect(
      key: key,
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Chrome.blur, sigmaY: Chrome.blur),
        child: Container(
          padding:
              padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            // Translucent on purpose: an opaque fill makes this a bar again,
            // and a bar is what the developer asked to move away from.
            color: scheme.surfaceContainer.withValues(alpha: 0.55),
            borderRadius: radius,
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.08),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _splitRow(BuildContext context) {
    final theme = Theme.of(context);
    final route = ModalRoute.of(context);
    final canPop = route?.canPop == true && !(route?.isFirst ?? true);
    final hasActions =
        widget.enableSearch || (widget.actions?.isNotEmpty ?? false);

    return Row(
      // The key goes on the widget `AnimatedSwitcher` actually compares — the
      // one it is handed. AnymeX puts it on a `Row` nested inside the search
      // pill, where the switcher never sees it; that works only because the two
      // branches happen to be different widget types today.
      key: const ValueKey('chrome-header-split'),
      children: [
        Flexible(
          child: _pill(
            context,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (canPop) ...[
                  _HeaderAction(
                    icon: Icons.arrow_back_ios_rounded,
                    tooltip: 'Back',
                    color: theme.colorScheme.onSurface,
                    size: 16,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.3,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // The gap between the pills is what makes them read as two floating
        // objects rather than as one bar with a hole in it.
        const Spacer(),
        if (hasActions) ...[
          const SizedBox(width: Chrome.gap),
          _pill(
            context,
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.enableSearch)
                  _HeaderAction(
                    icon: Icons.search_rounded,
                    tooltip: 'Search',
                    color: theme.colorScheme.primary,
                    onPressed: _toggleSearch,
                  ),
                // Every action is the same fixed box, whatever the caller
                // passed, so the header's height is a property of the header
                // and not of the call site. The box is Material's own 48px
                // minimum: a caller's bare `IconButton` or `PopupMenuButton`
                // lands exactly on its natural size rather than being
                // squeezed under it.
                //
                // `scaleDown` is the failure mode, not the layout. An action
                // that does not fit the slot used to be *silently destroyed*
                // rather than overflowing: measured, an `IconButton` with a
                // 64px icon and 24px padding rendered a 48x48 button around a
                // **0x0** icon — an invisible control, no exception, analyze
                // clean, no test failure. Scaling is a no-op for anything
                // that already fits, so every ordinary action is untouched
                // and a wrong one is visible instead of absent. Found by
                // `codeant-ai`, whose reading of the cause was different; see
                // the measurements on the thread.
                for (final action in widget.actions ?? const <Widget>[])
                  SizedBox(
                    width: Chrome.actionSize,
                    height: Chrome.actionSize,
                    child: IconTheme.merge(
                      data: const IconThemeData(size: 20),
                      child: Center(
                        child: FittedBox(fit: BoxFit.scaleDown, child: action),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _searchRow(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.searchController;
    return _pill(
      context,
      key: const ValueKey('chrome-header-search'),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          _HeaderAction(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: 'Close search',
            color: theme.colorScheme.primary,
            size: 18,
            onPressed: _toggleSearch,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: widget.onSearchChanged,
              onSubmitted: widget.onSearchSubmitted,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: TextStyle(
                  fontSize: 13.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          if (controller != null)
            // Listens rather than reading once: the field is typed into after
            // this row is built, and a clear button that only appears on the
            // next rebuild for some other reason is worse than none.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      onPressed: () {
                        controller.clear();
                        widget.onSearchChanged?.call('');
                      },
                      tooltip: 'Clear',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      icon: Icon(
                        Icons.cancel_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// One action inside the actions pill.
///
/// [Chrome.actionSize] square, which is Material's minimum touch target — the
/// pill is sized around the actions rather than the actions squeezed into the
/// pill.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
    this.size = 20,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    iconSize: size,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(
      minWidth: Chrome.actionSize,
      minHeight: Chrome.actionSize,
    ),
    icon: Icon(icon, size: size, color: color),
  );
}

/// A segmented control that **cannot** overflow.
///
/// Every tab is `1 / total` of the available width by construction, and its
/// label is `Flexible` and ellipsised, so there is no intrinsic-width
/// negotiation to lose. That is why this replaces Material's `TabBar` rather
/// than patching it: measured, that bar overflowed by 24px at 320, **11px at
/// 360 and 2.7px at 384** — Pixel-class widths — and `flutter analyze` was
/// clean throughout. AnymeX had designed the whole class of bug out; see the
/// mistakes table in `CLAUDE.md`.
class SegmentedTabs extends StatelessWidget implements PreferredSizeWidget {
  const SegmentedTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.height = Chrome.tabBarHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: Chrome.gutter),
  });

  final List<Widget> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;
  final EdgeInsets padding;

  @override
  Size get preferredSize =>
      Size.fromHeight(height + padding.top + padding.bottom);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = tabs.length;
    // -1 is the left edge and +1 the right, so the selected segment's centre
    // falls exactly on its own third (or quarter, or half).
    final alignX = total > 1 ? -1.0 + (2.0 * selectedIndex / (total - 1)) : 0.0;

    return Padding(
      padding: padding,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(Chrome.tabBarRadius),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.1)),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: Chrome.duration,
              curve: Curves.easeOutQuint,
              alignment: Alignment(alignX, 0),
              child: FractionallySizedBox(
                widthFactor: total > 0 ? 1 / total : 1,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.secondary,
                    borderRadius: BorderRadius.circular(Chrome.segmentRadius),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.secondary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final (index, tab) in tabs.indexed)
                  Expanded(
                    child: _Segment(
                      selected: index == selectedIndex,
                      onTap: () => onSelected(index),
                      child: tab,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (selected) return;
        HapticFeedback.lightImpact();
        onTap();
      },
      child: AnimatedScale(
        scale: selected ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        child: AnimatedOpacity(
          opacity: selected ? 1.0 : 0.6,
          duration: const Duration(milliseconds: 200),
          child: SizedBox.expand(
            child: Center(
              child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? scheme.onSecondary
                      : scheme.onSurfaceVariant,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(
                    size: 15,
                    color: selected
                        ? scheme.onSecondary
                        : scheme.onSurfaceVariant,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The container primitive: rounded, clipped, optionally glowing.
///
/// Everything that is a surface goes through this rather than composing its
/// own `ClipRRect` over a `Container`, so the app's roundness is one number
/// and a radius multiplier can be added later in one place rather than in
/// thirty widgets.
class ChromeCard extends StatelessWidget {
  const ChromeCard({
    super.key,
    this.child,
    this.padding,
    this.margin,
    this.color,
    this.radius = Chrome.cardRadius,
    this.border,
    this.glow = false,
    this.onTap,
    this.onLongPress,
  });

  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double radius;
  final BoxBorder? border;

  /// A soft primary-tinted bloom instead of a drop shadow. Elevation as
  /// colour, which is the one One UI rule AnymeX already agreed with.
  final bool glow;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = BorderRadius.circular(radius);
    Widget content = ClipRRect(
      borderRadius: shape,
      child: Material(
        color: color ?? scheme.surfaceContainerLow,
        child: onTap == null && onLongPress == null
            ? Padding(padding: padding ?? EdgeInsets.zero, child: child)
            : InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                child: Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: child,
                ),
              ),
      ),
    );
    if (border != null || glow) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          border: border,
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.05),
                    offset: const Offset(-1, 1),
                    blurRadius: 50,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: content,
      );
    }
    return margin == null ? content : Padding(padding: margin!, child: content);
  }
}

/// One row: a tinted square, a title over a subtitle, and whatever acts on it.
///
/// The 36x36 `primary`-at-12% square behind a 20px `primary` icon is the house
/// motif — it is what makes a list of these read as AnymeX rather than as a
/// stack of `ListTile`s.
class ChromeTile extends StatelessWidget {
  const ChromeTile({
    super.key,
    required this.title,
    this.titleSuffix,
    this.icon,
    this.leading,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.iconColor,
    this.iconBackground,
    this.showChevron = true,
    this.enabled = true,
    this.padding,
    this.content,
  });

  final String title;

  /// A badge that belongs *beside* the name rather than under it — an "18+",
  /// an update count. The title stays a `String` so it keeps its ellipsis;
  /// a `Widget` title would put the overflow decision on every caller.
  final Widget? titleSuffix;

  final IconData? icon;
  final Widget? leading;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? iconColor;
  final Color? iconBackground;
  final bool showChevron;
  final bool enabled;
  final EdgeInsetsGeometry? padding;

  /// Rendered under the row, inside the same tap target — a segmented
  /// selector, a slider. AnymeX puts a choice *inside* its row rather than
  /// behind a radio dialog, and that is the direction this app is moving.
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final lead =
        leading ??
        (icon == null
            ? null
            : Container(
                width: Chrome.leadingSize,
                height: Chrome.leadingSize,
                decoration: BoxDecoration(
                  color:
                      iconBackground ?? scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Chrome.leadingRadius),
                ),
                child: Icon(icon, size: 20, color: iconColor ?? scheme.primary),
              ));

    final tail =
        trailing ??
        (showChevron && onTap != null
            ? Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.onSurface.withValues(alpha: 0.35),
              )
            : null);

    final row = Padding(
      padding:
          padding ??
          const EdgeInsets.symmetric(horizontal: Chrome.gutter, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (lead != null) ...[lead, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: enabled
                                  ? scheme.onSurface
                                  : scheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        if (titleSuffix != null) ...[
                          const SizedBox(width: 6),
                          titleSuffix!,
                        ],
                      ],
                    ),
                    if (subtitleWidget != null)
                      subtitleWidget!
                    else if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (tail != null) ...[const SizedBox(width: Chrome.gap), tail],
            ],
          ),
          if (content != null) content!,
        ],
      ),
    );

    if (!enabled || (onTap == null && onLongPress == null)) {
      return Material(color: Colors.transparent, child: row);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, onLongPress: onLongPress, child: row),
    );
  }
}

/// A labelled group of rows: a `primary` label over one clipped card.
///
/// The chrome-vocabulary replacement for `OneUiGroup`. It exists as a
/// primitive rather than as a local helper per screen because nine screens
/// are converting onto it, and the previous vocabulary's group was the one
/// piece every one of them used.
///
/// The children are clipped by the card rather than shaped individually, so a
/// row can be a [ChromeTile], a switch, a slider or a whole sub-list and still
/// get the group's corners without knowing it is in a group.
class ChromeSection extends StatelessWidget {
  const ChromeSection({
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
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            Chrome.gutter,
            Chrome.sectionGap,
            Chrome.gutter,
            0,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Chrome.gutter,
                0,
                Chrome.gutter,
                Chrome.gap,
              ),
              child: Text(
                label!,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ChromeCard(child: Column(children: children)),
        ],
      ),
    );
  }
}

/// [ChromeSection] as a sliver, for [ChromeScaffold.slivers].
class SliverChromeSection extends StatelessWidget {
  const SliverChromeSection({super.key, this.label, required this.children});

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: ChromeSection(label: label, children: children),
  );
}

/// A destination card: a tinted icon tile over a title and a description.
///
/// AnymeX's shape for a *hub* of destinations
/// (`lib/screens/other_features.dart`), as distinct from a list of settings.
/// A hub has few entries and each deserves a sentence, so the description gets
/// its own line rather than being squeezed under a row's title.
///
/// The icon tile is deliberately larger than [ChromeTile]'s 36x36 motif — 12px
/// of padding around a 24px icon — because it is the card's subject rather
/// than its bullet.
class ChromeFeatureCard extends StatelessWidget {
  const ChromeFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  /// Defaults to `primary`. AnymeX tints a hub's sections differently so the
  /// groups read apart at a glance.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = accent ?? scheme.primary;

    return ChromeCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Chrome.gutter),
      border: Border.all(
        color: scheme.outline.withValues(alpha: 0.12),
        width: 1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Chrome.segmentRadius),
            ),
            // The same reason every action in the header carries one: a parent
            // that forces a size erases a child that cannot meet it, silently.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Icon(icon, size: 24, color: tint),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.3,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}
