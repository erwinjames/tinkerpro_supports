import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'platform_info.dart';
import 'push_service.dart';
import 'services/auth_service.dart';
import 'services/chat_prefs.dart';
import 'services/theme_prefs.dart';
import 'theme.dart';
import 'screens/auth_screens.dart';
import 'screens/chat_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Brand.canvas,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  if (kIsMobilePlatform) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  final api = await ApiClient.load();
  final prefs = await SharedPreferences.getInstance();
  final chatPrefs = ChatPrefs(prefs);
  final themePrefs = await ThemePrefs.load(prefs);
  runApp(TinkerProChatApp(
    api: api,
    chatPrefs: chatPrefs,
    themePrefs: themePrefs,
  ));
}

class TinkerProChatApp extends StatelessWidget {
  const TinkerProChatApp({
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
        title: 'TinkerPro Chat',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const _NoScrollbar(),
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
      return ChatShell(
        api: api,
        push: push,
        auth: auth,
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

/// Desktop builds get a Material scrollbar on every scrollable by default.
/// The chat surfaces are dense enough that it reads as clutter, so it is
/// dropped — the wheel, trackpad and touch scrolling are unaffected.
class _NoScrollbar extends MaterialScrollBehavior {
  const _NoScrollbar();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
