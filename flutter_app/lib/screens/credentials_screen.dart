import 'package:flutter/material.dart';

import '../models/credential_models.dart';
import '../services/credential_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

// Credentials Storage — native CRUD behind an emailed OTP gate. On open we
// request an OTP and show an entry field; once verified we reveal the list of
// client credentials with create / edit / delete. Credential text is masked in
// the list and only revealed in the detail/edit form.
class CredentialsScreen extends StatefulWidget {
  const CredentialsScreen({super.key, required this.service});
  final CredentialService service;

  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> {
  // OTP gate state.
  final TextEditingController _otp = TextEditingController();
  bool _requesting = true; // requesting the initial OTP
  bool _verifying = false;
  bool _verified = false;
  String? _otpStatus;

  // List state (after verification).
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
      _otpStatus =
          res.ok ? 'OTP sent to your email.' : (res.message ?? 'Failed to send OTP.');
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'CREDENTIALS',
      title: _verified ? 'Credentials.' : 'Locked.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: _verified
          ? StationAction(
              icon: Icons.add,
              tooltip: 'New credential',
              onPressed: _openForm,
            )
          : null,
      child: _verified ? _buildList(context) : _buildGate(context),
    );
  }

  // --- OTP gate ---------------------------------------------------------
  Widget _buildGate(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      children: [
        const SizedBox(height: 8),
        Text(
          'This vault is protected. We emailed a one-time password to your '
          'account. Enter it below to unlock client credentials.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'ONE-TIME PASSWORD'),
          style: text.titleMedium,
        ),
        if (_otpStatus != null) ...[
          const SizedBox(height: 12),
          Text(_otpStatus!.toUpperCase(),
              style: text.labelMedium?.copyWith(color: Brand.paperDim)),
        ],
        const SizedBox(height: 28),
        SignalButton(
          label: 'Verify',
          busy: _verifying,
          onPressed: (_verifying || _requesting) ? null : _verify,
        ),
        const SizedBox(height: 12),
        GhostButton(
          label: _requesting ? 'Sending OTP…' : 'Resend OTP',
          onPressed: () {
            if (!_requesting) _requestOtp();
          },
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // --- Credentials list -------------------------------------------------
  Widget _buildList(BuildContext context) {
    return RefreshIndicator(
      color: Brand.signal,
      backgroundColor: Brand.surface,
      onRefresh: _load,
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Brand.signal),
              ),
            )
          : _rows.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 64),
                    EmptyState(
                      label: 'No credentials',
                      hint: 'Tap + to store the first client. Pull to refresh.',
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const Hairline(),
                  itemBuilder: (_, i) => _CredentialRow(
                    row: _rows[i],
                    onTap: () => _openForm(_rows[i]),
                  ),
                ),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 12),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.rule,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.clientName.isEmpty ? 'Untitled' : row.clientName,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '••••••••',
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'TAP TO REVEAL',
              style: text.labelMedium?.copyWith(
                color: Brand.paperDim,
                letterSpacing: 2.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Add / edit form. The credential text is revealed here (masked in the list).
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
        backgroundColor: Brand.surface,
        title: const Text('Delete credential?'),
        content: const Text('This permanently removes the stored credential.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: _isEdit ? 'EDIT CREDENTIAL' : 'NEW CREDENTIAL',
      title: _isEdit ? 'Edit.' : 'Store.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          TextField(
            controller: _clientName,
            decoration: const InputDecoration(labelText: 'CLIENT NAME'),
            style: text.titleMedium,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text('CREDENTIALS', style: text.labelLarge),
              ),
              TextButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                child: Text(_obscure ? 'REVEAL' : 'HIDE'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _credentials,
            obscureText: _obscure,
            maxLines: _obscure ? 1 : 8,
            minLines: 1,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'CREDENTIALS TEXT',
              alignLabelWithHint: true,
            ),
            style: text.titleMedium,
          ),
          const SizedBox(height: 32),
          SignalButton(
            label: _isEdit ? 'Save changes' : 'Store credential',
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 12),
            GhostButton(label: 'Delete credential', onPressed: _delete),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
