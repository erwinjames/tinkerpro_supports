import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_admin_models.dart';
import '../services/user_admin_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class BranchesAdminScreen extends StatefulWidget {
  const BranchesAdminScreen({super.key, required this.service});

  final UserAdminService service;

  @override
  State<BranchesAdminScreen> createState() => _BranchesAdminScreenState();
}

class _BranchesAdminScreenState extends State<BranchesAdminScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  List<Branch> _rows = const [];
  String _search = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.branches(search: _search);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _search = value);
      _load();
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openForm([Branch? existing]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _BranchFormScreen(service: widget.service, existing: existing),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Branch branch) async {
    final staff = branch.staffCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${branch.name}?'),
        content: Text(
          staff > 0
              ? '$staff staff account${staff == 1 ? '' : 's'} assigned to this '
                    'branch will be left with no branch. The accounts '
                    'themselves are not touched.'
              : 'This branch will be removed permanently.',
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
            child: const Text('Delete branch'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.service.deleteBranch(branch.id);
    if (!mounted) return;
    _toast(
      res.ok
          ? (res.message ?? 'Branch deleted.')
          : (res.message ?? 'Could not delete the branch.'),
    );
    if (res.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final staff = _rows.fold<int>(0, (sum, r) => sum + r.staffCount);
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'Admin',
      title: 'Branches',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_rounded,
        tooltip: 'Add branch',
        onPressed: _openForm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _searchController,
            hint: 'Search name, code or address',
            onChanged: _onSearch,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 5)
                  : _rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          label: _search.trim().isEmpty
                              ? 'No branches yet'
                              : 'No matching branches',
                          hint: _search.trim().isEmpty
                              ? 'Add a branch to start assigning staff to '
                                    'office locations.'
                              : 'Try a different name, code or address.',
                          icon: Icons.account_tree_outlined,
                          action: _search.trim().isEmpty
                              ? FilledButton.icon(
                                  onPressed: _openForm,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('Add branch'),
                                )
                              : null,
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: _rows.length + 1,
                      separatorBuilder: (_, i) =>
                          SizedBox(height: i == 0 ? 12 : 10),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return GlassPanel(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Branch directory',
                                        style: text.titleSmall?.copyWith(
                                          color: b.paper,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Office locations a staff account can '
                                        'be assigned to.',
                                        style: text.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                GlowBadge(
                                  label:
                                      '${_rows.length} · $staff '
                                      '${staff == 1 ? 'staff' : 'staff'}',
                                  icon: Icons.account_tree_rounded,
                                ),
                              ],
                            ),
                          );
                        }
                        final row = _rows[i - 1];
                        return _BranchCard(
                          branch: row,
                          onEdit: () => _openForm(row),
                          onDelete: () => _delete(row),
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

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.onEdit,
    required this.onDelete,
  });

  final Branch branch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final accent = branch.isMain ? Brand.signal : Brand.info;
    return AppCard(
      onTap: onEdit,
      radius: Brand.radiusLg,
      padding: const EdgeInsets.all(14),
      borderColor: branch.active ? accent.withValues(alpha: 0.28) : b.rule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: branch.isMain
                    ? Icons.star_rounded
                    : Icons.account_tree_rounded,
                color: accent,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      branch.name,
                      style: text.titleSmall?.copyWith(
                        color: branch.active ? b.paper : b.paperDim,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusPill(label: branch.code, color: accent),
                        if (branch.isMain)
                          const StatusPill(
                            label: 'Main',
                            color: Brand.signal,
                            icon: Icons.star_rounded,
                          ),
                        if (!branch.active)
                          StatusPill(
                            label: 'Inactive',
                            color: b.paperDim,
                            icon: Icons.block_rounded,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (branch.address.isNotEmpty) ...[
            const SizedBox(height: 10),
            _MetaLine(icon: Icons.place_outlined, value: branch.address),
          ],
          if (branch.contactNumber.isNotEmpty) ...[
            const SizedBox(height: 6),
            _MetaLine(icon: Icons.phone_outlined, value: branch.contactNumber),
          ],
          const SizedBox(height: 10),
          const Hairline(),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.people_outline_rounded, size: 14, color: b.paperDim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${branch.staffCount} staff',
                  style: text.labelMedium?.copyWith(color: b.paperDim),
                ),
              ),
              AppIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit branch',
                onPressed: onEdit,
              ),
              const SizedBox(width: 6),
              AppIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete branch',
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: b.paperDim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _BranchFormScreen extends StatefulWidget {
  const _BranchFormScreen({required this.service, this.existing});

  final UserAdminService service;
  final Branch? existing;

  @override
  State<_BranchFormScreen> createState() => _BranchFormScreenState();
}

class _BranchFormScreenState extends State<_BranchFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _address;
  late final TextEditingController _contact;
  late String _status;
  late bool _isMain;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _code = TextEditingController(text: e?.code ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _contact = TextEditingController(text: e?.contactNumber ?? '');
    _status = e?.status.toLowerCase() == 'inactive' ? 'inactive' : 'active';
    _isMain = e?.isMain ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _address.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final code = _code.text.trim().toUpperCase();
    if (name.isEmpty) {
      _toast('Branch name is required.');
      return;
    }
    if (code.isEmpty) {
      _toast('Branch code is required.');
      return;
    }
    if (!RegExp(r'^[A-Z0-9-]{2,20}$').hasMatch(code)) {
      _toast('Code must be 2-20 characters: letters, numbers or dashes.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.saveBranch(
      id: widget.existing?.id ?? 0,
      name: name,
      code: code,
      address: _address.text,
      contactNumber: _contact.text,
      status: _status,
      isMain: _isMain,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    _toast(res.message ?? 'Could not save the branch.');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '11',
      stationLabel: 'Admin',
      title: _isEdit ? 'Edit branch' : 'Add branch',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          const SectionHeader(title: 'Branch'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Branch name',
                    hintText: 'e.g. Cebu Main Office',
                    prefixIcon: Icon(Icons.account_tree_outlined, size: 20),
                  ),
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _code,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    hintText: 'e.g. CEB',
                    prefixIcon: Icon(Icons.tag_rounded, size: 20),
                  ),
                  style: text.bodyLarge,
                ),
                Text(
                  '2-20 characters: letters, numbers or dashes. Must be unique.',
                  style: text.labelSmall?.copyWith(color: b.paperDim),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _address,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'Street, city, province',
                    prefixIcon: Icon(Icons.place_outlined, size: 20),
                  ),
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _contact,
                  maxLength: 40,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact number',
                    hintText: 'e.g. +63 32 000 0000',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                  style: text.bodyLarge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Status'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChoicePills<String>(
                  options: const ['active', 'inactive'],
                  value: _status,
                  onChanged: (v) => setState(() => _status = v),
                  labelOf: (v) => v == 'active' ? 'Active' : 'Inactive',
                ),
                const SizedBox(height: 8),
                Text(
                  "Inactive branches stay on record but can't be picked for "
                  'new staff.',
                  style: text.labelSmall?.copyWith(color: b.paperDim),
                ),
                const SizedBox(height: 10),
                const Hairline(),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Main branch', style: text.bodyMedium),
                            Text(
                              'Marks this as the head office. Only one branch '
                              'can be the main one — setting it here clears '
                              'the flag from any other branch.',
                              style: text.labelSmall?.copyWith(
                                color: b.paperDim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Switch(
                        value: _isMain,
                        onChanged: (v) => setState(() => _isMain = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SignalButton(
            label: _isEdit ? 'Save branch' : 'Add branch',
            icon: Icons.check_rounded,
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
