import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/admin_users_service.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/admin_fa.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';
import 'admin_user_perms.dart';
import '../../widgets/tp_loader.dart';

const _navy = Color(0xFF0C233E);
const _line = Color(0xFFE2E8F0);
const _surface2 = Color(0xFFF8FAFC);
const _orangeSoft = Color(0xFFFFF3E6);
const _orangeLine = Color(0xFFFED7AA);
const _orangeInk = Color(0xFFC25E00);
const _muted = Color(0xFF64748B);
const _faint = Color(0xFF94A3B8);

class _RoleMeta {
  const _RoleMeta(
    this.title,
    this.tag,
    this.icon,
    this.iconColor,
    this.desc,
    this.tagBg,
    this.tagFg,
    this.tagBorder,
  );
  final String title;
  final String tag;
  final IconData icon;
  final Color iconColor;
  final String desc;
  final Color tagBg;
  final Color tagFg;
  final Color tagBorder;
}

const _roleMetaMap = <String, _RoleMeta>{
  'admin': _RoleMeta(
    'Administrator Role',
    'ADMIN',
    Icons.workspace_premium,
    Color(0xFFFF7D00),
    'Full administrative permissions, system configurations, and operational command.',
    Color(0xFFFFF3E6),
    Color(0xFFC25E00),
    Color(0xFFFED7AA),
  ),
  'developer': _RoleMeta(
    'Developer Role',
    'DEVELOPER',
    Icons.code,
    Color(0xFF0EA5E9),
    'Engineering, debugging, system logs, API integrations, and code branch releases.',
    Color(0xFFEEF2FF),
    Color(0xFF4F46E5),
    Color(0xFFC7D2FE),
  ),
  'technical_staff': _RoleMeta(
    'Technical Staff Role',
    'TECH STAFF',
    Icons.build,
    Color(0xFF2563EB),
    'Hardware setups, terminal diagnostics, customer support, and field operations.',
    Color(0xFFECFEFF),
    Color(0xFF0891B2),
    Color(0xFFA5F3FC),
  ),
  'sales': _RoleMeta(
    'Sales Representative Role',
    'SALES',
    Icons.show_chart,
    Color(0xFF10B981),
    'Client onboarding, leads pipeline, pricing agreements, and marketing materials.',
    Color(0xFFECFDF5),
    Color(0xFF059669),
    Color(0xFFA7F3D0),
  ),
  'user': _RoleMeta(
    'Standard User Role',
    'STANDARD USER',
    Icons.person,
    Color(0xFF64748B),
    'Standard operational permissions for daily support tickets and task management.',
    Color(0xFFEFF6FF),
    Color(0xFF2563EB),
    Color(0xFFBFDBFE),
  ),
  'ojt': _RoleMeta(
    'OJT / Trainee Role',
    'OJT / TRAINEE',
    Icons.school,
    Color(0xFFA855F7),
    'Restricted onboarding profile for interns and trainees undergoing supervision.',
    Color(0xFFF5F3FF),
    Color(0xFF7C3AED),
    Color(0xFFDDD6FE),
  ),
};

class AdminRoleDefaultsEditor extends StatefulWidget {
  const AdminRoleDefaultsEditor({
    super.key,
    required this.api,
    required this.users,
    required this.onUsersChanged,
  });

  final ApiClient api;
  final List<Map<String, dynamic>> users;
  final VoidCallback onUsersChanged;

  @override
  State<AdminRoleDefaultsEditor> createState() =>
      _AdminRoleDefaultsEditorState();
}

class _AdminRoleDefaultsEditorState extends State<AdminRoleDefaultsEditor>
    with LiveRefresh<AdminRoleDefaultsEditor> {
  ApiClient get _api => widget.api;
  late final AdminUsersApi _users = AdminUsersApi(widget.api);
  bool _permBusy = false;
  List<Map<String, dynamic>> _roles = const [];
  final Map<String, Map<String, dynamic>> _defaults = {};
  final Map<String, String> _snap = {};
  bool _liveBusy = false;
  String _current = 'admin';
  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic>? _ojt;
  bool _ojtEnabled = false;
  final _ojtIps = TextEditingController();
  final Map<String, TextEditingController> _branchIps = {};
  bool _ojtSaving = false;
  String? _ojtError;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      final r = Platform.environment['TP_ROLE_TAB'];
      if (r != null && r.isNotEmpty) _current = r;
    }
    _load();
  }

  @override
  void dispose() {
    _ojtIps.dispose();
    for (final c in _branchIps.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _s(Map m, String k) => (m[k] ?? '').toString();

  @override
  List<String> get liveKeys => const ['user'];

  @override
  void onLiveChange() => _liveReload();

  String _canon(Map m) {
    final c = Map<String, dynamic>.from(m);
    final keys = c.keys.toList()..sort();
    return keys.map((k) => '$k=${adminPermOn(c[k]) ? 1 : 0}').join(',');
  }

  bool _roleDirty(String role) {
    final local = _defaults[role];
    if (local == null) return false;
    final base = _snap[role] ?? _canon(const <String, dynamic>{});
    return _canon(local) != base;
  }

  Future<void> _liveReload() async {
    if (_loading || _saving || _liveBusy) return;
    _liveBusy = true;
    try {
      final prevRoles = _roles;
      await _loadRoles();
      final res = await _api.get('getRoleDefaults');
      if (!mounted) return;
      if (res['status'] == 'success' && res['role_defaults'] is Map) {
        final server = <String, Map<String, dynamic>>{};
        (res['role_defaults'] as Map).forEach((k, v) {
          if (v is Map) server['$k'] = Map<String, dynamic>.from(v);
        });
        final dirty = {
          for (final k in {..._defaults.keys, ...server.keys})
            if (_roleDirty(k)) k,
        };
        for (final e in server.entries) {
          if (dirty.contains(e.key)) continue;
          _defaults[e.key] = e.value;
          _snap[e.key] = _canon(e.value);
        }
        for (final k in _defaults.keys.toList()) {
          if (!server.containsKey(k) && !dirty.contains(k)) {
            _defaults.remove(k);
            _snap.remove(k);
          }
        }
      }
      setState(() {
        if (_roles.isEmpty) _roles = prevRoles;
      });
      await _loadOjt(silent: true);
    } catch (_) {
    } finally {
      _liveBusy = false;
    }
  }

  bool get _ojtDirty {
    final o = _ojt;
    if (o == null) return false;
    if (_ojtEnabled != ((int.tryParse(_s(o, 'enabled')) ?? 0) == 1)) {
      return true;
    }
    if (_ojtIps.text != _s(o, 'allowed_ips')) return true;
    final branches = o['branches'] is List ? o['branches'] as List : const [];
    for (final b in branches.whereType<Map>()) {
      final site = _s(b, 'site');
      if (site.isEmpty) continue;
      if ((_branchIps[site]?.text ?? '') != _s(b, 'allowed_ips')) return true;
    }
    return false;
  }

  Future<void> _loadRoles() async {
    try {
      final res = await _api.get('roles.list');
      if (res['status'] == 'success' && res['data'] is List) {
        _roles = (res['data'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    } catch (_) {}
    if (_roles.isEmpty) {
      _roles = [
        for (final e in _roleMetaMap.entries)
          {
            'slug': e.key,
            'label': e.value.title.replaceAll(RegExp(r' Role$'), ''),
            'users': widget.users
                .where(
                  (u) =>
                      _s(u, 'role').toLowerCase() == e.key &&
                      _s(u, 'account_status') != 'disabled',
                )
                .length,
            'custom': 0,
          },
      ];
    }
    if (_roles.isNotEmpty && !_roles.any((r) => _s(r, 'slug') == _current)) {
      _current = _s(_roles.first, 'slug');
    }
  }

  Future<void> _load() async {
    await _loadRoles();
    try {
      final res = await _api.get('getRoleDefaults');
      if (res['status'] == 'success' && res['role_defaults'] is Map) {
        _defaults.clear();
        _snap.clear();
        (res['role_defaults'] as Map).forEach((k, v) {
          if (v is Map) {
            _defaults['$k'] = Map<String, dynamic>.from(v);
            _snap['$k'] = _canon(v);
          }
        });
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    _loadOjt();
  }

  Future<void> _loadOjt({bool silent = false}) async {
    try {
      final res = await _api.get('getOjtAccessSettings');
      if (!mounted) return;
      if (silent) {
        if (res['status'] != 'success' || _ojtSaving || _ojtDirty) return;
        if (jsonEncode(res) == jsonEncode(_ojt)) return;
      }
      if (res['status'] != 'success') {
        setState(
          () => _ojtError =
              '${res['message'] ?? 'Could not load OJT access settings.'}',
        );
        return;
      }
      final branches = res['branches'] is List
          ? res['branches'] as List
          : const [];
      final sites = <String>{};
      for (final b in branches.whereType<Map>()) {
        final site = _s(b, 'site');
        if (site.isEmpty) continue;
        sites.add(site);
        final text = _s(b, 'allowed_ips');
        final existing = _branchIps[site];
        if (existing == null) {
          _branchIps[site] = TextEditingController(text: text);
        } else if (existing.text != text) {
          existing.text = text;
        }
      }
      final gone = _branchIps.keys.where((k) => !sites.contains(k)).toList();
      final stale = [for (final k in gone) _branchIps.remove(k)!];
      final ips = _s(res, 'allowed_ips');
      setState(() {
        _ojt = res;
        _ojtError = null;
        _ojtEnabled = (int.tryParse(_s(res, 'enabled')) ?? 0) == 1;
        if (_ojtIps.text != ips) _ojtIps.text = ips;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in stale) {
          c.dispose();
        }
      });
    } catch (_) {}
  }

  Map<String, dynamic> get _perms {
    return _defaults.putIfAbsent(_current, () => <String, dynamic>{});
  }

  _RoleMeta _meta(String slug) {
    final m = _roleMetaMap[slug];
    if (m != null) return m;
    final r = _roles.firstWhere(
      (x) => _s(x, 'slug') == slug,
      orElse: () => const <String, dynamic>{},
    );
    final label = r.isEmpty ? slug : _s(r, 'label');
    final desc = r.isEmpty || _s(r, 'description').isEmpty
        ? 'Custom role. Set exactly what accounts with this clearance can reach.'
        : _s(r, 'description');
    return _RoleMeta(
      '$label Role',
      'CUSTOM',
      Icons.admin_panel_settings,
      const Color(0xFF0891B2),
      desc,
      const Color(0xFFEFF6FF),
      const Color(0xFF2563EB),
      const Color(0xFFBFDBFE),
    );
  }

  String _roleLabel(String slug) {
    for (final r in _roles) {
      if (_s(r, 'slug') == slug) return _s(r, 'label');
    }
    return _meta(slug).title.replaceAll(RegExp(r' Role$'), '');
  }

  Future<void> _compute(
    Future<AdminUsersPermsResult> call, {
    String? done,
  }) async {
    if (_permBusy) return;
    final role = _current;
    setState(() => _permBusy = true);
    try {
      final r = await call;
      if (!mounted) return;
      if (r.ok) {
        setState(() => _defaults[role] = r.permissions);
        if (done != null) toast(context, done);
      } else {
        toast(context, r.message.isEmpty ? 'Could not update the matrix.' : r.message);
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _permBusy = false);
    }
  }

  void _toggle(AdminPermDef p, bool on) {
    _compute(_users.perms('toggle', permissions: _perms, key: p.key, value: on));
  }

  void _grantAll() {
    _compute(
      _users.perms('grant_all', permissions: _perms),
      done: 'Granted all permissions for ${_current.toUpperCase()}',
    );
  }

  void _revokeAll() {
    _compute(
      _users.perms('revoke_all', permissions: _perms),
      done: 'Revoked all permissions for ${_current.toUpperCase()}',
    );
  }

  void _resetPreset() {
    _compute(
      _users.perms('role_preset', role: _current),
      done: 'Reset ${_current.toUpperCase()} to default preset',
    );
  }

  Future<Map<String, dynamic>> _saveDefaults() {
    return _api.post(
      'saveRoleDefaults',
      body: {'role': _current, 'permissions': jsonEncode(_perms)},
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = _canon(_perms);
      final res = await _saveDefaults();
      if (!mounted) return;
      if (res['status'] == 'success') _snap[_current] = saved;
      toast(
        context,
        res['status'] == 'success'
            ? '${res['message'] ?? 'Default role permissions saved.'}'
            : '${res['message'] ?? 'Failed to save role defaults.'}',
      );
    } catch (_) {
      if (mounted) toast(context, 'Network error saving role defaults.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sync() async {
    final label = _roleLabel(_current);
    final ok = await confirmDialog(
      context,
      title: 'Sync $label Permissions?',
      message:
          'This will update all registered users with the "$_current" role to these default permissions.',
      confirmLabel: 'Yes, Sync All Accounts',
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final saved = _canon(_perms);
      final sres = await _saveDefaults();
      if (sres['status'] == 'success') _snap[_current] = saved;
      final res = await _api.post(
        'syncRoleDefaultsToUsers',
        body: {'role': _current},
      );
      if (!mounted) return;
      if (res['status'] == 'success') {
        toast(context, '${res['message'] ?? 'Updated accounts successfully.'}');
        widget.onUsersChanged();
      } else {
        toast(context, '${res['message'] ?? 'Failed to sync users.'}');
      }
    } catch (_) {
      if (mounted) toast(context, 'Failed to sync users.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteRole(Map<String, dynamic> r) async {
    final slug = _s(r, 'slug');
    final ok = await confirmDialog(
      context,
      title: 'Delete ${_s(r, 'label')}?',
      message:
          'Its default access is removed too. Accounts keep their own permissions.',
      confirmLabel: 'Delete role',
    );
    if (!ok) return;
    try {
      final res = await _api.post('roles.delete', body: {'slug': slug});
      if (!mounted) return;
      if (res['status'] == 'success') {
        toast(context, '${res['message'] ?? 'Role deleted.'}');
        if (_current == slug) _current = 'admin';
        await _load();
      } else {
        await showWebModal<void>(
          context,
          title: 'Still in use',
          icon: Icons.info_outline,
          width: 460,
          builder: (_) =>
              Text('${res['message'] ?? 'Could not delete the role.'}'),
          actions: (ctx) => [
            SignalButton(label: 'OK', onPressed: () => Navigator.pop(ctx)),
          ],
        );
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error deleting role.');
    }
  }

  Future<void> _addRole() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var perms = <String, dynamic>{for (final p in kAdminPermDefs) p.key: 0};
    var busy = false;
    String? createdSlug;
    final created = await showWebModal<bool>(
      context,
      title: 'Add Role',
      icon: Icons.shield_outlined,
      width: 880,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> apply(Future<AdminUsersPermsResult> call) async {
            if (busy) return;
            setLocal(() => busy = true);
            try {
              final r = await call;
              if (r.ok) perms = r.permissions;
            } catch (_) {
              if (ctx.mounted) toast(ctx, 'Network error.');
            }
            if (ctx.mounted) setLocal(() => busy = false);
          }

          void flip(AdminPermDef p, bool on) {
            apply(_users.perms('toggle', permissions: perms, key: p.key, value: on));
          }

          Widget tile(AdminPermDef p) {
            final locked = p.parent != null && !adminPermOn(perms[p.parent]);
            return _PermTile(
              def: p,
              on: adminPermOn(perms[p.key]),
              locked: locked,
              child: p.parent != null,
              onChanged: (v) => flip(p, v),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FormRow(
                      label: 'Role name',
                      required: true,
                      labelWidth: 110,
                      child: TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Branch Manager',
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FormRow(
                      label: 'Description',
                      labelWidth: 110,
                      child: TextField(
                        controller: descCtrl,
                        maxLength: 255,
                        decoration: const InputDecoration(
                          hintText: 'What this role is for',
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(left: 110, top: 4),
                child: Text(
                  'Used as the clearance name shown when assigning accounts.',
                  style: TextStyle(fontSize: 11.5, color: _faint),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Default access',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        Text(
                          'Granted automatically when this role is assigned. You can change it later in the matrix.',
                          style: TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Copy from…',
                    onSelected: (slug) {
                      final src = _defaults[slug];
                      if (src != null) {
                        apply(_users.perms('normalize', permissions: src));
                      } else {
                        apply(_users.perms('role_defaults', role: slug));
                      }
                    },
                    itemBuilder: (_) => [
                      for (final r in _roles)
                        PopupMenuItem(
                          value: _s(r, 'slug'),
                          child: Text(_s(r, 'label')),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_all, size: 16, color: _muted),
                          SizedBox(width: 6),
                          Text(
                            'Copy from…',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  GhostButton(
                    label: 'All',
                    onPressed: () =>
                        apply(_users.perms('grant_all', permissions: perms)),
                  ),
                  const SizedBox(width: 8),
                  GhostButton(
                    label: 'None',
                    onPressed: () =>
                        apply(_users.perms('revoke_all', permissions: perms)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final cat in kAdminPermCategories)
                    SizedBox(
                      width: 400,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _catTitle(cat),
                          for (final p in kAdminPermDefs.where(
                            (p) => p.cat == cat && p.parent == null,
                          )) ...[
                            tile(p),
                            const SizedBox(height: 6),
                            for (final k in adminChildPerms(p.key)) ...[
                              Padding(
                                padding: const EdgeInsets.only(left: 18),
                                child: tile(k),
                              ),
                              const SizedBox(height: 6),
                            ],
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
      actions: (ctx) => [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        SignalButton(
          label: 'Create Role',
          onPressed: () async {
            final label = nameCtrl.text.trim();
            if (label.isEmpty) {
              toast(ctx, 'Role name is required.');
              return;
            }
            try {
              final norm = await _users.perms('normalize', permissions: perms);
              final res = await _api.post(
                'roles.create',
                body: {
                  'label': label,
                  'description': descCtrl.text.trim(),
                  'permissions': norm.ok ? norm.json : jsonEncode(perms),
                },
              );
              if (!ctx.mounted) return;
              if (res['status'] == 'success') {
                toast(ctx, '${res['message'] ?? 'Role created.'}');
                createdSlug = _s(res, 'slug');
                Navigator.pop(ctx, true);
              } else {
                toast(
                  ctx,
                  '${res['message'] ?? 'Could not create the role.'}',
                );
              }
            } catch (_) {
              if (ctx.mounted) toast(ctx, 'Network error creating role.');
            }
          },
        ),
      ],
    );
    if (created != true || !mounted) return;
    final slug = createdSlug;
    if (slug != null && slug.isNotEmpty) _current = slug;
    await _load();
    widget.onUsersChanged();
  }

  Future<void> _saveOjt() async {
    setState(() => _ojtSaving = true);
    try {
      final res = await _api.post(
        'saveOjtAccessSettings',
        body: {
          'enabled': _ojtEnabled ? '1' : '0',
          'allowed_ips': _ojtIps.text,
          'branch_ips': jsonEncode({
            for (final e in _branchIps.entries) e.key: e.value.text,
          }),
        },
      );
      if (!mounted) return;
      toast(
        context,
        res['status'] == 'success'
            ? '${res['message'] ?? 'Saved.'}'
            : '${res['message'] ?? 'Could not save.'}',
      );
      if (res['status'] == 'success') _loadOjt();
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _ojtSaving = false);
    }
  }

  void _addMine() {
    final sug = _s(_ojt ?? const {}, 'suggested');
    if (sug.isEmpty) return;
    final cur = _ojtIps.text.trim();
    if (cur.split(RegExp(r'[\s,;]+')).any((v) => v.trim() == sug)) {
      toast(context, 'That network is already in the list.');
      return;
    }
    _ojtIps.text = cur.isEmpty ? sug : '$cur\n$sug';
    toast(context, 'Added — press Save OJT access to apply.');
  }

  Widget _ghost(
    String label,
    IconData icon,
    Color iconColor,
    VoidCallback onTap,
  ) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15, color: iconColor),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _navy,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: _line),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0C233E),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );

  Widget _sectionHead(
    IconData icon,
    String eyebrow,
    String title,
    String sub,
    List<Widget> actions,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12, color: _orangeInk),
                    const SizedBox(width: 6),
                    Text(
                      eyebrow.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: _orangeInk,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 480,
                child: Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: _muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }

  Widget _rolePill(Map<String, dynamic> r) {
    final slug = _s(r, 'slug');
    final active = slug == _current;
    final meta = _meta(slug);
    final custom = (int.tryParse(_s(r, 'custom')) ?? 0) == 1;
    return Material(
      color: active ? _navy : _surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: active ? _navy : _line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _current = slug),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(meta.icon, size: 15, color: meta.iconColor),
              const SizedBox(width: 8),
              Text(
                _s(r, 'label'),
                style: TextStyle(
                  fontSize: 12.6,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.18)
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _s(r, 'users').isEmpty ? '0' : _s(r, 'users'),
                  style: TextStyle(
                    fontSize: 10.9,
                    fontWeight: FontWeight.w800,
                    color: active ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
              if (custom) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _deleteRole(r),
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: active ? Colors.white70 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _addRolePill() {
    return InkWell(
      onTap: _addRole,
      borderRadius: BorderRadius.circular(10),
      child: CustomPaint(
        painter: _DashedBorder(color: _orangeLine),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 15, color: _orangeInk),
              SizedBox(width: 6),
              Text(
                'Add Role',
                style: TextStyle(
                  fontSize: 12.6,
                  fontWeight: FontWeight.w700,
                  color: _orangeInk,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _catTitle(String cat) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.only(bottom: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Text(
      cat,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: _navy,
      ),
    ),
  );

  Widget _matrixColumn(String cat, Map<String, dynamic> perms) {
    final children = <Widget>[];
    for (final p in kAdminPermDefs.where(
      (p) => p.cat == cat && p.parent == null,
    )) {
      final on = adminPermOn(perms[p.key]);
      final kids = adminChildPerms(p.key).where((k) => k.cat == cat).toList();
      if (kids.isEmpty) {
        children.add(
          _PermTile(
            def: p,
            on: on,
            locked: false,
            child: false,
            onChanged: (v) => _toggle(p, v),
          ),
        );
        children.add(const SizedBox(height: 8));
        continue;
      }
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 160,
            child: _PermTile(
              def: p,
              on: on,
              locked: false,
              child: false,
              onChanged: (v) => _toggle(p, v),
            ),
          ),
        ),
      );
      children.add(
        Container(
          margin: const EdgeInsets.fromLTRB(11, 6, 0, 8),
          padding: const EdgeInsets.fromLTRB(14, 6, 0, 2),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: _orangeLine, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final k in kids) ...[
                _PermTile(
                  def: k,
                  on: adminPermOn(perms[k.key]),
                  locked: !on,
                  child: true,
                  onChanged: (v) => _toggle(k, v),
                ),
                const SizedBox(height: 7),
              ],
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_catTitle(cat), ...children],
      ),
    );
  }

  Widget _help(List<InlineSpan> spans, {IconData? icon}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 470,
        child: Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: Color(0xFF475569),
            ),
            children: [
              if (icon != null)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(icon, size: 13, color: _muted),
                  ),
                ),
              ...spans,
            ],
          ),
        ),
      ),
    ),
  );

  TextSpan _b(String t) => TextSpan(
    text: t,
    style: const TextStyle(fontWeight: FontWeight.w700, color: _navy),
  );

  WidgetSpan _code(String t) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _orangeSoft,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _orangeLine),
      ),
      child: Text(
        t,
        style: const TextStyle(
          fontSize: 11.5,
          color: _orangeInk,
          fontFamily: 'monospace',
        ),
      ),
    ),
  );

  String _humanAge(dynamic raw) {
    final sec = (num.tryParse('$raw') ?? 0).clamp(0, double.infinity);
    if (sec < 90) return 'just now';
    if (sec < 5400) return '${(sec / 60).round()} min ago';
    if (sec < 172800) return '${(sec / 3600).round()} hr ago';
    return '${(sec / 86400).round()} days ago';
  }

  Widget _branchCard(Map b) {
    final main = (int.tryParse(_s(b, 'is_main')) ?? 0) == 1;
    final count = int.tryParse(_s(b, 'ojt_count')) ?? 0;
    final inactive =
        (_s(b, 'status').isEmpty ? 'active' : _s(b, 'status')) != 'active';
    final fresh = (int.tryParse(_s(b, 'fresh')) ?? 0) == 1;
    final site = _s(b, 'site');
    final ctrl = _branchIps[site];
    Widget line;
    if (_s(b, 'ip').isEmpty) {
      line = Row(
        children: [
          const Icon(Icons.radio_button_unchecked, size: 13, color: _faint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'No address reported yet — start the ping agent at this branch with site=${_s(b, 'code')}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
          ),
        ],
      );
    } else {
      line = Row(
        children: [
          Icon(
            fresh ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 13,
            color: fresh ? const Color(0xFF16A34A) : const Color(0xFFD97706),
          ),
          const SizedBox(width: 6),
          Text(
            _s(b, 'ip'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _navy,
            ),
          ),
          Expanded(
            child: Text(
              ' — seen ${_humanAge(b['age'])}${fresh ? '' : ' (expired — not being trusted)'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF334155)),
            ),
          ),
        ],
      );
    }
    return Opacity(
      opacity: inactive ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: main ? const Color(0xFFFFFDFA) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: main ? _orangeLine : _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    _s(b, 'name').isEmpty
                        ? (_s(b, 'code').isEmpty ? 'Branch' : _s(b, 'code'))
                        : _s(b, 'name'),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                ),
                if (main) ...[
                  const SizedBox(width: 6),
                  _tagPill('MAIN', _orangeInk, _orangeSoft, _orangeLine),
                ],
                const SizedBox(width: 6),
                _tagPill(
                  _s(b, 'code').toUpperCase(),
                  _muted,
                  const Color(0xFFF1F5F9),
                  Colors.transparent,
                ),
                Expanded(
                  child: Text(
                    '$count OJT${count == 1 ? '' : 's'}${inactive ? ' · inactive' : ''}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: _faint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            line,
            const SizedBox(height: 8),
            if (ctrl != null)
              TextField(
                controller: ctrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText:
                      'Also allow for this branch — address, CIDR or DDNS hostname',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tagPill(String t, Color fg, Color bg, Color border) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: border),
    ),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: fg,
      ),
    ),
  );

  Widget _ojtSection() {
    final o = _ojt;
    if (o == null && _ojtError != null) {
      return _card(
        child: Row(
          children: [
            const Icon(Icons.lock_outline, color: _muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _ojtError!,
                style: const TextStyle(fontSize: 13, color: _muted),
              ),
            ),
          ],
        ),
      );
    }
    if (o == null) {
      return _card(
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: TpLoader(strokeWidth: 2.5)),
        ),
      );
    }
    final lan = (int.tryParse(_s(o, 'your_ip_lan')) ?? 0) == 1;
    final sug = _s(o, 'suggested');
    final branches = o['branches'] is List
        ? (o['branches'] as List).whereType<Map>().toList()
        : const <Map>[];
    final ttl = int.tryParse(_s(o, 'office_ttl')) ?? 604800;
    final mainBranch = o['main_branch'] is Map ? o['main_branch'] as Map : null;
    final unassigned = int.tryParse(_s(o, 'unassigned_ojt')) ?? 0;
    return _card(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHead(
            Icons.school,
            'OJT Access',
            'On-site only',
            'Restrict the OJT / Trainee role to the office network. This applies to every OJT account regardless of the clearance matrix above.',
            [
              if (sug.isNotEmpty)
                _ghost(
                  'Add my network ($sug)',
                  Icons.add_circle,
                  Brand.signal,
                  _addMine,
                ),
              SignalButton(
                label: 'Save OJT access',
                icon: Icons.shield,
                busy: _ojtSaving,
                onPressed: _ojtSaving ? null : _saveOjt,
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () => setState(() => _ojtEnabled = !_ojtEnabled),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Restrict OJT accounts to the office network',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        SizedBox(height: 4),
                        SizedBox(
                          width: 460,
                          child: Text(
                            'Users with the OJT / Trainee role can only sign in from a computer on the office network (a private/LAN address). Other roles are unaffected.',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _ojtEnabled,
                    activeTrackColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _ojtEnabled = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Text(
                'ALSO ALLOW THESE ADDRESSES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Color(0xFF475569),
                ),
              ),
              Spacer(),
              Text('optional', style: TextStyle(fontSize: 11, color: _faint)),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _ojtIps,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText:
                  'e.g. 203.0.113.24, 203.0.113.0/24, 2001:db8:abcd:1200::/56, office.ddns.net — one per line or comma-separated',
            ),
          ),
          const SizedBox(height: 14),
          _help([
            const TextSpan(
              text:
                  'Needed when OJTs use this site over the internet rather than the office LAN. Accepts single addresses or CIDR ranges, IPv4 and IPv6. Your current address is ',
            ),
            _b(_s(o, 'your_ip').isEmpty ? '—' : _s(o, 'your_ip')),
            TextSpan(
              text: lan
                  ? ' (on the office network — an OJT could sign in here).'
                  : ' (not a LAN address — an OJT would be blocked here).',
            ),
          ]),
          _help(icon: Icons.bolt, [
            const TextSpan(text: 'Addresses here apply to '),
            _b('every branch'),
            const TextSpan(
              text:
                  '. When the OJT / Trainee role is assigned, the network you assigned it from is added automatically — to that trainee\'s ',
            ),
            _b('branch'),
            const TextSpan(
              text:
                  ' below if the account has one, otherwise to this shared list. Use ',
            ),
            _b('Add my network'),
            const TextSpan(text: ' above to add it here by hand any time.'),
          ]),
          _help(icon: Icons.login, [
            const TextSpan(
              text:
                  'Every successful sign-in also keeps the lists current: when a staff account signs in from an address no rule covers yet, that network is saved to the signer\'s own ',
            ),
            _b('branch'),
            const TextSpan(
              text:
                  ' below (accounts with no branch go to the main branch) — an IPv4 line is saved as its ',
            ),
            _code('/24'),
            const TextSpan(text: ' network, IPv6 as its '),
            _code('/56'),
            const TextSpan(
              text: '. OJT / Trainee sign-ins never widen the lists.',
            ),
          ]),
          _help(icon: Icons.history, [
            const TextSpan(text: 'Sign-in entries last '),
            _b('for that day only'),
            const TextSpan(
              text:
                  '. On the first sign-in of the next day every one still left from an earlier day is deleted automatically, so the lists only ever hold today\'s networks. Press ',
            ),
            _b('Save OJT access'),
            const TextSpan(
              text:
                  ' to keep one for good — anything in the boxes when you save stops expiring. Additions and removals are both written to the activity log.',
            ),
          ]),
          _help(icon: Icons.lan, [
            const TextSpan(
              text: 'If the office line has no fixed address, enter a ',
            ),
            _b('DDNS hostname'),
            const TextSpan(text: ' instead (e.g. '),
            _code('office.ddns.net'),
            const TextSpan(
              text:
                  ') and turn on the DDNS client in the office router. The name is looked up at each sign-in, so it keeps working when the ISP changes your address — no need to come back here. Add ',
            ),
            _code('/48'),
            const TextSpan(
              text: ' after the name if your ISP delegates a /48 IPv6 prefix.',
            ),
          ]),
          const SizedBox(height: 8),
          const Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Branch networks',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                TextSpan(
                  text: 'per branch',
                  style: TextStyle(fontSize: 13, color: _faint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (ctx, c) {
              const gap = 12.0;
              final cols = ((c.maxWidth + gap) / (380 + gap)).floor().clamp(
                1,
                3,
              );
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final b in branches)
                    SizedBox(width: w, child: _branchCard(b)),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _help([
            const TextSpan(text: 'An OJT is checked against the network of '),
            _b('their own branch'),
            TextSpan(
              text:
                  ' — the branch set on their account — and not against the other branches. A machine at each branch reports its own address on a timer, so these entries keep themselves current: you do not need to add them by hand. When the ISP changes the address the new one is trusted on the next report, and the old one keeps working until it goes ${(ttl / 86400).round()} days without a refresh, so nobody is cut off mid-shift. If an entry is stale, that machine is off or its timer has stopped.',
            ),
          ]),
          _help(icon: Icons.satellite_alt, [
            const TextSpan(
              text:
                  'Each branch runs its own ping agent, pointed at this site with the shared key and that branch\'s code as the ',
            ),
            _code('site'),
            const TextSpan(text: ' value (e.g. '),
            _code('site=CEB'),
            const TextSpan(text: '). An agent sent with no '),
            _code('site'),
            const TextSpan(text: ' records under the main branch.'),
          ]),
          if (unassigned > 0)
            _help(icon: Icons.person_off, [
              _b('$unassigned'),
              TextSpan(
                text:
                    ' OJT account${unassigned == 1 ? ' has' : 's have'} no branch assigned, so ${unassigned == 1 ? 'it is' : 'they are'} checked against ',
              ),
              if (mainBranch != null && _s(mainBranch, 'name').isNotEmpty) ...[
                const TextSpan(text: 'the main branch ('),
                _b(_s(mainBranch, 'name')),
                const TextSpan(text: ')'),
              ] else
                const TextSpan(text: 'the addresses listed above only'),
              const TextSpan(
                text:
                    '. Set a branch on each account so the right office network applies.',
              ),
            ]),
          if (mainBranch == null && branches.isNotEmpty)
            _help(icon: Icons.info_outline, [
              const TextSpan(text: 'No branch is flagged as '),
              _b('Main'),
              const TextSpan(
                text:
                    ' yet. Set one on the Branches tab — OJT accounts with no branch of their own are checked against the main branch.',
              ),
            ]),
          if (branches.isEmpty)
            _help(icon: Icons.warning_amber_rounded, [
              const TextSpan(
                text:
                    'No branches have been created yet. Add them on the Branches tab, then assign each OJT to the branch they report to — until then every OJT is checked against the addresses listed above only.',
              ),
            ]),
          if (sug.contains(':'))
            _help(icon: Icons.info_outline, [
              const TextSpan(
                text:
                    'IPv6 addresses rotate, so allowlist the whole network prefix rather than one address — otherwise access breaks when it changes.',
              ),
            ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(60),
        child: Center(child: TpLoader(strokeWidth: 2.5)),
      );
    }
    final perms = _perms;
    final meta = _meta(_current);
    final mods = kAdminModuleDefs;
    final active = mods.where((p) => adminPermOn(perms[p.key])).length;
    final pct = mods.isEmpty ? 0 : (active / mods.length * 100).round();
    final userCount = widget.users
        .where(
          (u) =>
              _s(u, 'role').toLowerCase() == _current &&
              _s(u, 'account_status') != 'disabled',
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHead(
                Icons.shield,
                'Role Clearance Templates',
                'Default Roles Access Matrix',
                'Configure the baseline security clearance and permissions automatically granted to each role when registering or assigning accounts.',
                [
                  _ghost(
                    'Grant All',
                    Icons.done_all,
                    const Color(0xFF10B981),
                    _grantAll,
                  ),
                  _ghost(
                    'Revoke All',
                    Icons.close,
                    const Color(0xFFEF4444),
                    _revokeAll,
                  ),
                  _ghost('Reset Preset', Icons.undo, _muted, _resetPreset),
                  SignalButton(
                    label: 'Save Role Defaults',
                    icon: Icons.save,
                    busy: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in _roles) _rolePill(r),
                  _addRolePill(),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: meta.iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(meta.icon, color: meta.iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          meta.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: meta.tagBg,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: meta.tagBorder),
                          ),
                          child: Text(
                            meta.tag,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: meta.tagFg,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta.desc,
                      style: const TextStyle(fontSize: 12.5, color: _muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ACTIVE COVERAGE',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: _faint,
                    ),
                  ),
                  Text(
                    '$active / ${mods.length} Modules ($pct%)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _orangeInk,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _saving ? null : _sync,
                icon: const Icon(Icons.sync, size: 15, color: _orangeInk),
                label: Text(
                  'Sync to $userCount Users',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _orangeInk,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _orangeSoft,
                  side: const BorderSide(color: _orangeLine),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          child: LayoutBuilder(
            builder: (ctx, c) {
              const gap = 14.0;
              final cols = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 600 ? 2 : 1);
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final cat in kAdminPermCategories)
                    SizedBox(width: w, child: _matrixColumn(cat, perms)),
                ],
              );
            },
          ),
        ),
        if (_current == 'ojt') ...[const SizedBox(height: 16), _ojtSection()],
      ],
    );
  }
}

class _PermTile extends StatelessWidget {
  const _PermTile({
    required this.def,
    required this.on,
    required this.locked,
    required this.child,
    required this.onChanged,
  });

  final AdminPermDef def;
  final bool on;
  final bool locked;
  final bool child;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final bg = on ? _orangeSoft : (child ? _surface2 : Colors.white);
    return Opacity(
      opacity: locked ? 0.45 : 1,
      child: Tooltip(
        message: def.hint ?? def.label,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: locked ? null : () => onChanged(!on),
          borderRadius: BorderRadius.circular(9),
          child: CustomPaint(
            painter: child || locked
                ? _DashedBorder(color: on ? _orangeLine : _line)
                : null,
            child: Container(
              height: 34,
              padding: const EdgeInsets.only(left: 9, right: 2),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(9),
                border: child || locked
                    ? null
                    : Border.all(color: on ? _orangeLine : _line),
              ),
              child: Row(
                children: [
                  Icon(
                    adminFaIcon(def.icon),
                    size: 11.5,
                    color: on ? Brand.signal : _faint,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      def.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: on ? _orangeInk : const Color(0xFF334155),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: FittedBox(
                      child: Switch(
                        value: on,
                        activeTrackColor: const Color(0xFF10B981),
                        onChanged: locked ? null : onChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(9),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color;
}
