import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:open_filex/open_filex.dart';

import '../models/employment_models.dart';
import '../services/employment_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'employment_edit_screen.dart';

const String kEmploymentDeleteRequest = 'delete';
const String kEmploymentChanged = 'changed';

Color employmentStatusColor(BuildContext context, String status) {
  switch (status) {
    case 'submitted':
      return Brand.warning;
    case 'reviewed':
      return Brand.success;
    default:
      return const Color(0xFF64748B);
  }
}

IconData employmentStatusIcon(String status) {
  switch (status) {
    case 'submitted':
      return Icons.error_outline_rounded;
    case 'reviewed':
      return Icons.check_circle_rounded;
    default:
      return Icons.archive_rounded;
  }
}

class EmploymentStatusPill extends StatelessWidget {
  const EmploymentStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return EmploymentGlowPill(
      label: employmentStatusLabel(status),
      color: employmentStatusColor(context, status),
      icon: employmentStatusIcon(status),
    );
  }
}

class EmploymentGlowPill extends StatelessWidget {
  const EmploymentGlowPill({
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

void employmentToast(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), action: action, duration: duration),
    );
}

Future<bool> employmentConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.delete_outline_rounded,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icon, color: Brand.danger, size: 28),
      title: Text(title),
      content: Text(message),
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
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<EmploymentResult?> showStaffLinkSheet(
  BuildContext context, {
  required EmploymentService service,
  required int recordId,
  required String fullName,
}) {
  return showModalBottomSheet<EmploymentResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StaffLinkSheet(
      service: service,
      recordId: recordId,
      fullName: fullName,
    ),
  );
}

class _StaffLinkSheet extends StatefulWidget {
  const _StaffLinkSheet({
    required this.service,
    required this.recordId,
    required this.fullName,
  });

  final EmploymentService service;
  final int recordId;
  final String fullName;

  @override
  State<_StaffLinkSheet> createState() => _StaffLinkSheetState();
}

class _StaffLinkSheetState extends State<_StaffLinkSheet> {
  List<EmploymentStaff>? _staff;
  final _search = TextEditingController();
  String _query = '';
  int? _picked;
  bool _saving = false;
  bool _skipping = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await widget.service.staff();
    if (!mounted) return;
    setState(() => _staff = res.users);
  }

  Future<void> _submit(int userId) async {
    setState(() {
      _error = null;
      if (userId > 0) {
        _saving = true;
      } else {
        _skipping = true;
      }
    });
    final res = await widget.service.linkStaff(widget.recordId, userId);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _skipping = false;
    });
    if (!res.ok) {
      setState(
        () => _error = res.message ?? 'Could not save the staff account',
      );
      return;
    }
    Navigator.of(context).pop(res);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final staff = _staff;
    final q = _query.trim().toLowerCase();
    final visible = (staff ?? const <EmploymentStaff>[]).where((u) {
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();
    final name = widget.fullName.trim().isEmpty
        ? 'This sheet'
        : widget.fullName.trim();
    final busy = _saving || _skipping;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const IconTile(icon: Icons.badge_rounded, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Who is this sheet for?',
                      style: text.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$name is not linked to a staff account yet. Pick who this '
                'is, or continue without linking.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 14),
              AppSearchField(
                controller: _search,
                hint: 'Search staff by name…',
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 6),
              Text(
                staff != null && staff.isEmpty
                    ? 'No staff accounts available — continue with "Not a '
                          'staff account".'
                    : 'Start typing to search the staff list.',
                style: text.labelMedium,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: staff == null
                    ? const SkeletonList(count: 5)
                    : visible.isEmpty
                    ? const EmptyState(
                        label: 'No matching staff',
                        hint: 'Try a different name.',
                        icon: Icons.person_search_rounded,
                      )
                    : AppCard(
                        padding: EdgeInsets.zero,
                        child: ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Hairline(),
                          itemBuilder: (_, i) {
                            final u = visible[i];
                            final selected = _picked == u.id;
                            final suffix = [
                              if (u.role.isNotEmpty) u.role,
                              if (u.username.isNotEmpty) '@${u.username}',
                            ].join(' · ');
                            return Semantics(
                              selected: selected,
                              button: true,
                              child: InkWell(
                                onTap: busy
                                    ? null
                                    : () => setState(() => _picked = u.id),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 56,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        AppAvatar(name: u.name, size: 36),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                u.name,
                                                style: text.titleSmall,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (suffix.isNotEmpty)
                                                Text(
                                                  suffix,
                                                  style: text.bodySmall,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          selected
                                              ? Icons
                                                    .radio_button_checked_rounded
                                              : Icons
                                                    .radio_button_unchecked_rounded,
                                          color: selected
                                              ? b.signal
                                              : b.paperDim,
                                          size: 22,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: text.bodySmall?.copyWith(color: Brand.danger),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: _skipping ? 'Saving…' : 'Not a staff account',
                      onPressed: () {
                        if (!busy) _submit(0);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SignalButton(
                      label: _saving ? 'Saving…' : 'Link & continue',
                      icon: Icons.link_rounded,
                      busy: _saving,
                      onPressed: busy
                          ? null
                          : () {
                              final picked = _picked;
                              if (picked == null) {
                                setState(
                                  () => _error =
                                      'Pick a staff account, or choose "Not '
                                      'a staff account"',
                                );
                                return;
                              }
                              _submit(picked);
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> printEmploymentSheet(
  BuildContext context,
  EmploymentService service,
  int id,
) async {
  final pref = await service.authNamePref();
  if (!context.mounted) return;
  if (pref.remember) {
    final shown = pref.name.isEmpty
        ? 'a blank authorization name'
        : '"${pref.name}"';
    await _downloadAndOpen(context, service, id, pref.name);
    if (!context.mounted) return;
    employmentToast(
      context,
      'Printing with $shown.',
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Change',
        onPressed: () async {
          await service.forgetAuthRemember();
          if (context.mounted) await printEmploymentSheet(context, service, id);
        },
      ),
    );
    return;
  }
  final chosen = await showDialog<({String name, bool remember})>(
    context: context,
    builder: (_) => _AuthNameDialog(initial: pref.name),
  );
  if (chosen == null || !context.mounted) return;
  await service.saveAuthName(chosen.name, remember: chosen.remember);
  if (!context.mounted) return;
  await _downloadAndOpen(context, service, id, chosen.name);
}

Future<void> _downloadAndOpen(
  BuildContext context,
  EmploymentService service,
  int id,
  String authName,
) async {
  employmentToast(context, 'Preparing PDF…');
  try {
    final path = await service.downloadPdf(id, authName);
    final result = await OpenFilex.open(path, type: 'application/pdf');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (result.type != ResultType.done) {
      employmentToast(context, 'No app available to open the PDF');
    }
  } catch (e) {
    if (!context.mounted) return;
    employmentToast(context, e.toString());
  }
}

class _AuthNameDialog extends StatefulWidget {
  const _AuthNameDialog({required this.initial});

  final String initial;

  @override
  State<_AuthNameDialog> createState() => _AuthNameDialogState();
}

class _AuthNameDialogState extends State<_AuthNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );
  bool _remember = true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    Navigator.of(context).pop((name: _name.text.trim(), remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Authorization Name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'This name appears under Account Information. Leave it blank to '
            'print an empty line.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _done(),
            decoration: const InputDecoration(
              hintText: 'Name printed on the sheet',
              counterText: '',
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _remember,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: Text(
              'Remember this name and stop asking',
              style: text.bodyMedium,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _done,
          icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: const Text('Print'),
        ),
      ],
    );
  }
}

class EmploymentRecordScreen extends StatefulWidget {
  const EmploymentRecordScreen({
    super.key,
    required this.service,
    required this.record,
  });

  final EmploymentService service;
  final EmploymentRecord record;

  @override
  State<EmploymentRecordScreen> createState() => _EmploymentRecordScreenState();
}

class _EmploymentRecordScreenState extends State<EmploymentRecordScreen> {
  late EmploymentRecord _record = widget.record;
  bool _changed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _markReviewedOnOpen();
  }

  Future<void> _markReviewedOnOpen() async {
    if (_record.status != 'submitted') return;
    final res = await widget.service.setStatus(_record.id, 'reviewed');
    if (!mounted || !res.ok) return;
    setState(() {
      _record = _record.copyWith({'status': 'reviewed'});
      _changed = true;
    });
  }

  Future<void> _reload() async {
    try {
      final fresh = await widget.service.record(_record.id);
      if (!mounted) return;
      setState(() => _record = fresh);
    } catch (e) {
      if (mounted) employmentToast(context, e.toString());
    }
  }

  void _close([String? result]) {
    Navigator.of(context).pop(result ?? (_changed ? kEmploymentChanged : null));
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            EmploymentEditScreen(service: widget.service, record: _record),
      ),
    );
    if (saved == true) {
      _changed = true;
      await _reload();
    }
  }

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    final res = await widget.service.setStatus(_record.id, status);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      employmentToast(context, res.message ?? 'Could not update the status');
      return;
    }
    _changed = true;
    employmentToast(context, res.message ?? 'Marked as $status.');
    await _reload();
  }

  Future<void> _linkStaff() async {
    final res = await showStaffLinkSheet(
      context,
      service: widget.service,
      recordId: _record.id,
      fullName: _record.fullName,
    );
    if (res == null || !mounted) return;
    _changed = true;
    employmentToast(context, res.message ?? 'Saved.');
    await _reload();
  }

  Future<void> _delete() async {
    final ok = await employmentConfirm(
      context,
      title: 'Delete this sheet?',
      message:
          'The employee record and its dependents are permanently '
          'removed.',
      confirmLabel: 'Delete',
    );
    if (ok && mounted) _close(kEmploymentDeleteRequest);
  }

  Future<void> _actions() async {
    final b = context.brand;
    final status = _record.status;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        Widget tile(String value, IconData icon, String label, {Color? c}) =>
            ListTile(
              minTileHeight: 52,
              leading: Icon(icon, color: c ?? b.paper),
              title: Text(
                label,
                style: Theme.of(
                  ctx,
                ).textTheme.titleSmall?.copyWith(color: c ?? b.paper),
              ),
              onTap: () => Navigator.of(ctx).pop(value),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                tile('edit', Icons.edit_rounded, 'Edit'),
                tile('print', Icons.picture_as_pdf_rounded, 'Print PDF'),
                if (status != 'submitted')
                  tile(
                    'submitted',
                    Icons.error_outline_rounded,
                    'Mark as awaiting review',
                  ),
                if (status != 'reviewed')
                  tile(
                    'reviewed',
                    Icons.check_circle_rounded,
                    'Mark as reviewed',
                  ),
                if (status != 'archived')
                  tile('archived', Icons.archive_rounded, 'Archive'),
                tile(
                  'staff',
                  Icons.badge_rounded,
                  _record.staffName.trim().isEmpty
                      ? 'Link to a staff account'
                      : 'Change staff account',
                ),
                tile(
                  'delete',
                  Icons.delete_outline_rounded,
                  'Delete',
                  c: Brand.danger,
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'edit':
        await _edit();
      case 'print':
        await printEmploymentSheet(context, widget.service, _record.id);
      case 'submitted':
      case 'reviewed':
      case 'archived':
        await _setStatus(choice);
      case 'staff':
        await _linkStaff();
      case 'delete':
        await _delete();
    }
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    employmentToast(context, '$label copied');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final r = _record;
    final contacts = r.emergencyContacts;
    final deps = r.dependents;
    final name = r.fullName.trim().isEmpty ? 'Unnamed' : r.fullName;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: StationScaffold(
        stationLabel: 'Basic Employment Information Sheet',
        title: name,
        compact: true,
        showBottomBrand: false,
        onBack: _close,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StationAction(
              icon: Icons.edit_rounded,
              tooltip: 'Edit',
              onPressed: _edit,
            ),
            const SizedBox(width: 8),
            StationAction(
              icon: Icons.more_horiz_rounded,
              tooltip: 'More actions',
              onPressed: _actions,
            ),
          ],
        ),
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              GlassPanel(
                accent: employmentStatusColor(context, r.status),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Row(
                  children: [
                    AppAvatar(name: name, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: text.titleMedium?.copyWith(color: b.paper),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              r.field('job_title'),
                              r.field('work_location'),
                            ].where((s) => s.trim().isNotEmpty).join(' · '),
                            style: text.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: EmploymentStatusPill(
                                  key: ValueKey(r.status),
                                  status: r.status,
                                ),
                              ),
                              if (r.staffName.trim().isNotEmpty)
                                EmploymentGlowPill(
                                  label: r.staffName,
                                  color: Brand.info,
                                  icon: Icons.badge_rounded,
                                )
                              else if (r.staffLinkSkipped)
                                EmploymentGlowPill(
                                  label: 'Not a staff account',
                                  color: b.paperDim,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_busy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Employee information'),
              _Section(
                children: [
                  _InfoRow('Full name', r.field('full_name'), onCopy: _copy),
                  _InfoRow('Address', r.field('address'), onCopy: _copy),
                  _InfoRow(
                    'Birth place',
                    r.field('birth_place'),
                    onCopy: _copy,
                  ),
                  _InfoRow('Cell phone', r.field('cell_phone'), onCopy: _copy),
                  _InfoRow('Email address', r.field('email'), onCopy: _copy),
                  _InfoRow(
                    'SSS / Government ID',
                    r.field('government_id'),
                    onCopy: _copy,
                  ),
                  _InfoRow(
                    'Birth date',
                    employmentDate(r.field('birth_date')),
                    onCopy: _copy,
                  ),
                  _InfoRow(
                    'Marital status',
                    r.maritalStatus,
                    onCopy: _copy,
                    last: !r.isMarried,
                  ),
                  if (r.isMarried) ...[
                    _InfoRow(
                      "Spouse's name",
                      r.field('spouse_name'),
                      onCopy: _copy,
                    ),
                    _InfoRow(
                      "Spouse's employer",
                      r.field('spouse_employer'),
                      onCopy: _copy,
                    ),
                    _InfoRow(
                      "Spouse's work phone",
                      r.field('spouse_work_phone'),
                      onCopy: _copy,
                      last: true,
                    ),
                  ],
                ],
              ),
              if (!r.isMarried) ...[
                const SizedBox(height: 10),
                const EmploymentNotice(
                  'No legal spouse under the law — spouse fields not '
                  'applicable.',
                ),
              ],
              const SizedBox(height: 20),
              const SectionHeader(title: 'Job information'),
              _Section(
                children: [
                  _InfoRow('Title', r.field('job_title'), onCopy: _copy),
                  _InfoRow('Supervisor', r.field('supervisor'), onCopy: _copy),
                  _InfoRow(
                    'Work location',
                    r.field('work_location'),
                    onCopy: _copy,
                  ),
                  _InfoRow(
                    'E-mail address',
                    r.field('work_email'),
                    onCopy: _copy,
                  ),
                  _InfoRow('Work phone', r.field('work_phone'), onCopy: _copy),
                  _InfoRow(
                    'Cell phone',
                    r.field('work_cell_phone'),
                    onCopy: _copy,
                  ),
                  _InfoRow(
                    'Start date',
                    r.field('start_date').trim().isEmpty
                        ? ''
                        : employmentDate(r.field('start_date')),
                    onCopy: _copy,
                  ),
                  _InfoRow(
                    'Salary',
                    r.field('salary'),
                    onCopy: _copy,
                    last: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Emergency contacts'),
              if (contacts.isEmpty)
                const AppCard(child: _Muted('None recorded.'))
              else
                for (var i = 0; i < contacts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _Section(
                    title: 'Contact ${i + 1}',
                    children: [
                      _InfoRow(
                        'Full name',
                        contacts[i].fullName,
                        onCopy: _copy,
                      ),
                      _InfoRow('Address', contacts[i].address, onCopy: _copy),
                      _InfoRow(
                        'Primary phone',
                        contacts[i].primaryPhone,
                        onCopy: _copy,
                      ),
                      _InfoRow(
                        'Cell phone',
                        contacts[i].cellPhone,
                        onCopy: _copy,
                      ),
                      _InfoRow(
                        'Relationship',
                        contacts[i].relationship,
                        onCopy: _copy,
                        last: true,
                      ),
                    ],
                  ),
                ],
              const SizedBox(height: 20),
              const SectionHeader(
                title: 'Dependents (insurance purposes only)',
              ),
              if (r.hasNoDependents || deps.isEmpty)
                const AppCard(child: _Muted('No dependents declared.'))
              else
                _Section(
                  children: [
                    for (var i = 0; i < deps.length; i++)
                      _InfoRow(
                        deps[i].relationship.trim().isEmpty
                            ? 'Dependent'
                            : deps[i].relationship,
                        deps[i].name,
                        copyLabel: 'Dependent name',
                        onCopy: _copy,
                        last: i == deps.length - 1,
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              const SectionHeader(title: 'Submission'),
              _Section(
                children: [
                  _InfoRow('Status', employmentStatusLabel(r.status)),
                  _InfoRow('Submitted', employmentDateTime(r.createdAt)),
                  _InfoRow('Share link', r.linkLabel),
                  _InfoRow(
                    'Staff account',
                    r.staffName.trim().isNotEmpty
                        ? r.staffName
                        : (r.staffLinkSkipped ? 'Not a staff account' : ''),
                  ),
                  _InfoRow('Last updated by', r.reviewedByName, last: true),
                ],
              ),
              const SizedBox(height: 24),
              SignalButton(
                label: 'Print PDF',
                icon: Icons.picture_as_pdf_rounded,
                onPressed: () =>
                    printEmploymentSheet(context, widget.service, r.id),
              ),
              const SizedBox(height: 10),
              GhostButton(
                label: 'Edit',
                icon: Icons.edit_rounded,
                onPressed: _edit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return AppCard(
      radius: Brand.radiusLg,
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(
                title!,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: b.signalInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
    this.label,
    this.value, {
    this.onCopy,
    this.copyLabel,
    this.last = false,
  });

  final String label;
  final String value;
  final void Function(String label, String value)? onCopy;
  final String? copyLabel;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final v = value.trim();
    final has = v.isNotEmpty && v != '—';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: b.rule)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 118,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(label, style: text.bodySmall),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: SelectableText(
                  has ? v : '—',
                  style: text.bodyMedium?.copyWith(
                    color: has ? b.paper : b.paperDim,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (has && onCopy != null)
              IconButton(
                tooltip: 'Copy ${copyLabel ?? label}',
                icon: Icon(Icons.copy_rounded, size: 18, color: b.paperDim),
                onPressed: () => onCopy!(copyLabel ?? label, v),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class EmploymentNotice extends StatelessWidget {
  const EmploymentNotice(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: b.tint(Brand.orange, 0.10),
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: Brand.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: b.signalInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: b.signalInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(message, style: Theme.of(context).textTheme.bodySmall);
  }
}
