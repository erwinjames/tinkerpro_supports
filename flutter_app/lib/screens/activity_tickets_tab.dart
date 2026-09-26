import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/activity_models.dart';
import '../services/activity_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'activity_common.dart';

const Map<String, Color> _statusColors = {
  'new': Color(0xFF3B82F6),
  'assigned': Color(0xFF8B5CF6),
  'in_progress': Color(0xFFF59E0B),
  'resolved': Color(0xFF10B981),
  'closed': Color(0xFF6B7280),
};

const Map<String, Color> _priorityColors = {
  'low': Color(0xFF10B981),
  'medium': Color(0xFFF59E0B),
  'high': Color(0xFFEF4444),
};

Color _statusColor(String status) =>
    _statusColors[status] ?? const Color(0xFF3B82F6);

Color _priorityColor(String priority) =>
    _priorityColors[priority] ?? const Color(0xFFF59E0B);

class ActivityTicketsTab extends StatefulWidget {
  const ActivityTicketsTab({
    super.key,
    required this.service,
    required this.active,
    required this.refresh,
    required this.onCount,
  });

  final ActivityService service;
  final bool active;
  final ValueListenable<int> refresh;
  final ActivityCountSink onCount;

  @override
  State<ActivityTicketsTab> createState() => _ActivityTicketsTabState();
}

class _ActivityTicketsTabState extends State<ActivityTicketsTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<TicketLog> _rows = const <TicketLog>[];
  String _query = '';
  String _status = '';
  String _priority = '';
  bool _loading = true;
  bool _started = false;
  String? _error;

  static const List<String> _statuses = [
    'new',
    'assigned',
    'in_progress',
    'resolved',
    'closed',
  ];
  static const List<String> _priorities = ['low', 'medium', 'high'];

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_onRefreshSignal);
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(covariant ActivityTicketsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refresh != oldWidget.refresh) {
      oldWidget.refresh.removeListener(_onRefreshSignal);
      widget.refresh.addListener(_onRefreshSignal);
    }
    if (widget.active && !_started) _activate();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_onRefreshSignal);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _activate() {
    _started = true;
    _load();
  }

  void _onRefreshSignal() {
    if (!mounted || !widget.active) return;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = _rows.isEmpty);
    try {
      final rows = await widget.service.tickets();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
      widget.onCount(rows.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = activityErrorText(e);
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value.trim().toLowerCase());
    });
  }

  List<TicketLog> get _visible => _rows
      .where((r) {
        if (_status.isNotEmpty && r.status != _status) return false;
        if (_priority.isNotEmpty && r.priority != _priority) return false;
        if (_query.isEmpty) return true;
        return r.haystack.contains(_query);
      })
      .toList(growable: false);

  String _statusLabel(String value) {
    if (value == 'in_progress') return 'In progress';
    if (value.isEmpty) return 'All';
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _priorityLabel(String value) {
    if (value.isEmpty) return 'All';
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  void _open(TicketLog row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ActivityDetailSheet(
        service: widget.service,
        eyebrow: widget.service.isSuperAdmin ? 'Ticket trace' : 'Ticket',
        title: '#${row.id} — ${row.subjectLabel}',
        subtitle: 'Filed ${activityLongWhen(row.createdAt)}',
        icon: Icons.confirmation_number_outlined,
        color: _statusColor(row.status),
        pills: [
          StatusPill(label: row.statusLabel, color: _statusColor(row.status)),
          StatusPill(
            label: row.priorityLabel,
            color: _priorityColor(row.priority),
          ),
        ],
        note: row.description,
        noteLabel: 'Description',
        groups: [
          ActivityDetailGroup('Ticket', [
            ActivityDetailField('Ticket ID', '#${row.id}'),
            ActivityDetailField('Subject', row.subjectLabel),
            ActivityDetailField('Status', row.statusLabel),
            ActivityDetailField('Priority', row.priorityLabel),
            ActivityDetailField('Filed', activityLongWhen(row.createdAt)),
            ActivityDetailField('Updated', activityLongWhen(row.updatedAt)),
          ]),
          ActivityDetailGroup('Customer', [
            ActivityDetailField('Name', row.customerName),
            ActivityDetailField('Business', row.businessName),
            ActivityDetailField('VAT registered', row.vatReg ? 'Yes' : 'No'),
            ActivityDetailField(
              'Conversation',
              row.conversationId > 0 ? '#${row.conversationId}' : '—',
            ),
          ]),
          ActivityDetailGroup('Assignment', [
            ActivityDetailField(
              'Agent',
              row.assigned ? row.agentLabel : 'Unassigned',
            ),
            ActivityDetailField(
              'Username',
              row.agentUsername.isEmpty ? '—' : '@${row.agentUsername}',
            ),
          ]),
        ],
        traceQuery: {'subject': 'ticket', 'ticket_id': '${row.id}'},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = _visible;
    final filtered = _status.isNotEmpty || _priority.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Subject, customer, business, agent…',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ActivityFilterMenu(
                icon: Icons.flag_outlined,
                label: 'All statuses',
                value: _status,
                options: _statuses,
                labelOf: _statusLabel,
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActivityFilterMenu(
                icon: Icons.priority_high_rounded,
                label: 'All priorities',
                value: _priority,
                options: _priorities,
                labelOf: _priorityLabel,
                onChanged: (v) => setState(() => _priority = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionHeader(
          title: 'Tickets',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loading ? '—' : '${rows.length} of ${_rows.length}',
                style: text.labelMedium,
              ),
              if (filtered) ...[
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Reset filters',
                  child: InkWell(
                    onTap: () => setState(() {
                      _status = '';
                      _priority = '';
                    }),
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.filter_alt_off_rounded,
                        size: 18,
                        color: context.brand.signal,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ActivityFeedView<TicketLog>(
            loading: _loading,
            error: _error,
            rows: rows,
            onRefresh: _load,
            resetToken: '$_query|$_status|$_priority',
            footerNoun: 'tickets',
            emptyLabel: _rows.isEmpty ? 'No tickets' : 'No matching ticket',
            emptyHint: _rows.isEmpty
                ? 'No tickets yet. Pull down to refresh.'
                : 'Try a different search, status or priority.',
            emptyIcon: Icons.confirmation_number_outlined,
            itemBuilder: (context, row, i) => ActivityRise(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TicketCard(row: row, onTap: () => _open(row)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.row, required this.onTap});

  final TicketLog row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '#${row.id}',
                style: text.labelMedium?.copyWith(
                  color: b.paperDim,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.subjectLabel,
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(activityShortWhen(row.createdAt), style: text.labelMedium),
            ],
          ),
          if (row.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              row.description,
              style: text.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(
                label: row.statusLabel,
                color: _statusColor(row.status),
              ),
              StatusPill(
                label: row.priorityLabel,
                color: _priorityColor(row.priority),
              ),
              GlowBadge(
                label: row.assigned ? row.agentLabel : 'unassigned',
                color: row.assigned ? Brand.info : const Color(0xFF64748B),
                icon: Icons.person_outline_rounded,
              ),
            ],
          ),
          if (row.customerName.isNotEmpty || row.businessName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.badge_outlined, size: 13, color: b.paperDim),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    [
                      if (row.customerName.isNotEmpty) row.customerName,
                      if (row.businessName.isNotEmpty) row.businessName,
                    ].join(' · '),
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
