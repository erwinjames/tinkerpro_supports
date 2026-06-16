import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';

/// Credentials vault — gated behind an email OTP. The server marks the
/// session as verified after [verifyOtp]; until then the list endpoint
/// rejects reads, so we show an unlock flow first.
class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key, required this.service});
  final CredentialsService service;

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  bool _unlocked = false;
  bool _otpSent = false;
  bool _busy = false;
  String? _info;
  final _otpCtrl = TextEditingController();

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    setState(() => _busy = true);
    final res = await widget.service.requestOtp();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _otpSent = res.ok;
      _info = res.ok
          ? (res.message.isEmpty ? 'Code sent to your email.' : res.message)
          : (res.message.isEmpty ? 'Could not send code.' : res.message);
    });
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text.trim();
    if (code.length < 4) {
      setState(() => _info = 'Enter the code from your email.');
      return;
    }
    setState(() => _busy = true);
    final ok = await widget.service.verifyOtp(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _unlocked = ok;
      if (!ok) _info = 'Invalid or expired code.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return _CredentialsList(service: widget.service);

    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'CREDENTIALS',
      title: 'Vault.',
      showBottomBrand: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, color: Brand.signal, size: 40),
              const SizedBox(height: 16),
              Text('This vault is protected',
                  style: text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(
                'Verify with a one-time code sent to your account email to view stored client credentials.',
                style: text.bodySmall?.copyWith(color: Brand.paperDim),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_otpSent) ...[
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                      labelText: 'Verification code', hintText: '6-digit code'),
                  onSubmitted: (_) => _verify(),
                ),
                const SizedBox(height: 12),
                SignalButton(
                    label: _busy ? 'Verifying…' : 'Verify & unlock',
                    icon: Icons.lock_open,
                    onPressed: _busy ? null : _verify),
                const SizedBox(height: 8),
                GhostButton(
                    label: 'Resend code',
                    onPressed: () {
                      if (!_busy) _requestOtp();
                    }),
              ] else
                SignalButton(
                    label: _busy ? 'Sending…' : 'Send code',
                    icon: Icons.mark_email_read_outlined,
                    onPressed: _busy ? null : _requestOtp),
              if (_info != null) ...[
                const SizedBox(height: 14),
                Text(_info!,
                    style: text.bodySmall, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CredentialsList extends StatelessWidget {
  const _CredentialsList({required this.service});
  final CredentialsService service;

  @override
  Widget build(BuildContext context) {
    return AdminListPage<Credential>(
      stationNumber: '11',
      stationLabel: 'CREDENTIALS',
      title: 'Vault.',
      addLabel: 'New entry',
      searchable: false,
      fetch: (_) => service.list(),
      onAdd: (ctx, refresh) => _edit(ctx, refresh),
      itemBuilder: (ctx, c, refresh) => _CredRow(
        credential: c,
        onEdit: () => _edit(ctx, refresh, existing: c),
        onDelete: () async {
          if (!await confirmDialog(ctx,
              title: 'Delete entry',
              message: 'Remove credentials for ${c.clientName}?')) return;
          final ok = await service.delete(c.id);
          if (!ctx.mounted) return;
          toast(ctx, ok ? 'Deleted' : 'Delete failed');
          if (ok) refresh();
        },
      ),
    );
  }

  Future<void> _edit(BuildContext context, VoidCallback refresh,
      {Credential? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.clientName ?? '');
    final textCtrl =
        TextEditingController(text: existing?.credentialsText ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New credentials' : 'Edit credentials'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Client name'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textCtrl,
                minLines: 4,
                maxLines: 12,
                decoration: const InputDecoration(
                    labelText: 'Credentials', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (context.mounted) toast(context, 'Client name is required.');
      return;
    }
    final ok = await service.save(
      id: existing?.id,
      clientName: name,
      credentialsText: textCtrl.text,
    );
    if (!context.mounted) return;
    toast(context, ok ? 'Saved' : 'Save failed');
    if (ok) refresh();
  }
}

class _CredRow extends StatelessWidget {
  const _CredRow(
      {required this.credential,
      required this.onEdit,
      required this.onDelete});
  final Credential credential;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(credential.clientName, style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(credential.credentialsText,
                      style: text.bodySmall
                          ?.copyWith(color: Brand.paperDim, height: 1.4)),
                ],
              ),
            ),
            IconButton(
                tooltip: 'Edit',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18)),
            IconButton(
                tooltip: 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18)),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: Brand.rule),
        const SizedBox(height: 10),
      ],
    );
  }
}
