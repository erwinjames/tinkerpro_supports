import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinkerpro_chat/api_client.dart';
import 'package:tinkerpro_chat/models/announcement_models.dart';
import 'package:tinkerpro_chat/screens/announcement_dialog.dart';
import 'package:tinkerpro_chat/services/announcement_service.dart';
import 'package:tinkerpro_chat/theme.dart';

Map<String, dynamic> payload({
  required int id,
  required String title,
  required String body,
  String tone = 'info',
  String toneLabel = 'Information',
  String icon = 'fa-bullhorn',
  int requireAck = 0,
}) {
  return <String, dynamic>{
    'id': id,
    'title': title,
    'body': body,
    'icon': icon,
    'tone': tone,
    'tone_label': toneLabel,
    'link_url': '',
    'link_label': '',
    'require_ack': requireAck,
    'is_read': 0,
    'is_acknowledged': 0,
    'is_pending': 1,
    'author': 'super_admin',
    'created_at': '2026-09-18 16:00:00',
    'db_offset': 28800,
  };
}

Future<(AnnouncementService, ApiClient)> harness(
  List<Map<String, dynamic>> items,
) async {
  SharedPreferences.setMockInitialValues({
    'server_base_url': 'https://support.tinkerpro.io',
    'session_cookie': 'PHPSESSID=test',
  });
  final api = await ApiClient.load();
  final service = AnnouncementService(api);
  for (final item in items) {
    service.ingest(item);
  }
  return (service, api);
}

Future<void> openDialog(
  WidgetTester tester,
  AnnouncementService service,
  ApiClient api,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(
      extensions: <ThemeExtension<dynamic>>[
        Brand.forBrightness(Brightness.light),
      ],
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => AnnouncementDialog(service: service, api: api),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('pending is driven by read and acknowledgement state', () {
    final base = payload(id: 1, title: 't', body: 'b', requireAck: 1);
    final unread = Announcement.fromJson(base);
    expect(unread.isPending, isTrue);

    final read = unread.markedRead(acknowledged: false);
    expect(read.isRead, isTrue);
    expect(read.isPending, isTrue);

    final acked = read.markedRead(acknowledged: true);
    expect(acked.isPending, isFalse);
  });

  test('tone and icon map to the web palette', () {
    final warning = Announcement.fromJson(
      payload(id: 2, title: 't', body: 'b', tone: 'warning', icon: 'fa-tools'),
    );
    expect(warning.toneColors.accent, const Color(0xFFFF7D00));
    expect(warning.iconData, Icons.build_rounded);

    final unknown = Announcement.fromJson(
      payload(id: 3, title: 't', body: 'b', tone: 'nope', icon: 'fa-nope'),
    );
    expect(unknown.toneColors.accent, const Color(0xFF2563EB));
    expect(unknown.iconData, Icons.campaign_rounded);
  });

  test('posted time is shifted out of the database timezone', () {
    final item = Announcement.fromJson(payload(id: 4, title: 't', body: 'b'));
    final posted = item.postedAt(28800);
    expect(posted, isNotNull);
    expect(posted!.toUtc(), DateTime.utc(2026, 9, 18, 8));
  });

  testWidgets('shows the announcement and pages through the deck',
      (tester) async {
    final (service, api) = await harness([
      payload(id: 10, title: 'First notice', body: 'Body one'),
      payload(id: 11, title: 'Second notice', body: 'Body two'),
    ]);
    await openDialog(tester, service, api);

    expect(find.text('ANNOUNCEMENT'), findsOneWidget);
    expect(find.text('First notice'), findsOneWidget);
    expect(find.text('Body one'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Back'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pump();

    expect(find.text('Second notice'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });

  testWidgets('an acknowledgement-required notice cannot be dismissed',
      (tester) async {
    final (service, api) = await harness([
      payload(
        id: 20,
        title: 'Security policy',
        body: 'Confirm you have read it.',
        tone: 'critical',
        toneLabel: 'Critical',
        requireAck: 1,
      ),
    ]);
    await openDialog(tester, service, api);

    expect(find.text('Action required'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.text('I understand'), findsOneWidget);
  });

  testWidgets('an optional notice can be closed', (tester) async {
    final (service, api) = await harness([
      payload(id: 30, title: 'FYI', body: 'Nothing to confirm.'),
    ]);
    await openDialog(tester, service, api);

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
  });
}
