// TinkerPro Support — desktop client (Windows + Linux).
//
// A trimmed, desktop-native build of the support console that talks to the
// live server at https://tinkerpro.io. It reuses the mobile client's
// pure-Dart core (api_client, models, http-only services, theme, list
// screens) but drops the mobile-only chat / call / push stack and the
// Analyze, Pricing, and Offer pages.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'api_client.dart';
import 'services/admin_services.dart';
import 'services/call_service.dart';
import 'services/chat_prefs.dart';
import 'services/chat_runtime.dart';
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

/// The live backend this desktop build always points at. There is no
/// server-config screen on desktop — the URL is fixed to production.
///
/// Note: the support API (`api.php`) lives on the `support.` subdomain —
/// the bare `tinkerpro.io` root is the marketing site and has no API.
const String kLiveServerUrl = 'https://support.tinkerpro.io';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop window chrome: open maximized with a sensible minimum size so the
  // console fills the screen like a native app (not a small phone-shaped
  // window). Linux/Windows only.
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    minimumSize: Size(1100, 720),
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
  // Always pin to the live server — desktop has no connect screen.
  if (api.baseUrl != kLiveServerUrl) {
    await api.setBaseUrl(kLiveServerUrl);
  }

  final prefs = await SharedPreferences.getInstance();
  final themePrefs = await ThemePrefs.load(prefs);
  final chatPrefs = ChatPrefs(prefs);

  runApp(SupportDesktopApp(
      api: api, themePrefs: themePrefs, chatPrefs: chatPrefs));
}

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
        title: 'TinkerPro Support',
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        darkTheme: darkTheme(),
        themeMode: themePrefs.value,
        // App-wide keyboard shortcuts (Esc = back/close). See [GlobalShortcuts].
        builder: (context, child) => GlobalShortcuts(child: child ?? const SizedBox.shrink()),
        home: api.hasSession
            ? DesktopShell(
                api: api,
                auth: auth,
                themePrefs: themePrefs,
                chatPrefs: chatPrefs)
            : LoginScreen(
                api: api,
                auth: auth,
                themePrefs: themePrefs,
                chatPrefs: chatPrefs),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Global keyboard shortcuts
// ─────────────────────────────────────────────────────────────────────────

/// App-wide shortcuts injected via [MaterialApp.builder], so they work on
/// every screen, dialog, and pushed route.
///
///  • **Esc** — back / close: pops the nearest navigator that *can* pop (a
///    dialog, the chat thread, participants, etc.). On a root shell page there
///    is nothing to pop, so it's a no-op — it never closes the app.
///
/// Enter-to-confirm is handled where it's unambiguous (the chat composer sends,
/// the login form submits, confirm dialogs autofocus their primary button).
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
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _back,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Login
// ─────────────────────────────────────────────────────────────────────────

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

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // Brand palette pulled from the web login (login.php) so the desktop
  // sign-in matches it: navy artwork backdrop + frosted-white glass card +
  // orange CTA — independent of the app's dark theme.
  static const _navy = Color(0xFF0C233E);
  static const _orange = Color(0xFFF5690B);
  static const _orange2 = Color(0xFFFF8C3B);

  InputDecoration _glassField(String label, {Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.6),
      suffixIcon: suffix,
      labelStyle: const TextStyle(color: Color(0xCC1A1A1A)),
      floatingLabelStyle: const TextStyle(color: _orange),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: border(Colors.black.withValues(alpha: 0.12)),
      border: border(Colors.black.withValues(alpha: 0.12)),
      focusedBorder: border(_orange, 1.6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed background artwork (navy fallback if the asset or
          // its manifest is momentarily unavailable).
          const ColoredBox(color: _navy),
          Image.asset(
            'assets/brand/login_background.png',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    // Frosted glass — same recipe as the web .glass-card
                    // (blur 22 + ~75% white fill): clean and readable.
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 45,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Logo — matches the web login wordmark, with the
                          // same warm glow.
                          Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(boxShadow: [
                                BoxShadow(
                                  color: _orange.withValues(alpha: 0.3),
                                  blurRadius: 15,
                                ),
                              ]),
                              child: Image.asset(
                                'assets/brand/logo.png',
                                height: 60,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Icon(
                                    Icons.public, color: _orange, size: 48),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text('Support Access',
                              textAlign: TextAlign.center,
                              style: text.headlineSmall?.copyWith(
                                  color: _navy, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(kLiveServerUrl,
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(
                                  color: _navy.withValues(alpha: 0.7))),
                          const SizedBox(height: 28),
                          TextField(
                            controller: _email,
                            autofocus: true,
                            style: const TextStyle(color: _navy),
                            cursorColor: _orange,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _glassField('Email address'),
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _password,
                            obscureText: _obscure,
                            style: const TextStyle(color: _navy),
                            cursorColor: _orange,
                            decoration: _glassField(
                              'Key password',
                              suffix: IconButton(
                                icon: Icon(
                                    _obscure
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    size: 18,
                                    color: _navy.withValues(alpha: 0.5)),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 14),
                          // "Keep me signed in" — mirrors the web remember-me.
                          InkWell(
                            onTap: () =>
                                setState(() => _remember = !_remember),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                      value: _remember,
                                      onChanged: (v) => setState(
                                          () => _remember = v ?? false),
                                      activeColor: _orange,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('Keep me signed in',
                                      style: text.bodyMedium?.copyWith(
                                          color:
                                              _navy.withValues(alpha: 0.8))),
                                ],
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: text.bodySmall?.copyWith(
                                    color: const Color(0xFFDC2626),
                                    fontWeight: FontWeight.w500)),
                          ],
                          const SizedBox(height: 22),
                          _GradientButton(
                            label:
                                _busy ? 'UNLOCKING…' : 'UNLOCK DASHBOARD',
                            onPressed: _busy ? null : _submit,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The orange gradient sign-in CTA, mirroring the web login button.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.7,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_LoginScreenState._orange, _LoginScreenState._orange2],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _LoginScreenState._orange.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Container(
              height: 52,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2)),
                  const SizedBox(width: 10),
                  const Icon(Icons.login, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Desktop shell — NavigationRail
// ─────────────────────────────────────────────────────────────────────────

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
  List<String> _labels = const [];

  late final DashboardService _dashboard = DashboardService(widget.api);
  late final CustomerService _customers = CustomerService(widget.api);
  late final LeadService _leads = LeadService(widget.api);
  late final TicketService _tickets = TicketService(widget.api);
  late final TaskService _tasks = TaskService(widget.api);
  late final PosVersionService _posVersions = PosVersionService(widget.api);
  late final LicenseService _licenses = LicenseService(widget.api);
  late final ReleaseNotesService _releaseNotes =
      ReleaseNotesService(widget.api);
  late final HelpService _help = HelpService(widget.api);
  late final EmailService _email = EmailService(widget.api);
  late final UserService _users = UserService(widget.api);
  late final CredentialsService _credentials = CredentialsService(widget.api);
  late final FilesService _files = FilesService(widget.api);
  late final BlogService _blog = BlogService(widget.api);
  late final ActivityLogService _activityLogs =
      ActivityLogService(widget.api);
  late final NotificationCenter _notifications =
      NotificationCenter(leads: _leads, customers: _customers);

  // Shared chat runtime — one realtime connection / inbox / CallService for
  // both the Chat page and the floating dock.
  late final ChatRuntime _chat =
      ChatRuntime(api: widget.api, auth: widget.auth);
  CallService? _callsListening;
  bool _callScreenOpen = false;

  @override
  void initState() {
    super.initState();
    _notifications.refresh();
    _chat.addListener(_onChatRuntimeChange);
    _chat.bootstrap();
  }

  @override
  void dispose() {
    _notifications.dispose();
    _chat.removeListener(_onChatRuntimeChange);
    _callsListening?.removeListener(_onCallChange);
    _chat.dispose();
    super.dispose();
  }

  /// Attach the incoming-call listener once the runtime stands up its
  /// CallService — so calls pop a screen no matter which page is showing.
  void _onChatRuntimeChange() {
    final calls = _chat.calls;
    if (calls != null && !identical(calls, _callsListening)) {
      _callsListening?.removeListener(_onCallChange);
      _callsListening = calls;
      calls.addListener(_onCallChange);
    }
  }

  void _onCallChange() {
    final calls = _callsListening;
    if (calls == null || !mounted) return;
    if (calls.isActive && !_callScreenOpen) {
      _callScreenOpen = true;
      Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => CallScreen(calls: calls),
          ))
          .whenComplete(() => _callScreenOpen = false);
    }
  }

  /// Jump to a section by its label (robust to ordering changes).
  void _goToLabel(String label) {
    final i = _labels.indexOf(label);
    if (i >= 0) setState(() => _index = i);
  }

  Future<void> _logout() async {
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

  /// The ordered section list — drives BOTH the NavigationRail and the
  /// IndexedStack, so adding a page is a single entry here.
  List<_Section> _buildSections() {
    return [
      _Section(
        'Overview',
        'Dashboard',
        Icons.dashboard_outlined,
        Icons.dashboard,
        () => DashboardScreen(
          dashboard: _dashboard,
          notifications: _notifications,
          onNavigate: (_) => _goToLabel('Leads'),
          onOpenChat: () => _goToLabel('Chat'),
        ),
      ),
      _Section('Operations', 'Tickets', Icons.confirmation_number_outlined,
          Icons.confirmation_number, () => TicketListScreen(service: _tickets)),
      _Section(
          'Operations',
          'Chat',
          Icons.chat_bubble_outline,
          Icons.chat_bubble,
          () => ChatPage(
                runtime: _chat,
                api: widget.api,
                chatPrefs: widget.chatPrefs,
                onSignOut: _logout,
              )),
      _Section(
          'Operations',
          'Leads',
          Icons.local_fire_department_outlined,
          Icons.local_fire_department,
          () => LeadListScreen(service: _leads, notifications: _notifications)),
      // The web sidebar's "BIR Registration" links to customer.php — the
      // same customer endpoint this screen uses.
      _Section(
          'Operations',
          'BIR Registration',
          Icons.assignment_ind_outlined,
          Icons.assignment_ind,
          () => CustomerListScreen(
              service: _customers, notifications: _notifications)),
      _Section('Operations', 'Tasks', Icons.task_alt_outlined, Icons.task_alt,
          () => TaskListScreen(service: _tasks)),
      _Section('Product', 'POS Version', Icons.devices_outlined, Icons.devices,
          () => PosVersionScreen(service: _posVersions)),
      _Section('Product', 'Release Notes', Icons.notes_outlined, Icons.notes,
          () => ReleaseNotesScreen(service: _releaseNotes)),
      _Section('Product', 'Blog Posts', Icons.article_outlined, Icons.article,
          () => BlogScreen(service: _blog)),
      _Section('Product', 'License Key', Icons.vpn_key_outlined, Icons.vpn_key,
          () => LicenseKeyScreen(service: _licenses)),
      _Section('Administration', 'Credentials', Icons.password_outlined,
          Icons.password, () => CredentialsScreen(service: _credentials)),
      _Section('Administration', 'Users', Icons.group_outlined, Icons.group,
          () => UsersScreen(service: _users)),
      _Section('Administration', 'Email', Icons.mail_outline, Icons.mail,
          () => EmailScreen(service: _email)),
      _Section('Administration', 'Files', Icons.folder_outlined, Icons.folder,
          () => FilesScreen(service: _files)),
      _Section('Administration', 'Activity Logs', Icons.receipt_long_outlined,
          Icons.receipt_long, () => ActivityLogsScreen(service: _activityLogs)),
      _Section('Administration', 'Help Page', Icons.help_outline, Icons.help,
          () => HelpScreen(service: _help)),
      _Section('Administration', 'Settings', Icons.settings_outlined,
          Icons.settings,
          () => SettingsPanel(
              api: widget.api,
              themePrefs: widget.themePrefs,
              onLogout: _logout)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sections = _buildSections();
    _labels = [for (final s in sections) s.label];
    if (_index >= sections.length) _index = 0;

    // The dock shows everywhere except the full Chat page.
    final activeLabel = _labels.isNotEmpty ? _labels[_index] : '';
    final onChatPage = activeLabel == 'Chat';
    // Pages that own a bottom-right FloatingActionButton — lift the dock above
    // it so the two buttons don't overlap. (Only Tasks today.)
    const fabPages = {'Tasks'};
    final dockBottom = fabPages.contains(activeLabel) ? 92.0 : 24.0;

    return Scaffold(
      backgroundColor: Brand.canvas,
      body: Row(
        children: [
          _DesktopSidebar(
            index: _index,
            username: widget.api.username ?? 'Operator',
            role: (widget.api.username == null) ? 'Support' : 'Operator',
            sections: sections,
            onChanged: (i) => setState(() => _index = i),
            onLogout: _logout,
          ),
          const VerticalDivider(width: 1, thickness: 1, color: Brand.rule),
          Expanded(
            child: Stack(
              children: [
                IndexedStack(
                  index: _index,
                  children: [for (final s in sections) s.build()],
                ),
                if (!onChatPage)
                  Positioned(
                    right: 24,
                    bottom: dockBottom,
                    child: FloatingChatDock(
                      runtime: _chat,
                      api: widget.api,
                      chatPrefs: widget.chatPrefs,
                      onSignOut: _logout,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One navigable section of the console. [group] places it under a labeled
/// heading in the sidebar.
class _Section {
  const _Section(this.group, this.label, this.icon, this.selectedIcon,
      this.builder);
  final String group;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
  Widget build() => builder();
}

/// Premium desktop sidebar — branded header, grouped navigation with hover
/// + selected states, and a user footer. ~256px fixed, like Linear / Slack.
class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.index,
    required this.username,
    required this.role,
    required this.sections,
    required this.onChanged,
    required this.onLogout,
  });

  final int index;
  final String username;
  final String role;
  final List<_Section> sections;
  final ValueChanged<int> onChanged;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // Build the grouped item list, emitting a heading whenever the group
    // changes.
    final children = <Widget>[];
    String? currentGroup;
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      if (s.group != currentGroup) {
        currentGroup = s.group;
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(20, children.isEmpty ? 4 : 18, 20, 8),
          child: Text(
            s.group.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: Brand.paperDim,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ));
      }
      children.add(_NavTile(
        section: s,
        selected: i == index,
        onTap: () => onChanged(i),
      ));
    }

    return SizedBox(
      width: 256,
      child: Container(
        color: Brand.canvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Brand header ──────────────────────────────────────────
            // The whole header section is a full-width white band so the
            // original (navy+orange) logo and its eyebrow read clearly; the
            // eyebrow is recolored dark since it now sits on white.
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset(
                    'assets/brand/logo.png',
                    width: double.infinity,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                        Icons.public, color: Brand.signal, size: 22),
                  ),
                  const SizedBox(height: 12),
                  Text('CONTROL SUITE',
                      textAlign: TextAlign.center,
                      style: text.labelSmall?.copyWith(
                          color: const Color(0xFF0C233E),
                          letterSpacing: 2.2)),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1, color: Brand.rule),
            // ── Grouped navigation ────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: children,
              ),
            ),
            // ── User footer ───────────────────────────────────────────
            const Divider(height: 1, thickness: 1, color: Brand.rule),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Brand.signalGlow(0.18),
                    child: Text(
                      (username.isNotEmpty ? username[0] : '?').toUpperCase(),
                      style: const TextStyle(
                          color: Brand.signal,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(role,
                            maxLines: 1,
                            style: text.labelSmall
                                ?.copyWith(color: Brand.paperDim)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: onLogout,
                    splashRadius: 18,
                    icon: const Icon(Icons.logout,
                        color: Brand.paperDim, size: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single sidebar nav row with hover + selected states and an accent bar.
class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });
  final _Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final text = Theme.of(context).textTheme;
    final fg = selected
        ? Brand.signal
        : (_hover ? Brand.paper : Brand.paperDim);
    final bg = selected
        ? Brand.signalGlow(0.12)
        : (_hover ? Brand.surfaceHi : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                // Accent bar for the active item.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 3,
                  height: selected ? 18 : 0,
                  margin: const EdgeInsets.only(right: 9),
                  decoration: BoxDecoration(
                    color: Brand.signal,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Icon(selected ? widget.section.selectedIcon : widget.section.icon,
                    size: 19, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: fg,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
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

// ─────────────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────────────

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.api,
    required this.themePrefs,
    required this.onLogout,
  });

  final ApiClient api;
  final ThemePrefs themePrefs;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SETTINGS', style: text.labelMedium),
            const SizedBox(height: 8),
            Text('Console', style: text.headlineSmall),
            const SizedBox(height: 24),
            const Hairline(),
            const SizedBox(height: 24),
            _row(text, 'Signed in as', api.username ?? '—'),
            const SizedBox(height: 12),
            _row(text, 'Server', api.baseUrl),
            const SizedBox(height: 28),
            Text('APPEARANCE', style: text.labelMedium),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: themePrefs,
              builder: (context, _) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {themePrefs.value},
                onSelectionChanged: (s) => themePrefs.setMode(s.first),
              ),
            ),
            const Spacer(),
            GhostButton(label: 'Sign out', onPressed: onLogout),
          ],
        ),
      ),
    );
  }

  Widget _row(TextTheme text, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: 140,
            child: Text(label,
                style: text.bodySmall?.copyWith(color: Brand.paperDim))),
        Expanded(child: Text(value, style: text.bodyMedium)),
      ],
    );
  }
}
