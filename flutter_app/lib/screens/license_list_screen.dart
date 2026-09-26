import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/license_models.dart';
import '../services/license_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class LicenseListScreen extends StatefulWidget {
  const LicenseListScreen({super.key, required this.service});
  final LicenseService service;

  @override
  State<LicenseListScreen> createState() => _LicenseListScreenState();
}

enum _LicenseFilter { all, inUse, available, trial, expired }

enum _LicenseState { inUse, trial, expired, permanent }

_LicenseState _stateOf(LicenseKey row) {
  if (row.isTrial) {
    final raw = row.dateExpired;
    final exp = raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
    if (exp != null && exp.isBefore(DateTime.now())) {
      return _LicenseState.expired;
    }
  }
  if (row.isUsed) return _LicenseState.inUse;
  if (row.isTrial) return _LicenseState.trial;
  return _LicenseState.permanent;
}

class _LicenseListScreenState extends State<LicenseListScreen> {
  final _searchController = TextEditingController();
  List<LicenseKey> _rows = const [];
  bool _loading = true;
  _LicenseFilter _filter = _LicenseFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _openForm([LicenseKey? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _LicenseFormScreen(service: widget.service, existing: existing),
      ),
    );
    if (changed == true) _load();
  }

  bool _matches(LicenseKey r) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty &&
        !r.licenseKey.toLowerCase().contains(q) &&
        !r.storeName.toLowerCase().contains(q) &&
        !r.storeEmail.toLowerCase().contains(q)) {
      return false;
    }
    final st = _stateOf(r);
    switch (_filter) {
      case _LicenseFilter.all:
        return true;
      case _LicenseFilter.inUse:
        return r.isUsed;
      case _LicenseFilter.available:
        return !r.isUsed;
      case _LicenseFilter.trial:
        return r.isTrial;
      case _LicenseFilter.expired:
        return st == _LicenseState.expired;
    }
  }

  bool _matchesFilter(LicenseKey r, _LicenseFilter f) {
    switch (f) {
      case _LicenseFilter.all:
        return true;
      case _LicenseFilter.inUse:
        return r.isUsed;
      case _LicenseFilter.available:
        return !r.isUsed;
      case _LicenseFilter.trial:
        return r.isTrial;
      case _LicenseFilter.expired:
        return _stateOf(r) == _LicenseState.expired;
    }
  }

  String _filterLabel(_LicenseFilter f) {
    switch (f) {
      case _LicenseFilter.all:
        return 'All';
      case _LicenseFilter.inUse:
        return 'In use';
      case _LicenseFilter.available:
        return 'Available';
      case _LicenseFilter.trial:
        return 'Trial';
      case _LicenseFilter.expired:
        return 'Expired';
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final rows = _rows.where(_matches).toList();
    return StationScaffold(
      stationNumber: '12',
      stationLabel: 'License keys',
      title: 'Licenses',
      subtitle: _loading ? '' : '${_rows.length} keys',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_rounded,
        tooltip: 'New license',
        onPressed: _openForm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _searchController,
            hint: 'Search key, store or email',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          ChoicePills<_LicenseFilter>(
            options: _LicenseFilter.values,
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
            labelOf: _filterLabel,
            countOf: _loading
                ? null
                : (f) => _rows.where((r) => _matchesFilter(r, f)).length,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: b.signal,
              backgroundColor: b.surface,
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 7)
                  : rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          icon: Icons.vpn_key_rounded,
                          label: _rows.isEmpty
                              ? 'No license keys'
                              : 'No matching keys',
                          hint: _rows.isEmpty
                              ? 'Tap + to mint the first key. Pull to refresh.'
                              : 'Try a different search or filter.',
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _Entry(
                        index: i,
                        child: _LicenseRow(
                          row: rows[i],
                          onTap: () => _openForm(rows[i]),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseRow extends StatelessWidget {
  const _LicenseRow({required this.row, required this.onTap});
  final LicenseKey row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final st = _stateOf(row);
    final (String label, Color color, IconData icon) = switch (st) {
      _LicenseState.expired => (
        'Expired',
        Brand.danger,
        Icons.event_busy_rounded,
      ),
      _LicenseState.inUse => ('In use', Brand.success, Icons.vpn_key_rounded),
      _LicenseState.trial => ('Trial', Brand.warning, Icons.timelapse_rounded),
      _LicenseState.permanent => (
        'Permanent',
        Brand.info,
        Icons.all_inclusive_rounded,
      ),
    };
    final subtitle = row.storeName.isEmpty
        ? (row.isTrial && row.dateExpired != null
              ? 'Expires ${row.dateExpired}'
              : 'Unassigned')
        : row.storeName;
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: color.withValues(alpha: 0.35),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color, size: 42, iconSize: 19),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subtitle,
                        style: text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (row.machineType.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      StatusPill(
                        label: row.machineType,
                        color: context.brand.isDark ? Brand.info : Brand.navy,
                        icon: row.machineType == 'Server'
                            ? Icons.dns_rounded
                            : Icons.point_of_sale_rounded,
                      ),
                    ],
                    const SizedBox(width: 8),
                    GlowBadge(label: label, color: color, icon: icon),
                  ],
                ),
                const SizedBox(height: 8),
                _KeyChip(value: row.licenseKey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = Duration(milliseconds: reduce ? 0 : 220);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Machine role $label',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          color: selected
              ? Brand.orange.withValues(alpha: b.isDark ? 0.18 : 0.12)
              : b.surfaceHi,
          border: Border.all(
            color: selected ? Brand.orange.withValues(alpha: 0.75) : b.rule,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    AnimatedScale(
                      scale: selected ? 1.08 : 1,
                      duration: duration,
                      curve: Curves.easeOutBack,
                      child: Icon(
                        icon,
                        size: 20,
                        color: selected ? b.signalInk : b.paperDim,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: text.labelLarge?.copyWith(
                          color: selected ? b.paper : b.paperDim,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: duration,
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: Brand.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final start = (index.clamp(0, 5)) * 0.12;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.value});
  final String value;

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('License key copied')));
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final canCopy = value.isNotEmpty;
    final radius = BorderRadius.circular(Brand.radius);
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: b.surfaceHi,
        border: Border.all(
          color: canCopy ? Brand.orange.withValues(alpha: 0.4) : b.rule,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canCopy ? () => _copy(context) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(Icons.key_rounded, size: 16, color: b.signalInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      canCopy ? value : '\u2014',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: b.paper,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  if (canCopy) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.copy_rounded, size: 17, color: b.signal),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return canCopy ? Tooltip(message: 'Copy license key', child: chip) : chip;
  }
}

class _LicenseFormScreen extends StatefulWidget {
  const _LicenseFormScreen({required this.service, this.existing});
  final LicenseService service;
  final LicenseKey? existing;

  @override
  State<_LicenseFormScreen> createState() => _LicenseFormScreenState();
}

class _LicenseFormScreenState extends State<_LicenseFormScreen> {
  late final TextEditingController _key;
  late final TextEditingController _storeName;
  late final TextEditingController _storeAddress;
  late final TextEditingController _storeEmail;
  late bool _trial;
  late String _role;
  DateTime? _expiry;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _key = TextEditingController(text: e?.licenseKey ?? '');
    _storeName = TextEditingController(text: e?.storeName ?? '');
    _storeAddress = TextEditingController(text: e?.storeAddress ?? '');
    _storeEmail = TextEditingController(text: e?.storeEmail ?? '');
    _trial = e?.isTrial ?? false;
    _role = e?.machineType ?? '';
    if (e?.dateExpired != null && e!.dateExpired!.isNotEmpty) {
      _expiry = DateTime.tryParse(e.dateExpired!);
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _storeName.dispose();
    _storeAddress.dispose();
    _storeEmail.dispose();
    super.dispose();
  }

  String? get _expiryStr => _expiry == null
      ? null
      : '${_expiry!.year.toString().padLeft(4, '0')}-'
            '${_expiry!.month.toString().padLeft(2, '0')}-'
            '${_expiry!.day.toString().padLeft(2, '0')}';

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now.add(const Duration(days: 30)),
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  void _generateKey() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    String group() =>
        List.generate(4, (_) => chars[rand.nextInt(chars.length)]).join();
    setState(() {
      _key.text = 'TP-${group()}-${group()}-${group()}-${group()}';
    });
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      _toast('License key is required.');
      return;
    }
    if (_role.isEmpty) {
      _toast('Machine role is required — pick Server or Terminal.');
      return;
    }
    if (_trial && _expiry == null) {
      _toast('Pick an expiry date for a trial key.');
      return;
    }
    setState(() => _saving = true);
    final LicenseResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: widget.existing!.id,
        licenseKey: key,
        trial: _trial,
        machineType: _role,
        expirationDate: _expiryStr,
        storeName: _storeName.text.trim(),
        storeAddress: _storeAddress.text.trim(),
        storeEmail: _storeEmail.text.trim(),
      );
    } else {
      res = await widget.service.add(
        licenseKey: key,
        trial: _trial,
        machineType: _role,
        expirationDate: _expiryStr,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the license.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const IconTile(
          icon: Icons.delete_outline_rounded,
          color: Brand.danger,
          size: 44,
          iconSize: 22,
        ),
        title: const Text('Delete license?'),
        content: const Text('This permanently removes the key.'),
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
      _toast(res.message ?? 'Could not delete the license.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final used = widget.existing?.isUsed ?? false;
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '12',
      stationLabel: 'Licenses',
      title: _isEdit ? 'Edit key' : 'Mint key',
      subtitle: _isEdit ? widget.existing!.licenseKey : 'New license key',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      bottomBar: _FormBottomBar(
        child: SignalButton(
          label: _isEdit ? 'Save changes' : 'Create license',
          icon: Icons.check_rounded,
          busy: _saving,
          onPressed: _saving ? null : _save,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              children: [
                GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.shield_rounded,
                            size: 18,
                            color: Brand.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Secure key vault',
                              style: text.labelMedium?.copyWith(
                                color: b.paper,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          GlowBadge(
                            label: _isEdit
                                ? (used ? 'In use' : 'Issued')
                                : 'New key',
                            color: Brand.orange,
                            icon: used
                                ? Icons.lock_rounded
                                : Icons.auto_awesome_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                        decoration: BoxDecoration(
                          color: b.surfaceHi,
                          borderRadius: BorderRadius.circular(Brand.radius),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('License key', style: text.labelLarge),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _key,
                              style: text.bodyLarge?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                              decoration: InputDecoration(
                                hintText: 'TP-XXXX-XXXX-XXXX-XXXX',
                                fillColor: b.surface,
                                prefixIcon: Icon(
                                  Icons.vpn_key_rounded,
                                  size: 18,
                                  color: b.signalInk,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(44, 44),
                                ),
                                onPressed: _generateKey,
                                icon: const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 16,
                                ),
                                label: const Text('Generate'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _FormSection(
                  title: 'Machine role',
                  icon: Icons.memory_rounded,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _RoleOption(
                            label: 'Server',
                            icon: Icons.dns_rounded,
                            selected: _role == 'Server',
                            onTap: () => setState(() => _role = 'Server'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RoleOption(
                            label: 'Terminal',
                            icon: Icons.point_of_sale_rounded,
                            selected: _role == 'Terminal',
                            onTap: () => setState(() => _role = 'Terminal'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Which machine this key is issued for.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    _ToggleRow(
                      label: 'Trial key',
                      hint: 'Trial keys expire on a set date',
                      value: _trial,
                      onChanged: (v) => setState(() => _trial = v),
                    ),
                    if (_trial) ...[
                      const SizedBox(height: 12),
                      Text('Expires', style: text.labelLarge),
                      const SizedBox(height: 6),
                      _DateField(
                        value: _expiryStr,
                        placeholder: 'Tap to pick a date',
                        onTap: _pickExpiry,
                      ),
                    ],
                  ],
                ),
                if (_isEdit) ...[
                  const SizedBox(height: 12),
                  _FormSection(
                    title: 'Customer',
                    icon: Icons.storefront_rounded,
                    children: [
                      _Field(label: 'Store name', controller: _storeName),
                      const SizedBox(height: 14),
                      _Field(label: 'Store address', controller: _storeAddress),
                      const SizedBox(height: 14),
                      _Field(
                        label: 'Store email',
                        controller: _storeEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ],
                  ),
                ],
                if (_isEdit && !used) ...[
                  const SizedBox(height: 12),
                  GhostButton(
                    label: 'Delete license',
                    icon: Icons.delete_outline_rounded,
                    onPressed: _delete,
                  ),
                ],
                if (_isEdit && used) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: b.tint(Brand.info, 0.1),
                      borderRadius: BorderRadius.circular(Brand.radiusLg),
                      border: Border.all(
                        color: Brand.info.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: Brand.info,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This key is in use by a customer and cannot be deleted.',
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormBottomBar extends StatelessWidget {
  const _FormBottomBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Material(
      color: b.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: b.rule)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: icon, size: 30, iconSize: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: label),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.placeholder,
    required this.onTap,
  });
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Material(
      color: b.surfaceHi,
      borderRadius: BorderRadius.circular(Brand.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 18, color: b.paperDim),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value ?? placeholder,
                  style: text.bodyLarge?.copyWith(
                    color: value == null ? b.paperDim : b.paper,
                  ),
                ),
              ),
              Icon(Icons.expand_more_rounded, size: 20, color: b.paperDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.titleSmall),
              if (hint != null) ...[
                const SizedBox(height: 2),
                Text(hint!, style: text.bodySmall),
              ],
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
