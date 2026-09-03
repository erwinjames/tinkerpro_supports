import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tinkerpro_chat/theme.dart';

void main() {
  testWidgets('theme builds', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: lightTheme(),
      darkTheme: darkTheme(),
      home: const Scaffold(body: SizedBox.shrink()),
    ));
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
