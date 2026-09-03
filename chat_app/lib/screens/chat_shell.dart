import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../push_service.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/chat_prefs.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../services/incoming_call_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/theme_prefs.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'auth_screens.dart';
import 'call_screen.dart';
import 'chat_inbox_screen.dart';
import 'chat_thread_screen.dart';
import 'settings_screen.dart';

class ChatShell extends StatefulWidget {
  const ChatShell({
    super.key,
    required this.api,
    required this.push,
    required this.auth,
    required this.chatPrefs,
    required this.themePrefs,
  });

  final ApiClient api;
  final PushService push;
  final AuthService auth;
  final ChatPrefs chatPrefs;
  final ThemePrefs themePrefs;

  @override
  State<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends State<ChatShell> with WidgetsBindingObserver {
  late final ChatService _chatService;
  late final ChatRealtimeService _chatRealtime;
  ChatInbox? _chatInbox;
  CallService? _callService;
  NotificationCenter? _notifications;
  StreamSubscription<IncomingCallEvent>? _incomingCallSub;
  bool _callScreenOpen = false;
  int? _myUserId;
  bool _chatStarted = false;
  bool _permissionsChecked = false;
  String? _chatBootstrapError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _chatService = ChatService(widget.api);
    _chatRealtime = ChatRealtimeService(widget.api);
    widget.push.registerCurrentDevice();

    _startIfPermitted();
    _reportLocation();
  }

  /// Chat is gated on the `chat` permission, matching the web sidebar and the
  /// full support app. Start immediately when the cached map already grants
  /// it, then re-check against the server — a permission granted on the web
  /// since last launch lights the app up without a re-login, and one revoked
  /// there closes it on next open.
  Future<void> _startIfPermitted() async {
    if (widget.api.hasPermission('chat')) {
      _chatStarted = true;
      _bootstrapChat();
    }
    await widget.auth.refreshPermissions();
    if (!mounted) return;
    setState(() => _permissionsChecked = true);
    if (!_chatStarted && widget.api.hasPermission('chat')) {
      _chatStarted = true;
      _bootstrapChat();
    }
  }

  /// Prompts for location on open and reports it so the web activity log
  /// records where this session was opened. Fire-and-forget: chat never
  /// waits on it, and a refused prompt is not an error.
  Future<void> _reportLocation() async {
    await LocationService(widget.api).reportOnOpen();
  }

  Future<void> _bootstrapChat() async {
    if (!mounted) return;
    setState(() => _chatBootstrapError = null);

    final cached = widget.api.userId;
    if (cached != null && cached > 0) {
      final alive = await _chatService.sessionAlive();
      if (!mounted) return;
      if (!alive) {
        await _handleStaleSession();
        return;
      }
    }

    final probe = await widget.auth.currentUserIdWithReason();
    if (!mounted) return;
    final uid = probe.userId;
    if (uid == null) {
      setState(() => _chatBootstrapError = probe.error ??
          'Could not load chat. Check your connection or sign in again.');
      return;
    }

    final inbox = ChatInbox(_chatService, _chatRealtime);
    final calls = CallService(
      realtime: _chatRealtime,
      chat: _chatService,
      myUserId: uid,
    );
    calls.addListener(_onCallChange);

    IncomingCallEvents.instance.start();
    _incomingCallSub = IncomingCallEvents.instance.stream.listen((evt) {
      switch (evt.action) {
        case IncomingCallAction.accept:
          calls.acceptIncomingFromPush(
            callId: evt.callId,
            callerId: evt.callerId,
            callerName: evt.callerName,
            media: evt.media,
          );
          break;
        case IncomingCallAction.decline:
        case IncomingCallAction.timeout:
          calls.declineIncomingFromPush(
            callId: evt.callId,
            callerId: evt.callerId,
            media: evt.media,
          );
          break;
        case IncomingCallAction.ended:
          break;
      }
    });

    final notifications =
        NotificationCenter(NotificationService(widget.api), _chatRealtime);

    setState(() {
      _myUserId = uid;
      _chatInbox = inbox;
      _callService = calls;
      _notifications = notifications;
    });

    unawaited(notifications.load());

    inbox.addListener(_onInboxChange);

    widget.push.bindCurrentlyViewedConv(_chatRealtime.currentlyViewedConv);
    widget.push.bindChatPrefs(widget.chatPrefs);
    widget.push.pendingChatNavigation.addListener(_consumePendingChatNav);
    _chatRealtime.currentlyViewedConv.addListener(_onCurrentConvChanged);

    unawaited(_chatRealtime.connect(uid));
    unawaited(inbox.load());

    _consumePendingChatNav();
  }

  void _onInboxChange() {
    if (_chatInbox?.authFailed == true) {
      _handleStaleSession();
    }
  }

  Future<void> _handleStaleSession() async {
    try {
      await widget.push.releaseCurrentDevice();
    } catch (_) {}
    try {
      await widget.auth.logout();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          api: widget.api,
          auth: widget.auth,
          chatPrefs: widget.chatPrefs,
          themePrefs: widget.themePrefs,
        ),
      ),
      (_) => false,
    );
  }

  void _onCurrentConvChanged() {
    final id = _chatRealtime.currentlyViewedConv.value;
    if (id != null) widget.push.dismissBubble(id);
  }

  Future<void> _consumePendingChatNav() async {
    final convId = widget.push.pendingChatNavigation.consume();
    if (convId == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openThreadFromNav(convId);
    });
  }

  void _openThreadFromNav(int convId) {
    final inbox = _chatInbox;
    final uid = _myUserId;
    if (inbox == null || uid == null || !mounted) return;
    final match = inbox.conversations.where((c) => c.id == convId).toList();
    final conv = match.isNotEmpty ? match.first : null;
    inbox.markLocallyRead(convId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          conversationId: convId,
          conversation: conv,
          myUserId: uid,
          service: _chatService,
          realtime: _chatRealtime,
          api: widget.api,
          chatPrefs: widget.chatPrefs,
          calls: _callService,
        ),
      ),
    );
  }

  void _onCallChange() {
    final calls = _callService;
    if (calls == null || !mounted) return;
    if (calls.isActive && !_callScreenOpen) {
      _callScreenOpen = true;
      Navigator.of(context, rootNavigator: true)
          .push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => CallScreen(calls: calls),
            ),
          )
          .whenComplete(() => _callScreenOpen = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          api: widget.api,
          auth: widget.auth,
          push: widget.push,
          chatPrefs: widget.chatPrefs,
          themePrefs: widget.themePrefs,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _chatRealtime.pause();
        break;
      case AppLifecycleState.resumed:
        _chatRealtime.resume();
        _chatInbox?.reload();
        _notifications?.load();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.push.pendingChatNavigation.removeListener(_consumePendingChatNav);
    _incomingCallSub?.cancel();
    _callService?.removeListener(_onCallChange);
    _callService?.dispose();
    _notifications?.dispose();
    _chatRealtime.dispose();
    _chatInbox?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.api.hasPermission('chat')) {
      return _permissionsChecked
          ? _AccessDenied(onSignOut: _handleStaleSession)
          : const _ChatBootstrapSplash();
    }

    final inbox = _chatInbox;
    final uid = _myUserId;
    if (inbox == null || uid == null) {
      return _ChatBootstrapSplash(
        error: _chatBootstrapError,
        onRetry: _bootstrapChat,
        onSignOut: _handleStaleSession,
      );
    }
    return ChatInboxScreen(
      service: _chatService,
      realtime: _chatRealtime,
      inbox: inbox,
      myUserId: uid,
      api: widget.api,
      chatPrefs: widget.chatPrefs,
      onSignOut: _handleStaleSession,
      onOpenSettings: _openSettings,
      notifications: _notifications,
      calls: _callService,
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final brand = context.brand;
    return Scaffold(
      backgroundColor: brand.canvas,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: brand.surfaceHi,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline,
                      size: 24, color: brand.paperDim),
                ),
                const SizedBox(height: 16),
                Text(
                  'Chat access not enabled',
                  style: text.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'This account does not have chat permission. Ask an '
                  'administrator to enable Chat for you, then open the app '
                  'again.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: 220,
                  child: GhostButton(
                    label: 'Sign out',
                    onPressed: onSignOut,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBootstrapSplash extends StatelessWidget {
  const _ChatBootstrapSplash({this.error, this.onRetry, this.onSignOut});

  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.brand.canvas,
      body: Center(
        child: error == null
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Brand.signal,
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CHAT UNAVAILABLE',
                      style: text.labelLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Hairline(),
                    const SizedBox(height: 16),
                    Text(
                      error!,
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (onRetry != null)
                      SizedBox(
                        width: 200,
                        child: SignalButton(
                          label: 'Retry',
                          icon: Icons.refresh,
                          onPressed: onRetry,
                        ),
                      ),
                    if (onSignOut != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 200,
                        child: GhostButton(
                          label: 'Sign out',
                          onPressed: onSignOut!,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
