import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/announcement_admin_models.dart';
import '../models/announcement_models.dart';
import '../services/announcement_admin_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

const List<String> _kStatusTabs = <String>[
  'all',
  'active',
  'scheduled',
  'draft',
  'expired',
];

const Map<String, String> _kStatusTabLabels = <String, String>{
  'all': 'All',
  'active': 'Active',
  'scheduled': 'Scheduled',
  'draft': 'Drafts',
  'expired': 'Expired',
};

class AnnouncementsAdminScreen extends StatefulWidget {
  const AnnouncementsAdminScreen({super.key, required this.service});

  final AnnouncementAdminService service;

  @override
  State<AnnouncementsAdminScreen> createState() =>
      _AnnouncementsAdminScreenState();
}

class _AnnouncementsAdminScreenState extends State<AnnouncementsAdminScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;

  List<AdminAnnouncement> _items = const [];
  Map<String, int> _counts = const {};
  int _dbOffset = 0;
  String _status = 'all';
  String _query = '';
  bool _loading = true;
  String? _error;
  int _seq = 0;

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
    final seq = ++_seq;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await widget.service.list(status: _status, query: _query);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = page.items;
        _counts = page.counts;
        _dbOffset = page.dbOffsetSeconds;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = e is HttpException
            ? e.message
            : 'Could not load announcements.';
      });
    }
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _query = value.trim();
      _load();
    });
  }

  Future<void> _compose({AdminAnnouncement? existing}) async {
    AnnouncementDraft draft;
    if (existing == null) {
      draft = AnnouncementDraft();
    } else {
      try {
        final fresh = await widget.service.get(existing.id);
        draft = AnnouncementDraft.from(fresh, _dbOffset);
      } catch (_) {
        if (!mounted) return;
        _toast(context, 'Could not load that announcement.');
        return;
      }
    }
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AnnouncementComposerScreen(
          service: widget.service,
          draft: draft,
          dbOffsetSeconds: _dbOffset,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _toggle(AdminAnnouncement item) async {
    final next = item.isPublished ? 'draft' : 'published';
    try {
      await widget.service.setStatus(item.id, next);
      if (!mounted) return;
      _toast(
        context,
        next == 'published'
            ? 'Announcement published.'
            : 'Announcement unpublished.',
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      _toast(
        context,
        e is HttpException ? e.message : 'Could not update the announcement.',
      );
    }
  }

  Future<void> _delete(AdminAnnouncement item) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this announcement for good?'),
        content: Text(
          '“${item.title}” and every read record for it will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await widget.service.delete(item.id);
      if (!mounted) return;
      _toast(context, 'Announcement deleted.');
      _load();
    } catch (e) {
      if (!mounted) return;
      _toast(
        context,
        e is HttpException ? e.message : 'Could not delete the announcement.',
      );
    }
  }

  Future<void> _openReaders(AdminAnnouncement item) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReadersSheet(
        service: widget.service,
        announcement: item,
        dbOffsetSeconds: _dbOffset,
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '12',
      stationLabel: 'Super Admin',
      title: 'Announcements',
      subtitle: 'Everyone you pick sees this as a pop-up on their next visit',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add_rounded,
        tooltip: 'New announcement',
        onPressed: () => _compose(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoicePills<String>(
            options: _kStatusTabs,
            value: _status,
            labelOf: (s) => _kStatusTabLabels[s] ?? s,
            countOf: (s) => _counts[s],
            onChanged: (s) {
              if (s == _status) return;
              setState(() => _status = s);
              _load();
            },
          ),
          const SizedBox(height: 12),
          AppSearchField(
            controller: _searchController,
            hint: 'Search announcements',
            onChanged: _onSearch,
            onSubmitted: (v) {
              _searchTimer?.cancel();
              _query = v.trim();
              _load();
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList(count: 5)
                  : _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          label: 'Could not load announcements',
                          hint: _error!,
                          icon: Icons.cloud_off_rounded,
                          action: FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Try again'),
                          ),
                        ),
                      ],
                    )
                  : _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        EmptyState(
                          label: _query.isEmpty
                              ? 'No announcements yet'
                              : 'No announcements match that search',
                          hint: _query.isEmpty
                              ? 'Create your first one.'
                              : 'Try a different word from the title or body.',
                          icon: Icons.campaign_rounded,
                          action: _query.isEmpty
                              ? FilledButton.icon(
                                  onPressed: () => _compose(),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('New announcement'),
                                )
                              : null,
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: _items.length + 1,
                      separatorBuilder: (_, i) =>
                          SizedBox(height: i == 0 ? 12 : 10),
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return _BroadcastSummary(counts: _counts);
                        }
                        final item = _items[i - 1];
                        return _EntryFade(
                          index: i - 1,
                          child: _AnnouncementCard(
                            item: item,
                            dbOffsetSeconds: _dbOffset,
                            onEdit: () => _compose(existing: item),
                            onToggle: () => _toggle(item),
                            onDelete: () => _delete(item),
                            onReaders: () => _openReaders(item),
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

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.item,
    required this.dbOffsetSeconds,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onReaders,
  });

  final AdminAnnouncement item;
  final int dbOffsetSeconds;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onReaders;

  Color get _lifecycleColor {
    switch (item.lifecycle) {
      case 'active':
        return Brand.success;
      case 'scheduled':
        return Brand.info;
      case 'expired':
        return Brand.danger;
      default:
        return Brand.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final accent = item.toneColors.accent;
    return AppCard(
      radius: Brand.radiusLg,
      borderColor: item.isPublished
          ? _lifecycleColor.withValues(alpha: 0.35)
          : b.rule,
      padding: const EdgeInsets.all(14),
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: b.tint(accent),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accent.withValues(
                      alpha: item.isPublished ? 0.55 : 0.35,
                    ),
                  ),
                ),
                child: Icon(
                  announcementIconFor(item.icon),
                  size: 20,
                  color: b.isDark
                      ? accent
                      : Color.lerp(accent, const Color(0xFF0B1B2E), 0.2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: text.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _GlowPill(
                          label: item.lifecycleLabel,
                          color: _lifecycleColor,
                          dot: true,
                        ),
                        if (item.requireAck)
                          const _GlowPill(
                            label: 'Must acknowledge',
                            color: Brand.orange,
                            icon: Icons.verified_rounded,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.body,
            style: text.bodySmall,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          _MetaLine(
            icon: Icons.groups_rounded,
            label: item.audienceLabel.isEmpty
                ? 'Everyone on the team'
                : item.audienceLabel,
          ),
          const SizedBox(height: 4),
          _MetaLine(
            icon: Icons.visibility_rounded,
            label: '${item.readCount} of ${item.reach} read',
          ),
          const SizedBox(height: 6),
          _ReadMeter(
            value: item.readCount,
            total: item.reach,
            color: _lifecycleColor,
          ),
          const SizedBox(height: 6),
          _MetaLine(
            icon: Icons.event_rounded,
            label: item.windowLabel(dbOffsetSeconds),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _CardAction(
                icon: Icons.visibility_rounded,
                tooltip: 'Who has read this',
                onPressed: onReaders,
              ),
              _CardAction(
                icon: Icons.edit_rounded,
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
              _CardAction(
                icon: item.isPublished
                    ? Icons.pause_rounded
                    : Icons.send_rounded,
                tooltip: item.isPublished ? 'Unpublish' : 'Publish',
                color: item.isPublished ? b.paperDim : Brand.success,
                onPressed: onToggle,
              ),
              const Spacer(),
              _CardAction(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete',
                color: Brand.danger,
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
  const _MetaLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Row(
      children: [
        Icon(icon, size: 14, color: b.paperDim),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, size: 20, color: color ?? b.paperDim),
          ),
        ),
      ),
    );
  }
}

class AnnouncementComposerScreen extends StatefulWidget {
  const AnnouncementComposerScreen({
    super.key,
    required this.service,
    required this.draft,
    required this.dbOffsetSeconds,
  });

  final AnnouncementAdminService service;
  final AnnouncementDraft draft;
  final int dbOffsetSeconds;

  @override
  State<AnnouncementComposerScreen> createState() =>
      _AnnouncementComposerScreenState();
}

class _AnnouncementComposerScreenState
    extends State<AnnouncementComposerScreen> {
  late final AnnouncementDraft _draft = widget.draft;
  late final TextEditingController _title = TextEditingController(
    text: _draft.title,
  );
  late final TextEditingController _body = TextEditingController(
    text: _draft.body,
  );
  late final TextEditingController _linkUrl = TextEditingController(
    text: _draft.linkUrl,
  );
  late final TextEditingController _linkLabel = TextEditingController(
    text: _draft.linkLabel,
  );
  final _peopleSearch = TextEditingController();

  List<AnnouncementStaffPick> _staff = const [];
  String _staffError = '';
  bool _staffLoading = true;
  String _peopleQuery = '';
  int _reach = 0;
  Timer? _reachTimer;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadStaff();
    _refreshReach();
  }

  @override
  void dispose() {
    _reachTimer?.cancel();
    _title.dispose();
    _body.dispose();
    _linkUrl.dispose();
    _linkLabel.dispose();
    _peopleSearch.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    try {
      final rows = await widget.service.staff();
      if (!mounted) return;
      setState(() {
        _staff = rows;
        _staffLoading = false;
        _staffError = rows.isEmpty
            ? 'No staff accounts are available to pick.'
            : '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _staffLoading = false;
        _staffError = e is HttpException
            ? e.message
            : 'The staff list could not be loaded.';
      });
    }
  }

  void _refreshReach() {
    _reachTimer?.cancel();
    _reachTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final value = await widget.service.previewReach(
          audienceType: _draft.audienceType,
          roles: _draft.roles,
          users: _draft.users,
        );
        if (!mounted) return;
        setState(() => _reach = value);
      } catch (_) {}
    });
  }

  String get _reachLabel =>
      _reach == 1 ? 'Reaches 1 person' : 'Reaches $_reach people';

  Future<void> _pickMoment({required bool start}) async {
    final current = start ? _draft.startsAt : _draft.expiresAt;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? now),
    );
    if (!mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 0,
      time?.minute ?? 0,
    );
    setState(() {
      if (start) {
        _draft.startsAt = picked;
      } else {
        _draft.expiresAt = picked;
      }
    });
  }

  String _momentLabel(DateTime? value, String fallback) {
    if (value == null) return fallback;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _save(String status) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    _draft.title = _title.text;
    _draft.body = _body.text;
    _draft.linkUrl = _linkUrl.text;
    _draft.linkLabel = _linkLabel.text;

    final result = await widget.service.save(
      _draft,
      status: status,
      dbOffsetSeconds: widget.dbOffsetSeconds,
    );
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.message;
      });
      return;
    }
    _toast(
      context,
      status == 'published' ? 'Announcement published.' : 'Draft saved.',
    );
    Navigator.of(context).pop(true);
  }

  List<AnnouncementStaffPick> get _visiblePeople {
    if (_peopleQuery.isEmpty) return _staff;
    return _staff.where((p) => p.searchKey.contains(_peopleQuery)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final publishLabel = _draft.published ? 'Save & keep live' : 'Publish';
    return StationScaffold(
      stationNumber: '12',
      stationLabel: 'Super Admin',
      title: _draft.isNew ? 'New Announcement' : 'Edit Announcement',
      subtitle: 'Everyone you pick sees this as a pop-up on their next visit',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(false),
      bottomBar: Row(
        children: [
          Expanded(
            child: GhostButton(
              label: 'Save as draft',
              icon: Icons.drafts_rounded,
              onPressed: _busy ? () {} : () => _save('draft'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SignalButton(
              label: publishLabel,
              busy: _busy,
              icon: Icons.send_rounded,
              onPressed: _busy ? null : () => _save('published'),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          _ComposerPreview(
            title: _title,
            body: _body,
            tone: _draft.tone,
            iconKey: _draft.icon,
            requireAck: _draft.requireAck,
            reach: _reach,
            published: _draft.published,
          ),
          const SizedBox(height: 18),
          if (_error.isNotEmpty) ...[
            AppCard(
              color: b.tint(Brand.danger, 0.1),
              borderColor: Brand.danger,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: Brand.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error,
                      style: text.bodySmall?.copyWith(color: Brand.danger),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          const _FieldLabel('Title'),
          TextField(
            controller: _title,
            maxLength: 190,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'System maintenance this Saturday',
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Message'),
          TextField(
            controller: _body,
            maxLines: 6,
            minLines: 4,
            maxLength: 20000,
            decoration: const InputDecoration(
              hintText:
                  'Write the announcement here. Line breaks are kept as you '
                  'type them.',
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Tone'),
          DropdownButtonFormField<String>(
            initialValue: _draft.tone,
            items: [
              for (final entry in kAnnouncementTones.entries)
                DropdownMenuItem<String>(
                  value: entry.key,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AnnouncementTone.of(entry.key).accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(entry.value, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _draft.tone = v ?? 'info'),
          ),
          const SizedBox(height: 4),
          Text('Sets the colour of the pop-up.', style: text.bodySmall),
          const SizedBox(height: 14),
          const _FieldLabel('Icon'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in kAnnouncementIconKeys)
                _IconChoice(
                  icon: announcementIconFor(key),
                  selected: _draft.icon == key,
                  accent: AnnouncementTone.of(_draft.tone).accent,
                  onTap: () => setState(() => _draft.icon = key),
                ),
            ],
          ),
          const SizedBox(height: 18),
          const _FieldLabel('Who sees this'),
          ChoicePills<String>(
            options: const ['all', 'roles', 'users'],
            value: _draft.audienceType,
            labelOf: (v) => switch (v) {
              'roles' => 'By role',
              'users' => 'Specific people',
              _ => 'Everyone',
            },
            onChanged: (v) {
              setState(() => _draft.audienceType = v);
              _refreshReach();
            },
          ),
          if (_draft.audienceType == 'roles') ...[
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final entry in kAnnouncementStaffRoles.entries)
                    _CheckRow(
                      label: entry.value,
                      checked: _draft.roles.contains(entry.key),
                      onChanged: (on) {
                        setState(() {
                          if (on) {
                            _draft.roles.add(entry.key);
                          } else {
                            _draft.roles.remove(entry.key);
                          }
                        });
                        _refreshReach();
                      },
                    ),
                ],
              ),
            ),
          ],
          if (_draft.audienceType == 'users') ...[
            const SizedBox(height: 10),
            AppSearchField(
              controller: _peopleSearch,
              hint: 'Search people',
              onChanged: (v) =>
                  setState(() => _peopleQuery = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 10),
            if (_staffLoading)
              const SkeletonList(count: 3, avatar: false)
            else if (_staffError.isNotEmpty)
              AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Brand.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_staffError, style: text.bodySmall)),
                  ],
                ),
              )
            else if (_visiblePeople.isEmpty)
              Text('No one matches that search.', style: text.bodySmall)
            else
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final person in _visiblePeople)
                      _CheckRow(
                        label: person.name,
                        hint: person.roleLabel,
                        checked: _draft.users.contains(person.id),
                        onChanged: (on) {
                          setState(() {
                            if (on) {
                              _draft.users.add(person.id);
                            } else {
                              _draft.users.remove(person.id);
                            }
                          });
                          _refreshReach();
                        },
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 15, color: b.paperDim),
              const SizedBox(width: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  _reachLabel,
                  key: ValueKey(_reach),
                  style: text.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _FieldLabel('Show from'),
          _MomentRow(
            label: _momentLabel(_draft.startsAt, 'Start immediately'),
            hint: 'Leave blank to start immediately.',
            onPick: () => _pickMoment(start: true),
            onClear: _draft.startsAt == null
                ? null
                : () => setState(() => _draft.startsAt = null),
          ),
          const SizedBox(height: 14),
          const _FieldLabel('Stop showing'),
          _MomentRow(
            label: _momentLabel(_draft.expiresAt, 'No end date'),
            hint: 'Leave blank to keep it until everyone has read it.',
            onPick: () => _pickMoment(start: false),
            onClear: _draft.expiresAt == null
                ? null
                : () => setState(() => _draft.expiresAt = null),
          ),
          const SizedBox(height: 18),
          const _FieldLabel('Button link'),
          TextField(
            controller: _linkUrl,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'help or https://…',
              counterText: '',
            ),
          ),
          const SizedBox(height: 4),
          Text('Optional. Adds a button to the pop-up.', style: text.bodySmall),
          const SizedBox(height: 14),
          const _FieldLabel('Button label'),
          TextField(
            controller: _linkLabel,
            maxLength: 80,
            decoration: const InputDecoration(
              hintText: 'Read the guide',
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            radius: Brand.radiusLg,
            borderColor: _draft.requireAck
                ? Brand.orange.withValues(alpha: 0.4)
                : b.rule,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _draft.requireAck,
              onChanged: (v) => setState(() => _draft.requireAck = v),
              title: Text('Require acknowledgement', style: text.titleSmall),
              subtitle: Text(
                'The pop-up cannot be dismissed until they confirm they read '
                'it.',
                style: text.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: b.paperDim,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.accent,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final ink = b.isDark
        ? accent
        : Color.lerp(accent, const Color(0xFF0B1B2E), 0.2)!;
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedScale(
        scale: selected ? 1.06 : 1,
        duration: Duration(milliseconds: reduce ? 0 : 200),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: Duration(milliseconds: reduce ? 0 : 220),
          curve: Curves.easeOut,
          child: Material(
            color: selected ? b.tint(accent, 0.16) : b.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
              side: BorderSide(
                color: selected ? accent.withValues(alpha: 0.8) : b.rule,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: 46,
                height: 46,
                child: Icon(icon, size: 20, color: selected ? ink : b.paperDim),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.checked,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final String? hint;
  final bool checked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!checked),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Checkbox(value: checked, onChanged: (v) => onChanged(v == true)),
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
                    if (hint != null && hint!.isNotEmpty)
                      Text(hint!, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({
    required this.label,
    required this.hint,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String hint;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: onPick,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 18, color: b.paperDim),
                    const SizedBox(width: 10),
                    Expanded(child: Text(label, style: text.titleSmall)),
                    if (onClear != null)
                      IconButton(
                        tooltip: 'Clear',
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(hint, style: text.bodySmall),
      ],
    );
  }
}

class _ReadersSheet extends StatefulWidget {
  const _ReadersSheet({
    required this.service,
    required this.announcement,
    required this.dbOffsetSeconds,
  });

  final AnnouncementAdminService service;
  final AdminAnnouncement announcement;
  final int dbOffsetSeconds;

  @override
  State<_ReadersSheet> createState() => _ReadersSheetState();
}

class _ReadersSheetState extends State<_ReadersSheet> {
  List<AnnouncementReader> _readers = const [];
  int _reach = 0;
  bool _loading = true;
  String _error = '';
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.service.readers(widget.announcement.id);
      if (!mounted) return;
      setState(() {
        _readers = data.readers;
        _reach = data.reach;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is HttpException ? e.message : 'Could not load readers.';
      });
    }
  }

  Future<void> _reset() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset read status'),
        content: const Text(
          'Clear the read status so everyone sees this announcement again?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await widget.service.resetReads(widget.announcement.id);
      if (!mounted) return;
      _changed = true;
      _toast(context, 'Read status cleared.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _toast(
        context,
        e is HttpException ? e.message : 'Could not reset the read status.',
      );
    }
  }

  String _when(String raw) {
    final parsed = announcementFromDb(raw, widget.dbOffsetSeconds);
    if (parsed == null) return raw;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
        '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: b.canvas,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Brand.radiusLg),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: b.rule,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Who has read this', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              _loading
                  ? 'Loading…'
                  : '${_readers.length} of $_reach have read it',
              style: text.bodySmall,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45,
              ),
              child: _loading
                  ? const SkeletonList(count: 3, avatar: false)
                  : _error.isNotEmpty
                  ? EmptyState(
                      label: 'Could not load readers',
                      hint: _error,
                      icon: Icons.cloud_off_rounded,
                    )
                  : _readers.isEmpty
                  ? const EmptyState(
                      label: 'Nobody has opened this yet',
                      hint: 'Readers appear here as soon as the pop-up shows.',
                      icon: Icons.visibility_off_rounded,
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _readers.length,
                      separatorBuilder: (_, _) => const Hairline(),
                      itemBuilder: (_, i) {
                        final reader = _readers[i];
                        return ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 52),
                          child: Row(
                            children: [
                              AppAvatar(name: reader.displayName, size: 34),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            reader.displayName,
                                            style: text.titleSmall,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (reader.acknowledged) ...[
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.check_circle_rounded,
                                            size: 15,
                                            color: Brand.success,
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      _when(reader.readAt),
                                      style: text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GhostButton(
                    label: 'Reset read status',
                    icon: Icons.restart_alt_rounded,
                    onPressed: _reset,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SignalButton(
                    label: 'Close',
                    icon: null,
                    onPressed: () => Navigator.of(context).pop(_changed),
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

class _ReadMeter extends StatelessWidget {
  const _ReadMeter({
    required this.value,
    required this.total,
    required this.color,
  });

  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final ratio = total == 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Semantics(
      label: '$value of $total have read this',
      child: LayoutBuilder(
        builder: (context, c) => Container(
          height: 5,
          decoration: BoxDecoration(
            color: b.surfaceHi,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: reduce ? ratio : 0, end: ratio),
              duration: Duration(milliseconds: reduce ? 0 : 460),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => Container(
                width: c.maxWidth * t,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BroadcastSummary extends StatelessWidget {
  const _BroadcastSummary({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final active = counts['active'] ?? 0;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Broadcasts',
                  style: text.titleSmall?.copyWith(color: b.paper),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: active > 0
                    ? _GlowPill(
                        key: const ValueKey('on-air'),
                        label: 'On air',
                        color: Brand.success,
                        dot: true,
                      )
                    : const GlowBadge(
                        key: ValueKey('idle'),
                        label: 'Idle',
                        icon: Icons.bolt_rounded,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _CountStat(
                label: 'Active',
                value: active,
                icon: Icons.podcasts_rounded,
                color: Brand.success,
              ),
              const _GlassDivider(),
              _CountStat(
                label: 'Scheduled',
                value: counts['scheduled'] ?? 0,
                icon: Icons.schedule_rounded,
                color: Brand.info,
              ),
              const _GlassDivider(),
              _CountStat(
                label: 'Drafts',
                value: counts['draft'] ?? 0,
                icon: Icons.drafts_rounded,
                color: Brand.warning,
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
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: b.isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Brand.navy.withValues(alpha: 0.1),
    );
  }
}

class _CountStat extends StatelessWidget {
  const _CountStat({
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
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final style = text.titleLarge?.copyWith(
      color: b.paper,
      fontSize: 21,
      height: 1.1,
    );
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(height: 4),
          reduce
              ? Text('$value', style: style)
              : TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: value.toDouble()),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) =>
                      Text('${v.round()}', style: style),
                ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.labelSmall?.copyWith(color: b.paperDim),
          ),
        ],
      ),
    );
  }
}

class _ComposerPreview extends StatelessWidget {
  const _ComposerPreview({
    required this.title,
    required this.body,
    required this.tone,
    required this.iconKey,
    required this.requireAck,
    required this.reach,
    required this.published,
  });

  final TextEditingController title;
  final TextEditingController body;
  final String tone;
  final String iconKey;
  final bool requireAck;
  final int reach;
  final bool published;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final colors = AnnouncementTone.of(tone);
    final accent = colors.accent;
    final ink = b.isDark
        ? accent
        : Color.lerp(accent, const Color(0xFF0B1B2E), 0.22)!;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Live preview',
                style: text.labelLarge?.copyWith(
                  color: b.paperDim,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            _GlowPill(
              label: reach == 1 ? '1 person' : '$reach people',
              color: accent,
              icon: Icons.groups_rounded,
            ),
          ],
        ),
        const SizedBox(height: 8),
        GlassPanel(
          accent: accent,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: AnimatedBuilder(
            animation: Listenable.merge([title, body]),
            builder: (context, _) {
              final heading = title.text.trim();
              final message = body.text.trim();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: Duration(milliseconds: reduce ? 0 : 260),
                        curve: Curves.easeOut,
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          color: accent.withValues(alpha: 0.18),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: Duration(milliseconds: reduce ? 0 : 240),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim,
                            child: FadeTransition(opacity: anim, child: child),
                          ),
                          child: Icon(
                            announcementIconFor(iconKey),
                            key: ValueKey('$iconKey-$tone'),
                            size: 21,
                            color: ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              heading.isEmpty
                                  ? 'Your headline appears here'
                                  : heading,
                              style: text.titleMedium?.copyWith(
                                color: heading.isEmpty ? b.paperDim : b.paper,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            AnimatedSwitcher(
                              duration: Duration(
                                milliseconds: reduce ? 0 : 220,
                              ),
                              child: _GlowPill(
                                key: ValueKey(tone),
                                label:
                                    kAnnouncementTones[tone] ?? 'Information',
                                color: accent,
                                dot: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message.isEmpty
                        ? 'The message body shows here as your readers will '
                              'see it in the pop-up.'
                        : message,
                    style: text.bodySmall?.copyWith(
                      color: message.isEmpty ? b.paperDim : b.paper,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _GlowPill(
                        label: published ? 'Live now' : 'Not published',
                        color: published ? Brand.success : b.paperDim,
                        dot: true,
                      ),
                      if (requireAck)
                        const _GlowPill(
                          label: 'Must acknowledge',
                          color: Brand.orange,
                          icon: Icons.verified_rounded,
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
