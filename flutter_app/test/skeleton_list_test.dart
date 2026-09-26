import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tinkerpro_support_flutter/theme.dart';
import 'package:tinkerpro_support_flutter/widgets/premium.dart';

void main() {
  testWidgets('SkeletonList survives an unbounded height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Scaffold(
          body: ListView(
            children: const [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [SkeletonList(count: 3)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
