import 'dart:async';
import 'dart:io' show File, Platform, exit;
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'api_client.dart';
import 'debug_bir_review.dart';
import 'debug_capture.dart';
import 'shell_badges.dart';
import 'shell_icons.dart';
import 'shell_notifications.dart';
import 'shell_reminders.dart';
import 'services/admin_services.dart';
import 'services/call_service.dart';
import 'services/chat_prefs.dart';
import 'services/chat_runtime.dart';
import 'services/desktop_alerts.dart';
import 'services/sound_engine.dart';
import 'services/desktop_notifier.dart';
import 'screens/admin/admin_list.dart' show confirmDialog;
import 'services/folder_sync_engine.dart';
import 'services/live_sync.dart';
import 'services/saved_logins.dart';
import 'services/nav_service.dart';
import 'services/notification_center.dart';
import 'services/services.dart';
import 'services/task_service.dart';
import 'services/theme_prefs.dart';
import 'theme.dart';
import 'widgets/floating_chat_dock.dart';
import 'widgets/premium.dart';
import 'screens/call_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/ticket_list_screen.dart';
import 'screens/lead_list_screen.dart';
import 'screens/customer_list_screen.dart';
import 'screens/task_list_screen.dart';
import 'screens/admin/pos_version_screen.dart';
import 'screens/admin/license_key_screen.dart';
import 'screens/admin/release_notes_screen.dart';
import 'screens/admin/help_screen.dart';
import 'screens/admin/email_screen.dart';
import 'screens/admin/users_screen.dart';
import 'screens/admin/credentials_screen.dart';
import 'screens/admin/files_screen.dart';
import 'screens/admin/blog_screen.dart';
import 'screens/admin/activity_logs_screen.dart';
import 'screens/chat_page.dart';
import 'screens/profile_panel.dart';
import 'screens/web/barcode_screen.dart';
import 'screens/web/client_screen.dart';
import 'screens/web/feedback_submit_dialog.dart';
import 'screens/web/announcements_screen.dart';
import 'screens/web/app_downloads_screen.dart';
import 'screens/web/feedback_screen.dart';
import 'screens/web/offers_screen.dart';
import 'screens/web/pricing_screen.dart';
import 'screens/web/taxpayer_portal_screen.dart';
import 'screens/web/web_settings_screen.dart';
import 'screens/web/whats_new_screen.dart';
import 'screens/web/employment_screen.dart';
import 'screens/web/vendor_portal_screen.dart';
import 'screens/web/zreading_screen.dart';
import 'widgets/brand_asset.dart';
import 'widgets/toast_host.dart';

const String kLiveServerUrl = 'https://support.tinkerpro.io';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    minimumSize: Size(800, 560),
    title: 'TinkerPro Support — Control Suite',
    titleBarStyle: TitleBarStyle.normal,
    backgroundColor: Colors.transparent,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitle('TinkerPro Support — Control Suite');
    await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });

  final api = await ApiClient.load();
  if (!api.hasBaseUrl) {
    await api.setBaseUrl(kLiveServerUrl);
  }

  final prefs = await SharedPreferences.getInstance();
  final themePrefs = await ThemePrefs.load(prefs);
  final chatPrefs = ChatPrefs(prefs);
  await DesktopNotifier.instance.init(prefs);

  await loadShellFonts();

  installDebugErrorLog();
  scheduleDebugCapture();
  if (kDebugMode && Platform.environment['TP_BIR_REVIEW'] == '1') {
    runApp(debugBirReviewApp(api));
    return;
  }
  runApp(
    SupportDesktopApp(api: api, themePrefs: themePrefs, chatPrefs: chatPrefs),
  );
}

final GlobalKey<ScaffoldMessengerState> navigatorKeyMessenger =
    GlobalKey<ScaffoldMessengerState>();

class SupportDesktopApp extends StatelessWidget {
  const SupportDesktopApp({
    super.key,
    required this.api,
    required this.themePrefs,
    required this.chatPrefs,
  });

  final ApiClient api;
  final ThemePrefs themePrefs;
  final ChatPrefs chatPrefs;

  @override
  Widget build(BuildContext context) {
    final auth = AuthService(api);
    return AnimatedBuilder(
      animation: themePrefs,
      builder: (context, _) => MaterialApp(
        scaffoldMessengerKey: navigatorKeyMessenger,
        title: 'TinkerPro Support',
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        darkTheme: darkTheme(),
        themeMode: themePrefs.value,
        builder: (context, child) => debugCaptureWrap(
          toastHost(GlobalShortcuts(child: child ?? const SizedBox.shrink())),
        ),
        home:
            api.hasSession &&
                !(kDebugMode && Platform.environment['TP_FORCE_LOGIN'] == '1')
            ? DesktopShell(
                api: api,
                auth: auth,
                themePrefs: themePrefs,
                chatPrefs: chatPrefs,
              )
            : LoginScreen(
                api: api,
                auth: auth,
                themePrefs: themePrefs,
                chatPrefs: chatPrefs,
              ),
      ),
    );
  }
}

class GlobalShortcuts extends StatelessWidget {
  const GlobalShortcuts({super.key, required this.child});

  final Widget child;

  void _back() {
    final ctx = primaryFocus?.context;
    if (ctx == null) return;
    final nav = Navigator.maybeOf(ctx);
    if (nav != null && nav.canPop()) nav.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _back},
      child: Focus(autofocus: true, child: child),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.themePrefs,
    required this.chatPrefs,
  });

  final ApiClient api;
  final AuthService auth;
  final ThemePrefs themePrefs;
  final ChatPrefs chatPrefs;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _remember = true;
  String? _error;
  List<SavedLogin> _saved = const [];
  DateTime? _lockedUntil;
  Timer? _lockTick;

  bool get _locked =>
      _lockedUntil != null && DateTime.now().isBefore(_lockedUntil!);

  String get _lockText {
    if (!_locked) return '';
    final left = _lockedUntil!.difference(DateTime.now());
    final m = left.inMinutes;
    final sec = (left.inSeconds % 60).toString().padLeft(2, '0');
    return 'Try again in $m:$sec';
  }

  void _startLock(Duration wait) {
    if (wait <= Duration.zero) return;
    _lockedUntil = DateTime.now().add(wait);
    _lockTick?.cancel();
    _lockTick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!_locked) {
        t.cancel();
        _lockedUntil = null;
      }
      setState(() {});
    });
  }

  bool _phoneMode = false;
  PhoneLoginRequest? _phoneReq;
  String? _phoneEnded;
  Timer? _phoneTimer;
  bool _phonePolling = false;
  DateTime? _phoneNextPoll;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    if (kDebugMode && Platform.environment['TP_PHONE_LOGIN'] == '1') {
      _phoneMode = true;
      final id = Platform.environment['TP_PHONE_ID'] ?? '';
      if (id.isNotEmpty) {
        _email.text = id;
        WidgetsBinding.instance.addPostFrameCallback((_) => _startPhone());
      }
    }
  }

  void _enterShell() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DesktopShell(
          api: widget.api,
          auth: widget.auth,
          themePrefs: widget.themePrefs,
          chatPrefs: widget.chatPrefs,
        ),
      ),
    );
  }

  void _setPhoneMode(bool on) {
    _stopPhone();
    setState(() {
      _phoneMode = on;
      _phoneReq = null;
      _phoneEnded = null;
      _error = null;
    });
  }

  void _stopPhone() {
    _phoneTimer?.cancel();
    _phoneTimer = null;
    _phonePolling = false;
    _phoneNextPoll = null;
  }

  Future<void> _startPhone() async {
    if (_busy || _locked) return;
    final id = _email.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Enter your username or email.');
      return;
    }
    _stopPhone();
    setState(() {
      _busy = true;
      _error = null;
      _phoneEnded = null;
    });
    try {
      final req = await widget.auth.startPhoneLogin(id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phoneReq = req;
      });
      _phoneNextPoll = DateTime.now().add(const Duration(seconds: 2));
      _phoneTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _phoneTick(),
      );
    } on LoginFailure catch (e) {
      if (!mounted) return;
      _startLock(e.retryAfter);
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on RateLimitedException catch (e) {
      if (!mounted) return;
      _startLock(e.retryAfter);
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _phoneTick() async {
    final req = _phoneReq;
    if (!mounted || req == null) return;
    final now = DateTime.now();
    if (now.isAfter(req.expiresAt.add(const Duration(seconds: 4)))) {
      _stopPhone();
      setState(
        () => _phoneEnded =
            'The request expired before it was approved. Send a new one to try again.',
      );
      return;
    }
    setState(() {});
    if (_phonePolling ||
        widget.api.coolingDown ||
        (_phoneNextPoll != null && now.isBefore(_phoneNextPoll!))) {
      return;
    }
    _phonePolling = true;
    try {
      final r = await widget.auth.pollPhoneLogin(req);
      if (!mounted || !identical(req, _phoneReq)) return;
      switch (r.state) {
        case PhoneLoginState.approved:
          _stopPhone();
          _enterShell();
          return;
        case PhoneLoginState.denied:
        case PhoneLoginState.expired:
          _stopPhone();
          setState(() => _phoneEnded = r.message);
          return;
        case PhoneLoginState.pending:
          final wait = r.retryAfter > const Duration(seconds: 2)
              ? r.retryAfter
              : const Duration(seconds: 2);
          _phoneNextPoll = DateTime.now().add(wait);
      }
    } catch (_) {
      _phoneNextPoll = DateTime.now().add(const Duration(seconds: 4));
    } finally {
      _phonePolling = false;
    }
  }

  Future<void> _loadSaved() async {
    final list = await SavedLogins.instance.list(widget.api.baseUrl);
    if (mounted) setState(() => _saved = list);
  }

  Future<void> _useSaved(SavedLogin login) async {
    final pw = await SavedLogins.instance.password(
      widget.api.baseUrl,
      login.email,
    );
    if (!mounted) return;
    _email.text = login.email;
    if (pw == null || pw.isEmpty) {
      _password.clear();
      _passFocus.requestFocus();
      setState(() => _error = 'Saved password not found. Enter it to sign in.');
      return;
    }
    _password.text = pw;
    await _submit(fromSaved: true);
  }

  Future<void> _forgetSaved(SavedLogin login) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove saved login',
      message: 'Remove the saved login for ${login.email} from this computer?',
      confirmLabel: 'Remove',
    );
    if (!ok) return;
    await SavedLogins.instance.remove(widget.api.baseUrl, login.email);
    await _loadSaved();
  }

  Future<void> _offerSave(String email, String password) async {
    final server = widget.api.baseUrl;
    final store = SavedLogins.instance;
    if (await store.isSaved(server, email)) {
      await store.save(server, email, password);
      return;
    }
    if (await store.wasPrompted(server, email)) return;
    if (!mounted) return;
    final save = await showWebModal<bool>(
      context,
      title: 'Save login for this account?',
      subtitle: email,
      icon: Icons.key_outlined,
      width: 460,
      barrierDismissible: false,
      builder: (_) => const Text(
        'Next time you can sign in from the login screen with one click, '
        'without typing your password. It is stored securely in this '
        "computer's keyring and you can remove it at any time.",
      ),
      actions: (ctx) => [
        GhostButton(
          label: 'Not now',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        SignalButton(
          label: 'Save login',
          icon: Icons.check,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    await store.markPrompted(server, email);
    if (save == true) await store.save(server, email, password);
  }

  @override
  void dispose() {
    _stopPhone();
    _lockTick?.cancel();
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit({bool fromSaved = false}) async {
    if (_busy || _locked) return;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login(email, password);
      if (!mounted) return;
      await _offerSave(email, password);
      if (!mounted) return;
      _enterShell();
    } on LoginFailure catch (e) {
      if (!mounted) return;
      var msg = e.message;
      if (fromSaved && e.wrongCredentials) {
        await SavedLogins.instance.remove(widget.api.baseUrl, email);
        await _loadSaved();
        _password.clear();
        _passFocus.requestFocus();
        msg =
            '$msg The saved password was removed — type your password to sign in.';
      }
      _startLock(e.retryAfter);
      setState(() {
        _busy = false;
        _error = msg;
      });
    } on RateLimitedException catch (e) {
      if (!mounted) return;
      _startLock(e.retryAfter);
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  static const _navy = Color(0xFF0C233E);
  static const _orange = Color(0xFFF5690B);
  static const _orange2 = Color(0xFFFF8C3B);
  static const _ink80 = Color(0xCC1A1A1A);

  InputDecoration _field(String hint, {Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.95),
      isDense: true,
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 36),
      hintStyle: const TextStyle(color: Color(0x661A1A1A), fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      enabledBorder: border(const Color(0x1F000000)),
      border: border(const Color(0x1F000000)),
      focusedBorder: border(_orange.withValues(alpha: 0.6)),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _ink80,
        fontSize: 14.4,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _glow(FocusNode node, Widget child) => AnimatedBuilder(
    animation: node,
    builder: (context, _) => AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: node.hasFocus
            ? [
                BoxShadow(
                  color: _orange.withValues(alpha: 0.15),
                  spreadRadius: 4,
                ),
              ]
            : const [],
      ),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: lightTheme(),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFFF1F1F3)),
            Image(
              image: brandAsset('assets/brand/login_background.png'),
              fit: BoxFit.fill,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
            LayoutBuilder(
              builder: (context, c) {
                final leftPad = (c.maxWidth * 0.27).clamp(160.0, 520.0);
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(leftPad, 20, 20, 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(width: 420, child: _card()),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  final _emailFocus = FocusNode();
  final _passFocus = FocusNode();

  Widget _errorBox(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0x26DC2626),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x66DC2626)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFFB91C1C),
        fontSize: 13.4,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  List<Widget> _phoneChildren() {
    final req = _phoneReq;
    if (req == null) {
      return [
        const Text(
          'Approve this sign-in from the TinkerPro Support app on your phone. '
          'Fingerprint sign-in must be turned on in the app.',
          style: TextStyle(color: _ink80, fontSize: 14, height: 1.45),
        ),
        const SizedBox(height: 22),
        _label('Username or Email'),
        _glow(
          _emailFocus,
          TextField(
            controller: _email,
            focusNode: _emailFocus,
            autofocus: true,
            style: const TextStyle(color: _navy, fontSize: 16),
            cursorColor: _orange,
            keyboardType: TextInputType.emailAddress,
            decoration: _field('username or name@example.com'),
            onSubmitted: (_) => _startPhone(),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), _errorBox(_error!)],
        const SizedBox(height: 26),
        _GradientButton(
          label: _busy
              ? 'SENDING…'
              : (_locked ? _lockText.toUpperCase() : 'SEND SIGN-IN REQUEST'),
          onPressed: _busy || _locked ? null : _startPhone,
        ),
        const SizedBox(height: 12),
        _OutlineAction(
          label: 'Use password instead',
          icon: Icons.password,
          onPressed: _busy ? null : () => _setPhoneMode(false),
        ),
      ];
    }

    final ended = _phoneEnded;
    final left = req.expiresAt.difference(DateTime.now());
    final secs = left.isNegative ? 0 : left.inSeconds;
    final countdown = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final fraction = (secs / 120).clamp(0.0, 1.0);

    return [
      Center(
        child: Container(
          width: 132,
          height: 132,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: ended == null
                  ? _orange.withValues(alpha: 0.55)
                  : const Color(0x1F000000),
              width: 2,
            ),
            boxShadow: ended == null
                ? [
                    BoxShadow(
                      color: _orange.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: Text(
            '${req.matchNumber}',
            style: TextStyle(
              color: ended == null ? _navy : const Color(0x661A1A1A),
              fontSize: 64,
              height: 1,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      if (ended == null) ...[
        const Text(
          'Open the notification on your phone, pick this number and '
          'confirm with your fingerprint.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _ink80,
            fontSize: 14.5,
            height: 1.45,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 5,
            color: _orange,
            backgroundColor: Colors.black.withValues(alpha: 0.08),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: _orange),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Waiting for approval…',
                style: TextStyle(color: Color(0x991A1A1A), fontSize: 13),
              ),
            ),
            Text(
              'Expires in $countdown',
              style: const TextStyle(
                color: Color(0x991A1A1A),
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _OutlineAction(
          label: 'Cancel',
          icon: Icons.close,
          onPressed: () => _setPhoneMode(false),
        ),
      ] else ...[
        _errorBox(ended),
        const SizedBox(height: 22),
        _GradientButton(
          label: _busy
              ? 'SENDING…'
              : (_locked ? _lockText.toUpperCase() : 'RESEND REQUEST'),
          onPressed: _busy || _locked ? null : _startPhone,
        ),
        const SizedBox(height: 12),
        _OutlineAction(
          label: 'Use password instead',
          icon: Icons.password,
          onPressed: _busy ? null : () => _setPhoneMode(false),
        ),
      ],
    ];
  }

  Widget _card() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 45,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
            ),
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image(
                    image: brandAsset('assets/brand/logo-stacked.png'),
                    width: 132,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.public, color: _orange, size: 56),
                  ),
                ),
                const SizedBox(height: 25),
                const Text(
                  'Support Access',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _navy,
                    fontSize: 28,
                    height: 1.2,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 30),
                if (_phoneMode) ..._phoneChildren(),
                if (!_phoneMode) ...[
                  if (_saved.isNotEmpty) ...[
                    _label('Saved accounts'),
                    for (final login in _saved)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            mouseCursor: SystemMouseCursors.click,
                            onTap: _busy || _locked
                                ? null
                                : () => _useSaved(login),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0x1F000000),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 15,
                                    backgroundColor: _navy,
                                    child: Text(
                                      login.email.isEmpty
                                          ? '?'
                                          : login.email[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      login.email,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _navy,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const Text(
                                    'Sign in',
                                    style: TextStyle(
                                      color: _orange,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove saved login',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _busy
                                        ? null
                                        : () => _forgetSaved(login),
                                    icon: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Color(0x991A1A1A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                  _label('Email Address'),
                  _glow(
                    _emailFocus,
                    TextField(
                      controller: _email,
                      focusNode: _emailFocus,
                      autofocus: true,
                      style: const TextStyle(color: _navy, fontSize: 16),
                      cursorColor: _orange,
                      keyboardType: TextInputType.emailAddress,
                      decoration: _field('name@example.com'),
                      onSubmitted: (_) => _passFocus.requestFocus(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _label('Key Password'),
                  _glow(
                    _passFocus,
                    TextField(
                      controller: _password,
                      focusNode: _passFocus,
                      obscureText: _obscure,
                      style: const TextStyle(color: _navy, fontSize: 16),
                      cursorColor: _orange,
                      decoration: _field(
                        '••••••••',
                        suffix: Tooltip(
                          message: 'Toggle Password Visibility',
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () => setState(() => _obscure = !_obscure),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 15),
                                child: Icon(
                                  _obscure
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  size: 17,
                                  color: const Color(0x731A1A1A),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => setState(() => _remember = !_remember),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: _remember
                                    ? _orange
                                    : Colors.black.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: _remember
                                      ? _orange
                                      : Colors.black.withValues(alpha: 0.25),
                                  width: 1.5,
                                ),
                                boxShadow: _remember
                                    ? [
                                        BoxShadow(
                                          color: _orange.withValues(alpha: 0.2),
                                          spreadRadius: 3,
                                        ),
                                      ]
                                    : const [],
                              ),
                              child: _remember
                                  ? const Icon(
                                      Icons.check,
                                      size: 13,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Keep me signed in',
                              style: TextStyle(
                                color: _ink80,
                                fontSize: 14.1,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _errorBox(_error!),
                  ],
                  const SizedBox(height: 26),
                  _GradientButton(
                    label: _busy
                        ? 'UNLOCKING…'
                        : (_locked
                              ? _lockText.toUpperCase()
                              : 'UNLOCK DASHBOARD'),
                    onPressed: _busy || _locked ? null : () => _submit(),
                  ),
                  const SizedBox(height: 12),
                  _OutlineAction(
                    label: 'Sign in with phone',
                    icon: Icons.phonelink_lock_outlined,
                    onPressed: _busy ? null : () => _setPhoneMode(true),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        widget.api.baseUrl
                            .replaceFirst(RegExp(r'^https?://'), '')
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Color(0x731A1A1A),
                          fontSize: 12.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Center(
                  child: _LegalLink(
                    label: 'Privacy Policy',
                    onTap: () => launchUrl(
                      Uri.parse('${widget.api.baseUrl}/privacy-policy'),
                      mode: LaunchMode.externalApplication,
                    ),
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

class _LegalLink extends StatefulWidget {
  const _LegalLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_LegalLink> createState() => _LegalLinkState();
}

class _LegalLinkState extends State<_LegalLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = _hover ? const Color(0xFFF5690B) : const Color(0x8C1A1A1A);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: TextStyle(
            color: c,
            fontSize: 13,
            decoration: _hover ? TextDecoration.underline : null,
            decorationColor: c,
          ),
        ),
      ),
    );
  }
}

class _OutlineAction extends StatefulWidget {
  const _OutlineAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_OutlineAction> createState() => _OutlineActionState();
}

class _OutlineActionState extends State<_OutlineAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final accent = enabled && _hover
        ? _LoginScreenState._orange
        : _LoginScreenState._navy;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled && _hover
                  ? _LoginScreenState._orange.withValues(alpha: 0.6)
                  : const Color(0x26000000),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: accent,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientButton extends StatefulWidget {
  const _GradientButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  State<_GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<_GradientButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final lift = enabled && _hover;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          transform: Matrix4.translationValues(0, lift ? -2 : 0, 0),
          height: 51,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: lift
                  ? const [
                      _LoginScreenState._orange2,
                      _LoginScreenState._orange,
                    ]
                  : const [
                      _LoginScreenState._orange,
                      _LoginScreenState._orange2,
                    ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: _LoginScreenState._orange.withValues(
                  alpha: enabled ? (lift ? 0.45 : 0.3) : 0.15,
                ),
                blurRadius: lift ? 25 : 20,
                offset: Offset(0, lift ? 10 : 6),
              ),
            ],
          ),
          foregroundDecoration: enabled
              ? null
              : BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.2,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopShell extends StatefulWidget {
  const DesktopShell({
    super.key,
    required this.api,
    required this.auth,
    required this.themePrefs,
    required this.chatPrefs,
  });

  final ApiClient api;
  final AuthService auth;
  final ThemePrefs themePrefs;
  final ChatPrefs chatPrefs;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _index = 0;
  bool _collapsed = false;
  bool _narrowExpanded = false;

  bool get _narrow => MediaQuery.sizeOf(context).width < 1000;

  bool get _effectiveCollapsed => _narrow ? !_narrowExpanded : _collapsed;

  void _toggleSidebar() => setState(() {
    if (_narrow) {
      _narrowExpanded = !_narrowExpanded;
    } else {
      _collapsed = !_collapsed;
    }
  });
  bool _startApplied = false;
  final Set<String> _visited = {};
  List<String> _keys = const [];
  List<NavGroup>? _nav;
  String? _role;
  Timer? _navTimer;
  final List<VoidCallback> _navLiveCancels = [];
  Timer? _navLiveDebounce;
  DateTime _navLiveLast = DateTime.fromMillisecondsSinceEpoch(0);
  late final NavService _navService = NavService(widget.api);

  late final DashboardService _dashboard = DashboardService(widget.api);
  late final CustomerService _customers = CustomerService(widget.api);
  late final LeadService _leads = LeadService(widget.api);
  late final TicketService _tickets = TicketService(widget.api);
  late final TaskService _tasks = TaskService(widget.api);
  late final PosVersionService _posVersions = PosVersionService(widget.api);
  late final LicenseService _licenses = LicenseService(widget.api);
  late final ReleaseNotesService _releaseNotes = ReleaseNotesService(
    widget.api,
  );
  late final HelpService _help = HelpService(widget.api);
  late final EmailService _email = EmailService(widget.api);
  late final UserService _users = UserService(widget.api);
  late final CredentialsService _credentials = CredentialsService(widget.api);
  late final FilesService _files = FilesService(widget.api);
  late final BlogService _blog = BlogService(widget.api);
  late final ActivityLogService _activityLogs = ActivityLogService(widget.api);
  late final NotificationCenter _notifications = NotificationCenter(
    leads: _leads,
    customers: _customers,
  );
  late final ShellBadges _badges = ShellBadges(widget.api);
  late final ShellNotifications _bell = ShellNotifications(widget.api);

  late final ChatRuntime _chat = ChatRuntime(
    api: widget.api,
    auth: widget.auth,
  );
  CallService? _callsListening;
  bool _callScreenOpen = false;
  StreamSubscription<Map<String, dynamic>>? _soundActivitySub;
  late final DesktopAlerts _alerts = DesktopAlerts(
    bell: _bell,
    chat: _chat,
    openPage: _goToKey,
  );

  @override
  void initState() {
    super.initState();
    _collapsed =
        kDebugMode && Platform.environment['TP_SHELL_OPEN'] == 'collapsed';
    _narrowExpanded =
        kDebugMode && Platform.environment['TP_SHELL_OPEN'] == 'expanded';
    _notifications.refresh();
    unawaited(SoundEngine.instance.attach(widget.api, widget.api.userId));
    _chat.addListener(_onChatRuntimeChange);
    _chat.bootstrap();
    _alerts.start();
    _refreshPermissions();
    _loadNav();
    LiveSync.instance.onSessionLost = _onSessionLost;
    LiveSync.instance.start(widget.api);
    FolderSyncEngine.instance.attach(widget.api);
    for (final k in const ['user', 'settings']) {
      _navLiveCancels.add(LiveSync.instance.listen(k, _onNavLiveChange));
    }
    _navLiveCancels.add(LiveSync.instance.listen('me', _onMeChange));
    _navTimer = Timer.periodic(const Duration(minutes: 2), (_) => _loadNav());

    if (kDebugMode && Platform.environment['TP_CYCLE_PAGES'] == '1') {
      var step = 0;
      final wait =
          int.tryParse(Platform.environment['TP_CYCLE_WAIT'] ?? '') ?? 7;
      Timer.periodic(Duration(seconds: wait), (t) async {
        if (step > 0 && step <= _keys.length) {
          await debugShot(
            '${step.toString().padLeft(2, '0')}_${_keys[step - 1]}',
          );
        }
        if (!mounted || step >= _keys.length) {
          t.cancel();
          debugPrint('TP_CYCLE_DONE');
          if (Platform.environment['TP_SHOT_DIR'] != null) exit(0);
          return;
        }
        debugPrint('TP_CYCLE_PAGE ${_keys[step]}');
        debugErrMark('PAGE ${_keys[step]}');
        setState(() => _index = step);
        step++;
      });
    }
    if (kDebugMode && Platform.environment['TP_OPEN_PROFILE'] == '1') {
      Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        final peer =
            int.tryParse(Platform.environment['TP_PROFILE_USER'] ?? '') ?? 0;
        if (peer > 0) {
          showProfilePanel(context, api: widget.api, userId: peer);
        } else {
          _openProfile();
        }
      });
    }
    if (kDebugMode && Platform.environment['TP_TOGGLE_SIDEBAR'] == '1') {
      for (final sec in [6, 9, 12, 15]) {
        Timer(Duration(seconds: sec), () => mounted ? _toggleSidebar() : null);
      }
    }
  }

  Future<void> _refreshPermissions() async {
    final changed = await widget.auth.refreshPermissions();
    if (changed && mounted) setState(() {});
  }

  Future<void> _onSessionLost(String message) async {
    if (!mounted) return;
    await _logout();
    navigatorKeyMessenger.currentState?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
    );
  }

  Future<void> _onMeChange() async {
    Map<String, dynamic> res;
    try {
      res = await widget.api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (res['success'] != true) {
      final msg = res['account_disabled'] == true
          ? 'This account has been disabled.'
          : (res['message']?.toString() ?? 'Your session has ended.');
      await _logout();
      final nav = navigatorKeyMessenger.currentState;
      nav?.showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    await _refreshPermissions();
    await _loadNav();
    if (!mounted) return;
    setState(() {});
    LiveSync.instance.notifyAll();
  }

  void _onNavLiveChange() {
    if (_navLiveDebounce?.isActive ?? false) return;
    final since = DateTime.now().difference(_navLiveLast);
    const gap = Duration(seconds: 15);
    final wait = since >= gap ? const Duration(milliseconds: 400) : gap - since;
    _navLiveDebounce = Timer(wait, () {
      if (!mounted) return;
      _navLiveLast = DateTime.now();
      _refreshPermissions();
      _loadNav();
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _navLiveDebounce?.cancel();
    for (final c in _navLiveCancels) {
      c();
    }
    _alerts.dispose();
    _soundActivitySub?.cancel();
    SoundEngine.instance.detach();
    _notifications.dispose();
    _badges.dispose();
    _bell.dispose();
    _chat.removeListener(_onChatRuntimeChange);
    _callsListening?.removeListener(_onCallChange);
    _chat.dispose();
    super.dispose();
  }

  void _onChatRuntimeChange() {
    if (_chat.ready && _soundActivitySub == null) {
      final rt = _chat.chatRealtime;
      unawaited(SoundEngine.instance.attach(widget.api, _chat.myUserId));
      SoundEngine.instance.chatConnected = () => rt.isConnected;
      _soundActivitySub = rt.activityRawEvents.listen(_onSoundActivity);
    }
    final calls = _chat.calls;
    if (calls != null && !identical(calls, _callsListening)) {
      _callsListening?.removeListener(_onCallChange);
      _callsListening = calls;
      calls.addListener(_onCallChange);
    }
  }

  void _onSoundActivity(Map<String, dynamic> d) {
    final last = d['last_message'];
    if (last is! Map) return;
    int n(Object? v) => int.tryParse('${v ?? ''}') ?? 0;
    SoundEngine.instance.chatMessage(
      messageId: n(last['id']),
      senderId: n(last['sender_id']),
      silent: last['silent'] == true,
      source: '${d['source'] ?? ''}',
    );
  }

  void _onCallChange() {
    final calls = _callsListening;
    if (calls == null || !mounted) return;
    if (calls.isActive && !_callScreenOpen) {
      _callScreenOpen = true;
      Navigator.of(context, rootNavigator: true)
          .push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => CallScreen(calls: calls),
            ),
          )
          .whenComplete(() => _callScreenOpen = false);
    }
  }

  void _goToKey(String key) {
    final i = _keys.indexOf(key);
    if (i >= 0) {
      setState(() => _index = i);
      LiveSync.instance.pollNow();
    }
  }

  Future<void> _loadNav() async {
    final nav = await _navService.fetch();
    if (!mounted || nav == null) return;
    final currentKey = _index < _keys.length ? _keys[_index] : null;
    final startKey = kDebugMode && !_startApplied
        ? Platform.environment['TP_START_PAGE']
        : null;
    _startApplied = true;
    _badges.setCounters([
      for (final g in nav)
        for (final i in g.items) ...[
          if (i.counter != null) i.counter!,
          for (final c in i.children)
            if (c.counter != null) c.counter!,
        ],
    ]);
    setState(() {
      _nav = nav;
      _role = _navService.role;
      final wanted = startKey ?? currentKey;
      if (wanted != null) {
        final flat = _flatten(nav);
        final i = flat.indexWhere((s) => s.item.key == wanted);
        _index = i >= 0 ? i : 0;
      }
    });
  }

  Future<void> _logout() async {
    LiveSync.instance.stop();
    FolderSyncEngine.instance.detach();
    await widget.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          api: widget.api,
          auth: widget.auth,
          themePrefs: widget.themePrefs,
          chatPrefs: widget.chatPrefs,
        ),
      ),
    );
  }

  void _openDesktopSettings() {
    if (_keys.contains('settings')) {
      WebSettingsScreen.requestTab.value = WebSettingsScreen.desktopTab;
      _goToKey('settings');
      return;
    }
    showWebModal<void>(
      context,
      title: 'Desktop app settings',
      subtitle: 'Settings that only apply to this app on this computer.',
      icon: Icons.desktop_windows_outlined,
      width: 680,
      builder: (_) => DesktopAppPane(
        api: widget.api,
        themePrefs: widget.themePrefs,
        onLogout: _logout,
        embedded: true,
      ),
    );
  }

  void _openProfile() {
    showProfilePanel(
      context,
      api: widget.api,
      selfName: widget.api.username,
      selfRole: _roleLabel(),
      onEditProfile: _keys.contains('settings')
          ? () {
              WebSettingsScreen.requestTab.value = 0;
              _goToKey('settings');
            }
          : null,
      onActivityLog: _keys.contains('activitylogs')
          ? () => _goToKey('activitylogs')
          : null,
      onDesktopSettings: _openDesktopSettings,
    );
  }

  Widget Function()? _pageFor(NavItem item) {
    switch (item.key) {
      case 'dashboard':
        return () => DashboardScreen(
          dashboard: _dashboard,
          notifications: _notifications,
          onNavigate: (_) => _goToKey('clientOffer'),
          onOpenChat: () => _goToKey('chat'),
          onNavigateKey: _goToKey,
        );
      case 'ticket':
        return () => TicketListScreen(service: _tickets);
      case 'chat':
        return () => ChatPage(
          runtime: _chat,
          api: widget.api,
          chatPrefs: widget.chatPrefs,
          onSignOut: _logout,
        );
      case 'posversion':
        return () => PosVersionScreen(service: _posVersions);
      case 'releasenotes':
        return () => ReleaseNotesScreen(service: _releaseNotes);
      case 'licensekey':
        return () => LicenseKeyScreen(service: _licenses);
      case 'blogposts':
        return () => BlogScreen(service: _blog);
      case 'customer':
        return () => CustomerListScreen(
          service: _customers,
          notifications: _notifications,
        );
      case 'clientOffer':
        return () =>
            LeadListScreen(service: _leads, notifications: _notifications);
      case 'credentials':
        return () => CredentialsScreen(service: _credentials);
      case 'user':
        return () => UsersScreen(service: _users);
      case 'emails':
        return () => EmailScreen(service: _email);
      case 'files':
        return () => FilesScreen(service: _files);
      case 'task':
        return () => TaskListScreen(service: _tasks);
      case 'activitylogs':
        return () => ActivityLogsScreen(service: _activityLogs);
      case 'helpPage':
        return () => HelpScreen(service: _help);
      case 'employment':
        return () => EmploymentScreen(api: widget.api);
      case 'vendorportal':
        return () => VendorPortalScreen(
          api: widget.api,
          canManage: item.mode == 'manage',
        );
      case 'whatsnew':
        return () => WhatsNewScreen(api: widget.api);
      case 'taxpayerportal':
        return () => TaxpayerPortalScreen(
          api: widget.api,
          canManage: item.mode == 'manage',
        );
      case 'offers':
        return () => OffersScreen(api: widget.api);
      case 'pricing':
        return () => PricingScreen(api: widget.api);
      case 'settings':
        return () => WebSettingsScreen(
          api: widget.api,
          themePrefs: widget.themePrefs,
          onLogout: _logout,
        );
      case 'announcements':
        return () => AnnouncementsScreen(
          api: widget.api,
          canManage: item.mode == 'manage',
        );
      case 'appdownloads':
        return () => AppDownloadsScreen(api: widget.api);
      case 'feedbackinbox':
        return () => FeedbackInboxScreen(api: widget.api);
      case 'client':
        return () => ClientScreen(api: widget.api);
      case 'zreading':
        return () => ZReadingScreen(api: widget.api);
      case 'barcode':
        return () => BarcodeScreen(api: widget.api);
    }
    return null;
  }

  List<NavGroup> _fallbackNav() {
    NavItem it(String key, String label, String icon) =>
        NavItem(key: key, label: label, icon: icon, page: key);
    final groups = <NavGroup>[
      NavGroup('Overview', [it('dashboard', 'Dashboard', 'th')]),
      NavGroup('Support', [
        it('ticket', 'Ticket', 'ticket-alt'),
        it('chat', 'Chat', 'comments'),
      ]),
      NavGroup('Product', [
        it('posversion', 'POS Version', 'code-branch'),
        it('releasenotes', 'Release Notes', 'scroll'),
        it('licensekey', 'License Key', 'id-card'),
        it('blogposts', 'Blog Posts', 'blog'),
      ]),
      NavGroup('Clients', [
        it('customer', 'BIR Registration', 'file-signature'),
        it('clientOffer', 'Leads / Forms', 'user-plus'),
        it('credentials', 'Credentials Storage', 'key'),
      ]),
      NavGroup('Workspace', [
        it('user', 'User', 'users-cog'),
        it('emails', 'Email', 'envelope'),
        it('files', 'Files Management', 'folder-open'),
        it('task', 'Task', 'list'),
        it('activitylogs', 'Activity Logs', 'clipboard-list'),
      ]),
      NavGroup('System', [it('helpPage', 'Help Page', 'question-circle')]),
    ];
    final perms = widget.api.permissions;
    if (perms.isEmpty) return groups;
    return [
      for (final g in groups)
        NavGroup(
          g.label,
          g.items.where((i) => widget.api.hasPermission(i.key)).toList(),
        ),
    ].where((g) => g.items.isNotEmpty).toList();
  }

  List<_Section> _flatten(List<NavGroup> groups) {
    final out = <_Section>[];
    for (final g in groups) {
      for (final item in g.items) {
        out.add(_section(g.label, item));
        for (final child in item.children) {
          out.add(_section(g.label, child));
        }
      }
    }
    return out;
  }

  _Section _section(String group, NavItem item) {
    final builder =
        _pageFor(item) ??
        () => PendingDesktopPage(label: item.label, page: item.page);
    return _Section(group, item, builder);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _nav ?? _fallbackNav();
    final sections = _flatten(groups);
    _keys = [for (final s in sections) s.item.key];
    if (_index >= sections.length) _index = 0;

    final activeKey = _keys.isNotEmpty ? _keys[_index] : '';
    final active = sections.isNotEmpty ? sections[_index] : null;
    if (activeKey.isNotEmpty) _visited.add(activeKey);
    _badges.setActive(activeKey);
    final onChatPage = activeKey == 'chat';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _openJumpTo(sections),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: context.brand.canvas,
          body: Column(
            children: [
              _TopBar(
                collapsed: _effectiveCollapsed,
                pageKey: activeKey,
                group: active?.group ?? '',
                title: active?.item.label ?? '',
                username: widget.api.username ?? 'Operator',
                role: _roleLabel(),
                notifications: _bell,
                showHelp: _keys.contains('helpPage'),
                onToggle: _toggleSidebar,
                onJump: () => _openJumpTo(sections),
                onLogout: _logout,
                onProfile: _openProfile,
                onOpenPage: _goToKey,
              ),
              Expanded(
                child: Row(
                  children: [
                    _DesktopSidebar(
                      index: _index,
                      collapsed: _effectiveCollapsed,
                      sections: sections,
                      badges: _badges,
                      onChanged: (i) {
                        if (sections[i].item.key == 'feedback') {
                          showFeedbackSubmitDialog(context, widget.api);
                          return;
                        }
                        setState(() => _index = i);
                        LiveSync.instance.pollNow();
                      },
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Container(height: 4, color: Brand.signal),
                          Expanded(
                            child: Stack(
                              children: [
                                IndexedStack(
                                  index: _index,
                                  children: [
                                    for (final s in sections)
                                      KeyedSubtree(
                                        key: ValueKey('page-${s.item.key}'),
                                        child: _visited.contains(s.item.key)
                                            ? s.build()
                                            : const SizedBox.shrink(),
                                      ),
                                  ],
                                ),
                                Positioned.fill(
                                  child: ShellReminders(
                                    api: widget.api,
                                    activeKey: activeKey,
                                    onOpenPage: _goToKey,
                                  ),
                                ),
                                if (!onChatPage)
                                  Positioned.fill(
                                    child: FloatingChatDock(
                                      runtime: _chat,
                                      api: widget.api,
                                      chatPrefs: widget.chatPrefs,
                                      onSignOut: _logout,
                                      onExpand: () => _goToKey('chat'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openJumpTo(List<_Section> sections) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _JumpToDialog(sections: sections),
    );
    if (picked == null || !mounted) return;
    if (sections[picked].item.key == 'feedback') {
      showFeedbackSubmitDialog(context, widget.api);
      return;
    }
    setState(() => _index = picked);
  }

  String _roleLabel() {
    final r = _role ?? '';
    if (r.isEmpty) return 'Operator';
    return r
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class _Section {
  const _Section(this.group, this.item, this.builder);
  final String group;
  final NavItem item;
  final Widget Function() builder;
  Widget build() => builder();
}

class PendingDesktopPage extends StatelessWidget {
  const PendingDesktopPage({
    super.key,
    required this.label,
    required this.page,
  });
  final String label;
  final String page;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_outlined,
            size: 48,
            color: context.brand.paperDim,
          ),
          const SizedBox(height: 16),
          Text(label, style: text.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'This page is being built for the desktop app.',
            style: text.bodyMedium?.copyWith(color: context.brand.paperDim),
          ),
        ],
      ),
    );
  }
}

class _Chrome {
  _Chrome(BuildContext context)
    : dark = Theme.of(context).brightness == Brightness.dark,
      b = context.brand;
  final bool dark;
  final BrandColors b;

  Color get bar => dark ? b.surface : Colors.white;
  Color get barRule => dark ? b.rule : const Color(0xFFE7ECF3);
  Color get logoRule => dark ? b.rule : const Color(0xFFE5E5E5);
  Color get ink => dark ? b.paper : const Color(0xFF0B1B30);
  Color get muted => dark ? b.paperDim : const Color(0xFF94A3B8);
  Color get btn => dark ? b.paperDim : const Color(0xFF55647A);
  Color get btnHover => dark ? b.surfaceHi : const Color(0xFFF1F5F9);
  Color get field => dark ? b.surfaceHi : const Color(0xFFF8FAFC);
  Color get fieldHoverBorder => dark ? b.rule : const Color(0xFFD8E0EA);
  Color get kbdBorder => dark ? b.rule : const Color(0xFFE2E8F0);
  Color get kbd => dark ? b.surface : Colors.white;
}

const Map<String, List<String>> _kCrumbs = {
  'dashboard': ['Overview', 'Dashboard'],
  'ticket': ['Support', 'Tickets'],
  'chat': ['Support', 'Chat'],
  'posversion': ['Product', 'POS Version'],
  'releasenotes': ['Product', 'Release Notes'],
  'licensekey': ['Product', 'License Keys'],
  'blogposts': ['Product', 'Blog Posts'],
  'customer': ['Clients', 'BIR Registration'],
  'clientOffer': ['Clients', 'Leads / Forms'],
  'client': ['Clients', 'Client'],
  'zreading': ['Clients', 'Z-Reading Requests'],
  'credentials': ['Clients', 'Credentials Storage'],
  'user': ['Workspace', 'Users'],
  'employment': ['Workspace', 'Employment Information'],
  'offers': ['Workspace', 'Offers'],
  'pricing': ['Workspace', 'Pricing'],
  'emails': ['Workspace', 'Email'],
  'files': ['Workspace', 'Files Management'],
  'activitylogs': ['Workspace', 'Activity Logs'],
  'task': ['Workspace', 'Tasks'],
  'helpPage': ['System', 'Help Center'],
  'barcode': ['System', 'Barcode'],
  'settings': ['System', 'Settings'],
  'announcements': ['System', 'Announcements'],
  'appdownloads': ['System', 'App Downloads'],
  'taxpayerportal': ['Clients', 'Taxpayer Portal'],
  'vendorportal': ['Workspace', 'Vendor Portal'],
  'feedbackinbox': ['System', 'Feedback'],
  'whatsnew': ['Overview', "What's New"],
};

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.collapsed,
    required this.pageKey,
    required this.group,
    required this.title,
    required this.username,
    required this.role,
    required this.notifications,
    required this.showHelp,
    required this.onToggle,
    required this.onJump,
    required this.onLogout,
    required this.onProfile,
    required this.onOpenPage,
  });

  final bool collapsed;
  final String pageKey;
  final String group;
  final String title;
  final String username;
  final String role;
  final ShellNotifications notifications;
  final bool showHelp;
  final VoidCallback onToggle;
  final VoidCallback onJump;
  final VoidCallback onLogout;
  final VoidCallback onProfile;
  final ValueChanged<String> onOpenPage;

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    final crumb = _kCrumbs[pageKey] ?? [group, title];
    final sideW = collapsed ? _kSidebarCollapsed : _kSidebarWidth;
    final barW = MediaQuery.sizeOf(context).width - sideW;
    final narrowBar = barW < 760;
    final tinyBar = barW < 620;
    return SizedBox(
      height: 57,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: sideW,
            child: Column(
              children: [
                Container(
                  height: 54,
                  color: c.bar,
                  alignment: Alignment.center,
                  child: LayoutBuilder(
                    builder: (context, c) => ClipRect(
                      child: OverflowBox(
                        minWidth: 0,
                        maxWidth: c.maxWidth,
                        child: _Logo(collapsed: collapsed || c.maxWidth < 200),
                      ),
                    ),
                  ),
                ),
                Container(height: 1, color: c.logoRule),
                Container(height: 2, color: Brand.navy),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 56,
                  color: c.bar,
                  padding: EdgeInsets.only(
                    left: 10,
                    right: narrowBar ? 10 : 16,
                  ),
                  child: Row(
                    children: [
                      _BarButton(
                        icon: Fa.bars,
                        tooltip: collapsed ? 'Expand menu' : 'Collapse menu',
                        onTap: onToggle,
                      ),
                      const SizedBox(width: 8),
                      Container(width: 1, height: 24, color: c.barRule),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              flex: 2,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 320,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 14,
                                          height: 2,
                                          decoration: BoxDecoration(
                                            color: Brand.signal,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            crumb[0].toUpperCase(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: c.muted,
                                              fontSize: 9.76,
                                              height: 1.15,
                                              letterSpacing: 1.37,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      crumb[1],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: c.ink,
                                        fontSize: 15.2,
                                        height: 1.15,
                                        letterSpacing: -0.15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (tinyBar)
                              _BarButton(
                                icon: Icons.search,
                                tooltip: 'Jump to… (Ctrl K)',
                                onTap: onJump,
                              )
                            else
                              Flexible(
                                flex: 3,
                                child: _JumpButton(onTap: onJump),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (MediaQuery.sizeOf(context).width >= 1150) ...[
                        const _Clock(),
                        const SizedBox(width: 8),
                        Container(width: 1, height: 24, color: c.barRule),
                        const SizedBox(width: 8),
                      ],
                      if (showHelp && pageKey != 'helpPage') ...[
                        _BarButton(
                          icon: Fa.questionCircleRegular,
                          tooltip: 'Help center',
                          onTap: () => onOpenPage('helpPage'),
                        ),
                        const SizedBox(width: 6),
                      ],
                      ShellBell(center: notifications, onOpenPage: onOpenPage),
                      const SizedBox(width: 6),
                      Container(width: 1, height: 24, color: c.barRule),
                      const SizedBox(width: 6),
                      _UserChip(
                        username: username,
                        role: role,
                        compact: narrowBar,
                        onProfile: onProfile,
                      ),
                      const SizedBox(width: 6),
                      _BarButton(
                        icon: Fa.powerOff,
                        tooltip: 'Log out',
                        danger: true,
                        onTap: onLogout,
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: c.barRule),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _brandImage(
  String name, {
  double? width,
  double? height,
  Widget fallback = const SizedBox.shrink(),
}) {
  return Image(
    image: brandAsset('assets/brand/$name'),
    width: width,
    height: height,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) {
      final file = File(
        '${File(Platform.resolvedExecutable).parent.path}/data/flutter_assets/assets/brand/$name',
      );
      if (!file.existsSync()) return fallback;
      return Image.file(
        file,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      );
    },
  );
}

class _Logo extends StatelessWidget {
  const _Logo({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final mark = _brandImage(
      'logo.png',
      width: 30,
      height: 30,
      fallback: const Icon(Icons.public, color: Brand.signal),
    );
    if (collapsed) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(width: 2),
        _brandImage('logo-wordmark.png', height: 21),
      ],
    );
  }
}

class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    final Color bg;
    final Color border;
    final Color fg;
    if (widget.danger) {
      bg = _hover ? const Color(0xFFFEF2F2) : Colors.transparent;
      border = _hover ? const Color(0xFFF49B9B) : const Color(0xFFFBCFCF);
      fg = _hover ? const Color(0xFFB91C1C) : const Color(0xFFDC2626);
    } else {
      bg = _hover ? c.btnHover : Colors.transparent;
      border = _hover ? c.barRule : Colors.transparent;
      fg = _hover ? c.ink : c.btn;
    }
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}

class _JumpButton extends StatefulWidget {
  const _JumpButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_JumpButton> createState() => _JumpButtonState();
}

class _JumpButtonState extends State<_JumpButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 260,
          height: 38,
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.field,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hover ? c.fieldHoverBorder : c.barRule),
          ),
          child: Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Jump to…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 13.1,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.kbd,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.kbdBorder),
                ),
                child: Text(
                  'Ctrl K',
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 9.3,
                    letterSpacing: 0.37,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final h = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final m = _now.minute.toString().padLeft(2, '0');
    final ap = _now.hour < 12 ? 'AM' : 'PM';
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${h.toString().padLeft(2, '0')}:$m $ap',
            style: TextStyle(
              color: c.ink,
              fontSize: 13.4,
              height: 1.15,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            '${days[_now.weekday - 1]}, ${months[_now.month - 1]} ${_now.day}',
            style: TextStyle(
              color: c.muted,
              fontSize: 10.1,
              height: 1.15,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserChip extends StatefulWidget {
  const _UserChip({
    required this.username,
    required this.role,
    required this.onProfile,
    this.compact = false,
  });

  final String username;
  final String role;
  final VoidCallback onProfile;
  final bool compact;

  @override
  State<_UserChip> createState() => _UserChipState();
}

class _UserChipState extends State<_UserChip> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode && Platform.environment['TP_OPEN_USERMENU'] == '1') {
      Timer(const Duration(seconds: 4), () {
        if (mounted && !_portal.isShowing) _toggle();
      });
    }
  }

  void _toggle() {
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
    setState(() {});
  }

  void _pick(VoidCallback f) {
    _portal.hide();
    setState(() {});
    f();
  }

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    final open = _portal.isShowing;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  _portal.hide();
                  setState(() {});
                },
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 9),
              child: Align(
                alignment: Alignment.topRight,
                child: _UserMenu(onProfile: () => _pick(widget.onProfile)),
              ),
            ),
          ],
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onTap: _toggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 40,
              constraints: const BoxConstraints(maxWidth: 190),
              padding: const EdgeInsets.fromLTRB(5, 0, 10, 0),
              decoration: BoxDecoration(
                color: _hover || open ? c.btnHover : c.field,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _hover || open ? c.fieldHoverBorder : c.barRule,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            color: Brand.navy,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Fa.user,
                            size: 11.5,
                            color: Colors.white,
                          ),
                        ),
                        Positioned(
                          right: -3,
                          bottom: -3,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E9F6E),
                              shape: BoxShape.circle,
                              border: Border.all(color: c.field, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(width: 9),
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.ink,
                              fontSize: 12.8,
                              height: 1.15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.role.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.muted,
                              fontSize: 9.6,
                              height: 1.15,
                              letterSpacing: 0.96,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(width: widget.compact ? 5 : 9),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Fa.chevronDown, size: 9.6, color: c.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu({required this.onProfile});
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 262,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: c.dark ? c.b.surface : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.barRule),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E0C233E),
              blurRadius: 44,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _UserMenuItem(
              icon: Fa.idBadge,
              title: 'View profile & stats',
              subtitle: 'Your activity and details',
              onTap: onProfile,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserMenuItem extends StatefulWidget {
  const _UserMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_UserMenuItem> createState() => _UserMenuItemState();
}

class _UserMenuItemState extends State<_UserMenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = _Chrome(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _hover ? c.btnHover : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SizedBox(
                  width: 16,
                  child: Icon(widget.icon, size: 13, color: Brand.signal),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: c.dark ? c.b.paper : Brand.navy,
                        fontSize: 13.1,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: c.dark ? c.b.paperDim : const Color(0xFF64748B),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JumpToDialog extends StatefulWidget {
  const _JumpToDialog({required this.sections});
  final List<_Section> sections;

  @override
  State<_JumpToDialog> createState() => _JumpToDialogState();
}

class _JumpToDialogState extends State<_JumpToDialog> {
  String _q = '';
  int _hi = 0;

  List<int> get _matches => [
    for (var i = 0; i < widget.sections.length; i++)
      if (_q.isEmpty ||
          widget.sections[i].item.label.toLowerCase().contains(
            _q.toLowerCase(),
          ) ||
          widget.sections[i].group.toLowerCase().contains(_q.toLowerCase()))
        i,
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final m = _matches;
    if (_hi >= m.length) _hi = m.isEmpty ? 0 : m.length - 1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            setState(() => _hi = (_hi + 1).clamp(0, m.length - 1)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            setState(() => _hi = (_hi - 1).clamp(0, m.length - 1)),
      },
      child: Dialog(
        alignment: const Alignment(0, -0.6),
        child: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Jump to a page…',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onChanged: (v) => setState(() {
                    _q = v.trim();
                    _hi = 0;
                  }),
                  onSubmitted: (_) {
                    if (m.isNotEmpty) Navigator.of(context).pop(m[_hi]);
                  },
                ),
              ),
              Divider(height: 1, color: context.brand.rule),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: [
                    for (var j = 0; j < m.length; j++)
                      ListTile(
                        selected: j == _hi,
                        selectedTileColor: Brand.signalGlow(0.1),
                        selectedColor: Brand.signal,
                        mouseCursor: SystemMouseCursors.click,
                        leading: Icon(
                          Fa.nav(widget.sections[m[j]].item.icon),
                          size: 18,
                        ),
                        title: Text(
                          widget.sections[m[j]].item.label,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Text(
                          widget.sections[m[j]].group.toUpperCase(),
                          style: text.labelSmall,
                        ),
                        onTap: () => Navigator.of(context).pop(m[j]),
                      ),
                    if (m.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'No matching page',
                          textAlign: TextAlign.center,
                          style: text.bodySmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _kSidebarWidth = 250;
const double _kSidebarCollapsed = 74;

class _DesktopSidebar extends StatefulWidget {
  const _DesktopSidebar({
    required this.index,
    required this.collapsed,
    required this.sections,
    required this.badges,
    required this.onChanged,
  });

  final int index;
  final bool collapsed;
  final List<_Section> sections;
  final ShellBadges badges;
  final ValueChanged<int> onChanged;

  @override
  State<_DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<_DesktopSidebar> {
  final _scroll = ScrollController();
  bool _canUp = false;
  bool _canDown = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(_DesktopSidebar old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final up = p.pixels > 4;
    final down = p.pixels < p.maxScrollExtent - 4;
    if (up != _canUp || down != _canDown) {
      setState(() {
        _canUp = up;
        _canDown = down;
      });
    }
  }

  void _step(double dir) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final to = (p.pixels + dir * p.viewportDimension * 0.6)
        .clamp(0.0, p.maxScrollExtent)
        .toDouble();
    _scroll.animateTo(
      to,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final collapsed = widget.collapsed;
    final sections = widget.sections;
    final children = <Widget>[];
    String? currentGroup;
    var childRun = <Widget>[];

    void flushChildren() {
      if (childRun.isEmpty) return;
      children.add(_SubNav(collapsed: collapsed, children: childRun));
      childRun = <Widget>[];
    }

    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      if (!s.item.isChild) flushChildren();
      if (s.group != currentGroup) {
        currentGroup = s.group;
        children.add(_NavHeader(label: s.group, collapsed: collapsed));
      }
      final tile = _NavTile(
        item: s.item,
        selected: i == widget.index,
        collapsed: collapsed,
        badges: widget.badges,
        onTap: () => widget.onChanged(i),
      );
      if (s.item.isChild) {
        childRun.add(tile);
      } else {
        children.add(tile);
      }
    }
    flushChildren();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: collapsed ? _kSidebarCollapsed : _kSidebarWidth,
      color: Brand.navy,
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
          return false;
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: AnimatedBuilder(
                  animation: widget.badges,
                  builder: (context, _) => ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 39, bottom: 16),
                    children: children,
                  ),
                ),
              ),
            ),
            if (_canUp)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _ScrollCue(up: true, onTap: () => _step(-1)),
              ),
            if (_canDown)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _ScrollCue(up: false, onTap: () => _step(1)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScrollCue extends StatefulWidget {
  const _ScrollCue({required this.up, required this.onTap});
  final bool up;
  final VoidCallback onTap;

  @override
  State<_ScrollCue> createState() => _ScrollCueState();
}

class _ScrollCueState extends State<_ScrollCue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  bool _hover = false;

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0C233E);
    final stops = [
      navy.withValues(alpha: 0),
      navy.withValues(alpha: 0.75),
      navy.withValues(alpha: 0.95),
    ];
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: widget.up ? Alignment.bottomCenter : Alignment.topCenter,
          end: widget.up ? Alignment.topCenter : Alignment.bottomCenter,
          stops: const [0, 0.55, 1],
          colors: stops,
        ),
      ),
      alignment: widget.up ? Alignment.topCenter : Alignment.bottomCenter,
      padding: EdgeInsets.only(
        top: widget.up ? 6 : 0,
        bottom: widget.up ? 0 : 6,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _hover ? const Color(0xFFE67000) : Brand.signal,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Brand.signal.withValues(alpha: _hover ? 0.45 : 0.35),
                  blurRadius: _hover ? 16 : 12,
                  offset: Offset(0, _hover ? 6 : 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _bounce,
              builder: (_, child) => Transform.translate(
                offset: Offset(
                  0,
                  -2 + 4 * (0.5 - 0.5 * math.cos(_bounce.value * 2 * math.pi)),
                ),
                child: child,
              ),
              child: Icon(
                widget.up ? Fa.chevronUp : Fa.chevronDown,
                size: 11.2,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavHeader extends StatelessWidget {
  const _NavHeader({required this.label, required this.collapsed});
  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return SizedBox(
        height: 37,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 1,
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 7),
            color: Colors.white.withValues(alpha: 0.12),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 16, 20, 6),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.38),
          fontSize: 10,
          height: 1.5,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SubNav extends StatelessWidget {
  const _SubNav({required this.collapsed, required this.children});
  final bool collapsed;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (collapsed) return Column(children: children);
    return Padding(
      padding: const EdgeInsets.only(left: 22, bottom: 2),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 2,
            bottom: 8,
            child: Container(
              width: 1,
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          Column(children: children),
        ],
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.badges,
    required this.onTap,
  });
  final NavItem item;
  final bool selected;
  final bool collapsed;
  final ShellBadges badges;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final item = widget.item;
    final collapsed = widget.collapsed;
    final child = item.isChild;
    final activeBg = context.brand.canvas;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = selected
        ? (dark ? Colors.white : Brand.navy)
        : (_hover ? Colors.white : Colors.white.withValues(alpha: 0.72));
    final iconColor = selected
        ? Brand.signal
        : (_hover
              ? Colors.white.withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.46));
    final bg = selected
        ? activeBg
        : (_hover ? Colors.white.withValues(alpha: 0.07) : Colors.transparent);
    final badge = widget.badges.badgeFor(item.counter);
    final height = child ? 33.0 : 34.0;

    Widget? pill;
    if (item.tag != null) {
      pill = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0x26EA580C),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          item.tag!,
          style: const TextStyle(
            color: Color(0xFFC25E00),
            fontSize: 10,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else if (badge != null) {
      pill = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: badge.color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          badge.text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    } else if (item.badge != null) {
      pill = Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Brand.signal,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          item.badge!,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    final leftPad = collapsed ? 8.0 : (selected ? 18.0 : 12.0);
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: height,
      padding: EdgeInsets.only(left: leftPad, right: collapsed ? 8 : 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: selected
            ? const BorderRadius.horizontal(left: Radius.circular(999))
            : BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final showLabel = !collapsed && c.maxWidth >= 120;
          final row = Row(
            mainAxisSize: showLabel ? MainAxisSize.max : MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                child: Icon(
                  Fa.nav(item.icon),
                  size: child ? 13.1 : 15.2,
                  color: iconColor,
                ),
              ),
              if (showLabel) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: child ? 14.16 : 15.24,
                      letterSpacing: -0.07,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (pill != null) ...[const SizedBox(width: 8), pill],
              ],
            ],
          );
          if (showLabel) return row;
          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: c.maxWidth < 18 ? 18 : c.maxWidth,
              child: row,
            ),
          );
        },
      ),
    );

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: selected ? 0 : 18,
            top: 1,
            bottom: 1,
          ),
          child: selected
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    body,
                    Positioned(
                      right: 0,
                      top: -14,
                      child: CustomPaint(
                        size: const Size(14, 14),
                        painter: _NotchPainter(activeBg, top: true),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: -14,
                      child: CustomPaint(
                        size: const Size(14, 14),
                        painter: _NotchPainter(activeBg, top: false),
                      ),
                    ),
                  ],
                )
              : body,
        ),
      ),
    );
    return collapsed
        ? Tooltip(
            message: item.label,
            waitDuration: const Duration(milliseconds: 300),
            child: tile,
          )
        : tile;
  }
}

class _NotchPainter extends CustomPainter {
  const _NotchPainter(this.color, {required this.top});
  final Color color;
  final bool top;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final corner = top ? Offset.zero : Offset(0, size.height);
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addOval(Rect.fromCircle(center: corner, radius: size.width)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _NotchPainter old) =>
      old.color != color || old.top != top;
}
