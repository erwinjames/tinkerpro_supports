import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'push_service.dart';
import 'services/chat_app_launcher.dart';
import 'services/chat_prefs.dart';
import 'services/phone_login_approvals.dart';
import 'services/reminder_service.dart';
import 'services/services.dart';
import 'services/theme_prefs.dart';
import 'theme.dart';
import 'screens/auth_screens.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final api = await ApiClient.load();
  await ChatAppLauncher.instance.refresh();
  await ReminderWidget.register();
  final prefs = await SharedPreferences.getInstance();
  final chatPrefs = ChatPrefs(prefs);
  final themePrefs = await ThemePrefs.load(prefs);
  await PhoneLoginApprovals.instance.bootstrap(api);
  runApp(TinkerProApp(api: api, chatPrefs: chatPrefs, themePrefs: themePrefs));
  if (kDebugMode && Platform.environment['TP_PHONE_APPROVAL_DEMO'] == '1') {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => PhoneLoginApprovals.instance.open(
        'demo',
        preview: const {
          'success': true,
          'platform': 'TinkerPro Support Desktop · Linux',
          'location': 'Cebu City, Central Visayas, Philippines',
          'ip': '203.177.12.40',
          'account': 'Juan Dela Cruz',
          'age_seconds': 4,
          'expires_in': 116,
          'choices': [37, 82, 14],
        },
      ),
    );
  }
}

final ThemeData _light = lightTheme();
final ThemeData _dark = darkTheme();

class TinkerProApp extends StatelessWidget {
  const TinkerProApp({
    super.key,
    required this.api,
    required this.chatPrefs,
    required this.themePrefs,
  });
  final ApiClient api;
  final ChatPrefs chatPrefs;
  final ThemePrefs themePrefs;

  @override
  Widget build(BuildContext context) {
    final auth = AuthService(api);
    final push = PushService(api);

    return AnimatedBuilder(
      animation: themePrefs,
      builder: (context, _) => MaterialApp(
        navigatorKey: PhoneLoginApprovals.instance.navigatorKey,
        title: 'TinkerPro Support',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const _NoScrollbarBehavior(),
        theme: _light,
        darkTheme: _dark,
        themeMode: themePrefs.value,
        builder: (context, child) {
          final theme = Theme.of(context);
          final dark = theme.brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness: dark ? Brightness.dark : Brightness.light,
              systemNavigationBarColor: theme.colorScheme.surface,
              systemNavigationBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: _RootRouter(
          api: api,
          auth: auth,
          push: push,
          chatPrefs: chatPrefs,
          themePrefs: themePrefs,
        ),
      ),
    );
  }
}

class _RootRouter extends StatelessWidget {
  const _RootRouter({
    required this.api,
    required this.auth,
    required this.push,
    required this.chatPrefs,
    required this.themePrefs,
  });

  final ApiClient api;
  final AuthService auth;
  final PushService push;
  final ChatPrefs chatPrefs;
  final ThemePrefs themePrefs;

  @override
  Widget build(BuildContext context) {
    if (!api.hasBaseUrl) {
      return ServerConfigScreen(
        api: api,
        auth: auth,
        chatPrefs: chatPrefs,
        themePrefs: themePrefs,
      );
    }
    if (api.hasSession) {
      return HomeShell(
        api: api,
        push: push,
        auth: auth,
        dashboard: DashboardService(api),
        customers: CustomerService(api),
        leads: LeadService(api),
        tickets: TicketService(api),
        chatPrefs: chatPrefs,
        themePrefs: themePrefs,
      );
    }
    return LoginScreen(
      api: api,
      auth: auth,
      chatPrefs: chatPrefs,
      themePrefs: themePrefs,
    );
  }
}

class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
