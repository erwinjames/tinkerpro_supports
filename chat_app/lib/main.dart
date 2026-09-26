import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'platform_info.dart';
import 'push_service.dart';
import 'services/auth_service.dart';
import 'services/chat_head.dart';
import 'services/chat_prefs.dart';
import 'services/handoff_service.dart';
import 'services/theme_prefs.dart';
import 'services/tone_prefs.dart';
import 'theme.dart';
import 'screens/auth_screens.dart';
import 'screens/chat_shell.dart';
import 'screens/handoff_screen.dart';

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChatHeadOverlayApp());
}

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

  if (kIsMobilePlatform) {
    unawaited(TonePrefs.applyToRingtoneService().then((_) {
      return TonePrefs.syncChannels();
    }));
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

class TinkerProChatApp extends StatefulWidget {
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
  State<TinkerProChatApp> createState() => _TinkerProChatAppState();
}

class _TinkerProChatAppState extends State<TinkerProChatApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late final AuthService _auth = AuthService(widget.api);
  late final PushService _push = PushService(widget.api);
  late final HandoffService _handoff = HandoffService(widget.api);

  bool _promptOpen = false;

  @override
  void initState() {
    super.initState();
    _handoff.addListener(_onHandoffChanged);
    if (widget.api.hasBaseUrl) unawaited(_handoff.bootstrap());
  }

  @override
  void dispose() {
    _handoff.removeListener(_onHandoffChanged);
    _handoff.dispose();
    super.dispose();
  }

  void _onHandoffChanged() {
    final message = _handoff.message;
    if (message != null && message.isNotEmpty) {
      _handoff.clearMessage();
      _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
    }

    final offer = _handoff.offer;
    if (offer != null && !_promptOpen) {
      _promptOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showPrompt(offer));
      return;
    }
    if (offer == null && _promptOpen) {
      _promptOpen = false;
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
  }

  void _showPrompt(HandoffOffer offer) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      _promptOpen = false;
      return;
    }
    navigator
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ContinueAsScreen(
              api: widget.api,
              offer: offer,
              signedInAs: widget.api.hasSession ? widget.api.username : null,
              onContinue: _acceptHandoff,
              onUseAnother: _handoff.dismiss,
            ),
          ),
        )
        .then((_) {
      _promptOpen = false;
      _handoff.dismiss();
    });
  }

  Future<void> _acceptHandoff(bool remember) async {
    final offer = _handoff.offer;
    if (offer == null) return;
    try {
      await _auth.loginWithHandoff(offer.token, remember: remember);
      final convId = offer.conversationId;
      if (convId != null && convId > 0) {
        _push.pendingChatNavigation.setTarget(convId);
      }
      _promptOpen = false;
      _handoff.dismiss();
      _navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => ChatShell(
            api: widget.api,
            push: _push,
            auth: _auth,
            chatPrefs: widget.chatPrefs,
            themePrefs: widget.themePrefs,
          ),
        ),
        (_) => false,
      );
    } catch (error) {
      _promptOpen = false;
      _handoff.dismiss();
      _messengerKey.currentState
          ?.showSnackBar(SnackBar(content: Text(_handoffError(error))));
    }
  }

  String _handoffError(Object error) {
    var text = error.toString();
    for (final prefix in ['Exception: ', 'HttpException: ']) {
      if (text.startsWith(prefix)) text = text.substring(prefix.length);
    }
    return text.trim().isEmpty
        ? 'That sign-in link is no longer valid.'
        : text.trim();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.themePrefs,
      builder: (context, _) => MaterialApp(
        title: 'TinkerPro Chat',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        scrollBehavior: const _NoScrollbar(),
        theme: lightTheme(),
        darkTheme: darkTheme(),
        themeMode: widget.themePrefs.value,
        home: _RootRouter(
          api: widget.api,
          auth: _auth,
          push: _push,
          chatPrefs: widget.chatPrefs,
          themePrefs: widget.themePrefs,
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

class _NoScrollbar extends MaterialScrollBehavior {
  const _NoScrollbar();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
