import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_models.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chatflow_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import '../widgets/tp_loader.dart';

class ChatParticipantsScreen extends StatefulWidget {
  const ChatParticipantsScreen({
    super.key,
    required this.service,
    required this.realtime,
    required this.conversationId,
    required this.myUserId,
  });

  final ChatService service;
  final ChatRealtimeService realtime;
  final int conversationId;
  final int myUserId;

  static Future<Object?> show(
    BuildContext context, {
    required ChatService service,
    required ChatRealtimeService realtime,
    required int conversationId,
    required int myUserId,
  }) {
    return showDialog<Object?>(
      context: context,
      builder: (_) => ChatParticipantsScreen(
        service: service,
        realtime: realtime,
        conversationId: conversationId,
        myUserId: myUserId,
      ),
    );
  }

  @override
  State<ChatParticipantsScreen> createState() =>
      _ChatParticipantsScreenState();
}

class _ChatParticipantsScreenState extends State<ChatParticipantsScreen> {
  late final ChatflowService _flow = ChatflowService(widget.service.api);
  ConversationDetail? _detail;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.realtime.onlineUsers.addListener(_onPresenceChange);
  }

  @override
  void dispose() {
    widget.realtime.onlineUsers.removeListener(_onPresenceChange);
    super.dispose();
  }

  void _onPresenceChange() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await widget.service.conversation(widget.conversationId);
    if (!mounted) return;
    setState(() {
      _detail = d;
      _loading = false;
    });
  }

  bool get _canAdd {
    final d = _detail;
    if (d == null || d.type == 'dm') return false;
    return d.createdBy == widget.myUserId || d.type == 'group';
  }

  bool get _canRemove {
    final d = _detail;
    if (d == null || d.type == 'dm') return false;
    return d.participants.any(
      (p) => p.id == widget.myUserId && p.role.trim() == 'super_admin',
    );
  }

  Future<void> _remove(ConversationMember member) async {
    if (_busy) return;
    final confirmed = await showWebModal<bool>(
      context,
      title: 'Remove member?',
      icon: Icons.person_remove_alt_1_outlined,
      width: 460,
      builder: (ctx) => Text(
        '${member.displayName} will be removed from this conversation and stop receiving its messages.',
        style: Theme.of(ctx).textTheme.bodyMedium,
      ),
      actions: (ctx) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        DangerButton(label: 'Remove', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final r = await _flow.removeParticipant(widget.conversationId, member.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      await _load();
    } else {
      final m = (r.message ?? '').trim();
      _toast(m.isEmpty ? 'Could not remove member' : m);
    }
  }

  bool get _canLeave {
    final d = _detail;
    if (d == null) return false;
    return d.type != 'dm';
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addMembers() async {
    if (_busy) return;
    if (_detail == null) return;
    final picked = await showDialog<List<int>>(
      context: context,
      builder: (_) => _AddMembersModal(
        flow: _flow,
        conversationId: widget.conversationId,
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() => _busy = true);
    final r = await _flow.addParticipants(widget.conversationId, picked);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      await _load();
    } else {
      _toast('Could not add members');
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    final confirmed = await showWebModal<bool>(
      context,
      title: 'Leave this conversation?',
      icon: Icons.warning_amber_rounded,
      width: 460,
      builder: (ctx) => Text(
        'You will be removed from it and stop receiving its messages.',
        style: Theme.of(ctx).textTheme.bodyMedium,
      ),
      actions: (ctx) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
        DangerButton(label: 'Leave', onPressed: () => Navigator.pop(ctx, true)),
      ],
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final r = await _flow.leaveConversation(widget.conversationId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.of(context).pop(participantsResultLeft);
    } else {
      _toast('Could not leave');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final text = Theme.of(context).textTheme;
    const title = 'Members';
    final subtitle = d == null
        ? 'Conversation members'
        : d.type == 'channel'
            ? '${d.visibility == 'private' ? 'Private' : 'Public'} channel · ${d.participants.length} members'
            : d.type == 'group'
                ? 'Group · ${d.participants.length} members'
                : 'Direct message';

    return WebModal(
      title: title,
      subtitle: subtitle,
      icon: Icons.group_outlined,
      width: 600,
      height: 620,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        if (_canLeave)
          GhostButton(
            label: 'Leave',
            icon: Icons.logout,
            onPressed: _busy ? null : _leave,
          ),
        if (_canAdd)
          SignalButton(
            label: 'Add members',
            icon: Icons.person_add_alt_1_outlined,
            busy: _busy,
            onPressed: _busy ? null : _addMembers,
          ),
        GhostButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: _loading
          ? const Center(child: TpLoader())
          : d == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const EmptyState(
                      icon: Icons.error_outline,
                      label: 'Could not load members',
                      hint: 'Check your connection and try again.',
                    ),
                    GhostButton(
                      label: 'Retry',
                      icon: Icons.refresh,
                      onPressed: _load,
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (d.topic != null &&
                        d.topic!.isNotEmpty &&
                        !d.topic!.contains(':'))
                      Container(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                        decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: context.brand.rule)),
                        ),
                        child: Text(d.topic!, style: text.bodyMedium),
                      ),
                    Expanded(
                      child: ColumnResizeScope(
                        tableId: 'chat:members',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            WebTableHeader(cells: [
                              const Expanded(child: Text('MEMBER')),
                              const SizedBox(width: 120, child: Text('ROLE')),
                              const SizedBox(width: 130, child: Text('STATUS')),
                              if (_canRemove) const SizedBox(width: 44),
                            ]),
                            Expanded(
                              child: ListView.builder(
                                itemCount: d.participants.length,
                                itemBuilder: (_, i) {
                                  final p = d.participants[i];
                                  return _MemberRow(
                                    member: p,
                                    isMe: p.id == widget.myUserId,
                                    liveOnline: widget
                                        .realtime.onlineUsers.value
                                        .contains(p.id),
                                    showRemove: _canRemove,
                                    onRemove: _canRemove && p.id != widget.myUserId
                                        ? (_busy ? null : () => _remove(p))
                                        : null,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

const String participantsResultLeft = '__left__';

String _roleLabel(String role) {
  final r = role.trim().replaceAll('_', ' ');
  if (r.isEmpty) return '—';
  return r
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.name, required this.online});
  final String name;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final initial = t.isEmpty ? '?' : t[0].toUpperCase();
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Brand.signal,
            ),
            child: Text(initial,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? Brand.success : const Color(0xFFCBD5E1),
                border: Border.all(color: context.brand.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isMe,
    required this.liveOnline,
    this.showRemove = false,
    this.onRemove,
  });
  final ConversationMember member;
  final bool isMe;
  final bool liveOnline;
  final bool showRemove;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final online = liveOnline || member.isOnline;
    final seen = formatLastSeen(
      online: online,
      lastSeenAt: member.lastSeenAt,
    );
    final status = online
        ? 'Online'
        : seen == null
            ? 'Offline'
            : 'Seen ${seen.toLowerCase()}';
    return WebTableRow(
      cells: [
        Expanded(
          child: Row(
            children: [
              _MemberAvatar(name: member.displayName, online: online),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 8),
                const StatusPill(label: 'You', color: Brand.signal),
              ],
            ],
          ),
        ),
        SizedBox(
          width: 120,
          child: Text(_roleLabel(member.role), style: text.bodySmall),
        ),
        SizedBox(
          width: 130,
          child: Text(
            status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(
              color: online ? Brand.success : null,
              fontWeight: online ? FontWeight.w600 : null,
            ),
          ),
        ),
        if (showRemove)
          SizedBox(
            width: 44,
            child: isMe
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Remove from group',
                    icon: const Icon(Icons.person_remove_alt_1_outlined,
                        size: 18, color: Brand.danger),
                    onPressed: onRemove,
                  ),
          ),
      ],
    );
  }
}

class _AddMembersModal extends StatefulWidget {
  const _AddMembersModal({required this.flow, required this.conversationId});
  final ChatflowService flow;
  final int conversationId;

  @override
  State<_AddMembersModal> createState() => _AddMembersModalState();
}

class _AddMembersModalState extends State<_AddMembersModal> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ChatUser> _users = const [];
  final Set<int> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({String? search}) async {
    setState(() => _loading = true);
    final users = await widget.flow.directoryFor(
      widget.conversationId,
      search: search,
    );
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce =
        Timer(const Duration(milliseconds: 350), () => _load(search: v));
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return WebModal(
      title: 'Add members',
      icon: Icons.person_add_alt_1_outlined,
      width: 560,
      height: 600,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        SignalButton(
          label: 'Add',
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: SearchField(
              controller: _search,
              hint: 'Search staff',
              width: null,
              autofocus: true,
              onChanged: _onSearchChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              _selected.isEmpty
                  ? 'NO MEMBERS SELECTED'
                  : '${_selected.length} SELECTED',
              style: text.bodySmall,
            ),
          ),
          Divider(height: 1, color: context.brand.rule),
          Expanded(
            child: _loading
                ? const Center(child: TpLoader())
                : _users.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (_, i) {
                          final u = _users[i];
                          final selected = _selected.contains(u.id);
                          return WebTableRow(
                            selected: selected,
                            onTap: () => _toggle(u.id),
                            cells: [
                              _MemberAvatar(
                                  name: u.displayName, online: u.isOnline),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(u.displayName,
                                        style: text.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w600)),
                                    Text(_roleLabel(u.role),
                                        style: text.bodySmall),
                                  ],
                                ),
                              ),
                              Checkbox(
                                value: selected,
                                onChanged: (_) => _toggle(u.id),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
