import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkerpro_support_flutter/api_client.dart';
import 'package:tinkerpro_support_flutter/models/account_settings_models.dart';
import 'package:tinkerpro_support_flutter/screens/account_settings_screens.dart';
import 'package:tinkerpro_support_flutter/screens/settings_screen.dart';
import 'package:tinkerpro_support_flutter/services/account_settings_service.dart';
import 'package:tinkerpro_support_flutter/services/chat_app_launcher.dart';
import 'package:tinkerpro_support_flutter/services/chat_prefs.dart';
import 'package:tinkerpro_support_flutter/services/services.dart';
import 'package:tinkerpro_support_flutter/theme.dart';

class _Fake extends AccountSettingsService {
  _Fake(super.api);

  SelfSettings self = const SelfSettings(
    fullName: 'Erwin James',
    email: 'ej@example.com',
    emailVerified: false,
    username: 'ej',
    role: 'super_admin',
    mfaEnabled: false,
    chatAlias: '',
  );
  final List<String> calls = [];
  Set<String> hidden = {'zreading'};
  Set<String>? savedHidden;
  String reminderMode = 'own';
  int reminderSource = 0;
  List<PosApiKey> keys = [];

  @override
  Future<SelfSettings?> load() async => self;

  @override
  Future<SettingsResult> updateAccount({
    required String fullName,
    required String email,
    String? chatAlias,
  }) async {
    calls.add('update:$fullName|$email|${chatAlias ?? 'null'}');
    return const SettingsResult(ok: true, message: 'Account updated.');
  }

  @override
  Future<SettingsResult> sendEmailCode() async {
    calls.add('send');
    return const SettingsResult(ok: true);
  }

  @override
  Future<SettingsResult> verifyEmail(String otp) async {
    calls.add('verify:$otp');
    self = SelfSettings(
      fullName: self.fullName,
      email: self.email,
      emailVerified: true,
      username: self.username,
      role: self.role,
      mfaEnabled: self.mfaEnabled,
      chatAlias: self.chatAlias,
    );
    return const SettingsResult(ok: true);
  }

  @override
  Future<SettingsResult> changePassword({
    required String current,
    required String next,
    required String confirm,
  }) async {
    calls.add('password:$current>$next');
    return const SettingsResult(ok: true, message: 'Password changed.');
  }

  @override
  Future<Set<String>?> sidebarHidden() async => {...hidden};

  @override
  Future<SettingsResult> saveSidebarHidden(Set<String> hidden) async {
    savedHidden = {...hidden};
    return const SettingsResult(ok: true);
  }

  @override
  Future<GlobalReminder?> globalReminder() async => GlobalReminder(
    mode: reminderMode,
    sourceUserId: reminderSource,
    users: const [
      ReminderOption(id: 4, name: 'Ana'),
      ReminderOption(id: 9, name: 'Ben'),
    ],
  );

  @override
  Future<SettingsResult> saveGlobalReminder({
    required String mode,
    required int sourceUserId,
  }) async {
    calls.add('reminder:$mode:$sourceUserId');
    return const SettingsResult(ok: true);
  }

  @override
  Future<List<PosApiKey>?> posKeys() async => keys;

  @override
  Future<({bool ok, String? token, String? message})> createPosKey(
    String label,
  ) async {
    calls.add('create:$label');
    keys = [
      const PosApiKey(
        id: 3,
        label: 'TinkerPro POS',
        masked: 'tpk_ab12••••••••••••',
        createdAt: '2026-09-19 09:00:00',
        lastUsedAt: '',
        lastUsedIp: '',
        requestCount: 0,
        revokedAt: '',
        active: true,
      ),
    ];
    return (ok: true, token: 'tpk_ab12SECRET', message: null);
  }

  @override
  Future<SettingsResult> revokePosKey(int id) async {
    calls.add('revoke:$id');
    keys = const [];
    return const SettingsResult(ok: true);
  }
}

Future<(ApiClient, _Fake)> _setup({String role = 'super_admin'}) async {
  SharedPreferences.setMockInitialValues({});
  final api = await ApiClient.load();
  await api.setUserRole(role);
  return (api, _Fake(api));
}

Widget _host(Widget child) => MaterialApp(theme: darkTheme(), home: child);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('super admin sees every section, a plain user only their own', (
    tester,
  ) async {
    _tall(tester);
    var (api, _) = await _setup();
    await tester.pumpWidget(
      _host(SettingsScreen(api: api, auth: AuthService(api))),
    );
    await tester.pump();
    for (final label in [
      'Account',
      'Password',
      'Two-factor authentication',
      'Agent operating hours',
      'Unresolved ticket reminder',
      'POS API key',
      'Global sidebar navigation',
      'Dashboard reminders',
      'Clear local cache',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }

    (api, _) = await _setup(role: 'user');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _host(SettingsScreen(api: api, auth: AuthService(api))),
    );
    await tester.pump();
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Two-factor authentication'), findsOneWidget);
    expect(find.text('Agent operating hours'), findsNothing);
    expect(find.text('POS API key'), findsNothing);
    expect(find.text('Global sidebar navigation'), findsNothing);
    expect(find.text('Dashboard reminders'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin gets sidebar and POS keys but not super-admin tools', (
    tester,
  ) async {
    _tall(tester);
    final (api, _) = await _setup(role: 'admin');
    await tester.pumpWidget(
      _host(SettingsScreen(api: api, auth: AuthService(api))),
    );
    await tester.pump();
    expect(find.text('Global sidebar navigation'), findsOneWidget);
    expect(find.text('POS API key'), findsOneWidget);
    expect(find.text('Dashboard reminders'), findsNothing);
    expect(find.text('Agent operating hours'), findsNothing);
  });

  testWidgets('account saves fields and verifies email with a code', (
    tester,
  ) async {
    _tall(tester);
    final (_, fake) = await _setup();
    await tester.pumpWidget(_host(AccountSettingsScreen(service: fake)));
    await tester.pumpAndSettle();
    expect(find.text('Not verified'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'e.g. Maya'), 'Maya');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('update:Erwin James|ej@example.com|Maya'));

    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(fake.calls, contains('send'));
    expect(find.textContaining('expires in 10:00'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '000000'), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('verify:123456'));
    expect(find.text('Verified'), findsOneWidget);
  });

  test('password strength matches the web scoring', () {
    expect(passwordScore(''), 0);
    expect(passwordScore('abcdefgh'), 1);
    expect(passwordScore('abcdefghijkl'), 2);
    expect(passwordScore('Abcdefghijkl'), 3);
    expect(passwordScore('Abcdefghijk1!'), 4);
  });

  testWidgets('password needs a match before it is sent', (tester) async {
    _tall(tester);
    final (_, fake) = await _setup();
    await tester.pumpWidget(_host(PasswordSettingsScreen(service: fake)));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'oldpass12');
    await tester.enterText(fields.at(1), 'Newpass12!x');
    await tester.enterText(fields.at(2), 'different');
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(fake.calls.where((c) => c.startsWith('password')), isEmpty);

    await tester.enterText(fields.at(2), 'Newpass12!x');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('password:oldpass12>Newpass12!x'));
  });

  testWidgets('global sidebar saves hidden keys and refreshes the session', (
    tester,
  ) async {
    _tall(tester);
    final (_, fake) = await _setup();
    var synced = 0;
    await tester.pumpWidget(
      _host(GlobalSidebarScreen(service: fake, onSaved: () async => synced++)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Z-Reading Request'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Barcode'), 200);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Barcode'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Save sidebar items'), 200);
    await tester.tap(find.text('Save sidebar items'));
    await tester.pumpAndSettle();
    expect(fake.savedHidden, {'zreading', 'barcode'});
    expect(synced, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Show all'), -200);
    await tester.tap(find.text('Show all'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Save sidebar items'), 200);
    await tester.tap(find.text('Save sidebar items'));
    await tester.pumpAndSettle();
    expect(fake.savedHidden, isEmpty);
  });

  testWidgets('dashboard reminders save as soon as they change', (
    tester,
  ) async {
    _tall(tester);
    final (_, fake) = await _setup();
    await tester.pumpWidget(_host(DashboardRemindersScreen(service: fake)));
    await tester.pumpAndSettle();
    expect(
      find.text('Every account sees the tasks assigned to them.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Everyone sees their own tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Everyone watches one account').last);
    await tester.pumpAndSettle();
    expect(fake.calls, contains('reminder:user:4'));
    expect(find.text('Every account will see Ana’s due work.'), findsOneWidget);
  });

  testWidgets('POS key is shown once after generating and can be revoked', (
    tester,
  ) async {
    _tall(tester);
    final (_, fake) = await _setup();
    await tester.pumpWidget(_host(PosApiKeysScreen(service: fake)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate key'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('create:TinkerPro POS'));
    expect(find.text('tpk_ab12SECRET'), findsOneWidget);
    expect(find.text('Key created — copy it now'), findsOneWidget);
    expect(find.text('tpk_ab12••••••••••••'), findsOneWidget);

    await tester.tap(find.byTooltip('Revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('revoke:3'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chat settings hide when TinkerPro Chat is installed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 15000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(() => ChatAppLauncher.instance.debugInstalled = null);
    final (api, _) = await _setup();
    final prefs = ChatPrefs(await SharedPreferences.getInstance());

    ChatAppLauncher.instance.debugInstalled = false;
    await tester.pumpWidget(
      _host(SettingsScreen(api: api, auth: AuthService(api), chatPrefs: prefs)),
    );
    await tester.pump();
    expect(find.text('Chat bubble notifications'), findsOneWidget);
    expect(find.text('Chat theme'), findsOneWidget);
    expect(find.text('Agent operating hours'), findsOneWidget);
    expect(find.text('Name, email, chat alias'), findsOneWidget);
    expect(find.text('Sign out'), findsWidgets);

    ChatAppLauncher.instance.debugInstalled = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _host(SettingsScreen(api: api, auth: AuthService(api), chatPrefs: prefs)),
    );
    await tester.pump();
    expect(find.text('Chat bubble notifications'), findsNothing);
    expect(find.text('Chat theme'), findsNothing);
    expect(find.text('Handled by TinkerPro Chat'), findsNothing);
    expect(find.text('Agent operating hours'), findsNothing);
    expect(find.text('Name and email'), findsOneWidget);
    expect(find.text('Unresolved ticket reminder'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('account hides the chat alias and never sends it', (
    tester,
  ) async {
    _tall(tester);
    final (_, fake) = await _setup();
    await tester.pumpWidget(
      _host(AccountSettingsScreen(service: fake, showChatFields: false)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Chat Alias'), findsNothing);
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('update:Erwin James|ej@example.com|null'));
  });
}
