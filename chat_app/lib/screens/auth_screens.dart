import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api_client.dart';
import '../push_service.dart';
import '../services/biometric_auth.dart';
import '../services/chat_prefs.dart';
import '../services/auth_service.dart';
import '../services/theme_prefs.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'chat_shell.dart';

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
      title: 'Connect to server',
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

  final ChatPrefs chatPrefs;

  final ThemePrefs themePrefs;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _googleBusy = false;
  bool _obscure = true;
  bool _remember = true;

  String? _googleClientId;

  late final BiometricAuth _biometrics = BiometricAuth(widget.api);
  bool _fingerprintReady = false;
  bool _fingerprintBusy = false;
  String _fingerprintLabel = '';

  @override
  void initState() {
    super.initState();
    _loadGoogleConfig();
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final ready = await _biometrics.isEnabled() && await _biometrics.deviceCanScan();
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
    if (_fingerprintBusy || _busy) return;
    setState(() => _fingerprintBusy = true);
    try {
      final res = await _biometrics.signIn(remember: _remember);
      if (res == null) return;
      await widget.auth.adoptSession(res);
      if (!mounted) return;
      _goHome();
    } catch (error) {
      if (!mounted) return;
      final enabled = await _biometrics.isEnabled();
      if (mounted) setState(() => _fingerprintReady = enabled);
      if (!mounted || auto) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(error)),
          duration: const Duration(seconds: 5),
        ),
      );
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
          'Sign in to TinkerPro Chat by scanning your fingerprint instead of '
          'typing your password on this phone.',
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
    super.dispose();
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChatShell(
          api: widget.api,
          push: PushService(widget.api),
          auth: widget.auth,
          chatPrefs: widget.chatPrefs,
          themePrefs: widget.themePrefs,
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    var text = error.toString();
    for (final prefix in ['Exception: ', 'HttpException: ', 'ChatAuthException: ']) {
      if (text.startsWith(prefix)) text = text.substring(prefix.length);
    }
    return text.trim().isEmpty ? 'Sign-in failed. Please try again.' : text.trim();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.auth.login(_email.text, _password.text,
          remember: _remember);
      if (!mounted) return;
      await _offerFingerprint();
      if (!mounted) return;
      _goHome();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(error)),
          duration: const Duration(seconds: 6),
        ),
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

      final googleSignIn =
          GoogleSignIn(serverClientId: clientId, scopes: const ['email']);

      await googleSignIn.signOut();
      final account = await googleSignIn.signIn();
      if (account == null) {

        if (mounted) setState(() => _googleBusy = false);
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google did not return an ID token.');
      }
      await widget.auth.loginWithGoogle(idToken, remember: _remember);
      if (!mounted) return;
      await _offerFingerprint();
      if (!mounted) return;
      _goHome();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(error)),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      title: 'Sign in',
      showBottomBrand: false,
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
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _FieldLabel('Email'),
                const SizedBox(height: 6),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'you@company.com',
                    prefixIcon: Icon(Icons.alternate_email, size: 19),
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                _FieldLabel('Password'),
                const SizedBox(height: 6),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: InputDecoration(
                    hintText: 'Your password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 19),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 19,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _busy
                      ? null
                      : () => setState(() => _remember = !_remember),
                  borderRadius: BorderRadius.circular(Brand.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _remember,
                            onChanged: _busy
                                ? null
                                : (v) =>
                                    setState(() => _remember = v ?? true),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Keep me signed in',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SignalButton(
                  label: _busy ? 'Signing in…' : 'Sign in',
                  busy: _busy,
                  onPressed: _submit,
                ),
                if (_fingerprintReady) ...[
                  const SizedBox(height: 14),
                  _FingerprintButton(
                    busy: _fingerprintBusy,
                    label: _fingerprintLabel,
                    onPressed: _fingerprintBusy
                        ? null
                        : () => _signInWithFingerprint(),
                  ),
                ],
                if (_googleClientId != null && _googleClientId!.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const _OrDivider(),
                  const SizedBox(height: 16),
                  _GoogleButton(
                    busy: _googleBusy,
                    onPressed: _googleBusy ? null : _signInWithGoogle,
                  ),
                ],
                const SizedBox(height: 44),
                const BrandLockup(size: 84),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
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
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: context.brand.paperDim,
          ),
    );
  }
}

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
          color: context.brand.surface,
          border: Border.all(color: context.brand.rule, width: 1),
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
                          ?.copyWith(letterSpacing: 1.5, color: context.brand.paper)),
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
                    strokeWidth: 2, color: Brand.signal),
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
