import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkerpro_support_flutter/api_client.dart';
import 'package:tinkerpro_support_flutter/screens/activity_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/announcements_admin_screen.dart';
import 'package:tinkerpro_support_flutter/screens/barcode_screen.dart';
import 'package:tinkerpro_support_flutter/screens/blog_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/branches_admin_screen.dart';
import 'package:tinkerpro_support_flutter/screens/client_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/credentials_screen.dart';
import 'package:tinkerpro_support_flutter/screens/customer_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/email_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/employment_screen.dart';
import 'package:tinkerpro_support_flutter/screens/feedback_screen.dart';
import 'package:tinkerpro_support_flutter/screens/file_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/help_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/lead_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/license_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/offer_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/posversion_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/pricing_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/releasenotes_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/role_defaults_screen.dart';
import 'package:tinkerpro_support_flutter/screens/task_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/ticket_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/user_admin_list_screen.dart';
import 'package:tinkerpro_support_flutter/screens/vendor_admin_screen.dart';
import 'package:tinkerpro_support_flutter/services/activity_service.dart';
import 'package:tinkerpro_support_flutter/services/announcement_admin_service.dart';
import 'package:tinkerpro_support_flutter/services/barcode_service.dart';
import 'package:tinkerpro_support_flutter/services/blog_service.dart';
import 'package:tinkerpro_support_flutter/services/notification_center.dart';
import 'package:tinkerpro_support_flutter/services/client_service.dart';
import 'package:tinkerpro_support_flutter/services/credential_service.dart';
import 'package:tinkerpro_support_flutter/services/email_service.dart';
import 'package:tinkerpro_support_flutter/services/feedback_service.dart';
import 'package:tinkerpro_support_flutter/services/file_service.dart';
import 'package:tinkerpro_support_flutter/services/help_service.dart';
import 'package:tinkerpro_support_flutter/services/license_service.dart';
import 'package:tinkerpro_support_flutter/services/offer_service.dart';
import 'package:tinkerpro_support_flutter/services/posversion_service.dart';
import 'package:tinkerpro_support_flutter/services/pricing_service.dart';
import 'package:tinkerpro_support_flutter/services/releasenotes_service.dart';
import 'package:tinkerpro_support_flutter/services/services.dart';
import 'package:tinkerpro_support_flutter/services/task_service.dart';
import 'package:tinkerpro_support_flutter/services/user_admin_service.dart';
import 'package:tinkerpro_support_flutter/services/vendor_admin_service.dart';
import 'package:tinkerpro_support_flutter/theme.dart';

void main() {
  late ApiClient api;
  late NotificationCenter notifications;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = await ApiClient.load();
    notifications = NotificationCenter(
      leads: LeadService(api),
      customers: CustomerService(api),
    );
  });

  Future<void> smoke(
    WidgetTester tester,
    String label,
    Widget screen, {
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(theme: dark ? darkTheme() : lightTheme(), home: screen),
    );
    final mode = dark ? 'dark' : 'light';
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: '$label threw on first build ($mode)',
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.takeException(),
      isNull,
      reason: '$label threw while settling ($mode)',
    );
  }

  testWidgets('menu screens build in both themes', (tester) async {
    final cases = <String, Widget Function()>{
      'Activity': () => ActivityListScreen(service: ActivityService(api)),
      'Announcements': () =>
          AnnouncementsAdminScreen(service: AnnouncementAdminService(api)),
      'Barcode': () => BarcodeScreen(service: BarcodeService(api)),
      'Blog': () => BlogListScreen(service: BlogService(api)),
      'Branches': () => BranchesAdminScreen(service: UserAdminService(api)),
      'Clients': () => ClientListScreen(service: ClientService(api)),
      'Credentials': () => CredentialsScreen(service: CredentialService(api)),
      'Customers': () => CustomerListScreen(
        service: CustomerService(api),
        notifications: notifications,
      ),
      'Email': () => EmailListScreen(service: EmailService(api)),
      'Employment': () => EmploymentScreen(api: api),
      'Feedback': () => FeedbackInboxScreen(service: FeedbackService(api)),
      'Files': () => FileListScreen(service: FileService(api)),
      'Help': () => HelpListScreen(service: HelpService(api)),
      'Leads': () => LeadListScreen(
        service: LeadService(api),
        notifications: notifications,
      ),
      'Licenses': () => LicenseListScreen(service: LicenseService(api)),
      'Offers': () => OfferListScreen(service: OfferService(api), api: api),
      'POS versions': () =>
          PosVersionListScreen(service: PosVersionService(api)),
      'Pricing': () =>
          PricingListScreen(service: PricingService(api), api: api),
      'Release notes': () =>
          ReleaseNotesListScreen(service: ReleaseNotesService(api)),
      'Role defaults': () => RoleDefaultsScreen(service: UserAdminService(api)),
      'Tasks': () => TaskListScreen(service: TaskService(api)),
      'Tickets': () => TicketListScreen(service: TicketService(api)),
      'Users': () =>
          UserAdminListScreen(service: UserAdminService(api), api: api),
      'Vendors': () => VendorAdminScreen(service: VendorAdminService(api)),
    };

    for (final entry in cases.entries) {
      await smoke(tester, entry.key, entry.value());
      await smoke(tester, entry.key, entry.value(), dark: true);
    }
  });

  testWidgets('help add-topic form opens', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme(),
        home: HelpListScreen(service: HelpService(api)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('New help topic'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('Add topic'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
  });
}
