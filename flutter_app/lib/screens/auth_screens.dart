import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api_client.dart';
import '../push_service.dart';
import '../services/biometric_auth.dart';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not reach server: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: b.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _AuthHero(
                  eyebrow: 'Server',
                  title: 'Connect your workspace',
                  subtitle:
                      'Point this device at your TinkerPro Support installation.',
                ),
                Transform.translate(
                  offset: const Offset(0, -44),
                  child: _AuthBody(
                    children: [
                      _AuthCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'The app talks to your TinkerPro Support backend. Paste the base '
                              'URL of the deployment you want this device registered against.',
                              style: text.bodyMedium?.copyWith(
                                color: b.paperDim,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const _FieldLabel('Base URL'),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _controller,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              textInputAction: TextInputAction.go,
                              onSubmitted: (_) => _busy ? null : _save(),
                              decoration: _authField(
                                context,
                                hint:
                                    'https://support.tinkerpro.com.ph/tpsupporttesting',
                                icon: Icons.dns_rounded,
                              ),
                              style: text.bodyLarge?.copyWith(color: b.paper),
                            ),
                            const SizedBox(height: 20),
                            SignalButton(
                              label: 'Continue',
                              busy: _busy,
                              onPressed: _save,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: b.paperDim,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'No trailing slash. HTTPS recommended.',
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
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

class _AuthReveal extends StatefulWidget {
  const _AuthReveal({required this.child});

  final Widget child;

  @override
  State<_AuthReveal> createState() => _AuthRevealState();
}

class _AuthRevealState extends State<_AuthReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
      ),
    );
  }
}

InputDecoration _authField(
  BuildContext context, {
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  final b = context.brand;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: b.surfaceHi,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    prefixIcon: Icon(icon, size: 20, color: b.paperDim),
    suffixIcon: suffix,
    border: border(b.rule),
    enabledBorder: border(b.rule),
    focusedBorder: border(b.signal, 1.6),
    disabledBorder: border(b.rule),
    floatingLabelBehavior: FloatingLabelBehavior.never,
  );
}

class _AuthHero extends StatelessWidget {
  const _AuthHero({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppHeaderBand(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.asset(
                          'assets/brand/tinkerpro-wordmark-dark.png',
                          height: 30,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          semanticLabel: 'TinkerPro',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Support Console',
                          style: text.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 32),
              Text(
                eyebrow,
                style: text.labelMedium?.copyWith(
                  color: Brand.orange,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: text.headlineLarge?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: text.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 2,
                  width: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    color: Brand.orange,
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

class _AuthBody extends StatelessWidget {
  const _AuthBody({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _AuthReveal(
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        radius: 20,
        blur: 18,
        child: child,
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
  final ChatPrefs chatPrefs;
  final ThemePrefs themePrefs;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _googleBusy = false;
  bool _obscure = true;
  bool _remember = true;
  String? _error;
  String? _googleClientId;

  late final BiometricAuth _biometrics = BiometricAuth(widget.api);
  bool _fingerprintReady = false;
  bool _fingerprintBusy = false;
  String _fingerprintLabel = '';

  @override
  void initState() {
    super.initState();
    final saved = widget.api.rememberedEmail;
    if (saved.isNotEmpty) _email.text = saved;
    _loadGoogleConfig();
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final ready =
        await _biometrics.isEnabled() && await _biometrics.deviceCanScan();
    if (!ready) return;
    final label = await _biometrics.enrolledLabel();
    if (!mounted) return;
    setState(() {
      _fingerprintReady = true;
      _fingerprintLabel = label;
    });
    await _signInWithFingerprint(auto: true);
  }

  Future<void> _signInWithFingerprint({bool auto = false}) async {
    if (_busy || _googleBusy || _fingerprintBusy) return;
    setState(() {
      _fingerprintBusy = true;
      _error = null;
    });
    try {
      final res = await _biometrics.signIn(remember: _remember);
      if (res == null) return;
      await widget.auth.adoptSession(res);
      if (!mounted) return;
      _goHome();
    } catch (error) {
      final enabled = await _biometrics.isEnabled();
      if (!mounted) return;
      setState(() {
        _fingerprintReady = enabled;
        if (!auto) _error = _friendlyError(error);
      });
    } finally {
      if (mounted) setState(() => _fingerprintBusy = false);
    }
  }

  Future<void> _offerFingerprint() async {
    if (await _biometrics.isEnabled()) return;
    if (!await _biometrics.deviceCanScan()) return;
    if (!mounted) return;
    final wants = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Use your fingerprint next time?'),
        content: const Text(
          'Sign in to TinkerPro Support by scanning your fingerprint instead '
          'of typing your password on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Turn on'),
          ),
        ],
      ),
    );
    if (wants != true) return;
    try {
      await _biometrics.enable(label: widget.api.username ?? '');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    }
  }

  Future<void> _loadGoogleConfig() async {
    if (!Platform.isAndroid) return;
    final id = await widget.auth.googleClientId();
    if (mounted) setState(() => _googleClientId = id);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

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

  String _friendlyError(Object error) {
    var text = error.toString();
    for (final prefix in [
      'Exception: ',
      'HttpException: ',
      'SocketException: ',
    ]) {
      if (text.startsWith(prefix)) text = text.substring(prefix.length);
    }
    if (text.contains('Failed host lookup') ||
        text.contains('Connection refused')) {
      return 'Unable to reach the server. Check your connection and try again.';
    }
    return text.trim().isEmpty
        ? 'Sign-in failed. Please try again.'
        : text.trim();
  }

  Future<void> _afterSignIn(String email) async {
    await widget.api.setRememberedEmail(_remember ? email : null);
    TextInput.finishAutofillContext();
    if (!mounted) return;
    await _offerFingerprint();
    if (!mounted) return;
    _goHome();
  }

  Future<void> _submit() async {
    if (_busy || _googleBusy) return;
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login(email, _password.text, remember: _remember);
      await _afterSignIn(email);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    final clientId = _googleClientId;
    if (clientId == null || clientId.isEmpty || _busy) return;
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: clientId,
        scopes: const ['email'],
      );
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) return;
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google did not return an ID token.');
      }
      await widget.auth.loginWithGoogle(idToken, remember: _remember);
      await _afterSignIn(account.email);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  void _changeServer() {
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
  }

  String get _serverHost {
    final uri = Uri.tryParse(widget.api.baseUrl);
    final host = uri?.host ?? '';
    return host.isEmpty ? widget.api.baseUrl : host;
  }

  InputDecoration _field({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) => _authField(context, hint: hint, icon: icon, suffix: suffix);

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final locked = _busy || _googleBusy;
    final showGoogle = _googleClientId != null && _googleClientId!.isNotEmpty;

    return Scaffold(
      backgroundColor: b.canvas,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AuthHero(
                  eyebrow: 'Sign in',
                  title: 'Welcome back',
                  subtitle:
                      'Sign in to your TinkerPro Support account to '
                      'manage tickets, clients and conversations.',
                  trailing: AppIconButton(
                    icon: Icons.dns_rounded,
                    tooltip: 'Change server',
                    onPressed: locked ? null : _changeServer,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -44),
                  child: _AuthBody(
                    children: [
                      _card(context, locked, showGoogle),
                      const SizedBox(height: 24),
                      _Footer(host: _serverHost),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, bool locked, bool showGoogle) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return _AuthCard(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Semantics(
                liveRegion: true,
                child: _ErrorBanner(message: _error!),
              ),
              const SizedBox(height: 16),
            ],
            const _FieldLabel('Email address'),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              enabled: !locked,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: _field(
                hint: 'you@company.com',
                icon: Icons.mail_outline_rounded,
              ),
              style: text.bodyLarge?.copyWith(color: b.paper),
            ),
            const SizedBox(height: 18),
            const _FieldLabel('Password'),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              focusNode: _passwordFocus,
              enabled: !locked,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: _field(
                hint: 'Enter your password',
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 19,
                    color: b.paperDim,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              style: text.bodyLarge?.copyWith(color: b.paper),
            ),
            const SizedBox(height: 14),
            _RememberToggle(
              value: _remember,
              onChanged: locked ? null : (v) => setState(() => _remember = v),
            ),
            const SizedBox(height: 20),
            _PrimaryButton(
              label: _busy ? 'Signing in…' : 'Sign in',
              busy: _busy,
              onPressed: locked ? null : _submit,
            ),
            if (_fingerprintReady) ...[
              const SizedBox(height: 14),
              _FingerprintButton(
                busy: _fingerprintBusy,
                label: _fingerprintLabel,
                onPressed: locked || _fingerprintBusy
                    ? null
                    : () => _signInWithFingerprint(),
              ),
            ],
            if (showGoogle) ...[
              const SizedBox(height: 20),
              const _OrDivider(),
              const SizedBox(height: 20),
              _GoogleButton(
                busy: _googleBusy,
                onPressed: locked ? null : _signInWithGoogle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                host,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: b.paperDim),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '© ${DateTime.now().year} TinkerPro. All rights reserved.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: b.paperDim, fontSize: 11),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: context.brand.paper,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    const red = Brand.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: red.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.brand.paper,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RememberToggle extends StatelessWidget {
  const _RememberToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: onChanged == null
                    ? null
                    : (v) => onChanged!(v ?? true),
                activeColor: b.signal,
                checkColor: Brand.onSignal,
                side: BorderSide(color: b.paperDim, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Keep me signed in',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: b.paper),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final enabled = onPressed != null;
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: b.signal,
          foregroundColor: Brand.onSignal,
          disabledBackgroundColor: busy
              ? b.signal.withValues(alpha: 0.75)
              : b.surfaceHi,
          disabledForegroundColor: busy ? Brand.onSignal : b.paperDim,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Brand.onSignal,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: enabled || busy ? Brand.onSignal : b.paperDim,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!busy) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: enabled ? Brand.onSignal : b.paperDim,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: b.rule)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: b.paperDim),
          ),
        ),
        Expanded(child: Container(height: 1, color: b.rule)),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: b.surface,
          foregroundColor: b.paper,
          side: BorderSide(color: b.rule),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: b.signal,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'G',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Continue with Google',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: b.paper,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _FingerprintButton extends StatelessWidget {
  const _FingerprintButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  final bool busy;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final brand = context.brand;
    return InkWell(
      onTap: onPressed,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: brand.surface,
          border: Border.all(color: brand.signal, width: 1),
          borderRadius: BorderRadius.circular(Brand.radiusSm),
        ),
        alignment: Alignment.center,
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Brand.signal,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fingerprint, size: 22, color: brand.signalInk),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label.isEmpty
                          ? 'SIGN IN WITH FINGERPRINT'
                          : 'FINGERPRINT — ${label.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(
                        letterSpacing: 1.2,
                        color: brand.paper,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
