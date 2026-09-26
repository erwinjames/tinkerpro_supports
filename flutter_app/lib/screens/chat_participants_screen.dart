import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_models.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

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
  State<ChatParticipantsScreen> createState() => _ChatParticipantsScreenState();
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

    if (d.type == 'group') return true;
    if (d.type == 'channel' && d.visibility == 'private') return true;
    return false;
  }

  bool get _canLeave {
    final d = _detail;
    if (d == null) return false;
    return d.type != 'dm';
  }

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
        builder: (_) =>
            _AddMembersScreen(service: widget.service, excludeIds: existingIds),
      ),
    );
    if (!mounted || picked == null || picked.isEmpty) return;

    setState(() => _busy = true);
    final added = await widget.service.addParticipants(
      widget.conversationId,
      picked,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (added.isNotEmpty) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ADDED ${added.length} MEMBER'
            '${added.length == 1 ? '' : 'S'}',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No members added')));
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.brand.surface,
        title: Text(
          'Delete conversation',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        content: Text(
          'This will permanently remove every message and attachment '
          'in this conversation for everyone. This cannot be undone.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'CANCEL',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'DELETE',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: Brand.signal),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final result = await widget.service.deleteConversation(
      widget.conversationId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      Navigator.of(context).pop(participantsResultLeft);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete · ${result.error ?? ""}'.trim()),
        ),
      );
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.brand.surface,
        title: Text(
          'Leave conversation',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        content: Text(
          'You will stop receiving messages here until you are added back.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'CANCEL',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'LEAVE',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: Brand.signal),
            ),
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
      Navigator.of(context).pop(_participantsResultLeft);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not leave')));
    }
  }

  String? _avatarUrl(String? rel) {
    if (rel == null || rel.isEmpty) return null;
    if (rel.startsWith('http')) return rel;
    final clean = rel.replaceAll(RegExp(r'^/+'), '');
    return '${widget.service.api.baseUrl}/$clean';
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final title = d?.name ?? 'Participants';
    final subLabel = d == null
        ? 'Members'
        : d.type == 'channel'
        ? 'Channel · ${d.visibility} members'
        : d.type == 'group'
        ? 'Group members'
        : 'Direct message';

    return StationScaffold(
      stationLabel: 'Chat',
      title: title,
      subtitle: subLabel,
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: _canAdd
          ? StationAction(
              icon: Icons.person_add_alt_rounded,
              tooltip: 'Add members',
              onPressed: _busy ? () {} : _addMembers,
            )
          : null,
      child: _loading
          ? const SkeletonList(count: 6)
          : d == null
          ? EmptyState(
              icon: Icons.cloud_off_rounded,
              label: 'Could not load',
              hint: 'Check your connection and try again.',
              action: GhostButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                onPressed: _load,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.topic != null && d.topic!.isNotEmpty) ...[
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.short_text_rounded,
                          size: 20,
                          color: b.paperDim,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(d.topic!, style: text.bodyMedium)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                SectionHeader(
                  title: 'Members',
                  trailing: GlowBadge(
                    label: '${d.participants.length}',
                    color: Brand.info,
                    icon: Icons.groups_2_rounded,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: d.participants.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = d.participants[i];
                      return _MemberRow(
                        member: p,
                        avatarUrl: _avatarUrl(p.avatar),
                        isMe: p.id == widget.myUserId,
                        liveOnline: widget.realtime.onlineUsers.value.contains(
                          p.id,
                        ),
                      );
                    },
                  ),
                ),
                if (_canLeave) ...[
                  const SizedBox(height: 12),
                  GhostButton(
                    label: _busy ? 'Working…' : 'Leave conversation',
                    icon: Icons.logout_rounded,
                    onPressed: _busy ? () {} : _leave,
                  ),
                ],
                if (_canDelete) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 48,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Brand.danger,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Brand.radius),
                        ),
                      ),
                      onPressed: _busy ? null : _delete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      label: Text(
                        _busy ? 'Working…' : 'Delete conversation',
                        style: text.labelLarge?.copyWith(
                          color: Brand.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

const String _participantsResultLeft = '__left__';
const String participantsResultLeft = _participantsResultLeft;

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isMe,
    required this.liveOnline,
    this.avatarUrl,
  });
  final ConversationMember member;
  final bool isMe;
  final bool liveOnline;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final online = liveOnline || member.isOnline;
    final seen = formatLastSeen(online: online, lastSeenAt: member.lastSeenAt);
    final role = member.role.trim();
    final roleLabel = role.isEmpty
        ? null
        : role[0].toUpperCase() + role.substring(1);
    return AppCard(
      padding: const EdgeInsets.all(14),
      radius: Brand.radiusLg,
      child: Row(
        children: [
          _PresenceAvatar(
            name: member.displayName,
            imageUrl: avatarUrl,
            online: online,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  [?roleLabel, ?seen].join(' · '),
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            const StatusPill(label: 'You', color: Brand.orange),
          ],
        ],
      ),
    );
  }
}

class _PresenceAvatar extends StatelessWidget {
  const _PresenceAvatar({
    required this.name,
    required this.online,
    this.imageUrl,
  });
  final String name;
  final bool online;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Semantics(
      label: online ? 'Online' : 'Offline',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppAvatar(name: name, size: 42, imageUrl: imageUrl),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? Brand.success : b.paperDim,
                border: Border.all(color: b.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMembersScreen extends StatefulWidget {
  const _AddMembersScreen({required this.service, required this.excludeIds});
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
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(search: v),
    );
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  String? _avatarUrl(String? rel) {
    if (rel == null || rel.isEmpty) return null;
    if (rel.startsWith('http')) return rel;
    final clean = rel.replaceAll(RegExp(r'^/+'), '');
    return '${widget.service.api.baseUrl}/$clean';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationLabel: 'Chat',
      title: 'Add members',
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.check_rounded,
        tooltip: 'Confirm',
        onPressed: () => Navigator.of(context).pop(_selected.toList()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _search,
            hint: 'Search staff to add',
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selected.isEmpty
                      ? 'No one selected'
                      : '${_selected.length} selected',
                  style: text.labelLarge?.copyWith(
                    color: _selected.isEmpty ? b.paperDim : b.paper,
                  ),
                ),
              ),
              if (_selected.isNotEmpty)
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const SkeletonList(count: 6)
                : _users.isEmpty
                ? const EmptyState(
                    icon: Icons.person_search_rounded,
                    label: 'No candidates',
                    hint: 'Everyone matching the search is already here.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final u = _users[i];
                      final selected = _selected.contains(u.id);
                      final role = u.role.trim();
                      final sub = [
                        if (role.isNotEmpty)
                          role[0].toUpperCase() + role.substring(1),
                        u.isOnline ? 'Online' : 'Offline',
                      ].join(' · ');
                      return Semantics(
                        selected: selected,
                        child: AppCard(
                          padding: const EdgeInsets.all(14),
                          radius: Brand.radiusLg,
                          color: selected ? b.tint(Brand.orange, 0.08) : null,
                          borderColor: selected ? Brand.orange : null,
                          onTap: () => _toggle(u.id),
                          child: Row(
                            children: [
                              _PresenceAvatar(
                                name: u.displayName,
                                imageUrl: _avatarUrl(u.avatar),
                                online: u.isOnline,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u.displayName,
                                      style: text.titleSmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      sub,
                                      style: text.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              AnimatedContainer(
                                duration:
                                    (MediaQuery.maybeOf(
                                          context,
                                        )?.disableAnimations ??
                                        false)
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? Brand.orange
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: selected ? Brand.orange : b.paperDim,
                                    width: 2,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: 12),
            SignalButton(
              label:
                  'Add ${_selected.length} member${_selected.length == 1 ? '' : 's'}',
              icon: Icons.person_add_alt_rounded,
              onPressed: () => Navigator.of(context).pop(_selected.toList()),
            ),
          ],
        ],
      ),
    );
  }
}
