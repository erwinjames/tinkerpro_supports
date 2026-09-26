import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../api_client.dart';
import '../models/user_admin_models.dart';
import '../services/user_admin_service.dart';
import '../theme.dart';
import '../widgets/permission_matrix.dart';
import '../widgets/premium.dart';
import '../widgets/role_visuals.dart';
import 'branches_admin_screen.dart';
import 'employment_screen.dart';
import 'role_defaults_screen.dart';
import 'vendor_admin_screen.dart';

List<RoleOption> _roleOptions(List<RoleOption> custom, [String? extra]) {
  final out = <RoleOption>[...builtinRoleOptions()];
  for (final r in custom) {
    if (!out.any((o) => o.slug == r.slug)) out.add(r);
  }
  final e = extra?.trim() ?? '';
  if (e.isNotEmpty && !out.any((o) => o.slug == e)) {
    out.add(
      RoleOption(
        slug: e,
        label: roleLabel(e, custom),
        custom: !kUserRoles.contains(e) && e != 'super_admin',
      ),
    );
  }
  return out;
}

class UserAdminListScreen extends StatefulWidget {
  const UserAdminListScreen({super.key, required this.service, this.api});
  final UserAdminService service;
  final ApiClient? api;

  @override
  State<UserAdminListScreen> createState() => _UserAdminListScreenState();
}

class _UserAdminListScreenState extends State<UserAdminListScreen> {
  List<AdminUser> _rows = const [];
  bool _loading = true;
  final _searchController = TextEditingController();
  String _query = '';
  String _roleFilter = '';
  List<RoleOption> _customRoles = const [];
  Map<String, Map<String, bool>> _roleDefaults = const {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    final results = await Future.wait([
      widget.service.rolesList(),
      widget.service.roleDefaults(),
    ]);
    if (!mounted) return;
    setState(() {
      _customRoles = (results[0] as List<RoleOption>)
          .where((r) => r.custom && !kUserRoles.contains(r.slug))
          .toList();
      _roleDefaults = results[1] as Map<String, Map<String, bool>>;
    });
  }

  List<String> get _filterRoles {
    final out = <String>['', ...kUserRoles];
    for (final r in _customRoles) {
      if (!out.contains(r.slug)) out.add(r.slug);
    }
    for (final u in _rows) {
      if (u.role.isNotEmpty && !out.contains(u.role)) out.add(u.role);
    }
    return out;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AdminUser> get _visible {
    final q = _query.trim().toLowerCase();
    return _rows.where((r) {
      if (_roleFilter.isNotEmpty && r.role != _roleFilter) return false;
      if (q.isEmpty) return true;
      return r.fullName.toLowerCase().contains(q) ||
          r.username.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q);
    }).toList();
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

  Future<void> _openForm([AdminUser? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _UserFormScreen(
          service: widget.service,
          existing: existing,
          customRoles: _customRoles,
          roleDefaults: _roleDefaults,
          isSuperAdmin: widget.api?.isSuperAdmin ?? false,
        ),
      ),
    );
    if (changed == true) _load();
  }

  List<RoleOption> get _inviteRoles => _roleOptions(_customRoles);

  bool get _canManageAccounts {
    final role = widget.api?.userRole.trim().toLowerCase() ?? '';
    return role == 'admin' || role == 'super_admin';
  }

  Future<void> _rowActions(AdminUser row) async {
    if (!_canManageAccounts) return;
    final name = row.fullName.isEmpty ? row.username : row.fullName;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(name, style: text.titleMedium),
              ),
              ListTile(
                minTileHeight: 52,
                leading: IconTile(
                  icon: Icons.edit_outlined,
                  color: Brand.info,
                  size: 34,
                  iconSize: 18,
                ),
                title: const Text('Edit user'),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
              ListTile(
                minTileHeight: 52,
                leading: IconTile(
                  icon: Icons.shield_outlined,
                  color: Brand.signal,
                  size: 34,
                  iconSize: 18,
                ),
                title: const Text('Assign role'),
                subtitle: const Text('Applies the role default access'),
                onTap: () => Navigator.of(ctx).pop('role'),
              ),
              ListTile(
                minTileHeight: 52,
                leading: IconTile(
                  icon: row.status
                      ? Icons.block_rounded
                      : Icons.check_circle_outline_rounded,
                  color: row.status ? Brand.warning : Brand.success,
                  size: 34,
                  iconSize: 18,
                ),
                title: Text(row.status ? 'Disable account' : 'Enable account'),
                onTap: () => Navigator.of(ctx).pop('status'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    if (action == 'edit') {
      await _openForm(row);
      return;
    }
    if (action == 'status') {
      final res = await widget.service.toggleStatus(row.id, !row.status);
      if (!mounted) return;
      _toast(
        res.ok
            ? (res.message ??
                  (row.status ? 'Account disabled.' : 'Account enabled.'))
            : (res.message ?? 'Could not change the account status.'),
      );
      if (res.ok) _load();
      return;
    }
    await _assignRole(row);
  }

  Future<void> _assignRole(AdminUser row) async {
    final name = row.fullName.isEmpty ? row.username : row.fullName;
    final slug = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        return AlertDialog(
          title: const Text('Assign role'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set the security clearance for $name. Default permissions '
                  'for the role will be applied.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final r in _inviteRoles)
                  ListTile(
                    minTileHeight: 52,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.radiusSm),
                    ),
                    leading: IconTile(
                      icon: roleIcon(r.slug),
                      color: roleColor(r.slug),
                      size: 32,
                      iconSize: 17,
                    ),
                    title: Text(r.label, style: text.titleSmall),
                    subtitle: Text(roleTag(r.slug), style: text.bodySmall),
                    trailing: r.slug == row.role
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: context.brand.signalInk,
                          )
                        : null,
                    onTap: () => Navigator.of(ctx).pop(r.slug),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (slug == null || !mounted) return;
    final res = await widget.service.assignRole(
      row.id,
      slug,
      defaultPermissionsForRole(slug, _roleDefaults),
    );
    if (!mounted) return;
    _toast(
      res.ok
          ? (res.message ?? 'Role assigned.')
          : (res.message ?? 'Failed to assign role.'),
    );
    if (res.ok) _load();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _invite() async {
    final role = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        final b = ctx.brand;
        return AlertDialog(
          title: const Text('Invite a user'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Generate a registration link (valid ~2 hours) for someone to '
                  'create their own account with this role.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final r in _inviteRoles)
                  ListTile(
                    minTileHeight: 52,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.radiusSm),
                    ),
                    leading: IconTile(
                      icon: roleIcon(r.slug),
                      color: roleColor(r.slug),
                      size: 32,
                      iconSize: 17,
                    ),
                    title: Text(r.label, style: text.titleSmall),
                    subtitle: Text(roleTag(r.slug), style: text.bodySmall),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: b.paperDim,
                    ),
                    onTap: () => Navigator.of(ctx).pop(r.slug),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (role == null || !mounted) return;

    _toast('Generating link…');
    final url = await widget.service.generateInvite(role);
    if (!mounted) return;
    if (url == null) {
      _toast('Could not generate the invite link.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        final b = ctx.brand;
        return AlertDialog(
          title: const Text('Registration link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusPill(
                    label: roleLabel(role, _customRoles),
                    color: roleColor(role),
                    icon: roleIcon(role),
                  ),
                  const SizedBox(width: 8),
                  Text('Valid ~2 hours', style: text.bodySmall),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: b.surfaceHi,
                  borderRadius: BorderRadius.circular(Brand.radiusSm),
                ),
                child: SelectableText(url, style: text.bodySmall),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.of(ctx).pop();
                _toast('Link copied');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _rows.where((r) => r.status).length;
    final visible = _visible;
    final roles = _filterRoles;
    final filtered = _query.trim().isNotEmpty || _roleFilter.isNotEmpty;
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'Admin',
      title: 'Users',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.api?.canManageEmployment ?? false) ...[
            EmploymentEntryButton(api: widget.api!),
            const SizedBox(width: 8),
          ],
          if (widget.api?.canAccess('user', 'user') ?? false) ...[
            VendorsEntryButton(api: widget.api!),
            const SizedBox(width: 8),
          ],
          StationAction(
            icon: Icons.link_rounded,
            tooltip: 'Invite (registration link)',
            onPressed: _invite,
          ),
          const SizedBox(width: 8),
          StationAction(
            icon: Icons.person_add_alt_1_rounded,
            tooltip: 'New user',
            onPressed: _openForm,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _searchController,
            hint: 'Search name, username or email',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          ChoicePills<String>(
            options: roles,
            value: _roleFilter,
            onChanged: (v) => setState(() => _roleFilter = v),
            labelOf: (r) => r.isEmpty ? 'All' : roleLabel(r, _customRoles),
            countOf: _loading
                ? null
                : (r) => r.isEmpty
                      ? _rows.length
                      : _rows.where((u) => u.role == r).length,
          ),
          if (widget.api?.isSuperAdmin ?? false) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ToolCard(
                    icon: Icons.shield_outlined,
                    color: Brand.signal,
                    label: 'Role defaults',
                    hint: 'Clearance per role',
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              RoleDefaultsScreen(service: widget.service),
                        ),
                      );
                      if (!mounted) return;
                      _loadRoles();
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ToolCard(
                    icon: Icons.account_tree_rounded,
                    color: Brand.info,
                    label: 'Branches',
                    hint: 'Office locations',
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            BranchesAdminScreen(service: widget.service),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 7)
                  : _rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          label: 'No users',
                          hint: 'Add the first account, or pull to refresh.',
                          icon: Icons.group_outlined,
                          action: FilledButton.icon(
                            onPressed: _openForm,
                            icon: const Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 18,
                            ),
                            label: const Text('New user'),
                          ),
                        ),
                      ],
                    )
                  : visible.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 48),
                        EmptyState(
                          label: 'No matching users',
                          hint: 'Try a different search or role.',
                          icon: Icons.person_search_rounded,
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: visible.length + 1,
                      separatorBuilder: (_, i) =>
                          SizedBox(height: i == 0 ? 12 : 10),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return _DirectorySummary(
                            total: _rows.length,
                            active: activeCount,
                            roleCount: roles.length - 1,
                            shown: visible.length,
                            filtered: filtered,
                          );
                        }
                        final row = visible[i - 1];
                        return _EntryFade(
                          index: i - 1,
                          child: _UserRow(
                            row: row,
                            roles: _customRoles,
                            onTap: () => _openForm(row),
                            onLongPress: _canManageAccounts
                                ? () => _rowActions(row)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      padding: const EdgeInsets.all(12),
      borderColor: color.withValues(alpha: 0.28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            IconTile(icon: icon, color: color, size: 34, iconSize: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    hint,
                    style: text.labelSmall?.copyWith(color: b.paperDim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.row,
    required this.onTap,
    this.onLongPress,
    this.roles = const [],
  });
  final AdminUser row;
  final List<RoleOption> roles;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final name = row.fullName.isEmpty ? row.username : row.fullName;
    final tint = roleColor(row.role);
    final card = AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      padding: const EdgeInsets.all(14),
      borderColor: row.status ? tint.withValues(alpha: 0.28) : b.rule,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AppAvatar(name: name, size: 42),
              Positioned(
                right: -1,
                bottom: -1,
                child: Tooltip(
                  message: row.status ? 'Active' : 'Inactive',
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: row.status ? Brand.success : b.paperDim,
                      border: Border.all(color: b.surface, width: 2),
                    ),
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
                  style: text.titleSmall?.copyWith(
                    color: row.status ? b.paper : b.paperDim,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  row.email.isEmpty ? '—' : row.email,
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _GlowPill(
                label: roleLabel(row.role, roles),
                color: tint,
                icon: roleIcon(row.role),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: row.status ? Brand.success : b.paperDim,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    row.status ? 'Active' : 'Inactive',
                    style: text.labelMedium?.copyWith(
                      color: row.status ? Brand.success : b.paperDim,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (onLongPress != null) ...[
            const SizedBox(width: 4),
            AppIconButton(
              icon: Icons.more_vert_rounded,
              tooltip: 'Account actions',
              onPressed: onLongPress,
              size: 40,
            ),
          ],
        ],
      ),
    );
    if (onLongPress == null) return card;
    return GestureDetector(onLongPress: onLongPress, child: card);
  }
}

class _UserFormScreen extends StatefulWidget {
  const _UserFormScreen({
    required this.service,
    this.existing,
    this.customRoles = const [],
    this.roleDefaults = const {},
    this.isSuperAdmin = false,
  });
  final UserAdminService service;
  final AdminUser? existing;
  final List<RoleOption> customRoles;
  final Map<String, Map<String, bool>> roleDefaults;
  final bool isSuperAdmin;

  @override
  State<_UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<_UserFormScreen> {
  late final TextEditingController _fullName;
  late final TextEditingController _username;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late String _role;
  late Map<String, bool> _permissions;
  late bool _active;
  late List<RoleOption> _customRoles;
  late Map<String, Map<String, bool>> _roleDefaults;
  bool _permsTouched = false;
  List<Branch> _branches = const [];
  int _branchId = 0;
  int _roleFieldRev = 0;
  bool _saving = false;
  final Set<String> _expanded = {kPermissionGroups.first.title};

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _fullName = TextEditingController(text: e?.fullName ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _password = TextEditingController();
    _customRoles = widget.customRoles;
    _roleDefaults = widget.roleDefaults;
    final existingRole = e?.role.trim() ?? '';
    _role = existingRole.isNotEmpty ? existingRole : 'user';
    _active = e?.status ?? true;
    _permissions = e == null
        ? defaultPermissionsForRole(_role, _roleDefaults)
        : {for (final k in kUserPermissionKeys) k: e.permissions[k] ?? false};
    _branchId = e?.branchId ?? 0;
    if (_customRoles.isEmpty || _roleDefaults.isEmpty) _refreshRoles();
    if (widget.isSuperAdmin) _loadBranches();
  }

  Future<void> _loadBranches() async {
    final rows = await widget.service.branchOptions();
    if (!mounted) return;
    setState(() {
      _branches = rows;
      if (_branchId != 0 && !rows.any((x) => x.id == _branchId)) _branchId = 0;
    });
  }

  Future<void> _refreshRoles() async {
    final results = await Future.wait([
      _customRoles.isEmpty
          ? widget.service.rolesList()
          : Future.value(_customRoles),
      _roleDefaults.isEmpty
          ? widget.service.roleDefaults()
          : Future.value(_roleDefaults),
    ]);
    if (!mounted) return;
    setState(() {
      _customRoles = (results[0] as List<RoleOption>)
          .where((r) => r.custom && !kUserRoles.contains(r.slug))
          .toList();
      _roleDefaults = results[1] as Map<String, Map<String, bool>>;
      if (!_isEdit && !_permsTouched) {
        _permissions = defaultPermissionsForRole(_role, _roleDefaults);
        _applyRoleVisibility();
      }
    });
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  List<RoleOption> get _roleChoices =>
      _roleOptions(_customRoles, widget.existing?.role);

  bool _isHidden(String key) => key == 'customer' && _role == 'technical_staff';

  void _applyRoleVisibility() {
    if (_role == 'technical_staff') _permissions['customer'] = false;
  }

  bool _on(String key) => _permissions[key] ?? false;

  bool _effective(PermissionDef d) {
    if (_isHidden(d.key) || !_on(d.key)) return false;
    return d.parent == null || _on(d.parent!);
  }

  List<PermissionDef> get _visibleDefs =>
      kPermissionDefs.where((d) => !_isHidden(d.key)).toList();

  Future<void> _changeRole(String next) async {
    if (next == _role) return;
    var apply = true;
    if (_isEdit) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change role?'),
          content: Text(
            'Apply the default permissions for '
            '${roleLabel(next, _customRoles)}, or keep the current ones?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep current'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Apply defaults'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == null) {
        setState(() => _roleFieldRev++);
        return;
      }
      apply = choice;
    }
    setState(() {
      _role = next;
      if (apply) {
        _permissions = defaultPermissionsForRole(next, _roleDefaults);
        _permsTouched = false;
      }
      _applyRoleVisibility();
    });
  }

  void _resetToDefaults() {
    setState(() {
      _permissions = defaultPermissionsForRole(_role, _roleDefaults);
      _permsTouched = false;
      _applyRoleVisibility();
    });
  }

  void _setAll(bool value) {
    setState(() {
      for (final k in kUserPermissionKeys) {
        _permissions[k] = value;
      }
      if (value) _permissions['filesShareOjt'] = false;
      _permsTouched = true;
      _applyRoleVisibility();
    });
  }

  void _setPerm(PermissionDef d, bool value) {
    setState(() {
      _permsTouched = true;
      applyPermissionChange(_permissions, d, value, role: _role);
    });
  }

  Future<void> _save() async {
    final fullName = _fullName.text.trim();
    final email = _email.text.trim();
    if (fullName.isEmpty) {
      _toast('Full name is required.');
      return;
    }
    if (!_isEdit) {
      if (_username.text.trim().isEmpty) {
        _toast('Username is required.');
        return;
      }
      if (_password.text.isEmpty) {
        _toast('Password is required.');
        return;
      }
    }
    _applyRoleVisibility();
    final permissions = normalizePermissions(_permissions);
    if (!permissions.values.any((v) => v)) {
      _toast('Choose at least one permission.');
      return;
    }
    setState(() => _saving = true);
    final UserAdminResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: widget.existing!.id,
        fullName: fullName,
        email: email,
        role: _role,
        permissions: permissions,
        branchId: widget.isSuperAdmin ? _branchId : null,
      );
    } else {
      res = await widget.service.add(
        fullName: fullName,
        username: _username.text.trim(),
        email: email,
        password: _password.text,
        role: _role,
        permissions: permissions,
        branchId: widget.isSuperAdmin ? _branchId : null,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the user.');
    }
  }

  Future<void> _toggleActive() async {
    final next = !_active;
    setState(() => _saving = true);
    final res = await widget.service.toggleStatus(widget.existing!.id, next);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.ok) _active = next;
    });
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not change the account status.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user?'),
        content: const Text('This permanently removes the account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.danger,
              foregroundColor: Colors.white,
            ),
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
      _toast(res.message ?? 'Could not delete the user.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _permissionGroup(PermissionGroup group) {
    return PermissionGroupCard(
      title: group.title,
      defs: group.items.where((d) => !_isHidden(d.key)).toList(),
      open: _expanded.contains(group.title),
      onToggleOpen: () => setState(() {
        if (!_expanded.remove(group.title)) _expanded.add(group.title);
      }),
      valueOf: _on,
      effectiveOf: _effective,
      onChanged: _setPerm,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final existing = widget.existing;
    final visible = _visibleDefs;
    final enabledCount = visible.where(_effective).length;
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'Users',
      title: _isEdit ? 'Edit user' : 'Add user',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          if (existing != null) ...[
            GlassPanel(
              accent: roleColor(_role),
              child: Row(
                children: [
                  AppAvatar(
                    name: existing.fullName.isEmpty
                        ? existing.username
                        : existing.fullName,
                    size: 48,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          existing.fullName.isEmpty
                              ? existing.username
                              : existing.fullName,
                          style: text.titleMedium?.copyWith(color: b.paper),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${existing.username}',
                          style: text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _GlowPill(
                                key: ValueKey(_role),
                                label: roleLabel(_role, _customRoles),
                                color: roleColor(_role),
                                icon: roleIcon(_role),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: _GlowPill(
                                key: ValueKey(_active),
                                label: _active ? 'Active' : 'Inactive',
                                color: _active ? Brand.success : b.paperDim,
                                dot: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          const SectionHeader(title: 'Account'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Field(
                  label: 'Full name',
                  icon: Icons.badge_outlined,
                  controller: _fullName,
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Username',
                    icon: Icons.alternate_email_rounded,
                    controller: _username,
                  ),
                ],
                const SizedBox(height: 14),
                _Field(
                  label: 'Email',
                  icon: Icons.mail_outline_rounded,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Password',
                    icon: Icons.lock_outline_rounded,
                    controller: _password,
                    obscure: true,
                  ),
                ],
                const SizedBox(height: 14),
                _RoleDropdown(
                  key: ValueKey(
                    'role-$_role-$_roleFieldRev-${_roleChoices.length}',
                  ),
                  value: _role,
                  options: _roleChoices,
                  onChanged: _changeRole,
                ),
                if (widget.isSuperAdmin) ...[
                  const SizedBox(height: 14),
                  _BranchDropdown(
                    key: ValueKey('branch-$_branchId-${_branches.length}'),
                    value: _branchId,
                    options: _branches,
                    onChanged: (v) => setState(() => _branchId = v),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Permissions',
            trailing: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '$enabledCount of ${visible.length} enabled',
                key: ValueKey(enabledCount),
                style: text.labelMedium?.copyWith(
                  color: enabledCount > 0 ? b.signalInk : b.paperDim,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          PermissionMeter(value: enabledCount, total: visible.length),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: _resetToDefaults,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Role defaults'),
              ),
              TextButton.icon(
                onPressed: () => _setAll(true),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Select all'),
              ),
              TextButton.icon(
                onPressed: () => _setAll(false),
                icon: const Icon(Icons.remove_done_rounded, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final g in kPermissionGroups) _permissionGroup(g),
          const SizedBox(height: 14),
          SignalButton(
            label: _isEdit ? 'Save changes' : 'Create user',
            icon: Icons.check_rounded,
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 24),
            const SectionHeader(title: 'Danger zone'),
            AppCard(
              borderColor: Brand.danger.withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GhostButton(
                    label: _active ? 'Disable account' : 'Enable account',
                    icon: _active
                        ? Icons.block_rounded
                        : Icons.check_circle_outline_rounded,
                    onPressed: _toggleActive,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _delete,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Brand.danger,
                        side: BorderSide(
                          color: Brand.danger.withValues(alpha: 0.5),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text(
                        'Delete user',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.icon,
    this.obscure = false,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
      ),
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String value;
  final List<RoleOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      itemHeight: 52,
      dropdownColor: b.surface,
      borderRadius: BorderRadius.circular(Brand.radius),
      style: text.bodyLarge,
      decoration: const InputDecoration(labelText: 'Role'),
      selectedItemBuilder: (_) => [
        for (final role in options)
          Row(
            children: [
              Icon(roleIcon(role.slug), size: 18, color: roleColor(role.slug)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${role.label} · ${roleTag(role.slug)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
      items: [
        for (final role in options)
          DropdownMenuItem<String>(
            value: role.slug,
            child: Row(
              children: [
                Icon(
                  roleIcon(role.slug),
                  size: 18,
                  color: roleColor(role.slug),
                ),
                const SizedBox(width: 10),
                Text(role.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(width: 8),
                Text(
                  roleTag(role.slug),
                  style: text.labelSmall?.copyWith(color: b.paperDim),
                ),
              ],
            ),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _BranchDropdown extends StatelessWidget {
  const _BranchDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final int value;
  final List<Branch> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      itemHeight: 52,
      dropdownColor: b.surface,
      borderRadius: BorderRadius.circular(Brand.radius),
      style: text.bodyLarge,
      decoration: const InputDecoration(
        labelText: 'Branch',
        prefixIcon: Icon(Icons.account_tree_outlined, size: 20),
      ),
      items: [
        const DropdownMenuItem<int>(value: 0, child: Text('No branch')),
        for (final branch in options)
          DropdownMenuItem<int>(
            value: branch.id,
            child: Text(
              '${branch.name} (${branch.code})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) => onChanged(v ?? 0),
    );
  }
}

class _GlowPill extends StatelessWidget {
  const _GlowPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final ink = b.isDark
        ? color
        : Color.lerp(color, const Color(0xFF0B1B2E), 0.3)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectorySummary extends StatelessWidget {
  const _DirectorySummary({
    required this.total,
    required this.active,
    required this.roleCount,
    required this.shown,
    required this.filtered,
  });

  final int total;
  final int active;
  final int roleCount;
  final int shown;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Directory',
                  style: text.titleSmall?.copyWith(color: b.paper),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: filtered
                    ? _GlowPill(
                        key: const ValueKey('filtered'),
                        label: '$shown shown',
                        color: Brand.info,
                        icon: Icons.filter_alt_rounded,
                      )
                    : const GlowBadge(
                        key: ValueKey('all'),
                        label: 'Live',
                        icon: Icons.bolt_rounded,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _GlassStat(
                label: 'Accounts',
                value: total,
                icon: Icons.group_rounded,
                color: b.signal,
              ),
              const _GlassDivider(),
              _GlassStat(
                label: 'Active',
                value: active,
                icon: Icons.check_circle_rounded,
                color: Brand.success,
              ),
              const _GlassDivider(),
              _GlassStat(
                label: 'Roles',
                value: roleCount,
                icon: Icons.badge_rounded,
                color: Brand.info,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlassDivider extends StatelessWidget {
  const _GlassDivider();

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: b.isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Brand.navy.withValues(alpha: 0.1),
    );
  }
}

class _GlassStat extends StatelessWidget {
  const _GlassStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: b.paperDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          _CountUp(
            value: value,
            style: text.titleLarge?.copyWith(
              color: b.paper,
              fontSize: 22,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

class _EntryFade extends StatelessWidget {
  const _EntryFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return child;
    final delay = (index.clamp(0, 7)) * 55;
    final total = 300 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
