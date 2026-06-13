import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'push_service.dart';
import 'services/chat_prefs.dart';
import 'services/services.dart';
import 'services/theme_prefs.dart';
import 'theme.dart';
import 'screens/auth_screens.dart';
import 'screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force a warm dark status bar to match Brand.canvas — avoids a jarring
  // blue/white strip on Android when the app first paints.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Brand.canvas,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final api = await ApiClient.load();
  final prefs = await SharedPreferences.getInstance();
  final chatPrefs = ChatPrefs(prefs);
  final themePrefs = await ThemePrefs.load(prefs);
  runApp(TinkerProApp(
    api: api,
    chatPrefs: chatPrefs,
    themePrefs: themePrefs,
  ));
}

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

    // AnimatedBuilder listens to themePrefs (a ValueNotifier<ThemeMode>)
    // and rebuilds MaterialApp when the user flips light/dark from the
    // Menu tab — Material's themeMode then resolves to the right theme.
    return AnimatedBuilder(
      animation: themePrefs,
      builder: (context, _) => MaterialApp(
        title: 'TinkerPro Support',
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        darkTheme: darkTheme(),
        themeMode: themePrefs.value,
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

/// Decides the starting screen:
///  * no server URL    → ServerConfigScreen (Station 01)
///  * URL + cookie     → HomeShell
///  * URL, no cookie   → LoginScreen (Station 02)
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
