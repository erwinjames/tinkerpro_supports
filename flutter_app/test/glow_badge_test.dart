import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerpro_support_flutter/theme.dart';
import 'package:tinkerpro_support_flutter/widgets/premium.dart';

void main() {
  testWidgets('long label does not overflow inside a wrap', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: Wrap(
                children: const [
                  GlowBadge(
                    label: 'TinkerPro POS — QuickTrade / QuickServe Bundle',
                    icon: Icons.inventory_2_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('works inside an unbounded row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: const [GlowBadge(label: 'Streaming live updates')],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [90.0, 130.0, 160.0]) {
    testWidgets('long label shrinks to fit a ${width.toInt()}px wrap', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: const [
                    GlowBadge(label: 'Needs note', icon: Icons.bolt_rounded),
                    GlowBadge(
                      label: 'TinkerPro POS • QuickTrade / QuickServe',
                      icon: Icons.inventory_2_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final box = tester.getSize(find.byType(GlowBadge).last);
      expect(box.width, lessThanOrEqualTo(width));
    });
  }

  testWidgets('supports intrinsic sizing inside dialogs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Scaffold(
          body: Center(
            child: IntrinsicWidth(
              child: Column(
                children: const [
                  GlowBadge(label: 'Ticket #1042', icon: Icons.bolt_rounded),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
