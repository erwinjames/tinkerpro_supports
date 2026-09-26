import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/chat_models.dart';
import '../services/chat_service.dart';
import '../services/chatflow_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import '../widgets/tp_loader.dart';

class ChatNewConversationScreen extends StatefulWidget {
  const ChatNewConversationScreen({
    super.key,
    required this.service,
    required this.api,
    this.canMessageRequests = false,
  });
  final ChatService service;
  final ApiClient api;
  final bool canMessageRequests;

  static Future<int?> show(
    BuildContext context, {
    required ChatService service,
    required ApiClient api,
    bool canMessageRequests = false,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) => ChatNewConversationScreen(
        service: service,
        api: api,
        canMessageRequests: canMessageRequests,
      ),
    );
  }

  @override
  State<ChatNewConversationScreen> createState() =>
      _ChatNewConversationScreenState();
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _ChatNewConversationScreenState extends State<ChatNewConversationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final ChatflowService _flow = ChatflowService(widget.api);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: widget.canMessageRequests ? 4 : 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Tab _tab(IconData icon, String label) => Tab(
        height: 44,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17),
          const SizedBox(width: 6),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Start a conversation',
      icon: Icons.edit_outlined,
      width: 640,
      height: 640,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            dividerColor: context.brand.rule,
            tabs: [
              _tab(Icons.person_outline, 'DM'),
              _tab(Icons.groups_outlined, 'GROUP'),
              _tab(Icons.tag, 'CHANNEL'),
              if (widget.canMessageRequests) _tab(Icons.facebook, 'FACEBOOK'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _DMPickerTab(service: widget.service, flow: _flow),
                _GroupComposerTab(service: widget.service, flow: _flow),
                _ChannelBrowserTab(service: widget.service, flow: _flow),
                if (widget.canMessageRequests) _FacebookTab(flow: _flow),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DMPickerTab extends StatefulWidget {
  const _DMPickerTab({required this.service, required this.flow});
  final ChatService service;
  final ChatflowService flow;

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

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await widget.service.directory(search: _search.text.trim());
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _start(ChatUser u) async {
    if (_starting) return;
    setState(() => _starting = true);
    final r = await widget.flow.createDirect(u.id);
    if (!mounted) return;
    setState(() => _starting = false);
    final id = r.conversationId;
    if (r.ok && id != null) {
      Navigator.of(context).pop(id);
    } else {
      _toast(context,
          'Could not start conversation${r.message == null ? '' : ': ${r.message}'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchBar(
          controller: _search,
          hint: 'Search staff',
          onChanged: _onSearchChanged,
        ),
        Divider(height: 1, color: context.brand.rule),
        if (_starting) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _loading
              ? const _CenteredSpinner()
              : _users.isEmpty
                  ? const EmptyState(
                      icon: Icons.person_search_outlined,
                      label: 'No staff found',
                      hint: '',
                    )
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (_, i) => _StaffRow(
                        user: _users[i],
                        onTap: _starting ? null : () => _start(_users[i]),
                      ),
                    ),
        ),
        _TabFooter(children: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ]),
      ],
    );
  }
}

class _GroupComposerTab extends StatefulWidget {
  const _GroupComposerTab({required this.service, required this.flow});
  final ChatService service;
  final ChatflowService flow;

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

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await widget.service.directory(search: _search.text.trim());
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast(context, 'Group name required');
      return;
    }
    if (_selected.isEmpty) {
      _toast(context, 'Add at least one member');
      return;
    }
    setState(() => _creating = true);
    final r = await widget.flow.createGroup(name, _selected.toList());
    if (!mounted) return;
    setState(() => _creating = false);
    final id = r.conversationId;
    if (r.ok && id != null) {
      Navigator.of(context).pop(id);
    } else {
      _toast(context, 'Could not create group');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = _selected.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: TextField(
            controller: _name,
            decoration: const InputDecoration(
              hintText: 'Group name',
              prefixIcon: Icon(Icons.groups_outlined, size: 18),
            ),
          ),
        ),
        _SearchBar(
          controller: _search,
          hint: 'Add members',
          onChanged: _onSearchChanged,
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            n == 0 ? 'NO MEMBERS SELECTED' : '$n SELECTED',
            style: text.bodySmall?.copyWith(letterSpacing: 0.5),
          ),
        ),
        Divider(height: 1, color: context.brand.rule),
        Expanded(
          child: _loading
              ? const _CenteredSpinner()
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    final sel = _selected.contains(u.id);
                    return _StaffRow(
                      user: u,
                      selected: sel,
                      onTap: () => _toggle(u.id),
                      trailing: Checkbox(
                        value: sel,
                        onChanged: (_) => _toggle(u.id),
                      ),
                    );
                  },
                ),
        ),
        _TabFooter(
          children: [
            GhostButton(
              label: 'Cancel',
              onPressed: () => Navigator.of(context).pop(),
            ),
            SignalButton(
              label: 'Create group',
              busy: _creating,
              onPressed: _creating ? null : _create,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChannelBrowserTab extends StatefulWidget {
  const _ChannelBrowserTab({required this.service, required this.flow});
  final ChatService service;
  final ChatflowService flow;

  @override
  State<_ChannelBrowserTab> createState() => _ChannelBrowserTabState();
}

class _ChannelBrowserTabState extends State<_ChannelBrowserTab> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _topic = TextEditingController();
  Timer? _debounce;
  List<ChannelBrief> _channels = const [];
  bool _loading = true;
  bool _busy = false;
  bool _showCreate = false;
  String _visibility = 'public';

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
    _topic.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.channels(search: _search.text.trim());
    if (!mounted) return;
    setState(() {
      _channels = rows;
      _loading = false;
    });
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _onChannelTap(ChannelBrief c) async {
    if (_busy) return;
    if (c.joined) {
      Navigator.of(context).pop(c.id);
      return;
    }
    if (c.isPrivate) {
      _toast(context, 'Private — ask a member to add you');
      return;
    }
    setState(() => _busy = true);
    final r = await widget.flow.joinChannel(c.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.of(context).pop(c.id);
    } else {
      _toast(context, 'Could not join');
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast(context, 'Channel name required');
      return;
    }
    setState(() => _busy = true);
    final r = await widget.flow.createChannel(name, _visibility, _topic.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    final id = r.conversationId;
    if (r.ok && id != null) {
      Navigator.of(context).pop(id);
    } else {
      _toast(context, 'Could not create channel');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: SearchField(
                  controller: _search,
                  hint: 'Search channels',
                  width: null,
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: 'Create channel',
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(44, 40),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => setState(() => _showCreate = !_showCreate),
                  child: const Icon(Icons.add, size: 18),
                ),
              ),
            ],
          ),
        ),
        if (_showCreate)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.brand.surfaceHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.brand.rule),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Channel name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _topic,
                  decoration: const InputDecoration(hintText: 'Topic (optional)'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _VisibilityOption(
                        icon: Icons.public,
                        label: 'PUBLIC',
                        hint: 'Anyone can join',
                        selected: _visibility == 'public',
                        onTap: () => setState(() => _visibility = 'public'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _VisibilityOption(
                        icon: Icons.lock_outline,
                        label: 'PRIVATE',
                        hint: 'Invite-only',
                        selected: _visibility == 'private',
                        onTap: () => setState(() => _visibility = 'private'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SignalButton(
                  label: 'Create channel',
                  expand: true,
                  busy: _busy,
                  onPressed: _busy ? null : _create,
                ),
              ],
            ),
          ),
        Divider(height: 1, color: context.brand.rule),
        if (_busy && !_showCreate) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _loading
              ? const _CenteredSpinner()
              : _channels.isEmpty
                  ? const EmptyState(
                      icon: Icons.tag,
                      label: 'No channels',
                      hint: 'Create one to get started.',
                    )
                  : ListView.builder(
                      itemCount: _channels.length,
                      itemBuilder: (_, i) => _ChannelRow(
                        channel: _channels[i],
                        onTap: _busy ? null : () => _onChannelTap(_channels[i]),
                      ),
                    ),
        ),
        _TabFooter(children: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ]),
      ],
    );
  }
}

class _FacebookTab extends StatefulWidget {
  const _FacebookTab({required this.flow});
  final ChatflowService flow;

  @override
  State<_FacebookTab> createState() => _FacebookTabState();
}

class _FacebookTabState extends State<_FacebookTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<FacebookContact> _contacts = const [];
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

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.flow.facebookContacts(_search.text.trim());
    if (!mounted) return;
    setState(() {
      _contacts = rows;
      _loading = false;
    });
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchBar(
          controller: _search,
          hint: 'Search Facebook contacts',
          onChanged: _onSearchChanged,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'People who have messaged your Page. Facebook does not allow starting '
            'a chat first — they must message you, and replies only deliver within '
            '24h of their last message.',
            style: text.bodySmall,
          ),
        ),
        Divider(height: 1, color: context.brand.rule),
        Expanded(
          child: _loading
              ? const _CenteredSpinner()
              : _contacts.isEmpty
                  ? const EmptyState(
                      icon: Icons.facebook,
                      label: 'No Facebook contacts',
                      hint: 'People who message your Page appear here.',
                    )
                  : ListView.builder(
                      itemCount: _contacts.length,
                      itemBuilder: (_, i) {
                        final c = _contacts[i];
                        return WebTableRow(
                          onTap: () => Navigator.of(context).pop(c.conversationId),
                          cells: [
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF1877F2),
                              ),
                              child: const Icon(Icons.facebook,
                                  color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name,
                                      style: text.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                    c.withinWindow
                                        ? 'Can reply now'
                                        : 'Outside 24h window — reply may not deliver',
                                    style: text.bodySmall?.copyWith(
                                      color: c.withinWindow
                                          ? const Color(0xFF1AAF5D)
                                          : const Color(0xFFD9822B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
        ),
        _TabFooter(children: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ]),
      ],
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
    return Material(
      color: selected ? Brand.signalGlow(0.08) : context.brand.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? Brand.signal : context.brand.rule,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? Brand.signal : context.brand.paperDim),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: selected ? Brand.signal : null,
                        )),
                    Text(hint, style: text.bodySmall),
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

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, required this.onTap});
  final ChannelBrief channel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = channel;
    return WebTableRow(
      onTap: onTap,
      cells: [
        IconTile(
          icon: c.isPrivate ? Icons.lock_outline : Icons.tag,
          size: 34,
          color: c.joined ? Brand.signal : context.brand.paperDim,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.name,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              if (c.topic != null && c.topic!.isNotEmpty)
                Text(
                  c.topic!,
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          child: Text(
            '${c.memberCount} member${c.memberCount == 1 ? '' : 's'}',
            style: text.bodySmall,
          ),
        ),
        SizedBox(
          width: 80,
          child: Align(
            alignment: Alignment.centerRight,
            child: c.joined
                ? const StatusPill(label: 'JOINED', color: Brand.success)
                : c.isPrivate
                    ? const StatusPill(label: 'PRIVATE')
                    : const StatusPill(label: 'JOIN', color: Brand.signal),
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.hint,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: SearchField(
        controller: controller,
        hint: hint,
        width: null,
        onChanged: onChanged,
      ),
    );
  }
}

class _TabFooter extends StatelessWidget {
  const _TabFooter({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        border: Border(top: BorderSide(color: context.brand.rule)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();
  @override
  Widget build(BuildContext context) {
    return const Center(child: TpLoader());
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.user,
    required this.onTap,
    this.trailing,
    this.selected = false,
  });
  final ChatUser user;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool selected;

  String get _role {
    final r = user.role.trim().replaceAll('_', ' ');
    if (r.isEmpty) return '—';
    return r
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = user.displayName.trim();
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return WebTableRow(
      onTap: onTap,
      selected: selected,
      cells: [
        SizedBox(
          width: 34,
          height: 34,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Brand.signal,
                ),
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
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
                    color: user.isOnline
                        ? Brand.success
                        : const Color(0xFFCBD5E1),
                    border:
                        Border.all(color: context.brand.surface, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(_role, style: text.bodySmall),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}
