import 'dart:math';

import 'package:flutter/material.dart';

import '../models/license_models.dart';
import '../services/license_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// License Keys — native CRUD. List of keys with create / edit / delete,
/// backed by the `*_license_key` actions on api.php.
class LicenseListScreen extends StatefulWidget {
  const LicenseListScreen({super.key, required this.service});
  final LicenseService service;

  @override
  State<LicenseListScreen> createState() => _LicenseListScreenState();
}

class _LicenseListScreenState extends State<LicenseListScreen> {
  List<LicenseKey> _rows = const [];
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

  Future<void> _openForm([LicenseKey? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _LicenseFormScreen(service: widget.service, existing: existing),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '12',
      stationLabel: 'LICENSE KEYS',
      title: 'Licenses.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add,
        tooltip: 'New license',
        onPressed: _openForm,
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
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
                        label: 'No license keys',
                        hint: 'Tap + to mint the first key. Pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Hairline(),
                    itemBuilder: (_, i) => _LicenseRow(
                      row: _rows[i],
                      onTap: () => _openForm(_rows[i]),
                    ),
                  ),
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
    final status = row.isUsed
        ? 'IN USE'
        : (row.isTrial ? 'TRIAL' : 'PERMANENT');
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
                color: row.isUsed ? Brand.signal : Brand.rule,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.licenseKey,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(
                    row.storeName.isEmpty
                        ? (row.isTrial && row.dateExpired != null
                            ? 'Expires ${row.dateExpired}'
                            : 'Unassigned')
                        : row.storeName,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(status,
                style: text.labelMedium?.copyWith(
                  color: row.isUsed ? Brand.signal : Brand.paperDim,
                  letterSpacing: 2.2,
                )),
          ],
        ),
      ),
    );
  }
}

/// Add / edit form. Permanent vs trial toggle reveals the expiry picker.
/// Store fields only matter on edit (a fresh key has no customer yet).
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

  /// Generate a secure key in the same format as the web:
  /// `TP-XXXX-XXXX-XXXX-XXXX` (4 groups of 4 alphanumerics).
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
        expirationDate: _expiryStr,
        storeName: _storeName.text.trim(),
        storeAddress: _storeAddress.text.trim(),
        storeEmail: _storeEmail.text.trim(),
      );
    } else {
      res = await widget.service.add(
        licenseKey: key,
        trial: _trial,
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
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('Delete license?'),
        content: const Text('This permanently removes the key.'),
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
      _toast(res.message ?? 'Could not delete the license.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final used = widget.existing?.isUsed ?? false;
    return StationScaffold(
      stationNumber: '12',
      stationLabel: _isEdit ? 'EDIT LICENSE' : 'NEW LICENSE',
      title: _isEdit ? 'Edit key.' : 'Mint key.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          _Field(label: 'LICENSE KEY', controller: _key),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: _generateKey,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 14, color: Brand.signal),
                  const SizedBox(width: 4),
                  Text('GENERATE',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: Brand.signal)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ToggleRow(
            label: 'TRIAL KEY',
            value: _trial,
            onChanged: (v) => setState(() => _trial = v),
          ),
          if (_trial) ...[
            const SizedBox(height: 16),
            StationDataRow(
              label: 'EXPIRES',
              value: _expiryStr ?? 'Tap to pick a date',
              onTap: _pickExpiry,
              trailingIcon: Icons.calendar_today,
            ),
          ],
          if (_isEdit) ...[
            const SizedBox(height: 28),
            Text('CUSTOMER', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 16),
            _Field(label: 'STORE NAME', controller: _storeName),
            const SizedBox(height: 16),
            _Field(label: 'STORE ADDRESS', controller: _storeAddress),
            const SizedBox(height: 16),
            _Field(label: 'STORE EMAIL', controller: _storeEmail),
          ],
          const SizedBox(height: 32),
          SignalButton(
            label: _isEdit ? 'Save changes' : 'Create license',
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (_isEdit && !used) ...[
            const SizedBox(height: 12),
            GhostButton(label: 'Delete license', onPressed: _delete),
          ],
          if (_isEdit && used) ...[
            const SizedBox(height: 16),
            Text(
              'This key is in use by a customer and cannot be deleted.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// Standard labelled text field matching the app's input styling.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      style: Theme.of(context).textTheme.titleMedium,
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
