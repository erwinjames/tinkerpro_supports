import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'api_client.dart';
import 'services/call_service.dart';
import 'services/chat_realtime.dart';
import 'services/chat_service.dart';
import 'services/lan_presence.dart';
import 'services/pos_shop_service.dart';
import 'services/os_notifications.dart';
import 'services/remote_access_service.dart';
import 'services/session_store.dart';
import 'services/support_notifier.dart';
import 'services/ticket_service.dart' show ShopInfo;
import 'screens/ai_chat_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/store_setup_screen.dart';
import 'screens/qr_sync_screen.dart';
import 'platform_info.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // window_manager is desktop-only; guard so the same source still
  // builds on mobile if we ever target it. On Windows the chat
  // screen later toggles setAlwaysOnTop / setPreventClose around
  // the "waiting for ticket acceptance" state — initializing here
  // is the prerequisite for those calls to take effect.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    // Fit the screen on launch: wait until the native window is ready,
    // then maximize so the form uses the whole monitor (a POS terminal
    // runs this as the primary window). Kept as a window (not full
    // borderless) so the cashier still has the title-bar close button.
    const winOpts = WindowOptions(
      title: 'TinkerPro Employee',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(winOpts, () async {
      await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
  }
  // Register the OS/system notification backend early (desktop needs the
  // AppUserModelID shortcut in place before the first toast). Best-effort.
  await OsNotifications.instance.init();
  final store = await SessionStore.open();
  // Mobile adopts the server URL scanned from the desktop's sync QR; desktop
  // leaves this null and uses the compile-time TPS_BASE_URL default.
  final api = await ApiClient.create(overrideBaseUrl: store.serverBaseUrl);
  runApp(EmployeeApp(api: api, store: store));
}

class EmployeeApp extends StatelessWidget {
  const EmployeeApp({super.key, required this.api, required this.store});

  final ApiClient api;
  final SessionStore store;

  /// Root navigator key so the global Esc-to-go-back shortcut can pop the
  /// current route from outside any screen's BuildContext.
  static final GlobalKey<NavigatorState> _navKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TinkerPro Employee',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: _navKey,
      // Bind the keyboard Esc key to "go back" everywhere — the POS
      // terminal is keyboard-first, so Esc should do exactly what tapping
      // any screen's back/close button does. maybePop() routes through
      // each route's PopScope (e.g. the chat screen's pending-ticket lock
      // and the active-call guard), so Esc respects the same guards a
      // back tap would and never force-closes a blocked screen. Dialogs
      // already handle Esc via their own dismiss intent, so this only
      // kicks in for full-page routes.
      builder: (context, child) {
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () {
              _navKey.currentState?.maybePop();
            },
          },
          child: Focus(
            autofocus: true,
            // App-wide activity tap detector — any pointer-down on any route
            // resets the mobile inactivity timer. Listener doesn't intercept
            // events, so it never interferes with the actual UI.
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _BootstrapState.onActivity?.call(),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      home: _Bootstrap(api: api, store: store),
    );
  }
}

/// Decides which screen to show on launch:
///   - no store_name in prefs        → StoreSetupScreen
///   - store_name present            → call chat.employeeStart, then chat
///
/// On a re-install where the cookie jar was wiped, calling
/// chat.employeeStart with the same store name re-binds the session to
/// the existing guest user on the server (per
/// findOrCreateEmployeeConversation), so chat history resumes.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.api, required this.store});

  final ApiClient api;
  final SessionStore store;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> with WidgetsBindingObserver {
  // _api / _chat are mutable so the mobile QR-sync flow can swap in an
  // ApiClient re-based onto the scanned server URL before bootstrapping.
  late ApiClient _api;
  late ChatService _chat;
  ChatRealtimeService? _realtime;
  CallService? _calls;
  LanPresence? _lan;
  EmployeeChatInfo? _info;
  String? _error;
  bool _resolving = false;

  // ── Mobile inactivity timeout ──────────────────────────────────────────
  // Mobile only (the desktop POS terminal is a kiosk and stays signed in):
  // after this much idle/away time the session is ended and the user must
  // re-scan the desktop QR to sign back in.
  static const _idleTimeout = Duration(hours: 1);
  Timer? _idleTimer;
  DateTime? _lastTouchWrite;
  bool _endingSession = false;

  /// Set while a mobile session is live so the app-wide pointer Listener in
  /// EmployeeApp.builder can report user activity from any route.
  static void Function()? onActivity;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    if (onActivity != null) onActivity = null;
    _lan?.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Coming back to the foreground: if we've been idle/away past the
      // limit, end the session; otherwise treat the return as activity and
      // re-establish the realtime socket (which the OS may have silently
      // killed in the background).
      if (_info != null && kIsMobilePlatform && _sessionExpired()) {
        _endSession();
        return;
      }
      _touchActivity();
      final info = _info;
      if (info != null) {
        _realtime?.kick(
          shadowUserId: info.meId,
          conversationId: info.conversationId,
        );
      }
    }
  }

  /// True when the last recorded activity is older than [_idleTimeout].
  bool _sessionExpired() {
    final last = widget.store.lastActiveAt;
    if (last == null) return false;
    return DateTime.now().difference(last) >= _idleTimeout;
  }

  /// Record "the app is being used now". Throttled so we don't hammer
  /// SharedPreferences on every pointer event. Mobile only.
  void _touchActivity() {
    if (!kIsMobilePlatform) return;
    final now = DateTime.now();
    if (_lastTouchWrite != null &&
        now.difference(_lastTouchWrite!) < const Duration(seconds: 20)) {
      return;
    }
    _lastTouchWrite = now;
    unawaited(widget.store.setLastActiveAt(now));
  }

  void _startIdleWatch() {
    if (!kIsMobilePlatform) return;
    _touchActivity();
    onActivity = _touchActivity;
    _idleTimer?.cancel();
    // Check once a minute while foregrounded; the resume/launch checks cover
    // time spent backgrounded (timers are throttled there anyway).
    _idleTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_info != null && _sessionExpired()) _endSession();
    });
  }

  /// End the session: tear down realtime/calls, clear the stored identity +
  /// server cookies, pop back to the root, and let the build show the QR
  /// login again.
  Future<void> _endSession() async {
    if (_endingSession) return;
    _endingSession = true;
    _idleTimer?.cancel();
    onActivity = null;
    try {
      await _realtime?.dispose();
    } catch (_) {}
    SupportNotifier.instance.detach();
    _lan?.stop();
    try {
      await _api.wipeCookies();
    } catch (_) {}
    await widget.store.reset();
    await widget.store.clearLastActiveAt();
    if (!mounted) {
      _endingSession = false;
      return;
    }
    // Drop any pushed screens (ticket form, chat, etc.) so we land on the
    // bootstrap root, which now renders the QR-login screen.
    Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
    setState(() {
      _info = null;
      _realtime = null;
      _calls = null;
      _lan = null;
      _resolving = false;
      _error = null;
      _endingSession = false;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = widget.api;
    _chat = ChatService(_api);
    if (widget.store.isConfigured) {
      if (kIsMobilePlatform && _sessionExpired()) {
        // Inactivity window elapsed while the app was closed — don't resume,
        // drop straight to the QR login.
        WidgetsBinding.instance.addPostFrameCallback((_) => _endSession());
      } else {
        _resumeFromStoredName();
      }
    }
    // Warm the POS DB lookup in the background so the /ticket form can
    // render from cache instantly when the user eventually opens it.
    // Fire-and-forget: a failure here is silent (the ticket form will
    // do its own discovery if cache is still empty by then).
    unawaited(_prewarmShopInfo());
  }

  Future<void> _prewarmShopInfo() async {
    try {
      // Only prewarm when an admin has actually configured a target. We
      // never auto-run the slow /24 LAN sweep at launch — that's the
      // whole reason for moving to admin-pinned config. If nothing's
      // configured yet, the ticket form's setup panel handles it.
      if (!widget.store.hasPosManualTarget) return;
      final svc = PosShopService(store: widget.store);
      final apiHost = Uri.tryParse(_api.baseUrl)?.host;
      final hints = <String>[if (apiHost != null && apiHost.isNotEmpty) apiHost];
      final pos = await svc.getShopInfo(
        hintHosts: hints,
        manualHost: widget.store.posManualHost,
        manualPort: widget.store.posManualPort,
      );
      if (pos == null) return;
      final businessName = pos.businessName.isNotEmpty
          ? pos.businessName
          : (widget.store.storeName ?? '');
      await widget.store.saveCachedShop(
        ShopInfo(
          businessName: businessName,
          vatReg: pos.vatReg,
          vatLabel: pos.vatLabel,
          tin: pos.tin,
          email: '',
          fullName: '',
        ),
      );
    } catch (_) {
      // Best-effort prewarm — never surface errors here.
    }
  }

  Future<void> _resumeFromStoredName() async {
    final name = widget.store.storeName ?? '';
    if (name.isEmpty) return;
    setState(() {
      _resolving = true;
      _error = null;
    });
    final info = await _chat.employeeStart(name);
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _resolving = false;
        _error = 'Could not resume session. Check your connection and retry.';
      });
      return;
    }
    // The store's latest ticket is already resolved/closed → don't resume back
    // into that dead chat. Drop the pending pointer so we land on the home (AI)
    // screen where the cashier can file a fresh ticket, instead of reopening a
    // read-only thread. (Authoritative server status, not the resolve bubble.)
    if (info.isTicketClosed) {
      await widget.store.clearPendingTicket();
    }
    await widget.store.saveIdentity(
      userId: info.meId,
      convId: info.conversationId,
    );
    _wireRealtimeAndCalls(info);
  }

  void _wireRealtimeAndCalls(EmployeeChatInfo info) {
    // Prefer the Soketi endpoint carried in the sync QR (the one the desktop
    // actually connects to). Falls back to the compile-time default when not
    // present (e.g. desktop builds, or manual mobile setup).
    final s = widget.store;
    final ChatRealtimeConfig? rtConfig = s.hasWsConfig
        ? ChatRealtimeConfig(
            apiKey: s.wsKey,
            host: s.wsHost!,
            port: s.wsPort,
            useTls: s.wsTls,
            path: s.wsPath,
          )
        : null;
    final realtime = ChatRealtimeService(_api, config: rtConfig);
    final calls = CallService(
      realtime: realtime,
      chat: _chat,
      shadowUserId: info.meId,
      conversationId: info.conversationId,
    );
    realtime.connect(
      shadowUserId: info.meId,
      conversationId: info.conversationId,
    );

    // Watch this store's conversation for agent messages so the cashier
    // is alerted (badge + banner + sound + OS toast) even when they're on
    // the AI landing or the app is minimized. onOpenChat is wired by the
    // landing screen, which owns the deps needed to push the chat route.
    SupportNotifier.instance.attach(
      realtime: realtime,
      meId: info.meId,
      convId: info.conversationId,
    );
    OsNotifications.instance.onTap =
        () => SupportNotifier.instance.onOpenChat?.call();

    // Same-store LAN discovery for the chat's "Add participant" picker.
    final lan = LanPresence(userId: info.meId, storeName: info.storeName);
    lan.start();

    // Eagerly extract + launch the bundled RustDesk so it registers
    // its ID with the rendezvous server in the background, and so the
    // /remote password gets pushed via IPC into the live instance.
    // prepare() now handles the launch itself — see RemoteAccessService.
    // Desktop-only: the mobile APK ships no RustDesk binary and hides the
    // entire remote-desktop flow, so we never spin it up there.
    if (kIsDesktopPlatform) {
      unawaited(RemoteAccessService.instance.prepare());
    }

    setState(() {
      _info = info;
      _realtime = realtime;
      _calls = calls;
      _lan = lan;
      _resolving = false;
    });
    // Session is live — begin tracking inactivity (mobile only).
    _startIdleWatch();
  }

  void _onSetupReady(EmployeeChatInfo info) {
    _wireRealtimeAndCalls(info);
  }

  /// Mobile QR-sync completed: the scanner already saved the server URL +
  /// store name and ran chat.employeeStart against a fresh ApiClient based
  /// on the scanned URL. Adopt that client and resume the normal flow.
  void _onMobileSynced(ApiClient api, EmployeeChatInfo info) {
    _api = api;
    _chat = ChatService(api);
    _wireRealtimeAndCalls(info);
  }

  @override
  Widget build(BuildContext context) {
    // Not configured yet — first-launch screen.
    if (!widget.store.isConfigured) {
      // Mobile onboards by scanning the desktop's sync QR (no manual entry).
      // Desktop keeps typing the store name — it's the device that GENERATES
      // the QR for phones to scan.
      if (kIsMobilePlatform) {
        return QrSyncScreen(
          store: widget.store,
          onSynced: _onMobileSynced,
        );
      }
      return StoreSetupScreen(
        chat: _chat,
        store: widget.store,
        onReady: _onSetupReady,
      );
    }

    // Configured but bootstrap failed — show retry.
    if (_error != null) {
      return Scaffold(
        backgroundColor: Brand.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off,
                    size: 48, color: Brand.textMuted),
                const SizedBox(height: 16),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _resolving ? null : _resumeFromStoredName,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Still resolving on warm start.
    if (_info == null || _realtime == null || _calls == null) {
      return const Scaffold(
        backgroundColor: Brand.surface,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    // Resume-on-restart: if the user closed the app while sitting on
    // the "Waiting for support to accept your ticket" card, the
    // pending pointer in SessionStore re-pins them to the same
    // scoped chat instead of dumping them on the Help Guide.
    // EmployeeChatScreen reads its sinceMessageId, parses the
    // matching ticket id and accepted/resolved state from history,
    // and clears the pending pointer the moment the ticket actually
    // moves forward.
    if (widget.store.hasPendingTicket) {
      return EmployeeChatScreen(
        api: _api,
        chat: _chat,
        realtime: _realtime!,
        calls: _calls!,
        lan: _lan!,
        store: widget.store,
        info: _info!,
        sinceMessageId: widget.store.pendingTicketAnchorMessageId,
        onTicketClosed: (ctx) {
          // On resolution we drop control back to the AI-first landing
          // screen so the cashier can either ask the bot another
          // question or open the FAQ / file another ticket.
          Navigator.of(ctx).pushReplacement(
            MaterialPageRoute(
              builder: (_) => AiChatScreen(
                api: _api,
                chat: _chat,
                realtime: _realtime!,
                calls: _calls!,
                lan: _lan!,
                store: widget.store,
                info: _info!,
              ),
            ),
          );
        },
      );
    }

    // No pending ticket — land on the new AI-first POS support screen.
    // The top bar's "Help articles" opens the legacy HelpGuideScreen
    // (FAQ), and "Submit ticket" opens the TicketFormScreen → live chat
    // flow that HelpGuideScreen used to drive.
    return AiChatScreen(
      api: _api,
      chat: _chat,
      realtime: _realtime!,
      calls: _calls!,
      lan: _lan!,
      store: widget.store,
      info: _info!,
    );
  }
}
