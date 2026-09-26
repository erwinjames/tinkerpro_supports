import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkerpro_support_flutter/api_client.dart';
import 'package:tinkerpro_support_flutter/models/announcement_admin_models.dart';
import 'package:tinkerpro_support_flutter/screens/announcements_admin_screen.dart';
import 'package:tinkerpro_support_flutter/services/announcement_admin_service.dart';
import 'package:tinkerpro_support_flutter/theme.dart';

void main() {
  testWidgets('announcement composer builds', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = await ApiClient.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: AnnouncementComposerScreen(
          service: AnnouncementAdminService(api),
          draft: AnnouncementDraft(),
          dbOffsetSeconds: 0,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Publish'), findsOneWidget);
  });
}
