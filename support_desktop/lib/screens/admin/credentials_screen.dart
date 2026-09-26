import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../theme.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';
import '../../widgets/tp_loader.dart';

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
    try {
      final res = await widget.service.requestOtp();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _otpSent = res.ok;
        _info = null;
      });
      if (res.ok) {
        toast(context, res.message);
      } else {
        toast(
          context,
          res.message.isNotEmpty ? res.message : 'Failed to send OTP.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, 'Network error occurred.');
    }
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text;
    if (code.length != 6) {
      toast(context, 'Please enter a 6-digit OTP code.');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.service.verifyOtp(code);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unlocked = res.ok;
      });
      toast(
        context,
        res.ok
            ? 'Success! Loading credentials...'
            : (res.message.isNotEmpty ? res.message : 'Invalid OTP.'),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, 'Network error occurred.');
    }
  }

  String? _masked;
  bool _hasEmail = true;

  @override
  void initState() {
    super.initState();
    widget.service.api.get('desktopCredentialsVault').then((res) {
      if (!mounted) return;
      setState(() {
        _masked = (res['masked_email'] ?? '').toString();
        _hasEmail = res['has_email'] != false;
        if (res['verified'] == true) _unlocked = true;
      });
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return _CredentialsList(service: widget.service);
    return Scaffold(
      backgroundColor: context.brand.canvas,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 10, bottom: 30),
        child: Center(
          child: Container(
            width: 500,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 30),
                  decoration: const BoxDecoration(
                    color: Brand.navy,
                    border: Border(
                      bottom: BorderSide(color: Brand.signal, width: 4),
                    ),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'SECURITY PROTOCOL',
                        style: TextStyle(
                          color: Brand.signal,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Vault Verification',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: !_hasEmail
                      ? Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: const Color(0x0DDC3545),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x33DC3545)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error, color: Color(0xFFDC3545)),
                              SizedBox(height: 8),
                              Text(
                                'No communication link established.',
                                style: TextStyle(
                                  color: Color(0xFFDC3545),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'You do not have an email address configured. Please contact the administrator.',
                                style: TextStyle(
                                  color: Color(0xCCDC3545),
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'DECRYPTION REQUIRED',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.2,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'A one-time decryption key has been routed to:',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15.2,
                                height: 1.6,
                                color: Color(0xFF0C233E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x0DFF7D00),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _masked ?? '…',
                                  style: const TextStyle(
                                    fontSize: 15.2,
                                    fontWeight: FontWeight.w700,
                                    color: Brand.signal,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (_otpSent) ...[
                              const Text(
                                'ENTER VERIFICATION KEY',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Center(
                                child: SizedBox(
                                  width: 320,
                                  child: TextField(
                                    controller: _otpCtrl,
                                    autofocus: true,
                                    keyboardType: TextInputType.number,
                                    maxLength: 6,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 10,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '000000',
                                      counterText: '',
                                      contentPadding: const EdgeInsets.all(16),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE5E7EB),
                                          width: 2,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Brand.signal,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    onSubmitted: (_) => _verify(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 32),
                              _bigButton(
                                'DECRYPT & ACCESS',
                                Icons.lock_open,
                                Brand.navy,
                                _busy ? null : _verify,
                                trailingIcon: true,
                              ),
                            ] else
                              _bigButton(
                                'TRANSMIT OTP CODE',
                                Icons.send,
                                Brand.signal,
                                _busy ? null : _requestOtp,
                              ),
                            if (_info != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _info!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bigButton(
    String label,
    IconData icon,
    Color bg,
    VoidCallback? onTap, {
    bool trailingIcon = false,
  }) {
    final iconW = Icon(icon, size: 16, color: Colors.white);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: bg.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: TpLoader(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!trailingIcon) ...[iconW, const SizedBox(width: 10)],
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    if (trailingIcon) ...[const SizedBox(width: 10), iconW],
                  ],
                ),
        ),
      ),
    );
  }
}

class _CredentialsList extends StatelessWidget {
  _CredentialsList({required this.service});
  final CredentialsService service;
  final List<Credential> _order = [];

  @override
  Widget build(BuildContext context) {
    return AdminTablePage<Credential>(
      stationNumber: '11',
      stationLabel: 'CREDENTIALS',
      title: 'Client Credentials',
      addLabel: 'Append entry',
      searchHint: 'Search clients…',
      liveKeys: const ['credentials'],
      fetch: (_) async {
        final page = await service.list();
        _order
          ..clear()
          ..addAll(page.items);
        return page;
      },
      localFilter: (c, q) => c.clientName.toLowerCase().contains(q),
      onAdd: (ctx, refresh) => _edit(ctx, refresh),
      onRowTap: (ctx, c, refresh) => _view(ctx, refresh, c),
      columns: [
        const AdminColumn('No.', width: 70, center: true, sortable: false),
        AdminColumn(
          'Vault Target',
          width: 260,
          sortValue: (c) => (c as Credential).clientName,
        ),
        AdminColumn(
          'Payload Preview',
          flex: 1,
          sortValue: (c) => (c as Credential).credentialsText,
        ),
        AdminColumn(
          'Last Access',
          width: 190,
          center: true,
          sortValue: (c) => (c as Credential).createdAt,
        ),
        const AdminColumn('Actions', width: 150, center: true, sortable: false),
      ],
      cells: (ctx, c, refresh) {
        final text = c.credentialsText.replaceAll('\n', ' ');
        return [
          AdminCellText('${_order.indexOf(c) + 1}'),
          AdminCellText(c.clientName, bold: true),
          Opacity(
            opacity: 0.7,
            child: AdminCellText(
              text.length > 50 ? '${text.substring(0, 50)}...' : text,
              mono: true,
              size: 14,
            ),
          ),
          AdminCellText(c.createdAt, muted: true, size: 13.5),
          AdminRowMenu(
            actions: [
              AdminMenuAction(
                'Decrypt & View',
                Icons.visibility_outlined,
                () => _view(ctx, refresh, c),
              ),
              AdminMenuAction(
                'Modify Record',
                Icons.edit_outlined,
                () => _edit(ctx, refresh, existing: c),
              ),
              AdminMenuAction(
                'Purge Record',
                Icons.delete_outline,
                () => _delete(ctx, refresh, c),
                danger: true,
              ),
            ],
          ),
        ];
      },
    );
  }

  Future<void> _delete(
    BuildContext context,
    VoidCallback refresh,
    Credential c,
  ) async {
    if (!await confirmDialog(
      context,
      title: 'Delete this credential?',
      message:
          'The credential will be permanently removed and cannot be recovered.',
      confirmLabel: 'Delete credential',
    )) {
      return;
    }
    if (!context.mounted) return;
    adminUndoDelete(
      context,
      message: 'Credential deleted',
      commit: () async {
        try {
          final res = await service.delete(c.id);
          if (!res.ok && context.mounted) {
            toast(
              context,
              res.message.isNotEmpty
                  ? res.message
                  : 'Error deleting credential.',
            );
          }
        } catch (_) {
          if (context.mounted) toast(context, 'Network error occurred.');
        }
        refresh();
      },
    );
  }

  Future<void> _view(
    BuildContext context,
    VoidCallback refresh,
    Credential c,
  ) async {
    final edit = await showWebModal<bool>(
      context,
      title: 'View Data Record',
      subtitle: c.clientName,
      icon: Icons.lock_open_outlined,
      width: 640,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StationDataRow(label: 'Client name', value: c.clientName),
          StationDataRow(
            label: 'Created',
            value: adminFormatDate(c.createdAt, withTime: true),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Credentials payload',
                style: Theme.of(
                  ctx,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              GhostButton(
                label: 'Copy',
                icon: Icons.copy,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: c.credentialsText),
                  );
                  if (ctx.mounted) toast(ctx, 'Copied to clipboard');
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ctx.brand.surfaceHi,
              border: Border.all(color: ctx.brand.rule),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              c.credentialsText.isEmpty
                  ? 'No additional notes provided.'
                  : c.credentialsText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
      actions: (ctx) => [
        GhostButton(
          label: 'Seal & Close Vault',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        SignalButton(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    );
    if (edit == true && context.mounted) {
      await _edit(context, refresh, existing: c);
    }
  }

  Future<void> _edit(
    BuildContext context,
    VoidCallback refresh, {
    Credential? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.clientName ?? '');
    final textCtrl = TextEditingController(
      text: existing?.credentialsText ?? '',
    );
    var busy = false;

    Future<void> submit(BuildContext ctx, StateSetter setLocal) async {
      if (busy) return;
      if (nameCtrl.text.isEmpty) {
        toast(ctx, 'Please fill out this field.');
        return;
      }
      setLocal(() => busy = true);
      try {
        final res = await service.save(
          id: existing?.id,
          clientName: nameCtrl.text,
          credentialsText: textCtrl.text,
        );
        if (!ctx.mounted) return;
        if (res.ok) {
          toast(ctx, res.message);
          Navigator.pop(ctx, true);
        } else {
          toast(
            ctx,
            res.message.isNotEmpty ? res.message : 'Error saving credential.',
          );
        }
      } catch (_) {
        if (ctx.mounted) toast(ctx, 'Network error occurred.');
      } finally {
        if (ctx.mounted) setLocal(() => busy = false);
      }
    }

    final saved = await showWebModal<bool>(
      context,
      title: existing == null
          ? 'Add New Client Credential'
          : 'Edit Client Credential',
      subtitle: 'Data Entry Protocol',
      icon: Icons.lock_outline,
      width: 720,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSectionTitle(
            '[01] Vault Target',
            icon: Icons.business_outlined,
          ),
          FormRow(
            label: 'Client Title / Name',
            icon: Icons.badge_outlined,
            required: true,
            labelWidth: 170,
            child: TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'e.g. ACME_VPN_SEC'),
            ),
          ),
          const SizedBox(height: 8),
          const AdminSectionTitle(
            '[02] Sensitive Payload',
            icon: Icons.key_outlined,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 8),
            child: Text(
              'RAW CREDENTIALS PAYLOAD',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: Color(0xFF888888),
              ),
            ),
          ),
          TextField(
            controller: textCtrl,
            minLines: 8,
            maxLines: 16,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
            decoration: const InputDecoration(
              hintText: 'Enter credentials or notes here...',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: (ctx) => [
        GhostButton(
          label: 'Abort',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        StatefulBuilder(
          builder: (bctx, setLocal) => SignalButton(
            label: 'Persist Data',
            icon: Icons.save_outlined,
            busy: busy,
            onPressed: busy ? null : () => submit(ctx, setLocal),
          ),
        ),
      ],
    );

    if (saved == true) refresh();
  }
}
