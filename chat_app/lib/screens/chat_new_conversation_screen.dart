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

class _ChatNewConversationScreenState
    extends State<ChatNewConversationScreen> with SingleTickerProviderStateMixin {
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
    return StationScaffold(
      title: 'New conversation',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            indicatorColor: Brand.signal,
            indicatorWeight: 2,
            labelColor: Brand.signal,
            unselectedLabelColor: context.brand.paperDim,
            labelStyle: Theme.of(context).textTheme.labelLarge,
            unselectedLabelStyle: Theme.of(context).textTheme.labelLarge,
            dividerColor: context.brand.rule,
            tabs: const [
              Tab(text: 'DM'),
              Tab(text: 'GROUP'),
              Tab(text: 'CHANNEL'),
            ],
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
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(search: v));
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
        const SnackBar(content: Text('COULD NOT START CONVERSATION')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _search,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            labelText: 'SEARCH STAFF',
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close,
                        size: 18, color: context.brand.paperDim),
                    onPressed: () {
                      _search.clear();
                      _load();
                    },
                  ),
          ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const _CenteredSpinner()
              : _users.isEmpty
                  ? const EmptyState(
                      label: 'No staff found',
                      hint: 'Try a different search.',
                    )
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, _) => const Hairline(),
                      itemBuilder: (_, i) => _StaffRow(
                        user: _users[i],
                        onTap: _starting ? null : () => _start(_users[i]),
                      ),
                    ),
        ),
      ],
    );
  }
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
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(search: v));
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GROUP NAME REQUIRED')),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ADD AT LEAST ONE MEMBER')),
      );
      return;
    }
    setState(() => _creating = true);
    final convId = await widget.service.createGroup(name, _selected.toList());
    if (!mounted) return;
    setState(() => _creating = false);
    if (convId != null) {
      Navigator.of(context).pop(convId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('COULD NOT CREATE GROUP')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'GROUP NAME'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          onChanged: _onSearchChanged,
          decoration: const InputDecoration(labelText: 'ADD MEMBERS'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              _selected.isEmpty
                  ? 'NO MEMBERS SELECTED'
                  : '${_selected.length} SELECTED',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const _CenteredSpinner()
              : _users.isEmpty
                  ? const EmptyState(label: 'No staff', hint: '—')
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, _) => const Hairline(),
                      itemBuilder: (_, i) {
                        final u = _users[i];
                        return _StaffRow(
                          user: u,
                          onTap: () => _toggle(u.id),
                          trailing: Icon(
                            _selected.contains(u.id)
                                ? Icons.check_box_outlined
                                : Icons.check_box_outline_blank,
                            color: _selected.contains(u.id)
                                ? Brand.signal
                                : context.brand.paperDim,
                            size: 20,
                          ),
                        );
                      },
                    ),
        ),
        const SizedBox(height: 12),
        SignalButton(
          label: _creating ? 'Creating…' : 'Create group',
          busy: _creating,
          onPressed: _creating ? null : _create,
        ),
      ],
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
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(search: v));
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('COULD NOT JOIN')),
      );
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
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(labelText: 'SEARCH CHANNELS'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Create channel',
              onPressed: _busy ? null : _showCreate,
              icon: const Icon(Icons.add, color: Brand.signal),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const _CenteredSpinner()
              : _channels.isEmpty
                  ? const EmptyState(
                      label: 'No channels',
                      hint: 'Create one to get started.',
                    )
                  : ListView.separated(
                      itemCount: _channels.length,
                      separatorBuilder: (_, _) => const Hairline(),
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
                                          'PRIVATE — ASK A MEMBER TO ADD YOU'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CHANNEL NAME REQUIRED')),
      );
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: context.brand.surface,
          border: Border(top: BorderSide(color: Brand.signal, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('NEW CHANNEL', style: text.labelLarge),
            const SizedBox(height: 8),
            const Hairline(),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'CHANNEL NAME'),
              style: text.titleMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _topic,
              decoration: const InputDecoration(labelText: 'TOPIC (OPTIONAL)'),
              style: text.titleMedium,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _VisibilityOption(
                    label: 'PUBLIC',
                    hint: 'Anyone can join',
                    selected: _visibility == 'public',
                    onTap: () => setState(() => _visibility = 'public'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _VisibilityOption(
                    label: 'PRIVATE',
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
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? Brand.signalGlow(0.12) : Colors.transparent,
          border: Border.all(
            color: selected ? Brand.signal : context.brand.rule,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: text.labelLarge?.copyWith(
                  color: selected ? Brand.signal : context.brand.paper,
                )),
            const SizedBox(height: 4),
            Text(hint, style: text.bodySmall),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              channel.isPrivate ? Icons.lock_outline : Icons.tag,
              size: 18,
              color: channel.joined ? Brand.signal : context.brand.paperDim,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(channel.name, style: text.titleSmall),
                  if (channel.topic != null && channel.topic!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      channel.topic!,
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${channel.memberCount} MEMBER${channel.memberCount == 1 ? '' : 'S'}',
                    style: text.labelMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              channel.joined
                  ? 'JOINED'
                  : (channel.isPrivate ? 'PRIVATE' : 'JOIN'),
              style: text.labelMedium?.copyWith(
                color: channel.joined
                    ? Brand.signal
                    : (channel.isPrivate ? context.brand.paperDim : Brand.signal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Brand.signal,
        ),
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.user, required this.onTap, this.trailing});
  final ChatUser user;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: user.isOnline ? Brand.signal : context.brand.rule,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName, style: text.titleSmall),
                  const SizedBox(height: 3),
                  Text(user.role.toUpperCase(), style: text.labelMedium),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
