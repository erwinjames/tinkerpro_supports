import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/user_admin_models.dart';
import '../services/user_admin_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Users / User Management — native CRUD. List of accounts with create / edit /
/// delete plus enable/disable, backed by the user actions on api.php.
class UserAdminListScreen extends StatefulWidget {
  const UserAdminListScreen({super.key, required this.service});
  final UserAdminService service;

  @override
  State<UserAdminListScreen> createState() => _UserAdminListScreenState();
}

class _UserAdminListScreenState extends State<UserAdminListScreen> {
  List<AdminUser> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
        builder: (_) =>
            _UserFormScreen(service: widget.service, existing: existing),
      ),
    );
    if (changed == true) _load();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Invite flow — pick a role, generate a 2-hour registration link, show it
  /// with a copy button. Mirrors the web "Invite" action.
  Future<void> _invite() async {
    final role = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final text = Theme.of(ctx).textTheme;
        return AlertDialog(
          backgroundColor: ctx.brand.surface,
          title: Text('Invite — choose role', style: text.headlineMedium),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Generate a registration link (valid ~2 hours) for someone to '
                'create their own account with this role.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final r in kUserRoles)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.replaceAll('_', ' ').toUpperCase(),
                      style: text.titleSmall),
                  trailing: const Icon(Icons.chevron_right,
                      size: 18, color: Brand.signal),
                  onTap: () => Navigator.of(ctx).pop(r),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('CANCEL',
                  style: text.labelLarge?.copyWith(color: ctx.brand.paperDim)),
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
        return AlertDialog(
          backgroundColor: ctx.brand.surface,
          title: Text('Registration link', style: text.headlineMedium),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${role.replaceAll('_', ' ').toUpperCase()} · valid ~2 hours',
                  style: text.labelMedium),
              const SizedBox(height: 12),
              SelectableText(url, style: text.bodySmall),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('CLOSE',
                  style: text.labelLarge?.copyWith(color: ctx.brand.paperDim)),
            ),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                Navigator.of(ctx).pop();
                _toast('Link copied');
              },
              child: Text('COPY',
                  style: text.labelLarge?.copyWith(color: Brand.signal)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'USER MANAGEMENT',
      title: 'Users.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StationAction(
            icon: Icons.link,
            tooltip: 'Invite (registration link)',
            onPressed: _invite,
          ),
          const SizedBox(width: 4),
          StationAction(
            icon: Icons.add,
            tooltip: 'New user',
            onPressed: _openForm,
          ),
        ],
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: context.brand.surface,
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
                        label: 'No users',
                        hint: 'Tap + to add the first account. Pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Hairline(),
                    itemBuilder: (_, i) => _UserRow(
                      row: _rows[i],
                      onTap: () => _openForm(_rows[i]),
                    ),
                  ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.row, required this.onTap});
  final AdminUser row;
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
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: row.status ? Brand.signal : context.brand.rule,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.fullName.isEmpty ? row.username : row.fullName,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
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
                Text(
                  row.role.replaceAll('_', ' ').toUpperCase(),
                  style: text.labelMedium?.copyWith(
                    color: context.brand.paperDim,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  row.status ? 'ACTIVE' : 'INACTIVE',
                  style: text.labelMedium?.copyWith(
                    color: row.status ? Brand.signal : context.brand.paperDim,
                    letterSpacing: 2.2,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Add / edit form. Add shows username + password; edit hides them and adds an
/// enable/disable action plus delete. Permission switches are built from the
/// known feature-flag keys.
class _UserFormScreen extends StatefulWidget {
  const _UserFormScreen({required this.service, this.existing});
  final UserAdminService service;
  final AdminUser? existing;

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
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _fullName = TextEditingController(text: e?.fullName ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _password = TextEditingController();
    _role = kUserRoles.contains(e?.role) ? e!.role : kUserRoles.first;
    _active = e?.status ?? true;
    // New user → seed permissions from the role's defaults. Editing → keep the
    // account's saved permissions.
    _permissions = e == null
        ? defaultPermissionsForRole(_role)
        : {for (final k in kUserPermissionKeys) k: e.permissions[k] ?? false};
  }

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
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
    setState(() => _saving = true);
    final UserAdminResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: widget.existing!.id,
        fullName: fullName,
        email: email,
        role: _role,
        permissions: _permissions,
      );
    } else {
      res = await widget.service.add(
        fullName: fullName,
        username: _username.text.trim(),
        email: email,
        password: _password.text,
        role: _role,
        permissions: _permissions,
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
        backgroundColor: context.brand.surface,
        title: const Text('Delete user?'),
        content: const Text('This permanently removes the account.'),
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
      _toast(res.message ?? 'Could not delete the user.');
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
      stationNumber: '11',
      stationLabel: _isEdit ? 'EDIT USER' : 'NEW USER',
      title: _isEdit ? 'Edit user.' : 'Add user.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          _Field(label: 'FULL NAME', controller: _fullName),
          if (!_isEdit) ...[
            const SizedBox(height: 16),
            _Field(label: 'USERNAME', controller: _username),
          ],
          const SizedBox(height: 16),
          _Field(
            label: 'EMAIL',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 16),
            _Field(label: 'PASSWORD', controller: _password, obscure: true),
          ],
          const SizedBox(height: 24),
          Text('ROLE', style: text.labelLarge),
          const SizedBox(height: 8),
          _RoleDropdown(
            value: _role,
            onChanged: (v) => setState(() {
              _role = v;
              // Auto-select the permission set for the chosen role.
              _permissions = defaultPermissionsForRole(v);
            }),
          ),
          const SizedBox(height: 28),
          Text('PERMISSIONS', style: text.labelLarge),
          const SizedBox(height: 4),
          for (final key in kUserPermissionKeys) ...[
            _ToggleRow(
              label: _prettyKey(key),
              value: _permissions[key] ?? false,
              onChanged: (v) => setState(() => _permissions[key] = v),
            ),
            const Hairline(),
          ],
          const SizedBox(height: 28),
          SignalButton(
            label: _isEdit ? 'Save changes' : 'Create user',
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 12),
            GhostButton(
              label: _active ? 'Disable account' : 'Enable account',
              onPressed: _toggleActive,
            ),
            const SizedBox(height: 12),
            GhostButton(label: 'Delete user', onPressed: _delete),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// Turn a feature-flag key into a readable label, e.g. clientOffer → "Client
// Offer", releasenotes → "Releasenotes".
String _prettyKey(String key) {
  final spaced = key.replaceAllMapped(
    RegExp('([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  if (spaced.isEmpty) return spaced;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Standard labelled text field matching the app's input styling.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.obscure = false,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: context.brand.surface,
      style: text.titleMedium,
      decoration: const InputDecoration(labelText: 'ROLE'),
      items: [
        for (final role in kUserRoles)
          DropdownMenuItem<String>(
            value: role,
            child: Text(role.replaceAll('_', ' ').toUpperCase()),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Brand.signal,
        ),
      ],
    );
  }
}
