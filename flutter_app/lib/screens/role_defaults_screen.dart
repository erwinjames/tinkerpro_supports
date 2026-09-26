import 'package:flutter/material.dart';

import '../models/user_admin_models.dart';
import '../services/user_admin_service.dart';
import '../theme.dart';
import '../widgets/permission_matrix.dart';
import '../widgets/premium.dart';
import '../widgets/role_visuals.dart';

class RoleDefaultsScreen extends StatefulWidget {
  const RoleDefaultsScreen({super.key, required this.service});

  final UserAdminService service;

  @override
  State<RoleDefaultsScreen> createState() => _RoleDefaultsScreenState();
}

class _RoleDefaultsScreenState extends State<RoleDefaultsScreen> {
  List<RoleOption> _roles = const [];
  final Map<String, Map<String, bool>> _data = {};
  String _current = 'admin';
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  final Set<String> _expanded = {kPermissionGroups.first.title};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.service.rolesList(),
      widget.service.roleDefaults(),
    ]);
    if (!mounted) return;
    final roles = results[0] as List<RoleOption>;
    final defaults = results[1] as Map<String, Map<String, bool>>;
    setState(() {
      _roles = roles;
      _data
        ..clear()
        ..addAll({
          for (final e in defaults.entries)
            e.key: {
              for (final k in kUserPermissionKeys) k: e.value[k] ?? false,
            },
        });
      if (!_roles.any((r) => r.slug == _current) && _roles.isNotEmpty) {
        _current = _roles.first.slug;
      }
      _loading = false;
    });
  }

  Map<String, bool> get _perms =>
      _data.putIfAbsent(_current, () => factoryRolePreset(_current));

  RoleOption? get _currentRole {
    for (final r in _roles) {
      if (r.slug == _current) return r;
    }
    return null;
  }

  bool _on(String key) => _perms[key] ?? false;

  bool _effective(PermissionDef d) {
    if (!_on(d.key)) return false;
    return d.parent == null || _on(d.parent!);
  }

  int get _moduleCount => kPermissionDefs.where((d) => d.parent == null).length;

  int get _moduleActive =>
      kPermissionDefs.where((d) => d.parent == null && _on(d.key)).length;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _setPerm(PermissionDef d, bool value) {
    setState(() {
      applyPermissionChange(_perms, d, value, role: _current);
      _changed = true;
    });
  }

  void _setAll(bool value) {
    setState(() {
      for (final k in kUserPermissionKeys) {
        _perms[k] = value;
      }
      if (value) _perms['filesShareOjt'] = false;
      _changed = true;
    });
    _toast(
      value
          ? 'Granted all permissions for ${_current.toUpperCase()}'
          : 'Revoked all permissions for ${_current.toUpperCase()}',
    );
  }

  void _resetPreset() {
    setState(() {
      _data[_current] = factoryRolePreset(_current);
      _changed = true;
    });
    _toast('Reset ${_current.toUpperCase()} to default preset');
  }

  Future<bool> _persist() async {
    final res = await widget.service.saveRoleDefaults(
      _current,
      normalizePermissions(_perms),
    );
    return res.ok;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await widget.service.saveRoleDefaults(
      _current,
      normalizePermissions(_perms),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.ok) _changed = false;
    });
    _toast(
      res.ok
          ? (res.message ?? 'Default role permissions saved.')
          : (res.message ?? 'Failed to save role defaults.'),
    );
  }

  Future<void> _sync() async {
    final label = roleLabel(_current, _roles);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sync $label permissions?'),
        content: Text(
          'This will update all registered users with the "$_current" role '
          'to these default permissions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Yes, sync all accounts'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    await _persist();
    final res = await widget.service.syncRoleDefaultsToUsers(_current);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.ok) _changed = false;
    });
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(res.ok ? 'Permissions synchronized' : 'Sync failed'),
        content: Text(
          res.message ??
              (res.ok
                  ? 'Updated accounts successfully.'
                  : 'Failed to sync users.'),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _addRole() async {
    final slug = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => _RoleFormScreen(
          service: widget.service,
          roles: _roles,
          defaults: _data,
        ),
      ),
    );
    if (slug == null || !mounted) return;
    setState(() => _current = slug);
    await _load();
  }

  Future<void> _deleteRole() async {
    final role = _currentRole;
    if (role == null || !role.custom) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${role.label}?'),
        content: const Text(
          'Its default access is removed too. Accounts keep their own '
          'permissions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete role'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final res = await widget.service.deleteRole(role.slug);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      _toast(res.message ?? 'Role deleted.');
      setState(() {
        _data.remove(role.slug);
        _current = 'admin';
      });
      await _load();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Still in use'),
        content: Text(res.message ?? 'Could not delete the role.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'Admin',
      title: 'Role defaults',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_moderator_rounded,
        tooltip: 'Add role',
        onPressed: _addRole,
      ),
      child: _loading
          ? const SkeletonList(count: 6)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChoicePills<String>(
                  options: [for (final r in _roles) r.slug],
                  value: _current,
                  onChanged: (v) => setState(() => _current = v),
                  labelOf: (r) => roleLabel(r, _roles),
                  countOf: (r) {
                    for (final o in _roles) {
                      if (o.slug == r) return o.users;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _RoleIdentityCard(
                          slug: _current,
                          roles: _roles,
                          active: _moduleActive,
                          total: _moduleCount,
                          users: _currentRole?.users ?? 0,
                          onSync: _saving ? null : _sync,
                        ),
                        const SizedBox(height: 16),
                        SectionHeader(
                          title: 'Default access',
                          trailing: _changed
                              ? const GlowBadge(
                                  label: 'Unsaved',
                                  color: Brand.warning,
                                  icon: Icons.edit_rounded,
                                )
                              : null,
                        ),
                        PermissionMeter(
                          value: _moduleActive,
                          total: _moduleCount,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: () => _setAll(true),
                              icon: const Icon(
                                Icons.done_all_rounded,
                                size: 18,
                              ),
                              label: const Text('Grant all'),
                            ),
                            TextButton.icon(
                              onPressed: () => _setAll(false),
                              icon: const Icon(
                                Icons.remove_done_rounded,
                                size: 18,
                              ),
                              label: const Text('Revoke all'),
                            ),
                            TextButton.icon(
                              onPressed: _resetPreset,
                              icon: const Icon(
                                Icons.restart_alt_rounded,
                                size: 18,
                              ),
                              label: const Text('Reset preset'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        for (final g in kPermissionGroups)
                          PermissionGroupCard(
                            title: g.title,
                            defs: g.items,
                            open: _expanded.contains(g.title),
                            onToggleOpen: () => setState(() {
                              if (!_expanded.remove(g.title)) {
                                _expanded.add(g.title);
                              }
                            }),
                            valueOf: _on,
                            effectiveOf: _effective,
                            onChanged: _setPerm,
                          ),
                        const SizedBox(height: 14),
                        SignalButton(
                          label: 'Save role defaults',
                          icon: Icons.check_rounded,
                          busy: _saving,
                          onPressed: _saving ? null : _save,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Saved defaults apply to accounts registered or '
                          'assigned this role from now on. Use Sync to push '
                          'them onto existing accounts.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: b.paperDim),
                        ),
                        if (_currentRole?.custom ?? false) ...[
                          const SizedBox(height: 24),
                          const SectionHeader(title: 'Danger zone'),
                          AppCard(
                            borderColor: Brand.danger.withValues(alpha: 0.35),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Deleting a role removes its default access. '
                                  'Accounts keep their own permissions, and the '
                                  'role can only go once no account still uses '
                                  'it.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 50,
                                  child: OutlinedButton.icon(
                                    onPressed: _saving ? null : _deleteRole,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Brand.danger,
                                      side: BorderSide(
                                        color: Brand.danger.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Delete role',
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
                  ),
                ),
              ],
            ),
    );
  }
}

class _RoleIdentityCard extends StatelessWidget {
  const _RoleIdentityCard({
    required this.slug,
    required this.roles,
    required this.active,
    required this.total,
    required this.users,
    required this.onSync,
  });

  final String slug;
  final List<RoleOption> roles;
  final int active;
  final int total;
  final int users;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final color = roleColor(slug);
    final pct = total == 0 ? 0 : ((active / total) * 100).round();
    return GlassPanel(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: roleIcon(slug), color: color, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            roleLabel(slug, roles),
                            style: text.titleMedium?.copyWith(color: b.paper),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlowBadge(label: roleTag(slug), color: color),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(roleDescription(slug, roles), style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 14, color: b.paperDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Active coverage · $active / $total modules ($pct%)',
                  style: text.labelMedium?.copyWith(color: b.paperDim),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GhostButton(
            label: 'Sync to $users ${users == 1 ? 'user' : 'users'}',
            icon: Icons.sync_rounded,
            onPressed: onSync ?? () {},
          ),
        ],
      ),
    );
  }
}

class _RoleFormScreen extends StatefulWidget {
  const _RoleFormScreen({
    required this.service,
    required this.roles,
    required this.defaults,
  });

  final UserAdminService service;
  final List<RoleOption> roles;
  final Map<String, Map<String, bool>> defaults;

  @override
  State<_RoleFormScreen> createState() => _RoleFormScreenState();
}

class _RoleFormScreenState extends State<_RoleFormScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final Map<String, bool> _perms = {
    for (final k in kUserPermissionKeys) k: false,
  };
  final Set<String> _expanded = {kPermissionGroups.first.title};
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  bool _on(String key) => _perms[key] ?? false;

  bool _effective(PermissionDef d) {
    if (!_on(d.key)) return false;
    return d.parent == null || _on(d.parent!);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _setAll(bool value) {
    setState(() {
      for (final k in kUserPermissionKeys) {
        _perms[k] = value;
      }
      if (value) _perms['filesShareOjt'] = false;
    });
  }

  Future<void> _copyFrom() async {
    final slug = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        return AlertDialog(
          title: const Text('Copy access from'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in widget.roles)
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
    final source = widget.defaults[slug] ?? factoryRolePreset(slug);
    setState(() {
      for (final k in kUserPermissionKeys) {
        _perms[k] = source[k] ?? false;
      }
    });
    _toast('Copied access from ${roleLabel(slug, widget.roles)}.');
  }

  Future<void> _create() async {
    final label = _name.text.trim();
    if (label.isEmpty) {
      _toast('Role name is required.');
      return;
    }
    if (label.length > 60) {
      _toast('Role name is too long (max 60 characters).');
      return;
    }
    final slug = slugifyRoleName(label);
    if (slug.length < 2) {
      _toast('Role name must contain at least two letters or numbers.');
      return;
    }
    if (kReservedRoleSlugs.contains(slug)) {
      _toast('That name matches a built-in role. Pick another.');
      return;
    }
    if (widget.roles.any((r) => r.slug == slug)) {
      _toast('A role with that name already exists.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.createRole(
      label: label,
      description: _description.text,
      permissions: normalizePermissions(_perms),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(res.slug ?? slug);
      return;
    }
    _toast(res.message ?? 'Could not create the role.');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'Admin',
      title: 'Add role',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          const SectionHeader(title: 'Identity'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  maxLength: 60,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Role name',
                    hintText: 'e.g. Branch Manager',
                    prefixIcon: Icon(Icons.badge_outlined, size: 20),
                  ),
                  style: text.bodyLarge,
                ),
                Text(
                  'Used as the clearance name shown when assigning accounts.',
                  style: text.labelSmall?.copyWith(color: b.paperDim),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _description,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'What this role is for',
                    prefixIcon: Icon(Icons.notes_rounded, size: 20),
                  ),
                  style: text.bodyLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Default access'),
          Text(
            'Granted automatically when this role is assigned. You can change '
            'it later in the matrix.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: _copyFrom,
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                label: const Text('Copy from…'),
              ),
              TextButton.icon(
                onPressed: () => _setAll(true),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('All'),
              ),
              TextButton.icon(
                onPressed: () => _setAll(false),
                icon: const Icon(Icons.remove_done_rounded, size: 18),
                label: const Text('None'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final g in kPermissionGroups)
            PermissionGroupCard(
              title: g.title,
              defs: g.items,
              open: _expanded.contains(g.title),
              onToggleOpen: () => setState(() {
                if (!_expanded.remove(g.title)) _expanded.add(g.title);
              }),
              valueOf: _on,
              effectiveOf: _effective,
              onChanged: (d, v) =>
                  setState(() => applyPermissionChange(_perms, d, v)),
            ),
          const SizedBox(height: 14),
          SignalButton(
            label: 'Create role',
            icon: Icons.check_rounded,
            busy: _saving,
            onPressed: _saving ? null : _create,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
