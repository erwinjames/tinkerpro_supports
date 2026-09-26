import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/activity_models.dart';
import '../services/activity_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'activity_common.dart';

const Color _dmColor = Color(0xFF6366F1);
const Color _groupColor = Color(0xFF14B8A6);

Color _typeColor(String type) => type == 'dm' ? _dmColor : _groupColor;

class ActivityConversationsTab extends StatefulWidget {
  const ActivityConversationsTab({
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
  State<ActivityConversationsTab> createState() =>
      _ActivityConversationsTabState();
}

enum _CvType { all, dm, group }

class _ActivityConversationsTabState extends State<ActivityConversationsTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<ConversationLog> _rows = const <ConversationLog>[];
  String _query = '';
  _CvType _type = _CvType.all;
  bool _loading = true;
  bool _started = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_onRefreshSignal);
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(covariant ActivityConversationsTab oldWidget) {
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
      final rows = await widget.service.conversations();
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

  String _typeLabel(_CvType t) {
    switch (t) {
      case _CvType.all:
        return 'All';
      case _CvType.dm:
        return 'Direct';
      case _CvType.group:
        return 'Group';
    }
  }

  List<ConversationLog> get _visible => _rows
      .where((r) {
        if (_type == _CvType.dm && r.type != 'dm') return false;
        if (_type == _CvType.group && r.type == 'dm') return false;
        if (_query.isEmpty) return true;
        return r.haystack.contains(_query);
      })
      .toList(growable: false);

  void _open(ConversationLog row) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _ConversationSheet(service: widget.service, conversation: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Name, topic, type…',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        ChoicePills<_CvType>(
          options: _CvType.values,
          value: _type,
          labelOf: _typeLabel,
          onChanged: (v) => setState(() => _type = v),
        ),
        const SizedBox(height: 12),
        SectionHeader(
          title: 'Conversations',
          trailing: Text(
            _loading ? '—' : '${rows.length} of ${_rows.length}',
            style: text.labelMedium,
          ),
        ),
        Expanded(
          child: ActivityFeedView<ConversationLog>(
            loading: _loading,
            error: _error,
            rows: rows,
            onRefresh: _load,
            resetToken: '$_query|$_type',
            footerNoun: 'conversations',
            emptyLabel: _rows.isEmpty
                ? 'No conversations'
                : 'No matching conversation',
            emptyHint: _rows.isEmpty
                ? 'No conversations yet. Pull down to refresh.'
                : 'Try a different name, topic or type.',
            emptyIcon: Icons.forum_outlined,
            itemBuilder: (context, row, i) => ActivityRise(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ConversationCard(row: row, onTap: () => _open(row)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.row, required this.onTap});

  final ConversationLog row;
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
              ActivityKindTile(
                icon: row.type == 'dm'
                    ? Icons.chat_bubble_outline_rounded
                    : Icons.forum_outlined,
                color: _typeColor(row.type),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      style: text.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (row.subtitle.isNotEmpty)
                      Text(
                        row.subtitle,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '#${row.id}',
                    style: text.labelSmall?.copyWith(
                      color: b.paperDim,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activityShortWhen(row.lastActivityAt),
                    style: text.labelMedium,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(label: row.typeLabel, color: _typeColor(row.type)),
              GlowBadge(
                label: '${row.memberCount} members',
                color: Brand.info,
                icon: Icons.group_outlined,
              ),
              GlowBadge(
                label: '${row.messageCount} messages',
                color: Brand.signal,
                icon: Icons.chat_outlined,
              ),
              if (row.ticketCount > 0)
                GlowBadge(
                  label: '${row.ticketCount} tickets',
                  color: Brand.warning,
                  icon: Icons.confirmation_number_outlined,
                ),
              if (row.fileCount > 0)
                GlowBadge(
                  label: '${row.fileCount} files',
                  color: Brand.success,
                  icon: Icons.attach_file_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversationSheet extends StatefulWidget {
  const _ConversationSheet({required this.service, required this.conversation});

  final ActivityService service;
  final ConversationLog conversation;

  @override
  State<_ConversationSheet> createState() => _ConversationSheetState();
}

class _ConversationSheetState extends State<_ConversationSheet> {
  ConversationActivity? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.conversationActivity(
        widget.conversation.id,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = activityErrorText(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.conversation;
    final text = Theme.of(context).textTheme;
    final data = _data;
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          GlassPanel(
            accent: _typeColor(row.type),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Conversation log',
                      style: text.labelMedium?.copyWith(
                        color: context.brand.signal,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                    StatusPill(
                      label: row.typeLabel,
                      color: _typeColor(row.type),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ActivityKindTile(
                      icon: row.type == 'dm'
                          ? Icons.chat_bubble_outline_rounded
                          : Icons.forum_outlined,
                      color: _typeColor(row.type),
                      size: 46,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.title,
                            style: text.titleLarge?.copyWith(
                              color: context.brand.paper,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Last activity ${activityLongWhen(row.lastActivityAt)}',
                            style: text.bodySmall,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 170, height: 14),
                  SizedBox(height: 12),
                  Skeleton(width: 230, height: 11),
                  SizedBox(height: 10),
                  Skeleton(width: 190, height: 11),
                ],
              ),
            )
          else if (data == null)
            AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _error ?? 'Could not load conversation.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  GhostButton(
                    label: 'Retry',
                    icon: Icons.refresh_rounded,
                    onPressed: _load,
                  ),
                ],
              ),
            )
          else ...[
            Row(
              children: [
                _stat(context, 'Tickets', data.tickets.length),
                const SizedBox(width: 8),
                _stat(context, 'Messages', data.totalMessages),
                const SizedBox(width: 8),
                _stat(context, 'Files', data.totalFiles),
                const SizedBox(width: 8),
                _stat(context, 'Members', data.participants.length),
              ],
            ),
            const SizedBox(height: 18),
            if (data.tickets.isNotEmpty) ...[
              _sectionHeader(context, 'Tickets', data.tickets.length),
              AppCard(
                radius: Brand.radiusLg,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (final t in data.tickets)
                      _row(
                        context,
                        icon: Icons.confirmation_number_outlined,
                        color: Brand.warning,
                        title:
                            '#${t.id} — ${t.subject.isEmpty ? '(no subject)' : t.subject}',
                        meta: [
                          t.statusLabel,
                          t.priority,
                          t.agent.isEmpty ? 'Unassigned' : t.agent,
                          activityLongWhen(t.createdAt),
                        ].where((e) => e.isNotEmpty).join(' · '),
                        isLast: identical(t, data.tickets.last),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            _sectionHeader(context, 'Members', data.participants.length),
            AppCard(
              radius: Brand.radiusLg,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: data.participants.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text('No participants.', style: text.bodySmall),
                    )
                  : Column(
                      children: [
                        for (final p in data.participants)
                          _row(
                            context,
                            icon: p.isStaff
                                ? Icons.support_agent_rounded
                                : Icons.person_outline_rounded,
                            color: p.isStaff ? Brand.info : Brand.signal,
                            title: p.name,
                            meta:
                                '${p.role.isEmpty ? 'guest' : p.role} · joined ${activityLongWhen(p.joinedAt)}',
                            isLast: identical(p, data.participants.last),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            if (data.files.isNotEmpty) ...[
              _sectionHeader(context, 'Recent files', data.files.length),
              AppCard(
                radius: Brand.radiusLg,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (final f in data.files)
                      _row(
                        context,
                        icon: Icons.attach_file_rounded,
                        color: Brand.success,
                        title: f.name.isEmpty ? 'file' : f.name,
                        meta: [
                          f.uploader.isEmpty ? 'unknown' : f.uploader,
                          activityLongWhen(f.createdAt),
                          f.sizeLabel,
                        ].where((e) => e.isNotEmpty).join(' · '),
                        isLast: identical(f, data.files.last),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
            _sectionHeader(
              context,
              data.totalMessages > data.messages.length
                  ? 'Messages (last ${data.messages.length})'
                  : 'Messages',
              data.messages.length,
            ),
            if (data.messages.isEmpty)
              AppCard(
                radius: Brand.radiusLg,
                child: Text('No messages yet.', style: text.bodySmall),
              )
            else
              AppCard(
                radius: Brand.radiusLg,
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    for (final m in data.messages) _message(context, m),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, int value) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: AppCard(
        radius: Brand.radiusLg,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Text(
              label,
              style: text.labelSmall?.copyWith(color: b.paperDim),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text('$value', style: text.titleMedium),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title, int count) {
    return SectionHeader(
      title: title,
      trailing: GlowBadge(label: '$count', color: context.brand.signal),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String meta,
    required bool isLast,
  }) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: b.rule)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: color, size: 30, iconSize: 15),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyMedium?.copyWith(
                    color: b.paper,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(meta, style: text.bodySmall, maxLines: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(BuildContext context, ConversationMessage m) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: m.sender.isEmpty ? '?' : m.sender, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.sender.isEmpty ? 'Unknown' : m.sender,
                        style: text.labelLarge?.copyWith(
                          color: b.paper,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      activityShortWhen(m.createdAt),
                      style: text.labelSmall?.copyWith(color: b.paperDim),
                    ),
                  ],
                ),
                if (m.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(m.body, style: text.bodySmall),
                ],
                if (m.attachments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in m.attachments)
                        GlowBadge(
                          label: a,
                          color: Brand.success,
                          icon: Icons.attach_file_rounded,
                        ),
                    ],
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
