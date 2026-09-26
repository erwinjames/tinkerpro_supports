import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkerpro_support_flutter/api_client.dart';
import 'package:tinkerpro_support_flutter/models/models.dart';
import 'package:tinkerpro_support_flutter/models/notification_models.dart';
import 'package:tinkerpro_support_flutter/screens/notification_panel.dart';
import 'package:tinkerpro_support_flutter/services/chat_realtime.dart';
import 'package:tinkerpro_support_flutter/services/notification_center.dart';
import 'package:tinkerpro_support_flutter/services/notification_service.dart';
import 'package:tinkerpro_support_flutter/services/services.dart';
import 'package:tinkerpro_support_flutter/theme.dart';

class _Alerts extends NotificationService {
  _Alerts(super.api);
  int markAllCalls = 0;
  bool serverRead = false;

  @override
  Future<({List<AppNotification> items, int unread})> fetch() async {
    final items = [
      AppNotification(
        id: 1,
        type: 'bir_status',
        title: 'Client moved to Completed',
        body: 'Acme Trading',
        isRead: serverRead,
        createdAt: null,
      ),
      AppNotification(
        id: 2,
        type: 'bir_status',
        title: 'Old notice',
        body: '',
        isRead: true,
        createdAt: null,
      ),
    ];
    return (items: items, unread: serverRead ? 0 : 1);
  }

  @override
  Future<bool> markAllRead() async {
    markAllCalls++;
    serverRead = true;
    return true;
  }
}

class _NoLeads extends LeadService {
  _NoLeads(super.api);
  @override
  Future<List<LeadBrief>> list() async => const [];
}

class _NoCustomers extends CustomerService {
  _NoCustomers(super.api);
  @override
  Future<List<CustomerBrief>> list({String? search, int limit = 50}) async =>
      const [];
}

void main() {
  testWidgets(
    'opening the panel marks alerts read but still shows them as new',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = await ApiClient.load();
      final service = _Alerts(api);
      final alerts = AppNotificationCenter(service, ChatRealtimeService(api));
      final center = NotificationCenter(
        leads: _NoLeads(api),
        customers: _NoCustomers(api),
      )..attachAlerts(alerts);

      await tester.pumpWidget(
        MaterialApp(
          theme: darkTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => NotificationPanel.show(context, center),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(service.markAllCalls, 1);
      expect(alerts.unread, 0);
      expect(find.text('Client moved to Completed'), findsOneWidget);
      FontWeight? weightOf(String label) =>
          tester.widget<Text>(find.text(label)).style?.fontWeight;
      expect(weightOf('Client moved to Completed'), FontWeight.w700);
      expect(weightOf('Old notice'), FontWeight.w500);
      expect(find.textContaining('1 new'), findsOneWidget);
      expect(find.text('Mark all read'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await alerts.load();
      expect(alerts.unread, 0);
      expect(center.unseenCount, 0);
    },
  );

  testWidgets('panel does not overflow on a small screen', (tester) async {
    tester.view.physicalSize = const Size(960, 1200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final api = await ApiClient.load();
    final alerts = AppNotificationCenter(
      _Alerts(api),
      ChatRealtimeService(api),
    );
    final center = NotificationCenter(
      leads: _NoLeads(api),
      customers: _NoCustomers(api),
    )..attachAlerts(alerts);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => NotificationPanel.show(context, center),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.text('Notifications'), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
