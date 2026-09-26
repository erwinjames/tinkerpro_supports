import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_models.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class ChatNewConversationScreen extends StatefulWidget {
  const ChatNewConversationScreen({super.key, required this.service});
  final ChatService service;

  @override
  State<ChatNewConversationScreen> createState() =>
      _ChatNewConversationScreenState();
}

class _ChatNewConversationScreenState extends State<ChatNewConversationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationLabel: 'Chat',
      title: 'New conversation',
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: b.surfaceHi,
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
            child: TabBar(
              controller: _tabs,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: b.isDark ? const Color(0xFF12304F) : Brand.navy,
                borderRadius: BorderRadius.circular(Brand.radiusSm + 1),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: b.paperDim,
              labelStyle: text.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: text.labelLarge,
              dividerColor: Colors.transparent,
              splashBorderRadius: BorderRadius.circular(Brand.radiusSm + 1),
              tabs: const [
                Tab(
                  height: 40,
                  child: _TabLabel(
                    icon: Icons.person_outline_rounded,
                    label: 'Direct',
                  ),
                ),
                Tab(
                  height: 40,
                  child: _TabLabel(
                    icon: Icons.groups_2_outlined,
                    label: 'Group',
                  ),
                ),
                Tab(
                  height: 40,
                  child: _TabLabel(icon: Icons.tag_rounded, label: 'Channel'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _DMPickerTab(service: widget.service),
                _GroupComposerTab(service: widget.service),
                _ChannelBrowserTab(service: widget.service),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _DMPickerTab extends StatefulWidget {
  const _DMPickerTab({required this.service});
  final ChatService service;

  @override
  State<_DMPickerTab> createState() => _DMPickerTabState();
}

class _DMPickerTabState extends State<_DMPickerTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ChatUser> _users = const [];
  bool _loading = true;
  bool _starting = false;

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
      _users = users;
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

  Future<void> _start(ChatUser u) async {
    if (_starting) return;
    setState(() => _starting = true);
    final convId = await widget.service.createDirect(u.id);
    if (!mounted) return;
    setState(() => _starting = false);
    if (convId != null) {
      Navigator.of(context).pop(convId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start conversation')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _search,
          hint: 'Search staff by name',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 7)
              : _users.isEmpty
              ? const EmptyState(
                  icon: Icons.person_search_rounded,
                  label: 'No staff found',
                  hint: 'Try a different name or username.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _StaffRow(
                    user: _users[i],
                    avatarUrl: _avatarFor(widget.service, _users[i]),
                    onTap: _starting ? null : () => _start(_users[i]),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: context.brand.paperDim,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

String? _avatarFor(ChatService service, ChatUser u) {
  final rel = u.avatar;
  if (rel == null || rel.isEmpty) return null;
  if (rel.startsWith('http')) return rel;
  final clean = rel.replaceAll(RegExp(r'^/+'), '');
  return '${service.api.baseUrl}/$clean';
}

class _GroupComposerTab extends StatefulWidget {
  const _GroupComposerTab({required this.service});
  final ChatService service;

  @override
  State<_GroupComposerTab> createState() => _GroupComposerTabState();
}

class _GroupComposerTabState extends State<_GroupComposerTab> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  Timer? _debounce;
  List<ChatUser> _users = const [];
  final Set<int> _selected = {};
  final Map<int, ChatUser> _picked = {};
  bool _loading = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load({String? search}) async {
    setState(() => _loading = true);
    final users = await widget.service.directory(search: search);
    if (!mounted) return;
    setState(() {
      _users = users;
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

  void _toggle(ChatUser u) {
    setState(() {
      if (_selected.remove(u.id)) {
        _picked.remove(u.id);
      } else {
        _selected.add(u.id);
        _picked[u.id] = u;
      }
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group name required')));
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add at least one member')));
      return;
    }
    setState(() => _creating = true);
    final convId = await widget.service.createGroup(name, _selected.toList());
    if (!mounted) return;
    setState(() => _creating = false);
    if (convId != null) {
      Navigator.of(context).pop(convId);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not create group')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final picked = _picked.values.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Group name',
            prefixIcon: Icon(Icons.groups_2_outlined, size: 21),
          ),
          style: text.bodyLarge,
        ),
        const SizedBox(height: 12),
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
                    ? 'No members selected'
                    : '${_selected.length} member${_selected.length == 1 ? '' : 's'} selected',
                style: text.labelLarge?.copyWith(
                  color: _selected.isEmpty ? b.paperDim : b.paper,
                ),
              ),
            ),
            if (_selected.isNotEmpty)
              TextButton(
                onPressed: () => setState(() {
                  _selected.clear();
                  _picked.clear();
                }),
                child: const Text('Clear'),
              ),
          ],
        ),
        if (picked.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: picked.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final u = picked[i];
                return InputChip(
                  avatar: AppAvatar(
                    name: u.displayName,
                    size: 24,
                    imageUrl: _avatarFor(widget.service, u),
                  ),
                  label: Text(u.displayName),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  deleteButtonTooltipMessage: 'Remove ${u.displayName}',
                  onDeleted: () => _toggle(u),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 6)
              : _users.isEmpty
              ? const EmptyState(
                  icon: Icons.person_search_rounded,
                  label: 'No staff found',
                  hint: 'Try a different name or username.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    final on = _selected.contains(u.id);
                    return _StaffRow(
                      user: u,
                      avatarUrl: _avatarFor(widget.service, u),
                      selected: on,
                      onTap: () => _toggle(u),
                      trailing: _SelectMark(selected: on),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        SignalButton(
          label: _creating
              ? 'Creating…'
              : (_selected.isEmpty
                    ? 'Create group'
                    : 'Create group (${_selected.length})'),
          icon: Icons.group_add_rounded,
          busy: _creating,
          onPressed: _creating ? null : _create,
        ),
      ],
    );
  }
}

class _SelectMark extends StatelessWidget {
  const _SelectMark({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedContainer(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? Brand.orange : Colors.transparent,
        border: Border.all(
          color: selected ? Brand.orange : b.paperDim,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : null,
    );
  }
}

class _ChannelBrowserTab extends StatefulWidget {
  const _ChannelBrowserTab({required this.service});
  final ChatService service;

  @override
  State<_ChannelBrowserTab> createState() => _ChannelBrowserTabState();
}

class _ChannelBrowserTabState extends State<_ChannelBrowserTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ChannelBrief> _channels = const [];
  bool _loading = true;
  bool _busy = false;

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
    final rows = await widget.service.channels(search: search);
    if (!mounted) return;
    setState(() {
      _channels = rows;
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

  Future<void> _join(ChannelBrief c) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await widget.service.joinChannel(c.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.of(context).pop(c.id);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not join')));
    }
  }

  Future<void> _showCreate() async {
    if (_busy) return;
    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: context.brand.surface,
      isScrollControlled: true,
      builder: (_) => _CreateChannelSheet(service: widget.service),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.of(context).pop(result);
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppSearchField(
                controller: _search,
                hint: 'Search channels',
                onChanged: _onSearchChanged,
              ),
            ),
            const SizedBox(width: 10),
            AppIconButton(
              icon: Icons.add_rounded,
              tooltip: 'Create channel',
              color: Brand.orange,
              size: 48,
              onPressed: _busy ? null : _showCreate,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 6)
              : _channels.isEmpty
              ? EmptyState(
                  icon: Icons.tag_rounded,
                  label: 'No channels',
                  hint: 'Create one to get started.',
                  action: GhostButton(
                    label: 'Create channel',
                    icon: Icons.add_rounded,
                    onPressed: _showCreate,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _channels.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ChannelRow(
                    channel: _channels[i],
                    onTap: _busy
                        ? null
                        : () {
                            final c = _channels[i];
                            if (c.joined) {
                              Navigator.of(context).pop(c.id);
                            } else if (c.isPrivate) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Private — ask a member to add you',
                                  ),
                                ),
                              );
                            } else {
                              _join(c);
                            }
                          },
                  ),
                ),
        ),
      ],
    );
  }
}

class _CreateChannelSheet extends StatefulWidget {
  const _CreateChannelSheet({required this.service});
  final ChatService service;

  @override
  State<_CreateChannelSheet> createState() => _CreateChannelSheetState();
}

class _CreateChannelSheetState extends State<_CreateChannelSheet> {
  final _name = TextEditingController();
  final _topic = TextEditingController();
  String _visibility = 'public';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Channel name required')));
      return;
    }
    setState(() => _busy = true);
    final id = await widget.service.createChannel(
      name: name,
      topic: _topic.text.trim().isEmpty ? null : _topic.text.trim(),
      visibility: _visibility,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const IconTile(icon: Icons.tag_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New channel', style: text.titleLarge),
                        Text(
                          'Topic-based space for your team',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Channel name',
                  prefixIcon: Icon(Icons.tag_rounded, size: 20),
                ),
                style: text.bodyLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _topic,
                decoration: const InputDecoration(
                  labelText: 'Topic (optional)',
                  prefixIcon: Icon(Icons.short_text_rounded, size: 20),
                ),
                style: text.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text('Visibility', style: text.labelLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _VisibilityOption(
                      icon: Icons.public_rounded,
                      label: 'Public',
                      hint: 'Anyone can join',
                      selected: _visibility == 'public',
                      onTap: () => setState(() => _visibility = 'public'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _VisibilityOption(
                      icon: Icons.lock_outline_rounded,
                      label: 'Private',
                      hint: 'Invite-only',
                      selected: _visibility == 'private',
                      onTap: () => setState(() => _visibility = 'private'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SignalButton(
                      label: 'Create',
                      busy: _busy,
                      onPressed: _busy ? null : _create,
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

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Semantics(
      button: true,
      selected: selected,
      child: AppCard(
        padding: const EdgeInsets.all(12),
        color: selected ? b.tint(Brand.orange, 0.10) : null,
        borderColor: selected ? Brand.orange : null,
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? Brand.orange : b.paperDim),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(hint, style: text.bodySmall),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: Brand.orange,
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, required this.onTap});
  final ChannelBrief channel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final topic = channel.topic;
    final members =
        '${channel.memberCount} member${channel.memberCount == 1 ? '' : 's'}';
    return AppCard(
      padding: const EdgeInsets.all(14),
      radius: Brand.radiusLg,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 42),
        child: Row(
          children: [
            IconTile(
              icon: channel.isPrivate
                  ? Icons.lock_outline_rounded
                  : Icons.tag_rounded,
              color: channel.joined ? Brand.orange : Brand.info,
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    topic != null && topic.isNotEmpty
                        ? '$members · $topic'
                        : members,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(
              label: channel.joined
                  ? 'Joined'
                  : (channel.isPrivate ? 'Private' : 'Join'),
              color: channel.joined
                  ? Brand.success
                  : (channel.isPrivate ? Brand.warning : Brand.orange),
              icon: channel.joined
                  ? Icons.check_rounded
                  : (channel.isPrivate
                        ? Icons.lock_outline_rounded
                        : Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.user,
    required this.onTap,
    this.trailing,
    this.avatarUrl,
    this.selected = false,
  });
  final ChatUser user;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? avatarUrl;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final role = user.role.trim();
    final sub = [
      if (role.isNotEmpty) role[0].toUpperCase() + role.substring(1),
      user.isOnline ? 'Online' : 'Offline',
    ].join(' · ');
    return Semantics(
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          boxShadow: b.shadow,
        ),
        child: AppCard(
          padding: const EdgeInsets.all(14),
          radius: Brand.radiusLg,
          color: selected ? b.tint(Brand.orange, 0.08) : null,
          borderColor: selected ? Brand.orange : null,
          onTap: onTap,
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppAvatar(
                    name: user.displayName,
                    size: 42,
                    imageUrl: avatarUrl,
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: user.isOnline ? Brand.success : b.paperDim,
                        border: Border.all(color: b.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
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
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
