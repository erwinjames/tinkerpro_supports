import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/customer_models.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'dashboard_screen.dart';

/// Two-step portal login:
///   Step 1 — customer types their TIN. We hit `getCustomerBranchesByTin`
///            and display whatever branches their registration spans.
///   Step 2 — they pick a branch. `getCustomerPortalByTin` opens the
///            session and returns the full Customer record. We push to
///            the dashboard.
///
/// The form is intentionally lean — no business name, no address, no
/// password — because portal access is identity-by-TIN only. Customers
/// without a TIN registration on the server can't log in at all (the
/// staff side handles registration, not this app).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _tinController = TextEditingController();
  bool _busy = false;
  String? _error;
  late bool _rememberMe;

  @override
  void initState() {
    super.initState();
    final last = widget.auth.store.lastTin;
    if (last != null) _tinController.text = _formatTinForDisplay(last);
    _rememberMe = widget.auth.store.rememberMe;
  }

  @override
  void dispose() {
    _tinController.dispose();
    super.dispose();
  }

  Future<void> _onLookup() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.auth.fetchBranches(_tinController.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.message;
    });
    if (result.branches.isEmpty) return;
    final tinDigits =
        _tinController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final picked = await _showBranchPicker(result.branches);
    if (picked == null || !mounted) return;
    await _loginWithBranch(tinDigits, picked.branchCode);
  }

  Future<void> _loginWithBranch(String tin, String branchCode) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final customer = await widget.auth.loginToBranch(tin, branchCode);
    if (!mounted) return;
    setState(() => _busy = false);
    if (customer == null) {
      setState(() => _error = 'Could not sign in. Please try again.');
      return;
    }
    // Honor the user's "Remember me" choice — main.dart's bootstrap
    // checks this before calling restoreSession() on next launch.
    await widget.auth.store.setRememberMe(_rememberMe);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => DashboardScreen(
        auth: widget.auth,
        initialCustomer: customer,
      ),
    ));
  }

  Future<Branch?> _showBranchPicker(List<Branch> branches) async {
    return showModalBottomSheet<Branch>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Brand.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _BranchPickerSheet(branches: branches),
    );
  }

  /// Cosmetic TIN grouping — `123-456-789-00000` style — for the input.
  /// We strip back to digits before sending to the server.
  String _formatTinForDisplay(String digits) {
    final raw = digits.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty) return '';
    final groups = <String>[];
    int i = 0;
    for (final size in const [3, 3, 3, 5]) {
      if (i >= raw.length) break;
      final end = (i + size).clamp(0, raw.length);
      groups.add(raw.substring(i, end));
      i = end;
    }
    if (i < raw.length) groups.add(raw.substring(i));
    return groups.join('-');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Top hero band — black with orange accent. Mirrors the web
            // portal's "REGISTERED CLIENT ACCESS" tone.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 280,
              child: Container(
                decoration: BoxDecoration(gradient: Brand.hero),
              ),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: Brand.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.key, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'REGISTERED CLIENT ACCESS',
                      style: TextStyle(
                        color: Brand.signal,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'Welcome',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Sign in with your TIN to view your registration status\nand chat with our admin team.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 36),
                _LoginCard(
                  controller: _tinController,
                  busy: _busy,
                  error: _error,
                  rememberMe: _rememberMe,
                  onRememberChanged: (v) =>
                      setState(() => _rememberMe = v),
                  onSubmit: _onLookup,
                  onChanged: (v) {
                    final formatted = _formatTinForDisplay(v);
                    if (formatted != v) {
                      _tinController.value = TextEditingValue(
                        text: formatted,
                        selection:
                            TextSelection.collapsed(offset: formatted.length),
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    "Don't have an account yet?\nReach out to your TinkerPro contact to register.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Brand.textMuted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.controller,
    required this.busy,
    required this.error,
    required this.rememberMe,
    required this.onRememberChanged,
    required this.onSubmit,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool busy;
  final String? error;
  final bool rememberMe;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onSubmit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Brand.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'TIN (Taxpayer Identification No.)',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Brand.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            enabled: !busy,
            onChanged: onChanged,
            onSubmitted: (_) => onSubmit(),
            inputFormatters: [
              // Allow digits + the cosmetic dashes our formatter inserts.
              FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              LengthLimitingTextInputFormatter(20),
            ],
            decoration: InputDecoration(
              hintText: '000-000-000-00000',
              prefixIcon: const Icon(Icons.numbers, color: Brand.textMuted),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            _ErrorChip(message: error!),
          ],
          const SizedBox(height: 12),
          // "Remember me" — when checked (default), the cookie jar
          // persists and the next launch lands straight on the dashboard.
          // When unchecked, main.dart wipes cookies on launch and forces
          // a fresh TIN entry. Default is true so existing customers keep
          // the convenient stay-signed-in behavior they had before.
          InkWell(
            onTap: busy ? null : () => onRememberChanged(!rememberMe),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: rememberMe,
                      onChanged: busy
                          ? null
                          : (v) => onRememberChanged(v ?? true),
                      activeColor: Brand.signal,
                      side: const BorderSide(color: Brand.stroke, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Keep me signed in on this device',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Brand.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: busy ? null : onSubmit,
            child: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('CONTINUE'),
          ),
        ],
      ),
    );
  }
}

class _ErrorChip extends StatelessWidget {
  const _ErrorChip({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Brand.danger, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Brand.danger,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchPickerSheet extends StatelessWidget {
  const _BranchPickerSheet({required this.branches});
  final List<Branch> branches;
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, controller) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Brand.stroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose your branch',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: Brand.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Multiple registrations exist for this TIN. Pick the one you want to access.',
                style: TextStyle(
                  color: Brand.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  controller: controller,
                  itemCount: branches.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final b = branches[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).pop(b),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Brand.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Brand.stroke),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Branch Code: ${b.branchCode}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (b.displayLocation.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      b.displayLocation,
                                      style: const TextStyle(
                                        color: Brand.textMuted,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward,
                                color: Brand.signal, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
