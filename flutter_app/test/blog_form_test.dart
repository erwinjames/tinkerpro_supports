import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkerpro_support_flutter/api_client.dart';
import 'package:tinkerpro_support_flutter/screens/blog_form_screen.dart';
import 'package:tinkerpro_support_flutter/services/blog_service.dart';
import 'package:tinkerpro_support_flutter/theme.dart';

void main() {
  testWidgets('blog form builds', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = await ApiClient.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: BlogFormScreen(service: BlogService(api)),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Headline'), findsOneWidget);
    expect(find.text('Article content'), findsOneWidget);
  });
}
