import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/credential_models.dart';
import '../services/credential_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key, required this.service});
  final CredentialService service;

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  final TextEditingController _otp = TextEditingController();
  bool _requesting = true;
  bool _verifying = false;
  bool _verified = false;
  String? _otpStatus;
  bool _otpSent = false;

  List<Credential> _rows = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _requestOtp();
  }

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    setState(() {
      _requesting = true;
      _otpStatus = null;
    });
    final res = await widget.service.requestOtp();
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _otpSent = res.ok;
      _otpStatus = res.ok
          ? 'OTP sent to your email.'
          : (res.message ?? 'Failed to send OTP.');
    });
  }

  Future<void> _verify() async {
    final code = _otp.text.trim();
    if (code.isEmpty) {
      _toast('Enter the OTP from your email.');
      return;
    }
    setState(() => _verifying = true);
    final res = await widget.service.verifyOtp(code);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (res.ok) {
      setState(() => _verified = true);
      _load();
    } else {
      _toast(res.message ?? 'Invalid or expired OTP.');
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.list();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _openForm([Credential? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _CredentialFormScreen(service: widget.service, existing: existing),
      ),
    );
    if (changed == true) _load();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Security',
      title: 'Credentials',
      subtitle: _verified
          ? 'Vault unlocked · ${_rows.length} stored'
          : 'Vault locked · verify with OTP',
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: _verified
          ? StationAction(
              icon: Icons.add_rounded,
              tooltip: 'New credential',
              onPressed: _openForm,
            )
          : null,
      child: AnimatedSwitcher(
        duration: Duration(
          milliseconds:
              (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
              ? 0
              : 340,
        ),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: _verified
            ? KeyedSubtree(
                key: const ValueKey('vault-open'),
                child: _buildList(context),
              )
            : KeyedSubtree(
                key: const ValueKey('vault-locked'),
                child: _buildGate(context),
              ),
      ),
    );
  }

  Widget _buildGate(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final statusColor = _otpSent ? Brand.success : Brand.danger;
    return ListView(
      children: [
        const SizedBox(height: 4),
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: _LockSeal(unlocking: _verifying)),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  'Vault locked',
                  style: text.titleLarge?.copyWith(color: b.paper),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'We emailed a one-time password to your account. '
                'Enter it below to unlock client credentials.',
                style: text.bodyMedium?.copyWith(color: b.paperDim),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: b.surfaceHi,
                  borderRadius: BorderRadius.circular(Brand.radius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('One-time password', style: text.labelLarge),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _otp,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      textAlign: TextAlign.center,
                      onSubmitted: (_) {
                        if (!_verifying && !_requesting) _verify();
                      },
                      decoration: InputDecoration(
                        hintText: 'Enter code',
                        prefixIcon: const Icon(Icons.pin_rounded),
                        fillColor: b.surface,
                      ),
                      style: text.titleLarge?.copyWith(
                        letterSpacing: 6,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_requesting)
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sending code to your email…',
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      )
                    else if (_otpStatus != null)
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: b.tint(statusColor, 0.10),
                            borderRadius: BorderRadius.circular(Brand.radius),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _otpSent
                                    ? Icons.mark_email_read_rounded
                                    : Icons.error_outline_rounded,
                                size: 18,
                                color: statusColor,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _otpStatus!,
                                  style: text.bodySmall?.copyWith(
                                    color: b.paper,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SignalButton(
          label: 'Unlock vault',
          icon: Icons.lock_open_rounded,
          busy: _verifying,
          onPressed: (_verifying || _requesting) ? null : _verify,
        ),
        const SizedBox(height: 12),
        GhostButton(
          label: _requesting ? 'Sending OTP…' : 'Resend OTP',
          icon: Icons.refresh_rounded,
          onPressed: () {
            if (!_requesting) _requestOtp();
          },
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 16, color: b.paperDim),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Credentials stay masked until you open one.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final b = context.brand;
    if (_loading && _rows.isEmpty) return const SkeletonList(count: 6);
    return RefreshIndicator(
      color: b.signal,
      backgroundColor: b.surface,
      onRefresh: _load,
      child: _rows.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 64),
                EmptyState(
                  icon: Icons.key_rounded,
                  label: 'No credentials',
                  hint: 'Store the first client credential. Pull to refresh.',
                  action: SignalButton(
                    label: 'New credential',
                    icon: Icons.add_rounded,
                    onPressed: _openForm,
                  ),
                ),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _Entry(
                index: i,
                child: _CredentialRow(
                  row: _rows[i],
                  onTap: () => _openForm(_rows[i]),
                ),
              ),
            ),
    );
  }
}

class _LockSeal extends StatelessWidget {
  const _LockSeal({required this.unlocking});

  final bool unlocking;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
      width: 84,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Brand.orange.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(
          color: Brand.orange.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: reduce ? 0 : 300),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          unlocking ? Icons.lock_open_rounded : Icons.lock_rounded,
          key: ValueKey<bool>(unlocking),
          size: 34,
          color: Brand.orange,
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final start = (index.clamp(0, 5)) * 0.12;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.row, required this.onTap});
  final Credential row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final hasSecret = row.credentialsText.isNotEmpty;
    final name = row.clientName.isEmpty ? 'Untitled' : row.clientName;
    return Semantics(
      button: true,
      label:
          '$name, ${hasSecret ? 'credentials stored, hidden' : 'no credentials stored'}',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        radius: Brand.radiusLg,
        borderColor: hasSecret ? Brand.orange.withValues(alpha: 0.32) : null,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: hasSecret
                    ? Brand.orange.withValues(alpha: b.isDark ? 0.18 : 0.12)
                    : b.surfaceHi,
                border: Border.all(
                  color: hasSecret
                      ? Brand.orange.withValues(alpha: 0.4)
                      : b.rule,
                ),
              ),
              child: Icon(
                hasSecret ? Icons.key_rounded : Icons.key_off_rounded,
                size: 20,
                color: hasSecret ? Brand.orange : b.paperDim,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasSecret ? '••••••••••••' : 'No credentials stored',
                    style: text.bodySmall?.copyWith(
                      color: b.paperDim,
                      fontFamily: hasSecret ? 'monospace' : null,
                      letterSpacing: hasSecret ? 1.5 : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GlowBadge(
              label: hasSecret ? 'Masked' : 'Empty',
              color: hasSecret ? Brand.success : Brand.warning,
              icon: hasSecret
                  ? Icons.visibility_off_rounded
                  : Icons.remove_rounded,
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: b.paperDim),
          ],
        ),
      ),
    );
  }
}

class _CredentialFormScreen extends StatefulWidget {
  const _CredentialFormScreen({required this.service, this.existing});
  final CredentialService service;
  final Credential? existing;

  @override
  State<_CredentialFormScreen> createState() => _CredentialFormScreenState();
}

class _CredentialFormScreenState extends State<_CredentialFormScreen> {
  late final TextEditingController _clientName;
  late final TextEditingController _credentials;
  bool _obscure = true;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _clientName = TextEditingController(text: e?.clientName ?? '');
    _credentials = TextEditingController(text: e?.credentialsText ?? '');
  }

  @override
  void dispose() {
    _clientName.dispose();
    _credentials.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _clientName.text.trim();
    if (name.isEmpty) {
      _toast('Client name is required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.save(
      id: widget.existing?.id,
      clientName: name,
      credentialsText: _credentials.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the credential.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete credential?'),
        content: const Text('This permanently removes the stored credential.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    final res = await widget.service.delete(widget.existing!.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not delete the credential.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _credentials.text));
    _toast('Copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final name = _clientName.text.trim();
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Credentials',
      title: _isEdit ? 'Edit credential' : 'New credential',
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          GlassPanel(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const IconTile(
                  icon: Icons.lock_rounded,
                  size: 48,
                  iconSize: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'New client' : name,
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      const GlowBadge(
                        label: 'OTP protected',
                        color: Brand.success,
                        icon: Icons.verified_user_rounded,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('Client name', style: text.labelLarge),
                ),
                TextField(
                  controller: _clientName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Client name',
                    prefixIcon: Icon(Icons.business_rounded),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text('Credentials', style: text.labelLarge),
                    ),
                    IconButton(
                      tooltip: 'Copy credentials',
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: b.paperDim,
                      ),
                      onPressed: _copy,
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 18,
                      ),
                      label: Text(_obscure ? 'Reveal' : 'Hide'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _credentials,
                  obscureText: _obscure,
                  maxLines: _obscure ? 1 : 8,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  style: text.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 0.6,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Credentials text',
                    prefixIcon: Icon(Icons.key_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SignalButton(
            label: _isEdit ? 'Save changes' : 'Store credential',
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Brand.danger,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.radius),
                  ),
                ),
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                label: const Text('Delete credential'),
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
