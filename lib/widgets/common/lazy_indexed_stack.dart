import 'package:flutter/material.dart';

/// An [IndexedStack] that does not build a child until it has been visited.
///
/// A plain IndexedStack builds every tab at startup, so the cost of adding a tab
/// is paid on first frame whether or not the user ever opens it. Once a tab has
/// been shown it stays built, which is the point — tab switches keep their
/// scroll position and in-flight requests.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
  });

  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late List<bool> _activated;

  @override
  void initState() {
    super.initState();
    _activated = List.generate(
      widget.children.length,
      (i) => i == widget.index,
    );
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.children.length != _activated.length) {
      _activated = List.generate(
        widget.children.length,
        (i) => i < _activated.length ? _activated[i] : false,
      );
    }
    _activated[widget.index] = true;
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _activated[i] ? widget.children[i] : const SizedBox.shrink(),
      ],
    );
  }
}
