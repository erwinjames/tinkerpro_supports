import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/admin_services.dart';
import '../../services/admin_users_service.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/admin_table_page.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';
import 'admin_branches.dart';
import 'admin_role_defaults.dart';
import 'admin_user_perms.dart';
import 'admin_users_forms.dart';
import '../../widgets/admin_fa.dart';
import '../../widgets/tp_loader.dart';

typedef _U = Map<String, dynamic>;

String _us(_U u, String k) => (u[k] ?? '').toString();

({Color bg, Color fg, Color border, Color solid, String label, IconData icon})
_roleInfo(String role, bool disabled) {
  if (disabled) {
    return (
      bg: const Color(0xFFFEF2F2),
      fg: const Color(0xFFDC2626),
      border: const Color(0xFFFECACA),
      solid: const Color(0xFFEF4444),
      label: 'Disabled',
      icon: Icons.block,
    );
  }
  switch (role.toLowerCase()) {
    case 'admin':
      return (
        bg: const Color(0xFFFFF3E6),
        fg: const Color(0xFFC25E00),
        border: const Color(0xFFFED7AA),
        solid: const Color(0xFFFF7D00),
        label: 'Administrator',
        icon: Icons.workspace_premium,
      );
    case 'developer':
      return (
        bg: const Color(0xFFEEF2FF),
        fg: const Color(0xFF4F46E5),
        border: const Color(0xFFC7D2FE),
        solid: const Color(0xFF6366F1),
        label: 'Developer',
        icon: Icons.code,
      );
    case 'technical_staff':
      return (
        bg: const Color(0xFFECFEFF),
        fg: const Color(0xFF0891B2),
        border: const Color(0xFFA5F3FC),
        solid: const Color(0xFF0891B2),
        label: 'Technical Staff',
        icon: Icons.build,
      );
    case 'sales':
      return (
        bg: const Color(0xFFECFDF5),
        fg: const Color(0xFF059669),
        border: const Color(0xFFA7F3D0),
        solid: const Color(0xFF059669),
        label: 'Sales Commercial',
        icon: Icons.show_chart,
      );
    case 'user':
      return (
        bg: const Color(0xFFEFF6FF),
        fg: const Color(0xFF2563EB),
        border: const Color(0xFFBFDBFE),
        solid: const Color(0xFF2563EB),
        label: 'Standard User',
        icon: Icons.person,
      );
    case 'ojt':
      return (
        bg: const Color(0xFFF5F3FF),
        fg: const Color(0xFF7C3AED),
        border: const Color(0xFFDDD6FE),
        solid: const Color(0xFF7C3AED),
        label: 'OJT / Trainee',
        icon: Icons.school,
      );
    default:
      return (
        bg: const Color(0xFFFFFBEB),
        fg: const Color(0xFFB45309),
        border: const Color(0xFFFDE68A),
        solid: const Color(0xFFD97706),
        label: 'Pending Role',
        icon: Icons.schedule,
      );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((e) => e.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) {
    return parts[0]
        .substring(0, parts[0].length < 2 ? parts[0].length : 2)
        .toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

Map<String, dynamic> _permsOf(_U u) {
  final raw = u['permissions'];
  Map<String, dynamic> m = {};
  if (raw is Map) {
    m = Map<String, dynamic>.from(raw);
  } else if (raw is String && raw.trim().isNotEmpty) {
    try {
      final d = jsonDecode(raw);
      if (d is Map) m = Map<String, dynamic>.from(d);
    } catch (_) {}
  }
  return adminHydratePerms(m);
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.service});
  final UserService service;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen>
    with LiveRefresh<UsersScreen> {
  UserService get service => widget.service;
  late final AdminUsersApi _api = AdminUsersApi(service.api);
  bool? _super;
  String _myRole = '';
  List<Map<String, dynamic>> _roles = const [];
  final Set<String> _pendingDelete = {};
  String _tableSearch = '';
  final _tableCtrl = AdminTableController();
  List<_U> _users = const [];
  bool _loading = true;
  String? _error;
  String _roleFilter = 'all';
  String _sort = 'name_asc';
  bool _cards = true;
  int _tab = 0;
  final _searchCtrl = TextEditingController();

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _tab = int.tryParse(Platform.environment['TP_USERS_TAB'] ?? '') ?? 0;
      final px = double.tryParse(Platform.environment['TP_USERS_SCROLL'] ?? '');
      if (px != null) {
        var tries = 0;
        void attempt() {
          tries++;
          if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
            _scroll.jumpTo(px.clamp(0, _scroll.position.maxScrollExtent));
            if (tries < 12) {
              Future.delayed(const Duration(seconds: 1), attempt);
            }
          } else if (tries < 30) {
            Future.delayed(const Duration(milliseconds: 500), attempt);
          }
        }

        Future.delayed(const Duration(seconds: 3), attempt);
      }
    }
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final s = await service.api.get('getMobileAuthSession');
      _myRole = _us(s, 'userRole').toLowerCase();
      _super =
          _us(s, 'userRole') == 'super_admin' ||
          (kDebugMode && Platform.environment['TP_USERS_FORCE_MATRIX'] == '1');
    } catch (_) {
      _super = false;
    }
    if (!mounted) return;
    setState(() {});
    _api.roles().then((r) {
      if (mounted) setState(() => _roles = r);
    });
    if (_super == true) {
      _loadBranchCount();
      await _loadUsers();
    }
  }

  int _branchCount = 0;

  @override
  List<String> get liveKeys => const ['user'];

  @override
  void onLiveChange() {
    if (_super != true || _loading) return;
    _loadUsers(silent: true);
    if (_tab != 2) _loadBranchCount();
  }

  Future<void> _loadBranchCount() async {
    try {
      final res = await service.api.get('branches.list');
      if (!mounted) return;
      if (res['status'] == 'success' && res['data'] is List) {
        setState(() => _branchCount = (res['data'] as List).length);
      }
    } catch (_) {}
  }

  Future<void> _loadUsers({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _users.isEmpty;
        _error = null;
      });
    }
    try {
      final rows = await _api.users();
      if (!mounted) return;
      setState(() {
        _users = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<_U> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    final list = _users.where((u) {
      if (_pendingDelete.contains(_us(u, 'id'))) return false;
      final dis = _us(u, 'account_status') == 'disabled';
      final r = (_us(u, 'role').isEmpty ? 'user' : _us(u, 'role'))
          .toLowerCase();
      if (_roleFilter == 'disabled') {
        if (!dis) return false;
      } else if (_roleFilter != 'all') {
        if (dis || r != _roleFilter) return false;
      }
      if (q.isNotEmpty &&
          ![
            _us(u, 'full_name'),
            _us(u, 'username'),
            _us(u, 'email'),
            _us(u, 'role'),
          ].any((s) => s.toLowerCase().contains(q))) {
        return false;
      }
      return true;
    }).toList();
    list.sort((a, b) {
      switch (_sort) {
        case 'name_desc':
          return _us(b, 'full_name').compareTo(_us(a, 'full_name'));
        case 'role':
          return _us(a, 'role').compareTo(_us(b, 'role'));
        case 'status':
          return _us(a, 'account_status').compareTo(_us(b, 'account_status'));
        case 'newest':
          return (int.tryParse(_us(b, 'id')) ?? 0).compareTo(
            int.tryParse(_us(a, 'id')) ?? 0,
          );
        default:
          return _us(a, 'full_name').compareTo(_us(b, 'full_name'));
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_super == null) {
      return Scaffold(
        backgroundColor: context.brand.canvas,
        body: const Center(child: TpLoader(strokeWidth: 2.5)),
      );
    }
    if (_super == false) return _tableView(context);
    return Scaffold(
      backgroundColor: context.brand.canvas,
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(26, 26, 26, 30),
        children: [
          _hero(),
          const SizedBox(height: 18),
          AdminTabBar(
            tabs: [
              const AdminTab(
                'Users Control Matrix',
                icon: Icons.manage_accounts,
              ),
              const AdminTab(
                'Default Role Permissions',
                icon: Icons.shield_outlined,
              ),
              AdminTab(
                'Branches',
                icon: Icons.account_tree_outlined,
                count: _branchCount > 0 ? '$_branchCount' : null,
              ),
            ],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 18),
          if (_tab == 0)
            ..._matrix()
          else if (_tab == 1)
            AdminRoleDefaultsEditor(
              api: service.api,
              users: _users,
              onUsersChanged: _loadUsers,
            )
          else
            AdminBranchesPanel(
              api: service.api,
              onCount: (n) => setState(() => _branchCount = n),
            ),
        ],
      ),
    );
  }

  Widget _heroButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1F38), Color(0xFF133357), Color(0xFF17416E)],
          stops: [0, 0.58, 1],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x290C233E),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -120,
            top: -160,
            child: Container(
              width: 760,
              height: 320,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x61FF7D00), Color(0x00FF7D00)],
                  stops: [0, 0.68],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(height: 3, color: Brand.signal),
          ),
          LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 1000;
              return Padding(
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
                child: Flex(
                  direction: wide ? Axis.horizontal : Axis.vertical,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: wide
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    _MaybeExpanded(
                      expand: wide,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x33FF7D00),
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: const Color(0x80FF7D00),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF22C55E),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                const Text(
                                  'SUPER ADMIN CONTROL CENTER',
                                  style: TextStyle(
                                    color: Color(0xFFFFB266),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Icon(Icons.shield, color: Brand.signal, size: 28),
                              SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  'User Access & Security',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Text(
                              'Centralized command center for managing user clearance, real-time permissions matrix, and system access.',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 13.5,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!wide) const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x26FFFFFF)),
                      ),
                      child: Wrap(
                        children: [
                          _heroButton(
                            'Default Roles',
                            Icons.shield_outlined,
                            () => setState(() => _tab = 1),
                          ),
                          if (_tab == 0) ...[
                            _heroButton(
                              'Export',
                              Icons.file_upload_outlined,
                              () => adminExportFlow(context, _api),
                            ),
                            _heroButton(
                              'Import',
                              Icons.file_download_outlined,
                              () => adminImportFlow(
                                context,
                                _api,
                                onImported: _loadUsers,
                              ),
                            ),
                            _heroButton(
                              'Invite Link',
                              Icons.link,
                              () =>
                                  adminInviteFlow(context, _api, isSuper: true),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_tab == 0) ...[
                      const SizedBox(width: 12, height: 12),
                      SignalButton(
                        label: 'Add New User',
                        icon: Icons.person_add_alt_1,
                        onPressed: () => _openForm(),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openForm({String? userId}) {
    return adminUserFormFlow(
      context,
      _api,
      isSuper: _super == true,
      userId: userId,
      showMatrixOnEdit: !(_super == true && _cards),
      customRoles: _roles,
      onSaved: _reloadAll,
    );
  }

  void _reloadAll() {
    if (_super == true) {
      _loadUsers(silent: true);
    } else {
      _tableCtrl.reload();
    }
  }

  Future<void> _deleteFlow(String id) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this user?',
      message:
          'The user account and its access permissions will be permanently removed.',
      confirmLabel: 'Delete user',
    );
    if (!ok || !mounted) return;
    setState(() => _pendingDelete.add(id));
    final messenger = ScaffoldMessenger.of(context);
    var undone = false;
    final ctrl = messenger.showSnackBar(
      SnackBar(
        content: const Text('User deleted'),
        duration: const Duration(seconds: 5),
        persist: false,
        action: SnackBarAction(label: 'Undo', onPressed: () => undone = true),
      ),
    );
    await ctrl.closed;
    if (undone) {
      if (mounted) setState(() => _pendingDelete.remove(id));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Delete undone'),
          duration: Duration(milliseconds: 1800),
        ),
      );
      return;
    }
    try {
      await _api.deleteUser(id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to delete User.')),
      );
    }
    _pendingDelete.remove(id);
    if (!mounted) return;
    _reloadAll();
  }

  Widget _hud(
    String label,
    String value,
    String hint,
    IconData icon,
    Color accent,
    Color soft,
  ) {
    return Container(
      height: 142,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0C233E),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(width: 4, color: accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: soft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 19, color: accent),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: accent == const Color(0xFFFF7D00)
                          ? const Color(0xFF0C233E)
                          : accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String key, String label, IconData icon, int count) {
    final active = _roleFilter == key;
    return Material(
      color: active ? const Color(0xFFFFF3E6) : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: active ? const Color(0xFFFED7AA) : const Color(0xFFE5E7EB),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => setState(() => _roleFilter = key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? const Color(0xFFC25E00)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? const Color(0xFFC25E00)
                      : const Color(0xFF334155),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: active ? Brand.signal : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: active ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _matrix() {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.all(60),
          child: Center(child: TpLoader(strokeWidth: 2.5)),
        ),
      ];
    }
    if (_error != null) {
      return [
        EmptyState(
          label: 'Failed to load control center records',
          hint: _error!,
        ),
      ];
    }
    var active = 0, disabled = 0, privileged = 0;
    final counts = <String, int>{
      'admin': 0,
      'developer': 0,
      'technical_staff': 0,
      'sales': 0,
      'user': 0,
      'ojt': 0,
    };
    for (final u in _users) {
      final dis = _us(u, 'account_status') == 'disabled';
      final r = (_us(u, 'role').isEmpty ? 'user' : _us(u, 'role'))
          .toLowerCase();
      if (dis) {
        disabled++;
      } else {
        active++;
        if (r == 'admin' || r == 'developer' || r == 'technical_staff') {
          privileged++;
        }
        if (counts.containsKey(r)) counts[r] = counts[r]! + 1;
      }
    }
    final list = _filtered;
    return [
      ResponsiveGrid(
        minItemWidth: 200,
        spacing: 18,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hud(
            'Total Registered Users',
            '${_users.length}',
            'All non-superadmin accounts',
            Icons.groups,
            const Color(0xFFFF7D00),
            const Color(0xFFFFF3E6),
          ),
          _hud(
            'Active Personnel',
            '$active',
            'Full access permitted',
            Icons.how_to_reg,
            const Color(0xFF10B981),
            const Color(0xFFECFDF5),
          ),
          _hud(
            'Disabled / Suspended',
            '$disabled',
            'Blocked from sign-in',
            Icons.person_off,
            const Color(0xFFEF4444),
            const Color(0xFFFEF2F2),
          ),
          _hud(
            'Privileged Roles',
            '$privileged',
            'Admins, Devs & Technical Staff',
            Icons.shield,
            const Color(0xFF6366F1),
            const Color(0xFFEEF2FF),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill('all', 'All Personnel', Icons.layers, _users.length),
                _pill(
                  'admin',
                  'Administrators',
                  Icons.workspace_premium,
                  counts['admin']!,
                ),
                _pill(
                  'developer',
                  'Developers',
                  Icons.code,
                  counts['developer']!,
                ),
                _pill(
                  'technical_staff',
                  'Technical Staff',
                  Icons.build,
                  counts['technical_staff']!,
                ),
                _pill('sales', 'Sales', Icons.show_chart, counts['sales']!),
                _pill('user', 'Standard Users', Icons.person, counts['user']!),
                _pill('ojt', 'OJT / Trainee', Icons.school, counts['ojt']!),
                _pill('disabled', 'Disabled', Icons.block, disabled),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SearchField(
                    controller: _searchCtrl,
                    width: null,
                    hint:
                        'Search by personnel name, username, email, or role...',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 170,
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sort,
                      isExpanded: true,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0C233E),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'name_asc',
                          child: Text('Sort: Name (A-Z)'),
                        ),
                        DropdownMenuItem(
                          value: 'name_desc',
                          child: Text('Sort: Name (Z-A)'),
                        ),
                        DropdownMenuItem(
                          value: 'role',
                          child: Text('Sort: Access Role'),
                        ),
                        DropdownMenuItem(
                          value: 'status',
                          child: Text('Sort: Account Status'),
                        ),
                        DropdownMenuItem(
                          value: 'newest',
                          child: Text('Sort: ID (Newest)'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _sort = v ?? _sort),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      _viewBtn(Icons.grid_view_rounded, true),
                      _viewBtn(Icons.format_list_bulleted, false),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Reload User Grid',
                  onPressed: () {
                    _loadUsers();
                    toast(context, 'Control center refreshed.');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      if (list.isEmpty)
        Column(
          children: [
            const EmptyState(
              label: 'No Personnel Found',
              hint:
                  'No personnel match the current security filter or search criteria.',
            ),
            const SizedBox(height: 12),
            SignalButton(
              label: 'Reset Filters',
              icon: Icons.replay,
              onPressed: () => setState(() {
                _searchCtrl.clear();
                _roleFilter = 'all';
              }),
            ),
          ],
        )
      else if (_cards)
        LayoutBuilder(
          builder: (ctx, c) {
            const gap = 20.0;
            final cols = ((c.maxWidth + gap) / (360 + gap)).floor().clamp(1, 6);
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            final cw = w > 390 ? 390.0 : w;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final u in list) SizedBox(width: cw, child: _card(u)),
              ],
            );
          },
        )
      else
        _listTable(list),
    ];
  }

  Widget _viewBtn(IconData icon, bool cards) {
    final active = _cards == cards;
    return InkWell(
      onTap: () => setState(() => _cards = cards),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 34,
        height: 32,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: active
              ? const [BoxShadow(color: Color(0x14000000), blurRadius: 3)]
              : const [],
        ),
        child: Icon(
          icon,
          size: 17,
          color: active ? Brand.signal : const Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _roleTag(String role, bool dis) {
    final b = _roleInfo(role, dis);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: b.bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: b.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(b.icon, size: 11, color: b.fg),
          const SizedBox(width: 5),
          Text(
            b.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: b.fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    String tip,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    return Tooltip(
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
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Icon(
            icon,
            size: 15,
            color: danger ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _card(_U u) {
    final dis = _us(u, 'account_status') == 'disabled';
    final b = _roleInfo(_us(u, 'role'), dis);
    final perms = _permsOf(u);
    final mods = kAdminModuleDefs;
    final on = mods.where((p) => adminPermOn(perms[p.key])).toList();
    final pct = mods.isEmpty ? 0 : (on.length / mods.length * 100).round();
    final chips = on.take(4).toList();
    final more = on.length - chips.length;
    final name = _us(u, 'full_name');
    return Opacity(
      opacity: dis ? 0.78 : 1,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A0C233E),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: b.solid,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _initials(name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: dis
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0C233E),
                        ),
                      ),
                      Text(
                        '@${_us(u, 'username')}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _roleTag(_us(u, 'role'), dis),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: !dis,
                        activeTrackColor: const Color(0xFF10B981),
                        onChanged: (_) => _toggleRaw(u),
                      ),
                    ),
                    Text(
                      dis ? 'DISABLED' : 'ACTIVE',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: dis
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.email, size: 12, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _us(u, 'email').isEmpty
                          ? 'No email attached'
                          : _us(u, 'email'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text(
                  'ACCESS MATRIX SCOPE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF475569),
                  ),
                ),
                const Spacer(),
                Text(
                  '${on.length} / ${mods.length} ($pct%)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: on.isNotEmpty
                        ? const Color(0xFFC25E00)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 5,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFF9A3C)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            adminFaIcon(p.icon),
                            size: 10,
                            color: Brand.signal,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            p.label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (more > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        '+$more more',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  if (on.isEmpty)
                    const Text(
                      'No modules active',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 22, color: Color(0xFFF1F5F9)),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => adminControlAccessFlow(
                    context,
                    _api,
                    user: u,
                    onChanged: () => _loadUsers(silent: true),
                  ),
                  icon: const Icon(Icons.tune, size: 15, color: Brand.signal),
                  label: const Text(
                    'Control Access',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0C233E),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const Spacer(),
                _iconBtn(
                  Icons.edit,
                  'Edit Profile Details',
                  () => _openForm(userId: _us(u, 'id')),
                ),
                const SizedBox(width: 6),
                _iconBtn(
                  Icons.link,
                  'Generate 2-Day Public Link',
                  () => adminPublicLinkFlow(context, _api, _us(u, 'id')),
                ),
                const SizedBox(width: 6),
                _iconBtn(
                  Icons.delete,
                  'Delete User Account',
                  () => _deleteFlow(_us(u, 'id')),
                  danger: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _listTable(List<_U> list) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ColumnResizeScope(
        tableId: 'users:list',
        child: Column(
          children: [
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Builder(
                builder: (context) => Row(
                  children: resizableRowCells(
                    context,
                    [
                      Expanded(flex: 3, child: Text('PERSONNEL', style: _th)),
                      Expanded(flex: 2, child: Text('ROLE', style: _th)),
                      Expanded(
                        flex: 3,
                        child: Text('ACCESS SCOPE', style: _th),
                      ),
                      SizedBox(width: 110, child: Text('STATUS', style: _th)),
                      SizedBox(
                        width: 130,
                        child: Text(
                          'ACTIONS',
                          style: _th,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                    header: true,
                    extra: 36,
                  ),
                ),
              ),
            ),
            for (final u in list) _listRow(u),
          ],
        ),
      ),
    );
  }

  Widget _listRow(_U u) {
    final dis = _us(u, 'account_status') == 'disabled';
    final b = _roleInfo(_us(u, 'role'), dis);
    final perms = _permsOf(u);
    final mods = kAdminModuleDefs;
    final on = mods.where((p) => adminPermOn(perms[p.key])).length;
    final pct = mods.isEmpty ? 0 : (on / mods.length * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Builder(
        builder: (context) => Row(
          children: resizableRowCells(context, [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: b.solid,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _initials(_us(u, 'full_name')),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _us(u, 'full_name'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          _us(u, 'email'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _roleTag(_us(u, 'role'), dis),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: pct / 100,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFF1F5F9),
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFFFF9A3C),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$on / ${mods.length} Modules',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFC25E00),
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            SizedBox(
              width: 110,
              child: Row(
                children: [
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: !dis,
                      activeTrackColor: const Color(0xFF10B981),
                      onChanged: (_) => _toggleRaw(u),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 130,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _iconBtn(
                    Icons.edit,
                    'Edit Account',
                    () => _openForm(userId: _us(u, 'id')),
                  ),
                  const SizedBox(width: 6),
                  _iconBtn(
                    Icons.link,
                    'Share Profile Link',
                    () => adminPublicLinkFlow(context, _api, _us(u, 'id')),
                  ),
                  const SizedBox(width: 6),
                  _iconBtn(
                    Icons.delete,
                    'Delete User',
                    () => _deleteFlow(_us(u, 'id')),
                    danger: true,
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _toggleRaw(_U u) async {
    final dis = _us(u, 'account_status') == 'disabled';
    final next = dis ? 'active' : 'disabled';
    try {
      final res = await _api.toggleStatus(_us(u, 'id'), next);
      if (!mounted) return;
      if (res['status'] == 'success') {
        toast(
          context,
          next == 'disabled'
              ? 'Account deactivated ✕'
              : 'Account restored active ✓',
        );
        _loadUsers(silent: true);
      } else {
        toast(
          context,
          _us(res, 'message').isEmpty
              ? 'Failed to toggle account status.'
              : _us(res, 'message'),
        );
      }
    } catch (_) {
      if (mounted) toast(context, 'Connection error.');
    }
  }

  Widget _tableView(BuildContext context) {
    final canExport = _myRole == 'admin' || _myRole == 'super_admin';
    return AdminTablePage<_U>(
      stationNumber: '12',
      stationLabel: 'USER',
      title: 'User',
      searchHint: 'Search by name, email, or username...',
      liveKeys: const ['user'],
      controller: _tableCtrl,
      fetch: (search) async {
        _tableSearch = search;
        final page = await _api.usersPage(page: 1, limit: 250, search: search);
        final items = page.items
            .where((u) => !_pendingDelete.contains(_us(u, 'id')))
            .toList();
        _rowsForIndex = items;
        return Paged(items: items, total: page.total);
      },
      pageSizes: const [10, 15, 25, 50, 100],
      initialPageSize: 25,
      extraActions: [
        if (canExport)
          GhostButton(
            label: 'Export',
            icon: Icons.file_upload_outlined,
            onPressed: () =>
                adminExportFlow(context, _api, search: _tableSearch.trim()),
          ),
        GhostButton(
          label: 'Invite',
          icon: Icons.link,
          onPressed: () => adminInviteFlow(context, _api, isSuper: false),
        ),
        SignalButton(
          label: 'Add New User',
          icon: Icons.person_add_alt_1,
          onPressed: () => _openForm(),
        ),
      ],
      header: AdminTabBar(
        tabs: const [AdminTab('Users', icon: Icons.groups)],
        index: 0,
        onChanged: (_) {},
      ),
      columns: [
        const AdminColumn('No.', width: 70, center: true, sortable: false),
        AdminColumn(
          'User Profile',
          flex: 3,
          sortValue: (u) => _us(u as _U, 'full_name'),
        ),
        AdminColumn('Email', flex: 3, sortValue: (u) => _us(u as _U, 'email')),
        AdminColumn(
          'Username',
          flex: 2,
          sortValue: (u) => _us(u as _U, 'username'),
        ),
        AdminColumn(
          'Access Level',
          width: 190,
          center: true,
          sortValue: (u) => _us(u as _U, 'role'),
        ),
        const AdminColumn(
          'Password',
          width: 150,
          center: true,
          sortable: false,
        ),
        const AdminColumn('Actions', width: 140, center: true, sortable: false),
      ],
      cells: (ctx, u, refresh) {
        final dis = _us(u, 'account_status') == 'disabled';
        final r = _us(u, 'role').isEmpty ? '' : _us(u, 'role').toLowerCase();
        final unassigned = !dis && (r.isEmpty || r == 'none');
        return [
          AdminCellText('${_rowsForIndex.indexOf(u) + 1}'),
          AdminCellText(_us(u, 'full_name'), bold: true),
          AdminCellText(_us(u, 'email'), muted: true),
          AdminCellText(_us(u, 'username')),
          dis
              ? const AdminBadge(
                  'Disabled',
                  color: Brand.danger,
                  icon: Icons.block,
                )
              : r == 'none'
              ? const AdminBadge(
                  'No role',
                  color: Color(0xFFC2410C),
                  icon: Icons.schedule,
                )
              : AdminBadge(
                  (r.isEmpty ? 'user' : r).replaceAll('_', ' '),
                  color: r == 'admin' ? Brand.signal : Brand.info,
                ),
          const Text(
            '••••••••',
            style: TextStyle(letterSpacing: 2, color: Color(0xFFCCCCCC)),
          ),
          AdminRowMenu(
            actions: unassigned
                ? [
                    AdminMenuAction(
                      'Role',
                      Icons.admin_panel_settings_outlined,
                      () {
                        if (!(_myRole == 'admin' || _myRole == 'super_admin')) {
                          toast(ctx, 'Only admins can assign roles.');
                          return;
                        }
                        adminAssignRoleFlow(
                          ctx,
                          _api,
                          userId: _us(u, 'id'),
                          name: _us(u, 'full_name'),
                          onDone: refresh,
                        );
                      },
                    ),
                  ]
                : [
                    AdminMenuAction(
                      'Delete',
                      Icons.delete_outline,
                      () => _deleteFlow(_us(u, 'id')),
                      danger: true,
                    ),
                  ],
          ),
        ];
      },
    );
  }

  List<_U> _rowsForIndex = const [];
}

const _th = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.8,
  color: Color(0xFF64748B),
);

class _MaybeExpanded extends StatelessWidget {
  const _MaybeExpanded({required this.expand, required this.child});
  final bool expand;
  final Widget child;

  @override
  Widget build(BuildContext context) => expand ? Expanded(child: child) : child;
}
