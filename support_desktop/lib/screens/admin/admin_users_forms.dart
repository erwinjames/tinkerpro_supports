import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/admin_users_service.dart';
import '../../theme.dart';
import '../../widgets/admin_fa.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';
import 'admin_user_perms.dart';
import '../../widgets/tp_loader.dart';

const _navy = Color(0xFF0C233E);
const _line = Color(0xFFE5E7EB);
const _muted = Color(0xFF6B7280);
const _orange = Color(0xFFFF7D00);
const _orangeSoft = Color(0xFFFFF8F1);
const _orangeLine = Color(0xFFFFC89A);
const _green = Color(0xFF10B981);
const _red = Color(0xFFDC3545);

String _s(Map m, String k) => (m[k] ?? '').toString();
bool _on(dynamic v) => v == 1 || v == true || v == '1';

class AdminModalCard {
  const AdminModalCard(this.key, this.label, this.icon, {this.hint, this.kids = const []});
  final String key;
  final String label;
  final String icon;
  final String? hint;
  final List<AdminModalCard> kids;
}

const kAdminUserModalCards = <AdminModalCard>[
  AdminModalCard('dashboard', 'Dashboard', 'fas fa-th-large', kids: [
    AdminModalCard('dashboardSignals', 'Signal Chips', 'fas fa-bolt', hint: 'Open tickets, unassigned, chats waiting'),
    AdminModalCard('dashboardToday', 'Today', 'fas fa-sun', hint: 'Counters since midnight'),
    AdminModalCard('dashboardHeartbeat', 'Activity Heartbeat', 'fas fa-wave-square', hint: 'Streaming 24-hour activity chart'),
    AdminModalCard('dashboardFeed', 'Activity Stream', 'fas fa-satellite-dish', hint: 'Live feed of staff activity'),
    AdminModalCard('dashboardTotals', 'Totals', 'fas fa-layer-group', hint: 'Stat cards with 14-day trend'),
    AdminModalCard('dashboardRevenue', 'License Revenue', 'fas fa-coins', hint: 'Vendor licence payment figures (admins only)'),
    AdminModalCard('dashboardStatus', 'Status Overview', 'fas fa-chart-pie', hint: 'Doughnut charts for health signals'),
    AdminModalCard('dashboardDistribution', 'Distribution', 'fas fa-map-marked-alt', hint: 'Market and geography charts'),
    AdminModalCard('dashboardTrends', 'Activity Trends', 'fas fa-chart-line', hint: 'Ticket priority and 6-month trend'),
    AdminModalCard('dashboardThroughput', 'Throughput', 'fas fa-tachometer-alt', hint: 'Emails, files and barcodes over 6 months'),
  ]),
  AdminModalCard('ticket', 'Ticket', 'fas fa-ticket-alt'),
  AdminModalCard('chat', 'Chat', 'fas fa-comments', kids: [
    AdminModalCard('chatCustomers', 'Customer Chats', 'fas fa-user-tag', hint: 'Customer, guest and Facebook conversations'),
    AdminModalCard('chatVendors', 'Vendor Chats', 'fas fa-store', hint: 'Conversations opened from the vendor portal'),
    AdminModalCard('messageRequests', 'Facebook Chats', 'fab fa-facebook-messenger', hint: 'Handles the Facebook Chats queue'),
  ]),
  AdminModalCard('posversion', 'POS Version', 'fas fa-cash-register'),
  AdminModalCard('releasenotes', 'Release Notes', 'fas fa-clipboard-list'),
  AdminModalCard('licensekey', 'License Key', 'fas fa-key'),
  AdminModalCard('blogposts', 'Blog Posts', 'fas fa-blog'),
  AdminModalCard('customer', 'BIR Registration', 'fas fa-file-invoice'),
  AdminModalCard('client', 'Client', 'fas fa-user-tie'),
  AdminModalCard('clientOffer', 'Leads / Forms', 'fas fa-bullhorn'),
  AdminModalCard('user', 'User', 'fas fa-users', kids: [
    AdminModalCard('employmentInfo', 'Employment Info', 'far fa-address-card', hint: 'Review and manage employment information sheets'),
  ]),
  AdminModalCard('emails', 'Email', 'fas fa-envelope'),
  AdminModalCard('task', 'Task', 'fas fa-tasks'),
  AdminModalCard('settings', 'Settings', 'fas fa-cog'),
  AdminModalCard('activitylogs', 'Activity Logs', 'fas fa-history'),
  AdminModalCard('helpPage', 'Help Page', 'fas fa-question-circle'),
  AdminModalCard('analyze', 'Analyze', 'fas fa-chart-line'),
  AdminModalCard('credentials', 'Credentials Storage', 'fas fa-shield-alt'),
  AdminModalCard('files', 'Files Management', 'fas fa-folder-open', kids: [
    AdminModalCard('filesAllFolders', 'All Folders', 'fas fa-folder-tree', hint: 'Sees every folder'),
    AdminModalCard('filesShareOjt', 'OJT File Management', 'fas fa-user-graduate', hint: 'Sees only folders shared with OJT'),
    AdminModalCard('filesFolderSync', 'Folder Sync', 'fas fa-sync-alt', hint: 'Opens their own Folder Sync workspace'),
  ]),
  AdminModalCard('installer', 'Installer', 'fas fa-file-archive'),
  AdminModalCard('barcode', 'Barcode', 'fas fa-barcode'),
  AdminModalCard('zreading', 'Z-Reading Request', 'fas fa-receipt'),
];

const kAdminRoleChoices = <(String, String)>[
  ('admin', 'Administrator [Full Access]'),
  ('developer', 'Developer [Build Access]'),
  ('technical_staff', 'Technical Staff [Support Access]'),
  ('sales', 'Sales [Commercial Access]'),
  ('user', 'Standard User [Limited Access]'),
  ('ojt', 'OJT / Trainee [Restricted Access]'),
];

void adminNotifyOjtNetwork(BuildContext context, Map res) {
  final rule = _s(res, 'ojt_network_added');
  if (rule.isEmpty) return;
  final scope = _s(res, 'ojt_network_scope').trim();
  toast(
    context,
    'Your network ($rule) was added to OJT on-site access for ${scope.isEmpty ? 'all branches' : scope}.',
  );
}

Widget _fieldLabel(String text, {String? note}) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text.rich(
    TextSpan(
      text: text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: Color(0xFF334155),
      ),
      children: [
        if (note != null)
          TextSpan(
            text: ' $note',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
              color: _muted,
            ),
          ),
      ],
    ),
  ),
);

Widget _linkBox(BuildContext context, String url) {
  return _CopyLinkBox(url: url);
}

class _CopyLinkBox extends StatefulWidget {
  const _CopyLinkBox({required this.url});
  final String url;
  @override
  State<_CopyLinkBox> createState() => _CopyLinkBoxState();
}

class _CopyLinkBoxState extends State<_CopyLinkBox> {
  bool _copied = false;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line, width: 1.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              widget.url,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12.5,
                fontFamily: 'monospace',
                color: _navy,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.url));
              if (!mounted) return;
              setState(() => _copied = true);
              _t?.cancel();
              _t = Timer(const Duration(milliseconds: 1500), () {
                if (mounted) setState(() => _copied = false);
              });
            },
            icon: Icon(_copied ? Icons.check : Icons.copy, size: 14),
            label: Text(_copied ? 'Copied' : 'Copy'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _copied ? _green : _orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _linkResultDialog(
  BuildContext context, {
  required String title,
  required List<InlineSpan> intro,
  required String url,
  bool success = false,
  Widget? extra,
}) {
  return showWebModal<void>(
    context,
    title: title,
    icon: success ? Icons.check_circle_outline : Icons.link,
    width: 560,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 13.5, color: _muted, height: 1.5),
            children: intro,
          ),
        ),
        const SizedBox(height: 14),
        _linkBox(ctx, url),
        ?extra,
      ],
    ),
    actions: (ctx) => [
      SignalButton(
        label: 'Done',
        icon: Icons.check,
        onPressed: () => Navigator.pop(ctx),
      ),
    ],
  );
}

const _warm = TextStyle(color: _orange, fontWeight: FontWeight.w700);

Future<void> adminPublicLinkFlow(
  BuildContext context,
  AdminUsersApi api,
  String userId,
) async {
  try {
    final res = await api.publicLink(userId);
    if (!context.mounted) return;
    if (res['status'] == 'success') {
      await _linkResultDialog(
        context,
        title: 'Public Link Generated',
        intro: const [
          TextSpan(text: 'This link expires in '),
          TextSpan(text: '2 days', style: _warm),
          TextSpan(text: '.'),
        ],
        url: _s(res, 'public_url'),
      );
    } else {
      toast(context, _s(res, 'message').isEmpty ? 'Failed to generate link.' : _s(res, 'message'));
    }
  } catch (_) {
    if (context.mounted) toast(context, 'Network error.');
  }
}

Future<void> adminUserCreatedDialog(BuildContext context, String url) {
  return _linkResultDialog(
    context,
    title: 'User Created!',
    success: true,
    intro: const [
      TextSpan(text: 'A shareable profile link has been generated. It will '),
      TextSpan(text: 'expire in 2 days', style: _warm),
      TextSpan(text: '.'),
    ],
    url: url,
  );
}

Future<bool> adminVerifyAdminDialog(
  BuildContext context,
  AdminUsersApi api, {
  String? subtext,
}) async {
  final pass = TextEditingController();
  var busy = false;
  final ok = await showWebModal<bool>(
    context,
    title: 'VERIFICATION',
    subtitle: 'SEC//AUTH',
    icon: Icons.fingerprint,
    width: 440,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> verify() async {
          if (busy) return;
          if (pass.text.isEmpty) {
            toast(ctx, 'Please enter a password');
            return;
          }
          setLocal(() => busy = true);
          try {
            final res = await api.verifyAdmin(pass.text);
            if (!ctx.mounted) return;
            if (res['status'] == 'success') {
              Navigator.pop(ctx, true);
            } else {
              setLocal(() => busy = false);
              toast(ctx, _s(res, 'message').isEmpty ? 'Invalid access key.' : _s(res, 'message'));
            }
          } catch (_) {
            if (!ctx.mounted) return;
            setLocal(() => busy = false);
            toast(ctx, 'Verification failed');
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'AUTHORIZATION REQUIRED',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1, color: _navy),
            ),
            const SizedBox(height: 6),
            Text(
              subtext ?? 'Please authenticate to unlock matrix operations.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pass,
              autofocus: true,
              obscureText: true,
              onSubmitted: (_) => verify(),
              decoration: const InputDecoration(
                hintText: 'ENTER ACCESS KEY',
                prefixIcon: Icon(Icons.key, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: GhostButton(label: 'ABORT', onPressed: () => Navigator.pop(ctx, false)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SignalButton(
                    label: 'VERIFY',
                    icon: Icons.lock,
                    busy: busy,
                    onPressed: busy ? null : verify,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
  pass.dispose();
  return ok == true;
}

Future<void> adminInviteFlow(
  BuildContext context,
  AdminUsersApi api, {
  required bool isSuper,
}) async {
  var branches = const <Map<String, dynamic>>[];
  if (isSuper) branches = await api.branchOptions();
  if (!context.mounted) return;
  var role = 'user';
  var branch = '';
  var employment = false;
  final go = await showWebModal<bool>(
    context,
    title: 'Registration Link',
    icon: Icons.link,
    width: 520,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose the role for the person registering with this link.',
            style: TextStyle(fontSize: 13.5, color: _muted),
          ),
          const SizedBox(height: 14),
          _fieldLabel('Role'),
          DropdownButtonFormField<String>(
            initialValue: role,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'none', child: Text('No Role [Assigned Later By Admin]')),
              DropdownMenuItem(value: 'user', child: Text('Standard User [Limited Access]')),
              DropdownMenuItem(value: 'ojt', child: Text('OJT / Trainee [Restricted Access]')),
              DropdownMenuItem(value: 'technical_staff', child: Text('Technical Staff [Support Access]')),
              DropdownMenuItem(value: 'sales', child: Text('Sales [Commercial Access]')),
              DropdownMenuItem(value: 'developer', child: Text('Developer [Build Access]')),
              DropdownMenuItem(value: 'admin', child: Text('Administrator [Full Access]')),
            ],
            onChanged: (v) => role = v ?? role,
          ),
          if (isSuper) ...[
            const SizedBox(height: 14),
            _fieldLabel('Branch'),
            DropdownButtonFormField<String>(
              initialValue: branch,
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('No branch assigned')),
                for (final b in branches)
                  DropdownMenuItem(
                    value: _s(b, 'id'),
                    child: Text('${_s(b, 'name')} (${_s(b, 'code')})'),
                  ),
              ],
              onChanged: (v) => branch = v ?? '',
            ),
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F1EF)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setLocal(() => employment = !employment),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: employment,
                  activeColor: _orange,
                  onChanged: (v) => setLocal(() => employment = v ?? false),
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Also collect the Basic Employment Information Sheet',
                          style: TextStyle(fontSize: 13.5, color: _navy),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'After registering, they are handed a form link to fill up.',
                          style: TextStyle(fontSize: 12.5, color: _muted),
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
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      SignalButton(
        label: 'Generate Link',
        icon: Icons.link,
        onPressed: () => Navigator.pop(ctx, true),
      ),
    ],
  );
  if (go != true || !context.mounted) return;
  Map<String, dynamic> res;
  try {
    res = await api.invite(role: role, employmentForm: employment, branchId: branch);
  } catch (_) {
    if (context.mounted) toast(context, 'Network error.');
    return;
  }
  if (!context.mounted) return;
  if (res['status'] != 'success') {
    toast(context, _s(res, 'message').isEmpty ? 'Failed to generate link.' : _s(res, 'message'));
    return;
  }
  await _linkResultDialog(
    context,
    title: 'Registration Link',
    success: true,
    intro: const [
      TextSpan(text: 'This link allows others to create an account. It will '),
      TextSpan(text: 'expire in 2 hours', style: _warm),
      TextSpan(text: '.'),
    ],
    url: _s(res, 'public_url'),
    extra: _InviteMailer(api: api, token: _s(res, 'token')),
  );
}

class _InviteMailer extends StatefulWidget {
  const _InviteMailer({required this.api, required this.token});
  final AdminUsersApi api;
  final String token;
  @override
  State<_InviteMailer> createState() => _InviteMailerState();
}

class _InviteMailerState extends State<_InviteMailer> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String _note = '';
  Color _noteColor = _muted;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _sent) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() {
        _note = 'Enter an email address first.';
        _noteColor = _red;
      });
      return;
    }
    setState(() {
      _busy = true;
      _note = 'Sending…';
      _noteColor = _muted;
    });
    try {
      final res = await widget.api.emailInvite(widget.token, email);
      if (!mounted) return;
      if (res['status'] == 'success') {
        setState(() {
          _busy = false;
          _sent = true;
          _note = _s(res, 'message');
          _noteColor = _green;
        });
      } else {
        setState(() {
          _busy = false;
          _note = _s(res, 'message').isEmpty ? 'Could not send the email.' : _s(res, 'message');
          _noteColor = _red;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = 'Network error. Please try again.';
        _noteColor = _red;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1, color: Color(0xFFF1F1EF)),
          const SizedBox(height: 16),
          _fieldLabel('Or send it by email'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _email,
                  enabled: !_sent,
                  keyboardType: TextInputType.emailAddress,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'name@example.com', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _busy || _sent ? null : _send,
                icon: _busy
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: TpLoader(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(_sent ? Icons.check : Icons.send, size: 14),
                label: Text(_busy ? 'Sending' : (_sent ? 'Sent' : 'Send')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _sent ? _green : _navy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _sent ? _green : _navy,
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
          if (_note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_note, style: TextStyle(fontSize: 12.5, color: _noteColor)),
          ],
        ],
      ),
    );
  }
}

Future<void> adminExportFlow(
  BuildContext context,
  AdminUsersApi api, {
  String search = '',
}) async {
  var prefs = true;
  var scoped = search.isNotEmpty;
  final go = await showWebModal<bool>(
    context,
    title: 'Export Users',
    icon: Icons.file_upload_outlined,
    width: 500,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'The file carries every account with its access level, module access and saved settings, ready to be imported back.',
            style: TextStyle(fontSize: 13.5, color: _muted, height: 1.5),
          ),
          const SizedBox(height: 10),
          if (search.isNotEmpty)
            CheckboxListTile(
              value: scoped,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: _orange,
              title: Text('Only the $search search results'),
              onChanged: (v) => setLocal(() => scoped = v ?? false),
            ),
          CheckboxListTile(
            value: prefs,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: _orange,
            title: const Text('Include saved user settings'),
            onChanged: (v) => setLocal(() => prefs = v ?? false),
          ),
        ],
      ),
    ),
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      SignalButton(label: 'Download CSV', onPressed: () => Navigator.pop(ctx, true)),
    ],
  );
  if (go != true || !context.mounted) return;
  toast(context, 'Preparing your CSV download.');
  try {
    final path = await api.downloadCsv({
      'with_password': '1',
      'with_preferences': prefs ? '1' : '0',
      if (scoped && search.isNotEmpty) 'search': search,
    });
    if (context.mounted) toast(context, 'Saved to $path');
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

Future<void> adminImportFlow(
  BuildContext context,
  AdminUsersApi api, {
  required VoidCallback onImported,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ImportDialog(api: api, onImported: onImported),
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.api, required this.onImported});
  final AdminUsersApi api;
  final VoidCallback onImported;
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  String? _path;
  String? _name;
  String _mode = 'upsert';
  String _perms = 'csv';
  bool _prefs = true;
  bool _checked = false;
  bool _applyEnabled = false;
  bool _busyCheck = false;
  bool _busyApply = false;
  Map<String, dynamic>? _result;
  bool _resultDry = true;

  void _reset() {
    _checked = false;
    _applyEnabled = false;
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    setState(() {
      _path = f.path;
      _name = f.name;
      _result = null;
      _reset();
    });
  }

  Future<void> _template() async {
    try {
      final path = await widget.api.downloadCsv({'template': '1'});
      if (mounted) toast(context, 'Saved to $path');
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _run(bool dry) async {
    final path = _path;
    if (path == null) {
      toast(context, 'Choose a CSV file first.');
      return;
    }
    setState(() {
      if (dry) {
        _busyCheck = true;
      } else {
        _busyApply = true;
      }
    });
    try {
      final res = await widget.api.importCsv(
        path: path,
        dryRun: dry,
        mode: _mode,
        permissions: _perms,
        withPreferences: _prefs,
      );
      if (!mounted) return;
      if (res['status'] != 'success') {
        setState(() {
          _busyCheck = false;
          _busyApply = false;
        });
        toast(context, _s(res, 'message').isEmpty ? 'Import failed.' : _s(res, 'message'));
        return;
      }
      adminNotifyOjtNetwork(context, res);
      final sum = res['summary'] is Map ? res['summary'] as Map : const {};
      final created = int.tryParse(_s(sum, 'created')) ?? 0;
      final updated = int.tryParse(_s(sum, 'updated')) ?? 0;
      setState(() {
        _busyCheck = false;
        _busyApply = false;
        _result = res;
        _resultDry = dry;
        if (dry) {
          _checked = true;
          _applyEnabled = created + updated > 0;
        } else {
          _checked = false;
          _applyEnabled = false;
        }
      });
      if (dry) {
        toast(
          context,
          created + updated == 0
              ? 'Nothing in this file would change.'
              : 'File checked. Review the preview, then press Import.',
        );
      } else {
        toast(context, '$created created, $updated updated.');
        widget.onImported();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busyCheck = false;
        _busyApply = false;
      });
      toast(context, 'Network error while importing.');
    }
  }

  Widget _select(String label, String value, List<(String, String)> items, ValueChanged<String> onChanged, {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [_fieldLabel(label), ?trailing]),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          items: [for (final i in items) DropdownMenuItem(value: i.$1, child: Text(i.$2))],
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ],
    );
  }

  Widget _stat(String label, int n, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text('$label: $n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
  );

  static const _importCols = [
    ColSpec(width: 50),
    ColSpec(flex: 2),
    ColSpec(width: 90),
    ColSpec(flex: 3),
  ];

  Widget _resultView() {
    final res = _result!;
    final sum = res['summary'] is Map ? res['summary'] as Map : const {};
    int n(String k) => int.tryParse(_s(sum, k)) ?? 0;
    final details = res['details'] is List ? (res['details'] as List).whereType<Map>().toList() : const <Map>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _stat(_resultDry ? 'Preview of ${_s(res, 'total')} rows' : 'Imported ${_s(res, 'total')} rows', 0, _navy),
            _stat('Created', n('created'), _green),
            _stat('Updated', n('updated'), const Color(0xFF2563EB)),
            _stat('Skipped', n('skipped'), _muted),
            _stat('Failed', n('failed'), _red),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
          child: SingleChildScrollView(
            child: ColumnResizeScope(
              tableId: 'users:import',
              child: Builder(builder: (context) {
                registerColumns(context, _importCols);
                return Table(
              columnWidths: {
                for (var i = 0; i < _importCols.length; i++) i: resizableTableWidth(context, i, _importCols[i]),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                  children: [
                    for (final (i, t) in const ['Line', 'User', 'Result', 'Details'].indexed)
                      ColumnHeaderCell(
                        index: i,
                        spec: _importCols[i],
                        child: Padding(padding: const EdgeInsets.all(8), child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
                      ),
                  ],
                ),
                if (details.isEmpty)
                  const TableRow(children: [
                    Padding(padding: EdgeInsets.all(8), child: Text('')),
                    Padding(padding: EdgeInsets.all(8), child: Text('No rows to show.', style: TextStyle(fontSize: 12))),
                    SizedBox(),
                    SizedBox(),
                  ]),
                for (final d in details)
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.all(8), child: Text(_s(d, 'line'), style: const TextStyle(fontSize: 12))),
                    Padding(padding: const EdgeInsets.all(8), child: Text(_s(d, 'user'), style: const TextStyle(fontSize: 12))),
                    Padding(padding: const EdgeInsets.all(8), child: Text(_s(d, 'action'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                    Padding(padding: const EdgeInsets.all(8), child: Text(_s(d, 'message'), style: const TextStyle(fontSize: 12))),
                  ]),
              ],
            );
              }),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Import Users',
      icon: Icons.file_download_outlined,
      width: 720,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        GhostButton(
          label: _busyCheck ? 'Working...' : 'Check File',
          icon: Icons.science_outlined,
          onPressed: _path == null || _busyCheck ? null : () => _run(true),
        ),
        SignalButton(
          label: _busyApply ? 'Working...' : 'Import',
          icon: Icons.file_download_outlined,
          busy: _busyApply,
          onPressed: _applyEnabled && !_busyApply ? () => _run(false) : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13, color: _muted, height: 1.6),
              children: [
                const TextSpan(
                  text:
                      'Upload a CSV to create or update accounts together with their access level, module access and saved settings. Matching is done by ',
                ),
                const TextSpan(text: 'id', style: TextStyle(fontWeight: FontWeight.w700, color: _navy)),
                const TextSpan(text: ', then '),
                const TextSpan(text: 'username', style: TextStyle(fontWeight: FontWeight.w700, color: _navy)),
                const TextSpan(text: ', then '),
                const TextSpan(text: 'email', style: TextStyle(fontWeight: FontWeight.w700, color: _navy)),
                const TextSpan(text: '. '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: InkWell(
                    onTap: _template,
                    child: const Text(
                      'Download template',
                      style: TextStyle(fontSize: 13, color: _orange, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12, color: _muted, height: 1.6),
              children: [
                TextSpan(text: 'New accounts need a full name, a username and a password. Set '),
                TextSpan(text: 'email_verified', style: TextStyle(fontWeight: FontWeight.w700, color: _navy)),
                TextSpan(
                  text:
                      ' to 1 so the account can sign in without the email verification step. Your own account and super admin accounts are never touched.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pick,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: BoxDecoration(
                color: _orangeSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _orangeLine, width: 1.5),
              ),
              child: Column(
                children: [
                  const Icon(Icons.cloud_upload_outlined, size: 28, color: _orange),
                  const SizedBox(height: 6),
                  Text(
                    _name ?? 'Choose a .csv file or drop it here',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: _navy),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _select(
                  'What to import',
                  _mode,
                  const [
                    ('upsert', 'Create new and update existing'),
                    ('create', 'Create new accounts only'),
                    ('update', 'Update existing accounts only'),
                  ],
                  (v) => setState(() {
                    _mode = v;
                    if (_checked) {
                      _result = null;
                      _reset();
                    }
                  }),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _select(
                  'Access rights',
                  _perms,
                  const [
                    ('csv', 'Use the access columns in the file'),
                    ('role', 'Use the defaults of the access level'),
                    ('keep', 'Keep the current access rights'),
                  ],
                  (v) => setState(() {
                    _perms = v;
                    if (_checked) {
                      _result = null;
                      _reset();
                    }
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _prefs,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: _orange,
            title: const Text('Import saved user settings (preferences column)'),
            onChanged: (v) => setState(() {
              _prefs = v ?? false;
              if (_checked) {
                _result = null;
                _reset();
              }
            }),
          ),
          if (_result != null) _resultView(),
        ],
      ),
    );
  }
}

Future<void> adminAssignRoleFlow(
  BuildContext context,
  AdminUsersApi api, {
  required String userId,
  required String name,
  required VoidCallback onDone,
}) async {
  String? chosen;
  final ok = await showWebModal<bool>(
    context,
    title: 'Assign Role',
    icon: Icons.admin_panel_settings_outlined,
    width: 520,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 13.5, color: _muted, height: 1.5),
              children: [
                const TextSpan(text: 'Set the security clearance for '),
                TextSpan(
                  text: name.isEmpty ? 'this user' : name,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: _navy),
                ),
                const TextSpan(text: '. Default permissions for the role will be applied.'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: chosen,
            isExpanded: true,
            hint: const Text('Select Clearance Level'),
            items: [
              for (final r in kAdminRoleChoices)
                DropdownMenuItem(value: r.$1, child: Text(r.$2)),
            ],
            onChanged: (v) => setLocal(() => chosen = v),
          ),
        ],
      ),
    ),
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      SignalButton(
        label: 'Assign Role',
        onPressed: () {
          if (chosen == null) {
            toast(ctx, 'Please choose a role.');
            return;
          }
          Navigator.pop(ctx, true);
        },
      ),
    ],
  );
  final role = chosen;
  if (ok != true || role == null || !context.mounted) return;
  try {
    final d = await api.perms('role_defaults', role: role, modalSet: true);
    final res = await api.assignRole(userId, role, d.ok ? d.json : '{}');
    if (!context.mounted) return;
    if (res['status'] == 'success') {
      toast(context, 'Role assigned.');
      adminNotifyOjtNetwork(context, res);
      onDone();
    } else {
      toast(context, _s(res, 'message').isEmpty ? 'Failed to assign role.' : _s(res, 'message'));
    }
  } catch (_) {
    if (context.mounted) toast(context, 'Network error.');
  }
}

Future<void> adminUserFormFlow(
  BuildContext context,
  AdminUsersApi api, {
  required bool isSuper,
  String? userId,
  bool showMatrixOnEdit = true,
  List<Map<String, dynamic>> customRoles = const [],
  required VoidCallback onSaved,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UserFormDialog(
      api: api,
      isSuper: isSuper,
      userId: userId,
      showMatrixOnEdit: showMatrixOnEdit,
      customRoles: customRoles,
      onSaved: onSaved,
    ),
  );
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog({
    required this.api,
    required this.isSuper,
    required this.userId,
    required this.showMatrixOnEdit,
    required this.customRoles,
    required this.onSaved,
  });
  final AdminUsersApi api;
  final bool isSuper;
  final String? userId;
  final bool showMatrixOnEdit;
  final List<Map<String, dynamic>> customRoles;
  final VoidCallback onSaved;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _alias = TextEditingController();
  final _focus = <String, FocusNode>{
    'userfullname': FocusNode(),
    'user_email': FocusNode(),
    'username': FocusNode(),
    'password': FocusNode(),
  };
  final Map<String, String> _errors = {};
  String? _role;
  String _branch = '';
  List<Map<String, dynamic>> _branches = const [];
  Map<String, dynamic> _perms = {};
  bool _unlocked = false;
  bool _loading = false;
  bool _saving = false;
  bool _permBusy = false;
  bool _disabled = false;
  bool _statusBusy = false;
  DateTime _lastSubmit = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _edit => widget.userId != null;

  @override
  void initState() {
    super.initState();
    _unlocked = widget.isSuper;
    if (widget.isSuper) {
      widget.api.branchOptions().then((b) {
        if (mounted) setState(() => _branches = b);
      });
    }
    if (_edit) _loadUser();
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _username, _password, _alias]) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _loadUser() async {
    setState(() => _loading = true);
    try {
      final u = await widget.api.userById(widget.userId!);
      if (!mounted) return;
      if (u.isEmpty || _s(u, 'id').isEmpty) {
        toast(context, 'An error occurred while fetching user details.');
        Navigator.pop(context);
        return;
      }
      Map<String, dynamic> p = {};
      final raw = u['permissions'];
      if (raw is Map) {
        p = Map<String, dynamic>.from(raw);
      } else if (raw is String && raw.trim().isNotEmpty) {
        final d = jsonDecodeSafe(raw);
        if (d is Map) p = Map<String, dynamic>.from(d);
      }
      setState(() {
        _name.text = _s(u, 'full_name');
        _alias.text = _s(u, 'chat_alias');
        _email.text = _s(u, 'email');
        _username.text = _s(u, 'username');
        _password.text = _s(u, 'password_plain');
        final r = _s(u, 'role');
        _role = r.isEmpty ? null : r;
        final b = _s(u, 'branch_id');
        _branch = b == '0' ? '' : b;
        _perms = p;
        _disabled = _s(u, 'account_status') == 'disabled';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      toast(context, 'An error occurred while fetching user details.');
      Navigator.pop(context);
    }
  }

  List<(String, String)> get _roleItems => [
    ...kAdminRoleChoices,
    for (final r in widget.customRoles)
      if ((int.tryParse(_s(r, 'custom')) ?? 0) == 1)
        (_s(r, 'slug'), '${_s(r, 'label')} [Custom]'),
  ];

  Future<void> _applyPerms(Future<AdminUsersPermsResult> call) async {
    setState(() => _permBusy = true);
    try {
      final r = await call;
      if (!mounted) return;
      if (r.ok) {
        setState(() => _perms = r.permissions);
      } else if (r.message.isNotEmpty) {
        toast(context, r.message);
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _permBusy = false);
    }
  }

  void _onRole(String? v) {
    if (v == null) return;
    setState(() => _role = v);
    if (!_edit) {
      _applyPerms(widget.api.perms('role_defaults', role: v, modalSet: true));
    }
  }

  void _toggle(String key, bool on) {
    if (!_unlocked || _permBusy) return;
    _applyPerms(
      widget.api.perms('toggle', permissions: _perms, key: key, value: on, modalSet: true),
    );
  }

  Future<void> _unlock() async {
    final ok = await adminVerifyAdminDialog(context, widget.api);
    if (ok && mounted) setState(() => _unlocked = true);
  }

  Future<void> _toggleStatus(bool disable) async {
    if (_statusBusy) return;
    setState(() => _statusBusy = true);
    try {
      final res = await widget.api.toggleStatus(widget.userId!, disable ? 'disabled' : 'active');
      if (!mounted) return;
      if (res['status'] == 'success') {
        setState(() => _disabled = disable);
        toast(context, disable ? 'Account has been disabled.' : 'Account has been re-enabled.');
        widget.onSaved();
      } else {
        toast(context, _s(res, 'message').isEmpty ? 'Failed to update account status.' : _s(res, 'message'));
      }
    } catch (_) {
      if (mounted) toast(context, 'Connection error. Could not update account status.');
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  Map<String, dynamic> get _submittedPerms {
    final out = <String, dynamic>{};
    for (final c in kAdminUserModalCards) {
      out[c.key] = _on(_perms[c.key]) ? 1 : 0;
      for (final k in c.kids) {
        out[k.key] = _on(_perms[k.key]) ? 1 : 0;
      }
    }
    return out;
  }

  Future<void> _submit() async {
    if (_saving) return;
    final now = DateTime.now();
    if (now.difference(_lastSubmit).inMilliseconds < 2000) {
      toast(context, 'Please wait a moment before saving again.');
      return;
    }
    setState(() => _saving = true);
    try {
      final check = await widget.api.perms(
        'form',
        permissions: _submittedPerms,
        modalSet: true,
        form: {
          'mode': _edit ? 'edit' : 'add',
          'userfullname': _name.text,
          'user_email': _email.text,
          'username': _username.text,
          'password': _password.text,
          'role': _role ?? '',
        },
      );
      if (!mounted) return;
      if (!check.ok) {
        setState(() => _saving = false);
        _showFieldError(check.message, check.field);
        return;
      }
      _lastSubmit = now;
      final body = <String, String>{
        'user_id': widget.userId ?? '',
        'userfullname': _name.text,
        'chat_alias': _alias.text,
        'user_email': _email.text,
        'username': _username.text,
        'password': _password.text,
        'role': _role ?? '',
        'permissions': check.json,
        'email_verified': '1',
        if (widget.isSuper) 'branch_id': _branch.isEmpty ? '0' : _branch,
      };
      final res = _edit ? await widget.api.updateUser(body) : await widget.api.addUser(body);
      if (!mounted) return;
      if (res['status'] == 'success') {
        adminNotifyOjtNetwork(context, res);
        widget.onSaved();
        final nav = Navigator.of(context);
        final outer = nav.context;
        nav.pop();
        final url = _s(res, 'public_url');
        if (!_edit && url.isNotEmpty && outer.mounted) {
          await adminUserCreatedDialog(outer, url);
        } else if (outer.mounted) {
          toast(outer, 'User ${_edit ? 'Updated' : 'Added'} Successfully');
        }
        return;
      }
      setState(() => _saving = false);
      _showFieldError(_s(res, 'message'), null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, 'An error occurred: $e');
    }
  }

  void _showFieldError(String message, String? field) {
    final m = message.toLowerCase();
    final key = (field != null && _focus.containsKey(field))
        ? field
        : m.contains('email')
        ? 'user_email'
        : m.contains('username')
        ? 'username'
        : m.contains('password')
        ? 'password'
        : null;
    toast(context, message);
    if (key == null) return;
    setState(() => _errors[key] = message);
    _focus[key]?.requestFocus();
  }

  Widget _input(
    String label,
    TextEditingController c,
    String hint, {
    String? note,
    String? focus,
    bool obscure = false,
    int? maxLength,
    TextInputType? keyboard,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel(label, note: note),
        TextField(
          controller: c,
          focusNode: focus == null ? null : _focus[focus],
          obscureText: obscure,
          maxLength: maxLength,
          keyboardType: keyboard,
          onChanged: focus == null || !_errors.containsKey(focus)
              ? null
              : (_) => setState(() => _errors.remove(focus)),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            suffixIcon: suffix,
            errorText: focus == null ? null : _errors[focus],
            errorMaxLines: 2,
          ),
        ),
      ],
    );
  }

  Widget _card(AdminModalCard c, {bool child = false, bool locked = false}) {
    final on = _on(_perms[c.key]);
    final enabled = _unlocked && !locked;
    return Tooltip(
      message: c.hint ?? c.label,
      waitDuration: const Duration(milliseconds: 600),
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: enabled ? () => _toggle(c.key, !on) : null,
          child: Container(
            width: child ? 200 : 180,
            constraints: BoxConstraints(minHeight: child ? 50 : 58),
            padding: EdgeInsets.symmetric(horizontal: child ? 12 : 13, vertical: child ? 9 : 11),
            decoration: BoxDecoration(
              color: on ? _orangeSoft : (child ? const Color(0xFFFBFBFA) : Colors.white),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: on ? _orange : const Color(0xFFE6E9EF), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: child ? 30 : 36,
                  height: child ? 30 : 36,
                  decoration: BoxDecoration(
                    color: on ? _orange : const Color(0xFFF1F3F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(adminFaIcon(c.icon), size: child ? 12 : 14, color: on ? Colors.white : const Color(0xFF8A93A6)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    c.label.toUpperCase(),
                    style: TextStyle(
                      fontSize: child ? 11 : 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: on ? _navy : const Color(0xFF475569),
                    ),
                  ),
                ),
                Icon(
                  on ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: on ? _orange : const Color(0xFFCBD5E1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _matrix() {
    final hideCustomer = _role == 'technical_staff';
    final plain = <Widget>[];
    final blocks = <Widget>[];
    void flush() {
      if (plain.isEmpty) return;
      blocks.add(Wrap(spacing: 12, runSpacing: 12, children: List.of(plain)));
      blocks.add(const SizedBox(height: 12));
      plain.clear();
    }

    for (final c in kAdminUserModalCards) {
      if (c.key == 'customer' && hideCustomer) continue;
      if (c.kids.isEmpty) {
        plain.add(_card(c));
        continue;
      }
      flush();
      final parentOn = _on(_perms[c.key]);
      blocks.add(Align(alignment: Alignment.centerLeft, child: _card(c)));
      blocks.add(
        Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 0, 12),
          padding: const EdgeInsets.fromLTRB(16, 8, 0, 2),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: _orangeLine, width: 2))),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final k in c.kids) _card(k, child: true, locked: !parentOn)],
          ),
        ),
      );
    }
    flush();
    final anyOff = kAdminUserModalCards.any((c) => !_on(_perms[c.key]));
    return Opacity(
      opacity: _disabled ? 0.4 : 1,
      child: IgnorePointer(
        ignoring: _disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '[02] ACCESS MATRIX',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: _muted),
                  ),
                ),
                if (!widget.isSuper && !_unlocked)
                  OutlinedButton.icon(
                    onPressed: _unlock,
                    icon: const Icon(Icons.lock, size: 14),
                    label: const Text('Unlock Matrix'),
                  ),
                if (_unlocked) ...[
                  if (anyOff || _edit)
                    TextButton(
                      onPressed: _permBusy
                          ? null
                          : () => _applyPerms(widget.api.perms('grant_all', permissions: _perms, modalSet: true)),
                      child: const Text('SELECT ALL', style: TextStyle(color: _orange, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  if (!anyOff || _edit)
                    TextButton(
                      onPressed: _permBusy
                          ? null
                          : () => _applyPerms(widget.api.perms('revoke_all', permissions: _perms, modalSet: true)),
                      child: const Text('CLEAR', style: TextStyle(color: _muted, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            ...blocks,
          ],
        ),
      ),
    );
  }

  Widget _statusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_disabled)
          Container(
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFC0C0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.block, color: _red),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Account Disabled', style: TextStyle(fontWeight: FontWeight.w800, color: _red)),
                      Text('This user cannot log in or access the system.', style: TextStyle(fontSize: 12.5, color: _muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Container(
          margin: const EdgeInsets.only(top: 18),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield, size: 15, color: _disabled ? _red : _green),
                        const SizedBox(width: 6),
                        const Text('Account Status', style: TextStyle(fontWeight: FontWeight.w800, color: _navy)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Disabling will prevent the user from logging in or using the account.',
                      style: TextStyle(fontSize: 12.5, color: _muted),
                    ),
                  ],
                ),
              ),
              Text(
                _disabled ? 'Disabled' : 'Active',
                style: TextStyle(fontWeight: FontWeight.w800, color: _disabled ? _red : _green),
              ),
              const SizedBox(width: 8),
              Switch(
                value: _disabled,
                activeTrackColor: _red,
                onChanged: _statusBusy ? null : _toggleStatus,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showMatrix = !_edit || widget.showMatrixOnEdit;
    return WebModal(
      title: _edit ? 'Update User' : 'Add User',
      subtitle: 'Identity Layer',
      icon: _edit ? Icons.manage_accounts : Icons.person_add_alt_1,
      width: 1000,
      actions: [
        SignalButton(
          label: _saving ? 'Saving...' : 'Save User Protocol',
          busy: _saving,
          onPressed: _saving || _loading ? null : _submit,
        ),
      ],
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(60),
              child: Center(child: TpLoader(strokeWidth: 2.5)),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '[01] BASIC CREDENTIALS',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: _muted),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _input('Full Name', _name, 'John Doe', focus: 'userfullname')),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _input(
                        'Email Address',
                        _email,
                        'email@example.com',
                        focus: 'user_email',
                        keyboard: TextInputType.emailAddress,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _input('Username', _username, 'jdoe_admin', focus: 'username')),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _input(
                        'Password',
                        _password,
                        _edit ? 'Leave blank to keep the current password' : '••••••••',
                        note: _edit ? '(leave blank to keep the current one)' : null,
                        focus: 'password',
                        obscure: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _input(
                        'Chat Alias',
                        _alias,
                        'Maya',
                        note: '(optional — shown to website visitors)',
                        maxLength: 60,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: widget.isSuper
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _fieldLabel('Branch', note: '(optional)'),
                                DropdownButtonFormField<String>(
                                  key: ValueKey('branch-${_branches.length}-$_branch'),
                                  initialValue: _branches.any((b) => _s(b, 'id') == _branch) ? _branch : '',
                                  isExpanded: true,
                                  items: [
                                    const DropdownMenuItem(value: '', child: Text('No branch assigned')),
                                    for (final b in _branches)
                                      DropdownMenuItem(
                                        value: _s(b, 'id'),
                                        child: Text('${_s(b, 'name')} (${_s(b, 'code')})'),
                                      ),
                                  ],
                                  onChanged: (v) => _branch = v ?? '',
                                ),
                              ],
                            )
                          : const SizedBox(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _fieldLabel('Security Clearance'),
                DropdownButtonFormField<String>(
                  key: ValueKey('role-$_loading'),
                  initialValue: _roleItems.any((r) => r.$1 == _role) ? _role : null,
                  isExpanded: true,
                  hint: const Text('Select Clearance Level'),
                  items: [
                    for (final r in _roleItems) DropdownMenuItem(value: r.$1, child: Text(r.$2)),
                  ],
                  onChanged: _onRole,
                ),
                if (_edit) _statusSection(),
                if (showMatrix) ...[
                  const SizedBox(height: 22),
                  _matrix(),
                ],
              ],
            ),
    );
  }
}

dynamic jsonDecodeSafe(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

Future<void> adminControlAccessFlow(
  BuildContext context,
  AdminUsersApi api, {
  required Map<String, dynamic> user,
  required VoidCallback onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ControlAccessDialog(api: api, user: user, onChanged: onChanged),
  );
}

class _ControlAccessDialog extends StatefulWidget {
  const _ControlAccessDialog({required this.api, required this.user, required this.onChanged});
  final AdminUsersApi api;
  final Map<String, dynamic> user;
  final VoidCallback onChanged;
  @override
  State<_ControlAccessDialog> createState() => _ControlAccessDialogState();
}

class _ControlAccessDialogState extends State<_ControlAccessDialog> {
  late Map<String, dynamic> _perms;
  late String _role;
  bool _busy = false;

  String get _id => _s(widget.user, 'id');

  @override
  void initState() {
    super.initState();
    _role = _s(widget.user, 'role').isEmpty ? 'user' : _s(widget.user, 'role');
    _perms = {};
    final raw = widget.user['permissions'];
    if (raw is Map) {
      _perms = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      final d = jsonDecodeSafe(raw);
      if (d is Map) _perms = Map<String, dynamic>.from(d);
    }
    _hydrate();
  }

  void _hydrate() {
    for (final p in kAdminPermDefs) {
      if (p.parent == null || !p.inheritWhenMissing) continue;
      if (!_perms.containsKey(p.key)) _perms[p.key] = _on(_perms[p.parent]) ? 1 : 0;
    }
  }

  Future<void> _save(Future<AdminUsersPermsResult> compute, {String? role}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final r = await compute;
      if (!mounted) return;
      if (!r.ok) {
        toast(context, r.message.isEmpty ? 'Failed to update access matrix.' : r.message);
        return;
      }
      setState(() => _perms = r.permissions);
      final res = await widget.api.accessDirect(_id, permissionsJson: r.json, role: role);
      if (!mounted) return;
      if (res['status'] == 'success') {
        toast(context, 'Access permissions saved successfully ✓');
        adminNotifyOjtNetwork(context, res);
        widget.user['permissions'] = r.json;
        if (role != null) widget.user['role'] = role;
        widget.onChanged();
      } else {
        toast(context, _s(res, 'message').isEmpty ? 'Failed to update access matrix.' : _s(res, 'message'));
        widget.onChanged();
      }
    } catch (_) {
      if (mounted) toast(context, 'Network connection error while saving permissions.');
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchRole(String? next) async {
    if (next == null || next == _role) return;
    var apply = true;
    final ok = await showWebModal<bool>(
      context,
      title: 'Switch Clearance Level?',
      icon: Icons.help_outline,
      width: 460,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Set security clearance to '),
                  TextSpan(text: next.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const TextSpan(text: ' for this personnel?'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: apply,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: _orange,
              title: Text('Apply default permissions for $next'),
              onChanged: (v) => setLocal(() => apply = v ?? false),
            ),
          ],
        ),
      ),
      actions: (ctx) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        SignalButton(label: 'Confirm Role Switch', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (!mounted) return;
    if (ok != true) {
      setState(() {});
      widget.onChanged();
      return;
    }
    setState(() => _busy = true);
    try {
      String? permsJson;
      if (apply) {
        final d = await widget.api.perms('role_defaults', role: next);
        if (d.ok) {
          permsJson = d.json;
          _perms = d.permissions;
        }
      }
      final res = await widget.api.accessDirect(_id, role: next, permissionsJson: permsJson);
      if (!mounted) return;
      if (res['status'] == 'success') {
        setState(() => _role = next);
        toast(context, 'Security role updated to ${next.toUpperCase()} ✓');
        adminNotifyOjtNetwork(context, res);
      } else {
        toast(context, _s(res, 'message').isEmpty ? 'Failed to update role.' : _s(res, 'message'));
      }
    } catch (_) {
      if (mounted) toast(context, 'Network connection error.');
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onChanged();
    }
  }

  Widget _tile(AdminPermDef p, bool locked) {
    final on = _on(_perms[p.key]);
    return Tooltip(
      message: p.hint ?? p.label,
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: Container(
          width: 250,
          padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFFFF7EE) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? const Color(0xFFFED7AA) : _line),
          ),
          child: Row(
            children: [
              Icon(adminFaIcon(p.icon), size: 12, color: on ? Brand.signal : const Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.label,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
              ),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: on,
                  activeTrackColor: Brand.signal,
                  onChanged: locked || _busy
                      ? null
                      : (v) => _save(widget.api.perms('toggle', permissions: _perms, key: p.key, value: v)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Security Clearance Matrix',
      subtitle: '${_s(widget.user, 'full_name')} · @${_s(widget.user, 'username')}',
      icon: Icons.lock_open,
      width: 900,
      actions: [
        SignalButton(label: 'Close Matrix', onPressed: () => Navigator.pop(context)),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Spacer(),
              GhostButton(
                label: 'Grant All',
                onPressed: _busy ? null : () => _save(widget.api.perms('grant_all', permissions: _perms)),
              ),
              const SizedBox(width: 8),
              GhostButton(
                label: 'Revoke All',
                onPressed: _busy ? null : () => _save(widget.api.perms('revoke_all', permissions: _perms)),
              ),
              const SizedBox(width: 8),
              GhostButton(
                label: 'Role Defaults',
                onPressed: _busy
                    ? null
                    : () => _save(
                        widget.api.perms('role_defaults', permissions: _perms, role: _role.toLowerCase()),
                        role: _role.toLowerCase(),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Assigned Role', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 12),
              SizedBox(
                width: 320,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('role-$_role-$_busy'),
                  initialValue: kAdminRoleChoices.any((r) => r.$1 == _role) ? _role : null,
                  isExpanded: true,
                  items: [for (final r in kAdminRoleChoices) DropdownMenuItem(value: r.$1, child: Text(r.$2))],
                  onChanged: _busy ? null : _switchRole,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final cat in kAdminPermCategories) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(
                cat.toUpperCase(),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Color(0xFF64748B)),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in kAdminPermDefs.where((p) => p.cat == cat && p.parent == null)) ...[
                  _tile(p, false),
                  for (final k in kAdminPermDefs.where((k) => k.parent == p.key)) _tile(k, !_on(_perms[p.key])),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
