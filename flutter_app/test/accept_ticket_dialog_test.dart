import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkerpro_support_flutter/api_client.dart';
import 'package:tinkerpro_support_flutter/screens/accept_ticket_dialog.dart';
import 'package:tinkerpro_support_flutter/services/chat_service.dart';
import 'package:tinkerpro_support_flutter/theme.dart';

void main() {
  testWidgets('accept ticket dialog builds', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = await ApiClient.load();
    await tester.pumpWidget(
      MaterialApp(
        theme: darkTheme(),
        home: Scaffold(
          body: AcceptTicketDialog(
            ticketId: 928918,
            conversationId: 1,
            service: ChatService(api),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('928918'), findsWidgets);
  });
}
