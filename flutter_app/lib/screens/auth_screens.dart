import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api_client.dart';
import '../push_service.dart';
import '../services/chat_prefs.dart';
import '../services/services.dart';
import '../services/theme_prefs.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'home_shell.dart';

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.chatPrefs,
    required this.themePrefs,
  });

  final ApiClient api;
  final AuthService auth;
  final ChatPrefs chatPrefs;
  final ThemePrefs themePrefs;

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.api.baseUrl;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.api.setBaseUrl(value);
      final bootstrap = await widget.api.get('getMobileBootstrap');
      if (bootstrap['success'] == false) {
        throw Exception(bootstrap['message'] ?? 'Server rejected connection.');
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(
            api: widget.api,
            auth: widget.auth,
            chatPrefs: widget.chatPrefs,
            themePrefs: widget.themePrefs,
          ),
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reach server: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '01',
      stationLabel: 'SERVER',
      title: 'Point at your\ninstallation.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The app talks to your TinkerPro Support backend. Paste the base '
            'URL of the deployment you want this device registered against.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'BASE URL',
              hintText: 'https://support.tinkerpro.com.ph/tpsupporttesting',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 32),
          SignalButton(
            label: 'Continue',
            busy: _busy,
            onPressed: _save,
          ),
          const Spacer(),
          Text('No trailing slash. HTTPS recommended.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.chatPrefs,
    required this.themePrefs,
  });

  final ApiClient api;
  final AuthService auth;

  /// Forwarded to HomeShell after a successful login so chat-tab
  /// preferences (bubble toggle, theme) are available immediately.
  final ChatPrefs chatPrefs;

  /// Forwarded to HomeShell + the Menu screen's appearance toggle so
  /// the user's theme choice persists across auth boundaries.
  final ThemePrefs themePrefs;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _googleBusy = false;

  /// Google web OAuth client id for this server, used as the SDK's
  /// serverClientId. null = still loading; '' = Google not configured here
  /// (button hidden); non-empty = show the button.
  String? _googleClientId;

  @override
  void initState() {
    super.initState();
    _loadGoogleConfig();
  }

  Future<void> _loadGoogleConfig() async {
    // Native Google sign-in is Android-only for now; skip the config probe
    // (and the button) everywhere else.
    if (!Platform.isAndroid) return;
    final id = await widget.auth.googleClientId();
    if (mounted) setState(() => _googleClientId = id);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Replace the auth stack with the main app shell after a successful login.
  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeShell(
          api: widget.api,
          push: PushService(widget.api),
          auth: widget.auth,
          dashboard: DashboardService(widget.api),
          customers: CustomerService(widget.api),
          leads: LeadService(widget.api),
          tickets: TicketService(widget.api),
          chatPrefs: widget.chatPrefs,
          themePrefs: widget.themePrefs,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.auth.login(_email.text, _password.text);
      if (!mounted) return;
      _goHome();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    final clientId = _googleClientId;
    if (clientId == null || clientId.isEmpty) return;
    setState(() => _googleBusy = true);
    try {
      // serverClientId makes the returned ID token's audience our web OAuth
      // client, which is what api.php?action=mobileOAuthLogin verifies.
      final googleSignIn =
          GoogleSignIn(serverClientId: clientId, scopes: const ['email']);
      // Sign out first so the account chooser always appears (and a
      // previously-picked account can be switched).
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) {
        // User dismissed the chooser.
        if (mounted) setState(() => _googleBusy = false);
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google did not return an ID token.');
      }
      await widget.auth.loginWithGoogle(idToken);
      if (!mounted) return;
      _goHome();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '02',
      stationLabel: 'IDENTIFY',
      title: 'Sign in.',
      trailing: StationAction(
        icon: Icons.dns_outlined,
        tooltip: 'Change server',
        onPressed: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ServerConfigScreen(
                api: widget.api,
                auth: widget.auth,
                chatPrefs: widget.chatPrefs,
                themePrefs: widget.themePrefs,
              ),
            ),
          );
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Connected to ${widget.api.baseUrl}',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 28),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'EMAIL'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'PASSWORD'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 36),
          SignalButton(
            label: 'Sign in',
            busy: _busy,
            onPressed: _submit,
          ),
          // Native Google sign-in — Android only, and only when this server
          // has Google OAuth configured (_googleClientId is left null on
          // other platforms in _loadGoogleConfig, so this stays hidden).
          if (_googleClientId != null && _googleClientId!.isNotEmpty) ...[
            const SizedBox(height: 28),
            const _OrDivider(),
            const SizedBox(height: 20),
            _GoogleButton(
              busy: _googleBusy,
              onPressed: _googleBusy ? null : _signInWithGoogle,
            ),
          ],
        ],
      ),
    );
  }
}

/// "or continue with" rule used above the social buttons.
class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Hairline()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('OR CONTINUE WITH',
              style: Theme.of(context).textTheme.labelMedium),
        ),
        const Expanded(child: Hairline()),
      ],
    );
  }
}

/// Outlined "Continue with Google" button matching the app's console styling.
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onPressed,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Brand.surface,
          border: Border.all(color: Brand.rule, width: 1),
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Brand.signal),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Google "G" wordmark colours, drawn simply.
                  const Text(
                    'G',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('CONTINUE WITH GOOGLE',
                      style: text.labelLarge
                          ?.copyWith(letterSpacing: 1.5, color: Brand.paper)),
                ],
              ),
      ),
    );
  }
}
