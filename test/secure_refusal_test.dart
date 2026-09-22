import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:otaku_reader/features/reader/widgets/secure_refusal_notice.dart';

/// The refusal notice.
///
/// It exists because the controller's `secureRefused` / `secureApplied` pair
/// shipped with **nothing rendering either one** — a refusal was
/// indistinguishable from success on screen, inside the very change whose
/// commit message argued a privacy promise must be reported rather than
/// swallowed. Found by `codeant-ai`.
void main() {
  Future<void> pump(WidgetTester tester, {required bool visible}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SecureRefusalNotice(visible: visible)),
        ),
      );

  testWidgets('says nothing when the platform applied the flag', (
    tester,
  ) async {
    await pump(tester, visible: false);
    expect(find.byType(Container), findsNothing);
    expect(find.textContaining('screenshots'), findsNothing);
  });

  testWidgets('tells the reader screenshots are still possible', (
    tester,
  ) async {
    await pump(tester, visible: true);

    // The fact the reader needs is about *screenshots*, not about a channel
    // returning false.
    expect(find.textContaining('screenshots'), findsOneWidget);
  });

  testWidgets('announces itself to a screen reader', (tester) async {
    // A privacy claim that only a sighted reader can discover is the same
    // defect one sense further along.
    final handle = tester.ensureSemantics();
    await pump(tester, visible: true);

    expect(
      tester.getSemantics(find.textContaining('screenshots')).label,
      contains('screenshots'),
    );
    handle.dispose();
  });

  for (final width in [320.0, 360.0, 384.0]) {
    testWidgets('fits at ${width.toInt()}px', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(width, 800)),
              child: const Scaffold(
                body: Center(child: SecureRefusalNotice(visible: true)),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
