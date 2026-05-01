import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_models.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Shows the member list for a non-DM conversation, with affordances to
/// add more (on groups + private channels) and to leave. Authorisation
/// rules live on the server — this screen just hides controls that
/// would always fail.
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

  @override
  State<ChatParticipantsScreen> createState() =>
      _ChatParticipantsScreenState();
}

class _ChatParticipantsScreenState extends State<ChatParticipantsScreen> {
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
    if (d == null) return false;
    // Per the Phase-2 authz matrix:
    //   group           → any participant
    //   private channel → any participant
    //   public channel  → rejected (use chat.joinChannel)
    //   dm              → rejected
    if (d.type == 'group') return true;
    if (d.type == 'channel' && d.visibility == 'private') return true;
    return false;
  }

  bool get _canLeave {
    final d = _detail;
    if (d == null) return false;
    return d.type != 'dm';
  }

  /// Per the server authz matrix:
  ///   DM      → either participant
  ///   group   → only the creator
  ///   channel → only the creator
  bool get _canDelete {
    final d = _detail;
    if (d == null) return false;
    if (d.type == 'dm') return true;
    return d.createdBy == widget.myUserId;
  }

  Future<void> _addMembers() async {
    if (_busy) return;
    final detail = _detail;
    if (detail == null) return;
    final existingIds = detail.participants.map((p) => p.id).toSet();

    final picked = await Navigator.of(context).push<List<int>>(
      MaterialPageRoute(
        builder: (_) => _AddMembersScreen(
          service: widget.service,
          excludeIds: existingIds,
        ),
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;

    setState(() => _busy = true);
    final added =
        await widget.service.addParticipants(widget.conversationId, picked);
    if (!mounted) return;
    setState(() => _busy = false);
    if (added.isNotEmpty) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('ADDED ${added.length} MEMBER'
                '${added.length == 1 ? '' : 'S'}')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('NO MEMBERS ADDED')),
      );
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        shape: const RoundedRectangleBorder(),
        title: Text('DELETE CONVERSATION',
            style: Theme.of(context).textTheme.labelLarge),
        content: Text(
          'This will permanently remove every message and attachment '
          'in this conversation for everyone. This cannot be undone.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('CANCEL',
                style: Theme.of(context).textTheme.labelMedium),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('DELETE',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Brand.signal)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result = await widget.service.deleteConversation(widget.conversationId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      // Same sentinel path as Leave — ChatThreadScreen pops itself back
      // to the inbox where the conversation.removed event has already
      // pruned the row.
      Navigator.of(context).pop(participantsResultLeft);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'COULD NOT DELETE · ${result.error?.toUpperCase() ?? ""}'.trim(),
        )),
      );
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        shape: const RoundedRectangleBorder(),
        title: Text('LEAVE CONVERSATION',
            style: Theme.of(context).textTheme.labelLarge),
        content: Text(
          'You will stop receiving messages here until you are added back.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('CANCEL',
                style: Theme.of(context).textTheme.labelMedium),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('LEAVE',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Brand.signal)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await widget.service.leaveConversation(widget.conversationId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      // Tell the caller we're out — ChatThreadScreen will pop itself to the
      // inbox, which in turn updates via the lifecycle event.
      Navigator.of(context).pop(_participantsResultLeft);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('COULD NOT LEAVE')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final title = d?.name ?? 'Participants';
    final subLabel = d == null
        ? 'CHAT · MEMBERS'
        : d.type == 'channel'
            ? 'CHANNEL · ${d.visibility.toUpperCase()} MEMBERS'
            : d.type == 'group'
                ? 'GROUP · MEMBERS'
                : 'DM · MEMBERS';

    return StationScaffold(
      stationNumber: '05',
      stationLabel: subLabel,
      title: title,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: _canAdd
          ? StationAction(
              icon: Icons.person_add_alt_outlined,
              tooltip: 'Add members',
              onPressed: _busy ? () {} : _addMembers,
            )
          : null,
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Brand.signal,
                ),
              ),
            )
          : d == null
              ? const EmptyState(
                  label: 'Could not load',
                  hint: 'Pull down to retry.',
                )
              : Column(
                  children: [
                    if (d.topic != null && d.topic!.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          d.topic!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Hairline(),
                    ],
                    Expanded(
                      child: ListView.separated(
                        itemCount: d.participants.length,
                        separatorBuilder: (_, _) => const Hairline(),
                        itemBuilder: (_, i) {
                          final p = d.participants[i];
                          return _MemberRow(
                            member: p,
                            isMe: p.id == widget.myUserId,
                            liveOnline:
                                widget.realtime.onlineUsers.value.contains(p.id),
                          );
                        },
                      ),
                    ),
                    if (_canLeave) ...[
                      const SizedBox(height: 12),
                      GhostButton(
                        label: _busy ? 'Working…' : 'Leave conversation',
                        onPressed: _busy ? () {} : _leave,
                      ),
                    ],
                    if (_canDelete) ...[
                      const SizedBox(height: 8),
                      GhostButton(
                        label: _busy ? 'Working…' : 'Delete conversation',
                        onPressed: _busy ? () {} : _delete,
                      ),
                    ],
                  ],
                ),
    );
  }
}

/// Sentinel result used by [ChatParticipantsScreen] when the user leaves
/// the conversation. The caller (ChatThreadScreen) checks for this and
/// pops itself back to the inbox.
const String _participantsResultLeft = '__left__';
const String participantsResultLeft = _participantsResultLeft;

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isMe,
    required this.liveOnline,
  });
  final ConversationMember member;
  final bool isMe;
  final bool liveOnline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final online = liveOnline || member.isOnline;
    final seen = formatLastSeen(
      online: online,
      lastSeenAt: member.lastSeenAt,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 7, right: 12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: online ? Brand.signal : Brand.rule,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(member.displayName, style: text.titleSmall),
                    ),
                    if (isMe)
                      Text('YOU',
                          style: text.labelMedium?.copyWith(
                            color: Brand.signal,
                          )),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [member.role.toUpperCase(), ?seen].join(' · '),
                  style: text.labelMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Add-members picker ─────────────────────────────

class _AddMembersScreen extends StatefulWidget {
  const _AddMembersScreen({
    required this.service,
    required this.excludeIds,
  });
  final ChatService service;
  final Set<int> excludeIds;

  @override
  State<_AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<_AddMembersScreen> {
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
    final users = await widget.service.directory(search: search);
    if (!mounted) return;
    setState(() {
      _users = users.where((u) => !widget.excludeIds.contains(u.id)).toList();
      _loading = false;
    });
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(search: v));
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '05',
      stationLabel: 'ADD MEMBERS',
      title: 'Pick teammates.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.check,
        tooltip: 'Confirm',
        onPressed: () => Navigator.of(context).pop(_selected.toList()),
      ),
      child: Column(
        children: [
          TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(labelText: 'SEARCH STAFF'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _selected.isEmpty
                  ? 'NO SELECTION'
                  : '${_selected.length} SELECTED',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Brand.signal,
                      ),
                    ),
                  )
                : _users.isEmpty
                    ? const EmptyState(
                        label: 'No candidates',
                        hint: 'Everyone matching the search is already here.',
                      )
                    : ListView.separated(
                        itemCount: _users.length,
                        separatorBuilder: (_, _) => const Hairline(),
                        itemBuilder: (_, i) {
                          final u = _users[i];
                          final selected = _selected.contains(u.id);
                          return InkWell(
                            onTap: () => _toggle(u.id),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(
                                        top: 7, right: 12),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: u.isOnline
                                          ? Brand.signal
                                          : Brand.rule,
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(u.displayName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall),
                                        const SizedBox(height: 3),
                                        Text(u.role.toUpperCase(),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    selected
                                        ? Icons.check_box_outlined
                                        : Icons.check_box_outline_blank,
                                    color: selected
                                        ? Brand.signal
                                        : Brand.paperDim,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
