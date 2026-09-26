import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';
import '../../widgets/tp_loader.dart';

const _navy = Color(0xFF0C233E);
const _line = Color(0xFFE6E9EF);
const _lineSoft = Color(0xFFF1F5F9);
const _surface2 = Color(0xFFF8FAFC);
const _orangeSoft = Color(0xFFFFF3E6);
const _orangeLine = Color(0xFFFED7AA);
const _orangeInk = Color(0xFFC25E00);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);

class AdminBranchesPanel extends StatefulWidget {
  const AdminBranchesPanel({super.key, required this.api, this.onCount});

  final ApiClient api;
  final ValueChanged<int>? onCount;

  @override
  State<AdminBranchesPanel> createState() => _AdminBranchesPanelState();
}

class _AdminBranchesPanelState extends State<AdminBranchesPanel>
    with LiveRefresh<AdminBranchesPanel> {
  List<Map<String, dynamic>> _branches = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (kDebugMode && Platform.environment['TP_BRANCH_MODAL'] == '1') {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) _edit();
      });
    }
  }

  String _s(Map m, String k) => (m[k] ?? '').toString();

  @override
  List<String> get liveKeys => const ['user'];

  @override
  void onLiveChange() {
    if (!_loading) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final res = await widget.api.get('branches.list');
      if (silent && !(res['status'] == 'success' && res['data'] is List)) {
        return;
      }
      final rows = res['status'] == 'success' && res['data'] is List
          ? (res['data'] as List)
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _branches = rows;
        _loading = false;
        _failed = false;
      });
      widget.onCount?.call(rows.length);
    } catch (_) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _delete(Map<String, dynamic> b) async {
    final staff = int.tryParse(_s(b, 'staff_count')) ?? 0;
    final ok = await confirmDialog(
      context,
      title: 'Delete ${_s(b, 'name')}?',
      message: staff > 0
          ? '$staff staff account${staff == 1 ? '' : 's'} assigned to this branch will be left with no branch. The accounts themselves are not touched.'
          : 'This branch will be removed permanently.',
      confirmLabel: 'Delete branch',
    );
    if (!ok) return;
    try {
      final res = await widget.api.post(
        'branches.delete',
        body: {'id': _s(b, 'id')},
      );
      if (!mounted) return;
      if (res['status'] == 'success') {
        toast(context, '${res['message'] ?? 'Branch deleted.'}');
        _load();
      } else {
        toast(context, '${res['message'] ?? 'Could not delete the branch.'}');
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error deleting branch.');
    }
  }

  Future<void> _edit([Map<String, dynamic>? b]) async {
    final name = TextEditingController(text: b == null ? '' : _s(b, 'name'));
    final code = TextEditingController(text: b == null ? '' : _s(b, 'code'));
    final address = TextEditingController(
      text: b == null ? '' : _s(b, 'address'),
    );
    final contact = TextEditingController(
      text: b == null ? '' : _s(b, 'contact_number'),
    );
    var status = b == null || _s(b, 'status').isEmpty
        ? 'active'
        : _s(b, 'status');
    var isMain = b != null && (int.tryParse(_s(b, 'is_main')) ?? 0) == 1;

    Widget label(String t, {bool req = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: t.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: Color(0xFF334155),
          ),
          children: [
            if (req)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
          ],
        ),
      ),
    );

    Widget help(String t) => Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(t, style: const TextStyle(fontSize: 11, color: _faint)),
    );

    Widget field(
      String l,
      TextEditingController c,
      String hint, {
      bool req = false,
      int? max,
      String? helpText,
      TextCapitalization cap = TextCapitalization.none,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label(l, req: req),
          TextField(
            controller: c,
            maxLength: max,
            textCapitalization: cap,
            decoration: InputDecoration(hintText: hint, counterText: ''),
          ),
          if (helpText != null) help(helpText),
        ],
      ),
    );

    final saved = await showWebModal<bool>(
      context,
      title: b == null ? 'Add Branch' : 'Edit Branch',
      icon: Icons.account_tree_outlined,
      width: 500,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            field(
              'Branch name',
              name,
              'e.g. Cebu Main Office',
              req: true,
              max: 120,
            ),
            field(
              'Code',
              code,
              'e.g. CEB',
              req: true,
              max: 20,
              cap: TextCapitalization.characters,
              helpText:
                  '2-20 characters: letters, numbers or dashes. Must be unique.',
            ),
            field('Address', address, 'Street, city, province', max: 255),
            field('Contact number', contact, 'e.g. +63 32 000 0000', max: 40),
            label('Status'),
            DropdownButtonFormField<String>(
              initialValue: status == 'inactive' ? 'inactive' : 'active',
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
              onChanged: (v) => status = v ?? status,
            ),
            help(
              'Inactive branches stay on record but can\'t be picked for new staff.',
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setLocal(() => isMain = !isMain),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: isMain,
                      activeColor: Brand.signal,
                      onChanged: (v) => setLocal(() => isMain = v ?? false),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 10),
                          Text(
                            'Main branch',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Marks this as the head office. Only one branch can be the main one — setting it here clears the flag from any other branch.',
                            style: TextStyle(fontSize: 11.5, color: _faint),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: (ctx) => [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        SignalButton(
          label: 'Save Branch',
          onPressed: () async {
            if (name.text.trim().isEmpty) {
              toast(ctx, 'Branch name is required.');
              return;
            }
            if (code.text.trim().isEmpty) {
              toast(ctx, 'Branch code is required.');
              return;
            }
            try {
              final res = await widget.api.post(
                'branches.save',
                body: {
                  'id': b == null ? '0' : _s(b, 'id'),
                  'name': name.text.trim(),
                  'code': code.text.trim().toUpperCase(),
                  'address': address.text.trim(),
                  'contact_number': contact.text.trim(),
                  'status': status,
                  'is_main': isMain ? '1' : '0',
                },
              );
              if (!ctx.mounted) return;
              if (res['status'] == 'success') {
                toast(ctx, '${res['message'] ?? 'Branch saved.'}');
                Navigator.pop(ctx, true);
              } else {
                toast(ctx, '${res['message'] ?? 'Could not save the branch.'}');
              }
            } catch (_) {
              if (ctx.mounted) toast(ctx, 'Network error saving branch.');
            }
          },
        ),
      ],
    );
    if (saved == true && mounted) _load();
  }

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
    message: tip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _line),
        ),
        child: Icon(icon, size: 14, color: _muted),
      ),
    ),
  );

  Widget _meta(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 13, color: _faint),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, height: 1.5, color: _muted),
          ),
        ),
      ],
    ),
  );

  Widget _card(Map<String, dynamic> b) {
    final inactive =
        (_s(b, 'status').isEmpty ? 'active' : _s(b, 'status')) != 'active';
    final main = (int.tryParse(_s(b, 'is_main')) ?? 0) == 1;
    final staff = int.tryParse(_s(b, 'staff_count')) ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
      decoration: BoxDecoration(
        color: inactive ? _surface2 : Colors.white,
        gradient: main && !inactive
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_orangeSoft, Colors.white],
                stops: [0, 0.46],
              )
            : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: main ? _orangeLine : _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: inactive ? _lineSoft : _orangeSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: inactive ? _line : _orangeLine),
                ),
                child: Text(
                  _s(b, 'code').toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: inactive ? _muted : _orangeInk,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _s(b, 'name'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
              if (main)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _orangeLine),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 10, color: _orangeInk),
                      SizedBox(width: 4),
                      Text(
                        'MAIN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: _orangeInk,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_s(b, 'address').isNotEmpty)
            _meta(Icons.location_on, _s(b, 'address')),
          if (_s(b, 'contact_number').isNotEmpty)
            _meta(Icons.phone, _s(b, 'contact_number')),
          if (inactive) _meta(Icons.block, 'Inactive'),
          const Spacer(),
          const SizedBox(height: 10),
          const Divider(height: 1, color: _lineSoft),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.people, size: 14, color: _faint),
              const SizedBox(width: 6),
              Text(
                '$staff staff',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _muted,
                ),
              ),
              const Spacer(),
              _iconBtn(Icons.edit, 'Edit branch', () => _edit(b)),
              const SizedBox(width: 6),
              _iconBtn(Icons.delete, 'Delete branch', () => _delete(b)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(IconData icon, String title, String sub) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    child: Column(
      children: [
        Icon(icon, size: 24, color: _faint),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14.5,
            color: _navy,
          ),
        ),
        const SizedBox(height: 3),
        Text(sub, style: const TextStyle(fontSize: 13, color: _muted)),
      ],
    ),
  );

  Widget _panel({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.fromLTRB(20, 18, 20, 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0D0C233E),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: TpLoader(strokeWidth: 2.5),
            ),
            SizedBox(height: 10),
            Text('Loading branches…', style: TextStyle(color: _muted)),
          ],
        ),
      );
    } else if (_failed) {
      body = _empty(
        Icons.warning_amber_rounded,
        'Could not load branches',
        'Check your connection and try again.',
      );
    } else if (_branches.isEmpty) {
      body = _empty(
        Icons.account_tree_outlined,
        'No branches yet',
        'Add a branch to start assigning staff to office locations.',
      );
    } else {
      body = LayoutBuilder(
        builder: (ctx, c) {
          const gap = 14.0;
          final cols = ((c.maxWidth + gap) / (260 + gap)).floor().clamp(1, 12);
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          final rows = <Widget>[];
          for (var i = 0; i < _branches.length; i += cols) {
            final slice = _branches.skip(i).take(cols).toList();
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < slice.length; j++) ...[
                      if (j > 0) const SizedBox(width: gap),
                      SizedBox(width: w, child: _card(slice[j])),
                    ],
                  ],
                ),
              ),
            );
            if (i + cols < _branches.length) {
              rows.add(const SizedBox(height: gap));
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _orangeSoft,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: _orangeLine),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_tree, size: 12, color: _orangeInk),
                          SizedBox(width: 6),
                          Text(
                            'BRANCH DIRECTORY',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: _orangeInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Branches',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const SizedBox(
                      width: 480,
                      child: Text(
                        'Office locations a staff account can be assigned to. Assign a branch from the Branch field in Add or Edit User.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: _muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SignalButton(
                label: 'Add Branch',
                icon: Icons.add,
                onPressed: () => _edit(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _panel(child: body),
      ],
    );
  }
}
