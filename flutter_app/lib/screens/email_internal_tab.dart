import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/email_models.dart';
import '../services/email_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class InternalFilterOption {
  const InternalFilterOption({
    required this.value,
    required this.label,
    this.group = '',
    this.count,
  });

  final String value;
  final String label;
  final String group;
  final int? count;
}

List<InternalFilterOption> buildInternalFilterOptions(InternalFilters f) {
  final options = <InternalFilterOption>[
    const InternalFilterOption(value: 'all', label: 'All recipients'),
    const InternalFilterOption(
      value: 'staff',
      label: 'All staff',
      group: 'Staff accounts',
    ),
  ];
  for (final role in f.roles) {
    options.add(
      InternalFilterOption(
        value: 'role:${role.value}',
        label: prettyRole(role.value),
        group: 'Staff accounts',
        count: role.total,
      ),
    );
  }
  options.add(
    const InternalFilterOption(
      value: 'contacts',
      label: 'All added emails',
      group: 'Added emails',
    ),
  );
  for (final label in f.labels) {
    options.add(
      InternalFilterOption(
        value: 'label:${label.value}',
        label: label.value,
        group: 'Added emails',
        count: label.total,
      ),
    );
  }
  options.add(
    const InternalFilterOption(
      value: 'label:__none__',
      label: '— No label —',
      group: 'Added emails',
    ),
  );
  return options;
}

class InternalEmailTab extends StatefulWidget {
  const InternalEmailTab({
    super.key,
    required this.service,
    required this.refresh,
    required this.onCount,
    required this.onCompose,
  });

  final EmailService service;
  final ValueListenable<int> refresh;
  final ValueChanged<int?> onCount;
  final void Function(InternalRecipient? prefill) onCompose;

  @override
  State<InternalEmailTab> createState() => _InternalEmailTabState();
}

class _InternalEmailTabState extends State<InternalEmailTab> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  InternalRecipientPage _page = const InternalRecipientPage();
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(reload);
    _load();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(reload);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void reload() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final page = await widget.service.internalRecipients(
      search: _search.text.trim(),
      filter: _filter,
    );
    if (!mounted) return;
    setState(() {
      _page = page;
      _loading = false;
    });
    widget.onCount(page.totalRecords);
  }

  void _queueSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  String get _filterLabel {
    final options = buildInternalFilterOptions(_page.filters);
    for (final option in options) {
      if (option.value == _filter) return option.label;
    }
    return 'All recipients';
  }

  Future<void> _pickFilter() async {
    final options = buildInternalFilterOptions(_page.filters);
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final b = ctx.brand;
        final text = Theme.of(ctx).textTheme;
        String? lastGroup;
        final children = <Widget>[];
        for (final option in options) {
          if (option.group != lastGroup && option.group.isNotEmpty) {
            lastGroup = option.group;
            children.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Text(
                  option.group.toUpperCase(),
                  style: text.labelSmall?.copyWith(
                    color: b.paperDim,
                    letterSpacing: 0.9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }
          final selected = option.value == _filter;
          children.add(
            ListTile(
              minTileHeight: 48,
              leading: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? b.signal : b.paperDim,
              ),
              title: Text(option.label, style: text.titleSmall),
              trailing: option.count == null
                  ? null
                  : GlowBadge(label: '${option.count}', color: b.info),
              onTap: () => Navigator.of(ctx).pop(option.value),
            ),
          );
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Filter recipients', style: text.titleMedium),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(child: ListView(shrinkWrap: true, children: children)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked == null || picked == _filter) return;
    setState(() => _filter = picked);
    _load();
  }

  Future<void> _openContact(InternalRecipient? row) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ContactEditScreen(
          service: widget.service,
          draft: row == null
              ? const ContactDraft()
              : ContactDraft.fromRecipient(row),
          labels: _page.filters.labels,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _confirmDelete(InternalRecipient row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this email?'),
        content: Text(
          '${row.email} will be removed from the internal recipient list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove email'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.service.deleteContact(row.id);
    if (!mounted) return;
    _toast(
      res.ok ? 'Email removed' : (res.message ?? 'Could not remove email.'),
    );
    _load();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final rows = _page.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _search,
          hint: 'Search name, email, company',
          onSubmitted: (_) => _load(),
          onChanged: (_) => _queueSearch(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _FilterButton(label: _filterLabel, onTap: _pickFilter),
            ),
            const SizedBox(width: 10),
            _SquareAction(
              icon: Icons.person_add_alt_1_rounded,
              tooltip: 'Add email',
              onTap: () => _openContact(null),
            ),
          ],
        ),
        if (_page.contactsError.isNotEmpty) ...[
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.all(12),
            borderColor: Brand.warning.withValues(alpha: 0.4),
            color: b.tint(Brand.warning, 0.1),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: Brand.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Added emails are unavailable: ${_page.contactsError}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 7)
              : RefreshIndicator(
                  color: b.signal,
                  backgroundColor: b.surface,
                  onRefresh: _load,
                  child: rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 56),
                            EmptyState(
                              icon: Icons.admin_panel_settings_rounded,
                              label: 'No recipients yet',
                              hint:
                                  'Use Add Email to include someone '
                                  'without an account.',
                              action: GhostButton(
                                label: 'Add email',
                                icon: Icons.person_add_alt_1_rounded,
                                onPressed: () => _openContact(null),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 92),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _RecipientRow(
                            row: rows[i],
                            onSend: () => widget.onCompose(rows[i]),
                            onEdit: () => _openContact(rows[i]),
                            onDelete: () => _confirmDelete(rows[i]),
                          ),
                        ),
                ),
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Filter recipients, $label',
      child: Material(
        color: b.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          side: BorderSide(color: b.rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Icon(Icons.filter_list_rounded, size: 19, color: b.signal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall,
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: b.paperDim,
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

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: b.signal,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radiusSm),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, size: 20, color: Brand.onSignal),
          ),
        ),
      ),
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.row,
    required this.onSend,
    required this.onEdit,
    required this.onDelete,
  });

  final InternalRecipient row;
  final VoidCallback onSend;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final accent = row.isStaff ? b.signal : Brand.info;
    final tagText = row.isStaff ? prettyRole(row.tag) : row.tag;
    final subtitle = row.subtitle.isEmpty
        ? ''
        : (row.isStaff ? '@${row.subtitle}' : row.subtitle);
    return AppCard(
      radius: Brand.radiusLg,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      onTap: onSend,
      child: Row(
        children: [
          AppAvatar(name: row.displayName, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name.isEmpty ? '—' : row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: b.paper,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: b.paperDim),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusPill(
                      label: row.isStaff ? 'Staff' : 'Added',
                      color: accent,
                      icon: row.isStaff
                          ? Icons.verified_user_rounded
                          : Icons.person_add_alt_rounded,
                    ),
                    if (tagText.isNotEmpty)
                      GlowBadge(
                        label: tagText,
                        color: row.isStaff ? Brand.success : Brand.warning,
                      ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: Icon(Icons.more_vert_rounded, color: b.paperDim),
            onSelected: (v) {
              if (v == 'send') onSend();
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'send',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.send_rounded),
                  title: Text('Add to message'),
                ),
              ),
              if (row.isContact) ...[
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_rounded),
                    title: Text('Edit email'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: Brand.danger,
                    ),
                    title: Text(
                      'Delete email',
                      style: TextStyle(color: Brand.danger),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class ContactEditScreen extends StatefulWidget {
  const ContactEditScreen({
    super.key,
    required this.service,
    required this.draft,
    this.labels = const [],
  });

  final EmailService service;
  final ContactDraft draft;
  final List<RecipientTally> labels;

  @override
  State<ContactEditScreen> createState() => _ContactEditScreenState();
}

class _ContactEditScreenState extends State<ContactEditScreen> {
  late final TextEditingController _email;
  late final TextEditingController _name;
  late final TextEditingController _company;
  late final TextEditingController _label;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.draft.email);
    _name = TextEditingController(text: widget.draft.name);
    _company = TextEditingController(text: widget.draft.company);
    _label = TextEditingController(text: widget.draft.label);
    _notes = TextEditingController(text: widget.draft.notes);
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _company.dispose();
    _label.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _toast('An email address is required.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.saveContact(
      ContactDraft(
        id: widget.draft.id,
        name: _name.text.trim(),
        email: email,
        company: _company.text.trim(),
        label: _label.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      _toast(res.message ?? 'Email saved.');
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save email.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final editing = widget.draft.isEditing;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Internal Email',
      title: editing ? 'Edit Email' : 'Add Email',
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          const SectionHeader(title: 'Contact'),
          AppCard(
            radius: Brand.radiusLg,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Label('Email *'),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: 'name@example.com',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                _Label('Name'),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Full name',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                _Label('Company'),
                TextField(
                  controller: _company,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Business name',
                    prefixIcon: Icon(Icons.apartment_rounded),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Grouping'),
          AppCard(
            radius: Brand.radiusLg,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Label('Label'),
                TextField(
                  controller: _label,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Vendors, Partners, Resellers',
                    prefixIcon: Icon(Icons.sell_rounded),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Labels group these emails so you can blast just one set.',
                  style: text.bodySmall?.copyWith(color: b.paperDim),
                ),
                if (widget.labels.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final label in widget.labels)
                        ActionChip(
                          label: Text(label.value),
                          onPressed: () {
                            _label.text = label.value;
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                _Label('Notes'),
                TextField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Optional'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SignalButton(
            label: editing ? 'Save Changes' : 'Save Email',
            icon: Icons.save_rounded,
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}
