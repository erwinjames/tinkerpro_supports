import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../services/bir_misc_service.dart';
import 'admin/admin_list.dart' show confirmDialog;
import 'bir_misc_ui.dart';
import 'bir_widgets.dart';

class BirMiscActions {
  BirMiscActions._();

  static String _s(Map<String, dynamic> r, String k) =>
      (r[k] ?? '').toString().trim();

  static Future<bool> delete(
    BuildContext context,
    ApiClient api,
    Map<String, dynamic> row, {
    VoidCallback? onHide,
    VoidCallback? onRestore,
    VoidCallback? onCommitted,
  }) async {
    final id = int.tryParse(_s(row, 'id')) ?? 0;
    if (id <= 0) return false;
    final ok = await confirmDialog(
      context,
      title: 'Delete this customer?',
      message:
          'The customer record and its linked history will be permanently removed.',
      confirmLabel: 'Delete customer',
    );
    if (!ok || !context.mounted) return false;
    final messenger = ScaffoldMessenger.of(context);
    final svc = BirMiscService(api);
    onHide?.call();
    var settled = false;
    Future<void> commit() async {
      if (settled) return;
      settled = true;
      messenger.hideCurrentSnackBar();
      final done = await svc.deleteCustomer(id).catchError((_) => false);
      if (!done) {
        messenger.showSnackBar(
          const SnackBar(
            persist: false,
            content: Text('Failed to delete Customer.'),
          ),
        );
      }
      onCommitted?.call();
    }

    final timer = Timer(const Duration(seconds: 5), commit);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: const Duration(seconds: 5),
          content: const Text('Customer deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (settled) return;
              settled = true;
              timer.cancel();
              onRestore?.call();
              messenger.showSnackBar(
                const SnackBar(
                  persist: false,
                  duration: Duration(milliseconds: 1800),
                  content: Text('Delete undone'),
                ),
              );
            },
          ),
        ),
      );
    return true;
  }

  static Future<void> _save(
    BuildContext context,
    BirMiscService svc,
    Uri uri,
    String fallbackName,
  ) async {
    final res = await svc.fetch(uri);
    if (!context.mounted) return;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = res.body.trim();
      birToast(
        context,
        body.isNotEmpty && body.length < 300 ? body : 'Download failed.',
        kind: BirToastKind.error,
        duration: const Duration(seconds: 3),
      );
      return;
    }
    final name = BirMiscService.dispositionName(res, fallbackName);
    final saved = await svc.saveBytes(res.bodyBytes, name);
    if (!context.mounted) return;
    birToast(
      context,
      'Saved to ${saved.path}',
      kind: BirToastKind.success,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: 'Open',
        onPressed: () => svc.open(saved.path),
      ),
    );
  }

  static Future<void> downloadCsv(
    BuildContext context,
    ApiClient api,
    Map<String, dynamic> row,
  ) async {
    final id = _s(row, 'id');
    final csvFile = _s(row, 'csv_file');
    final hasData = _s(row, 'csv_file_data').isNotEmpty;
    if (!hasData && csvFile.isEmpty) {
      birToast(
        context,
        'CSV file is not available for this customer yet.',
        kind: BirToastKind.warning,
        duration: const Duration(milliseconds: 1500),
      );
      return;
    }
    final svc = BirMiscService(api);
    final uri = hasData
        ? Uri.parse(api.actionUrl('downloadCustomerCsv', {'id': id}))
        : svc.pathUri(
            '$csvFile${csvFile.contains('?') ? '&' : '?'}v=${DateTime.now().millisecondsSinceEpoch}',
          );
    final fallback = hasData
        ? 'customer-$id.csv'
        : csvFile.split('/').last.split('?').first;
    try {
      await _save(context, svc, uri, fallback);
    } catch (_) {
      if (context.mounted) {
        birToast(context, 'Download failed.', kind: BirToastKind.error);
      }
    }
  }

  static Future<void> downloadXlsx(
    BuildContext context,
    ApiClient api,
    Map<String, dynamic> row,
  ) async {
    final id = _s(row, 'id');
    if (_s(row, 'csv_file_data').isEmpty) {
      birToast(
        context,
        'CSV file is not available for this customer yet.',
        kind: BirToastKind.warning,
        duration: const Duration(milliseconds: 1500),
      );
      return;
    }
    final svc = BirMiscService(api);
    try {
      await _save(
        context,
        svc,
        Uri.parse(api.actionUrl('downloadCustomerXlsx', {'id': id})),
        'customer-$id.xlsx',
      );
    } catch (_) {
      if (context.mounted) {
        birToast(context, 'Download failed.', kind: BirToastKind.error);
      }
    }
  }

  static Future<void> downloadDocs(
    BuildContext context,
    ApiClient api,
    Map<String, dynamic> row,
  ) async {
    final id = _s(row, 'id');
    if (id.isEmpty) {
      birToast(
        context,
        'Customer ID is missing.',
        kind: BirToastKind.error,
        duration: const Duration(milliseconds: 1500),
      );
      return;
    }
    final svc = BirMiscService(api);
    try {
      await _save(
        context,
        svc,
        Uri.parse(api.actionUrl('downloadCustomerDocuments', {'id': id})),
        'documents.zip',
      );
    } catch (_) {
      if (context.mounted) {
        birToast(
          context,
          'Failed to download documents.',
          kind: BirToastKind.error,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  static Future<void> apiToken(
    BuildContext context,
    ApiClient api,
    Map<String, dynamic> row,
  ) => BirApiTokenDialog.show(context, api, row);
}

class BirApiTokenDialog extends StatefulWidget {
  const BirApiTokenDialog({super.key, required this.api, required this.row});
  final ApiClient api;
  final Map<String, dynamic> row;

  static Future<void> show(
    BuildContext context,
    ApiClient api,
    Map<String, dynamic> row,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => BirApiTokenDialog(api: api, row: row),
    );
  }

  @override
  State<BirApiTokenDialog> createState() => _BirApiTokenDialogState();
}

class _BirApiTokenDialogState extends State<BirApiTokenDialog> {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  late final BirMiscService _svc = BirMiscService(widget.api);
  final _label = TextEditingController();
  List<BirApiToken>? _tokens;
  String? _error;
  String _plain = '';
  bool _generating = false;

  String _s(String k) => (widget.row[k] ?? '').toString().trim();
  int get _id => int.tryParse(_s('id')) ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_id <= 0) return;
    setState(() {
      _tokens = null;
      _error = null;
    });
    try {
      final t = await _svc.apiTokens(_id);
      if (mounted) setState(() => _tokens = t);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is BirMiscException ? e.message : 'Could not load tokens.';
          _tokens = const [];
        });
      }
    }
  }

  Future<void> _generate() async {
    if (_id <= 0) return;
    setState(() => _generating = true);
    try {
      final r = await _svc.createApiToken(_id, _label.text);
      if (!mounted) return;
      final token = (r['token'] ?? '').toString();
      if (r['status'] == 'success' && token.isNotEmpty) {
        setState(() => _plain = token);
        _label.clear();
        _load();
      } else {
        final m = (r['message'] ?? '').toString();
        birToast(
          context,
          m.isEmpty ? 'Could not create the token.' : m,
          kind: BirToastKind.error,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (_) {
      if (mounted) {
        birToast(
          context,
          'Could not create the token.',
          kind: BirToastKind.error,
          duration: const Duration(seconds: 3),
        );
      }
    }
    if (mounted) setState(() => _generating = false);
  }

  Future<void> _copy() async {
    if (_plain.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: _plain));
      if (mounted) {
        birToast(
          context,
          'Token copied to clipboard.',
          kind: BirToastKind.success,
          duration: const Duration(milliseconds: 1500),
        );
      }
    } catch (_) {
      if (mounted) {
        birToast(
          context,
          'Copy failed — select the token and copy it manually.',
          kind: BirToastKind.error,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  Future<void> _revoke(BirApiToken t) async {
    final ok = await birAlert(
      context,
      icon: BirAlertIcon.warning,
      title: 'Revoke this token?',
      text:
          'Any POS still using it will stop syncing immediately. This cannot be undone.',
      confirmLabel: 'Revoke',
      cancelLabel: 'Cancel',
      confirmColor: const Color(0xFFDC3545),
    );
    if (!ok || !mounted) return;
    try {
      final r = await _svc.revokeApiToken(t.id, _id);
      if (!mounted) return;
      if (r['status'] == 'success') {
        birToast(
          context,
          'Token revoked.',
          kind: BirToastKind.success,
          duration: const Duration(milliseconds: 1500),
        );
        _load();
      } else {
        final m = (r['message'] ?? '').toString();
        birToast(
          context,
          m.isEmpty ? 'Could not revoke the token.' : m,
          kind: BirToastKind.error,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (_) {
      if (mounted) {
        birToast(
          context,
          'Could not revoke the token.',
          kind: BirToastKind.error,
          duration: const Duration(seconds: 3),
        );
      }
    }
  }

  String _date(String v) {
    if (v.isEmpty) return 'never';
    final d = DateTime.tryParse(v.replaceFirst(' ', 'T'));
    if (d == null) return v;
    var h = d.hour % 12;
    if (h == 0) h = 12;
    final hh = h.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${_months[d.month - 1]} ${d.day}, ${d.year}, $hh:$mm ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  String get _openApiBase => '${_svc.base}/open-api';

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFF64748B);
    const sub = TextStyle(fontSize: 13, color: muted);
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5);
    final tinDigits = _s('tin').replaceAll(RegExp(r'\D+'), '');
    final sampleTin = tinDigits.isNotEmpty
        ? tinDigits.substring(0, tinDigits.length < 9 ? tinDigits.length : 9)
        : '<tin>';
    final branchDigits = _s('branch_code').replaceAll(RegExp(r'\D+'), '');
    final sampleBranch = branchDigits.isNotEmpty
        ? branchDigits
        : (tinDigits.length > 9 ? tinDigits.substring(9) : '00000');
    return BirDialogShell(
      title: 'POS API Token',
      subtitle: _s('company_name'),
      icon: Icons.key,
      width: 800,
      footer: Align(
        alignment: Alignment.centerRight,
        child: BirSolidButton(
          label: 'Close',
          height: 36,
          color: const Color(0xFF6C757D),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_plain.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x1216A34A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF16A34A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Color(0xFF16A34A),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Token created — copy it now',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Only a hash is stored. Once this modal closes the token can never be shown again.',
                    style: sub,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x0F0F172A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: SelectableText(_plain, style: mono),
                        ),
                      ),
                      const SizedBox(width: 8),
                      BirSolidButton(
                        label: 'Copy',
                        icon: Icons.copy,
                        height: 34,
                        color: const Color(0xFF198754),
                        onPressed: _copy,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            "The client's POS normally enrols itself with its TIN + branch code and never needs this screen. Generate one by hand only when a POS can't reach the enrol call, or to replace a token the client lost.",
            style: sub,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Label ',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: '(which terminal is this for?)',
                            style: TextStyle(color: muted),
                          ),
                        ],
                      ),
                      style: TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _label,
                      maxLength: 150,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Cashier 1 POS',
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              BirSolidButton(
                label: 'Generate token',
                icon: Icons.add,
                height: 40,
                color: const Color(0xFF007BFF),
                busy: _generating,
                onPressed: _generate,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x1A0F172A)),
            ),
            clipBehavior: Clip.antiAlias,
            child: _tokenList(sub, mono),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0x0A0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'How the POS uses this token',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  'this client: curl -H "Authorization: Bearer tps_…" "$_openApiBase?password=…"',
                  style: mono,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  'one branch:  curl -H "Authorization: Bearer tps_…" "$_openApiBase?tin=$sampleTin$sampleBranch&password=…"',
                  style: mono,
                ),
                const SizedBox(height: 4),
                const Text(
                  "password is always required — this client's POS software password, matched exactly. The token identifies the client, so tin is optional; sent, it narrows the result to one branch. Results always come back as a list in data.results.",
                  style: sub,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tokenList(TextStyle sub, TextStyle mono) {
    final tokens = _tokens;
    Widget empty(String t, {bool error = false}) => Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13.5,
          color: error ? const Color(0xFFDC3545) : const Color(0xFF64748B),
        ),
      ),
    );
    if (tokens == null) return empty('Loading…');
    if (_error != null) return empty(_error!, error: true);
    if (tokens.isEmpty) {
      return empty(
        "No tokens yet. Generate one and paste it into the client's POS.",
      );
    }
    return Column(
      children: [
        for (var i = 0; i < tokens.length; i++)
          _tokenRow(tokens[i], i == tokens.length - 1, sub, mono),
      ],
    );
  }

  Widget _tokenRow(BirApiToken t, bool last, TextStyle sub, TextStyle mono) {
    final meta = t.active
        ? 'Used ${t.requestCount}× · last ${_date(t.lastUsedAt)}'
        : 'Revoked ${_date(t.revokedAt)}';
    final issuedBy = t.source == 'self'
        ? ' · enrolled by the POS${t.createdIp.isNotEmpty ? ' from ${t.createdIp}' : ''}'
        : (t.createdByName.isNotEmpty ? ' · issued by ${t.createdByName}' : '');
    final serial = t.deviceSerial.isNotEmpty ? ' · SN ${t.deviceSerial}' : '';
    return Opacity(
      opacity: t.active ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(bottom: BorderSide(color: Color(0x120F172A))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          t.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (t.source == 'self') ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x1F6366F1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'SELF-ENROLLED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: t.masked, style: mono),
                        TextSpan(text: ' · $meta$serial$issuedBy'),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (t.active)
              OutlinedButton(
                onPressed: () => _revoke(t),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC3545),
                  side: const BorderSide(color: Color(0xFFDC3545)),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Revoke'),
              )
            else
              const BirBadge(
                label: 'Revoked',
                bg: Color(0xFF6C757D),
                fontSize: 11,
              ),
          ],
        ),
      ),
    );
  }
}
