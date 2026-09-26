import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/chat_models.dart';
import '../services/chat_prefs.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../services/chat_ui_data_service.dart';
import '../services/live_sync.dart';
import '../services/sound_engine.dart';
import 'admin/admin_list.dart' show confirmDialog;
import 'chat_new_conversation_screen.dart';
import 'chat_thread_screen.dart';
import 'chat_ui_widgets.dart';
import 'profile_panel.dart';
import '../widgets/tp_loader.dart';

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({
    super.key,
    required this.service,
    required this.realtime,
    required this.inbox,
    required this.myUserId,
    required this.api,
    required this.chatPrefs,
    required this.onSignOut,
    this.calls,
    this.onBack,
    this.twoPane = false,
  });

  final ChatService service;
  final ChatRealtimeService realtime;
  final ChatInbox inbox;
  final int myUserId;
  final ApiClient api;
  final ChatPrefs chatPrefs;
  final CallService? calls;
  final VoidCallback onSignOut;
  final VoidCallback? onBack;
  final bool twoPane;

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

enum _Chip { all, priority, unread, facebook, archived }

enum _View { main, requests }

class _Entry {
  const _Entry.header(this.label, this.count, {this.refresh = false})
    : conversation = null;
  const _Entry.row(this.conversation) : label = '', count = 0, refresh = false;
  final String label;
  final int count;
  final bool refresh;
  final Conversation? conversation;
}

class _ChatInboxScreenState extends State<ChatInboxScreen>
    with LiveRefresh<ChatInboxScreen> {
  final ValueNotifier<int?> _hoveredRow = ValueNotifier<int?>(null);
  final _search = TextEditingController();
  final _menuKey = GlobalKey();
  late final ChatUiDataService _ui;
  String _query = '';
  _Chip _chip = _Chip.all;
  _View _view = _View.main;
  int? _selectedId;
  bool _selectedSeen = false;

  @override
  void initState() {
    super.initState();
    _ui = ChatUiDataService(widget.api);
    _ui.addListener(_onUi);
    _ui.loadCaps();
    _ui.refresh();
    widget.inbox.addListener(_onChange);
    widget.realtime.onlineUsers.addListener(_onChange);
    if (widget.twoPane) {
      widget.inbox.openRequest.addListener(_onOpenRequest);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onOpenRequest());
    }
  }

  void _onOpenRequest() {
    final id = widget.inbox.openRequest.value;
    if (id == null || !mounted) return;
    widget.inbox.openRequest.value = null;
    _openThread(id);
  }

  @override
  void dispose() {
    _hoveredRow.dispose();
    if (widget.twoPane) {
      widget.inbox.openRequest.removeListener(_onOpenRequest);
    }
    widget.inbox.removeListener(_onChange);
    widget.realtime.onlineUsers.removeListener(_onChange);
    _ui.removeListener(_onUi);
    _ui.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['chat'];

  @override
  void onLiveChange() {
    widget.inbox.reload();
    _ui.refresh();
  }

  void _onUi() {
    if (mounted) setState(() {});
  }

  void _onChange() {
    if (!mounted) return;
    final sel = _selectedId;
    if (sel != null) {
      final present = widget.inbox.conversations.any((c) => c.id == sel);
      if (present) {
        _selectedSeen = true;
      } else if (_selectedSeen) {
        _selectedId = null;
        _selectedSeen = false;
      }
    }
    final ids = widget.inbox.conversations.map((c) => c.id);
    final unknown = ids.any((id) => _ui.meta(id).source.isEmpty);
    _ui.maybeRefresh(
      minGap: unknown
          ? const Duration(seconds: 3)
          : const Duration(seconds: 15),
    );
    setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await confirmDialog(
      context,
      title: 'Sign out',
      message:
          "You'll be returned to the sign-in screen. "
          'Cached chat data on this device will be cleared.',
      confirmLabel: 'Sign out',
    );
    if (confirmed && mounted) widget.onSignOut();
  }

  Future<void> _openNewConversation() async {
    final convId = await ChatNewConversationScreen.show(
      context,
      service: widget.service,
      api: widget.api,
      canMessageRequests: _ui.canMessageRequests,
    );
    if (!mounted || convId == null) return;
    await widget.inbox.reload();
    if (!mounted) return;
    _ui.refresh();
    _openThread(convId);
  }

  Future<void> _confirmHide(Conversation c) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Hide this conversation?',
      message:
          'Hides ${c.name.isEmpty ? 'this conversation' : c.name} from '
          'your inbox.\n\nThis only affects your account — the other '
          'participants still see it, and a new message brings it back.',
      confirmLabel: 'Hide',
    );
    if (!confirmed || !mounted) return;
    final err = await _ui.hideForMe(c.id);
    if (!mounted) return;
    if (err == null) {
      widget.inbox.removeLocally(c.id);
      if (_selectedId == c.id) {
        setState(() {
          _selectedId = null;
          _selectedSeen = false;
        });
      }
    } else {
      _toast('Could not hide: $err');
    }
  }

  Future<void> _togglePriority(Conversation c) async {
    final err = await _ui.setPriority(c.id, !_ui.meta(c.id).priority);
    if (err != null && mounted) _toast('Could not update priority: $err');
  }

  Future<void> _toggleArchived(Conversation c) async {
    final next = !_ui.meta(c.id).archived;
    final err = await _ui.setArchived(c.id, next);
    if (!mounted) return;
    if (err == null) {
      _toast(next ? 'Archived' : 'Moved to inbox');
    } else {
      _toast('Could not ${next ? 'archive' : 'unarchive'}: $err');
    }
  }

  Future<void> _showRowMenu(Conversation c, Offset position) async {
    final m = _ui.meta(c.id);
    final picked = await showChatMenu(context, position, [
      ChatMenuEntry(
        'priority',
        m.priority ? 'Remove priority' : 'Mark as priority',
      ),
      ChatMenuEntry('archive', m.archived ? 'Move to inbox' : 'Archive'),
      if (!m.isFacebook)
        const ChatMenuEntry('delete', 'Delete for me', danger: true),
    ]);
    if (!mounted) return;
    if (picked == 'priority') await _togglePriority(c);
    if (picked == 'archive') await _toggleArchived(c);
    if (picked == 'delete') await _confirmHide(c);
  }

  Future<void> _showInboxMenu() async {
    final box = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset(0, box.size.height + 6));
    final picked = await showChatMenu(context, pos, [
      const ChatMenuEntry('new', 'New conversation'),
      ChatMenuEntry(
        'archived',
        _chip == _Chip.archived ? 'Back to inbox' : 'Archived chats',
      ),
      const ChatMenuEntry('refresh', 'Refresh'),
      ChatMenuEntry(
        'sound',
        SoundEngine.instance.chatMuted.value
            ? 'Unmute notification sounds'
            : 'Mute notification sounds',
      ),
      const ChatMenuEntry('signout', 'Sign out'),
    ]);
    if (!mounted) return;
    switch (picked) {
      case 'new':
        _openNewConversation();
        break;
      case 'archived':
        setState(() {
          _view = _View.main;
          _chip = _chip == _Chip.archived ? _Chip.all : _Chip.archived;
        });
        break;
      case 'refresh':
        _reload();
        break;
      case 'sound':
        final muted = !SoundEngine.instance.chatMuted.value;
        await SoundEngine.instance.setChatMuted(muted);
        if (!muted) SoundEngine.instance.reaction('unmute:${DateTime.now().millisecondsSinceEpoch}');
        break;
      case 'signout':
        _confirmSignOut();
        break;
    }
  }

  Future<void> _reload() async {
    await widget.inbox.reload();
    await _ui.refresh();
  }

  Conversation? _find(int id) {
    for (final c in widget.inbox.conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _openThread(int conversationId) {
    widget.inbox.markLocallyRead(conversationId);
    if (widget.twoPane) {
      setState(() {
        _selectedId = conversationId;
        _selectedSeen = _find(conversationId) != null;
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          conversationId: conversationId,
          conversation: _find(conversationId),
          myUserId: widget.myUserId,
          service: widget.service,
          realtime: widget.realtime,
          api: widget.api,
          chatPrefs: widget.chatPrefs,
          calls: widget.calls,
          ui: _ui,
          onInboxReload: _reload,
          conversations: () => widget.inbox.conversations,
        ),
      ),
    );
  }

  bool _textPass(Conversation c) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (c.name.toLowerCase().contains(q)) return true;
    return (c.lastMessage?.body.toLowerCase() ?? '').contains(q);
  }

  List<Conversation> _prioFirst(Iterable<Conversation> list) {
    final l = list.toList();
    final idx = {for (var i = 0; i < l.length; i++) l[i].id: i};
    l.sort((a, b) {
      final pa = _ui.meta(a.id).priority ? 1 : 0;
      final pb = _ui.meta(b.id).priority ? 1 : 0;
      if (pa != pb) return pb - pa;
      return idx[a.id]! - idx[b.id]!;
    });
    return l;
  }

  int get _requestsUnread {
    if (!_ui.canMessageRequests) return 0;
    return widget.inbox.conversations
        .where((c) => _ui.meta(c.id).isRequest && c.unreadCount > 0)
        .length;
  }

  List<_Entry> _entries() {
    final all = widget.inbox.conversations;
    final view = _ui.canMessageRequests ? _view : _View.main;
    bool chipPass(Conversation c) {
      final m = _ui.meta(c.id);
      switch (_chip) {
        case _Chip.priority:
          return m.priority;
        case _Chip.unread:
          return c.unreadCount > 0;
        case _Chip.facebook:
          return m.isFacebook;
        default:
          return true;
      }
    }

    bool archivePass(Conversation c) => _chip == _Chip.archived
        ? _ui.meta(c.id).archived
        : !_ui.meta(c.id).archived;

    final rows = view == _View.requests
        ? all.where((c) => _ui.meta(c.id).isRequest && _textPass(c)).toList()
        : all
              .where(
                (c) =>
                    _textPass(c) &&
                    chipPass(c) &&
                    archivePass(c) &&
                    !_ui.meta(c.id).isRequest,
              )
              .toList();

    final out = <_Entry>[];
    void section(
      String label,
      List<Conversation> list, {
      bool refresh = false,
    }) {
      if (list.isEmpty) return;
      out.add(_Entry.header(label, list.length, refresh: refresh));
      out.addAll(list.map(_Entry.row));
    }

    bool isCustomer(Conversation c) => _ui.meta(c.id).isExternal;

    if (view == _View.requests) {
      section('Facebook chats', _prioFirst(rows), refresh: true);
    } else if (_chip == _Chip.archived) {
      section('Archived', _prioFirst(rows));
    } else if (_chip == _Chip.all) {
      bool isNew(Conversation c) =>
          c.unreadCount > 0 &&
          !(isCustomer(c) && _ui.meta(c.id).ticketAccepted);
      final fresh = _prioFirst(rows.where(isNew));
      final seen = rows.where((c) => !isNew(c)).toList();
      section('New', fresh);
      section('Customers', _prioFirst(seen.where(isCustomer)));
      section('Direct Messages', _prioFirst(seen.where((c) => !isCustomer(c))));
    } else {
      section('Customers', _prioFirst(rows.where(isCustomer)));
      section('Direct Messages', _prioFirst(rows.where((c) => !isCustomer(c))));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    if (!widget.twoPane) {
      return Scaffold(
        backgroundColor: t.surfaceSoft,
        body: _listPanel(compact: true),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(17, 38, 17, 26),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.borderSoft),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0C0A09).withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 340,
                decoration: BoxDecoration(
                  color: t.surfaceSoft,
                  border: Border(right: BorderSide(color: t.borderSoft)),
                ),
                child: _listPanel(compact: false),
              ),
              Expanded(child: _threadPane()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _threadPane() {
    final t = ChatTokens.of(context);
    final id = _selectedId;
    if (id == null) {
      return Container(
        color: t.bg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: t.surface.withValues(alpha: 0.85),
                border: Border(bottom: BorderSide(color: t.borderSoft)),
              ),
              child: const ChatHeaderTitle(
                title: 'Select a conversation',
                subtitle: 'Pick someone from the list to start chatting',
              ),
            ),
            const Align(
              alignment: Alignment.topCenter,
              child: ChatEmptyState(
                title: 'No conversation selected',
                message: 'Pick a conversation on the left or start a new one.',
              ),
            ),
          ],
        ),
      );
    }
    return ChatThreadScreen(
      key: ValueKey('thread-$id'),
      conversationId: id,
      conversation: _find(id),
      myUserId: widget.myUserId,
      service: widget.service,
      realtime: widget.realtime,
      api: widget.api,
      chatPrefs: widget.chatPrefs,
      calls: widget.calls,
      embedded: true,
      ui: _ui,
      onInboxReload: _reload,
      conversations: () => widget.inbox.conversations,
      onClosed: () {
        if (!mounted) return;
        setState(() {
          _selectedId = null;
          _selectedSeen = false;
        });
      },
    );
  }

  Widget _searchField(ChatTokens t) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: t.border),
    );
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: t.text,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: t.surface,
          hintText: 'Search conversations',
          hintStyle: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: t.subtle,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 11,
          ),
          prefixIcon: Icon(Icons.search, size: 15, color: t.subtle),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  splashRadius: 16,
                  icon: Icon(Icons.close, size: 15, color: t.subtle),
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: const BorderSide(color: ChatTokens.primary),
          ),
        ),
      ),
    );
  }

  Widget _listPanel({required bool compact}) {
    final t = ChatTokens.of(context);
    final hPad = compact ? 12.0 : 16.0;
    final all = widget.inbox.conversations;
    final entries = _entries();
    final canReq = _ui.canMessageRequests;
    final view = canReq ? _view : _View.main;
    final inArchived = _chip == _Chip.archived && view == _View.main;
    final backAction =
        widget.onBack ??
        (widget.twoPane && _selectedId != null
            ? () => setState(() {
                _selectedId = null;
                _selectedSeen = false;
              })
            : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(
            hPad,
            compact ? 12 : 16,
            hPad,
            compact ? 12 : 14,
          ),
          decoration: BoxDecoration(
            color: t.surfaceSoft,
            border: Border(bottom: BorderSide(color: t.borderSoft)),
          ),
          child: Row(
            children: [
              if (widget.twoPane || widget.onBack != null) ...[
                ChatIconBtn(
                  icon: Icons.arrow_back,
                  tooltip: 'Close',
                  onPressed: backAction,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: _searchField(t)),
              const SizedBox(width: 8),
              ChatIconBtn(
                key: _menuKey,
                icon: Icons.more_horiz,
                iconSize: 18,
                tooltip: 'Menu',
                primary: true,
                onPressed: _showInboxMenu,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.surfaceSoft,
            border: Border(bottom: BorderSide(color: t.borderSoft)),
          ),
          child: Row(
            children: [
              Expanded(
                child: ChatTab(
                  label: 'Chat',
                  icon: Icons.forum,
                  active: view == _View.main,
                  onTap: () => setState(() => _view = _View.main),
                ),
              ),
              if (canReq)
                Expanded(
                  child: ChatTab(
                    label: 'Facebook Chats',
                    icon: Icons.facebook,
                    active: view == _View.requests,
                    badge: _requestsUnread,
                    onTap: () => setState(() => _view = _View.requests),
                  ),
                ),
            ],
          ),
        ),
        if (view == _View.main)
          Container(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 10),
            decoration: BoxDecoration(
              color: t.surfaceSoft,
              border: Border(bottom: BorderSide(color: t.borderSoft)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: inArchived
                    ? [
                        ChatChip(
                          label: 'Back to inbox',
                          icon: Icons.arrow_back,
                          selected: false,
                          onTap: () => setState(() => _chip = _Chip.all),
                        ),
                      ]
                    : [
                        ChatChip(
                          label: 'All',
                          selected: _chip == _Chip.all,
                          onTap: () => setState(() => _chip = _Chip.all),
                        ),
                        const SizedBox(width: 6),
                        ChatChip(
                          label: 'Priority',
                          icon: Icons.star,
                          selected: _chip == _Chip.priority,
                          onTap: () => setState(() => _chip = _Chip.priority),
                        ),
                        const SizedBox(width: 6),
                        ChatChip(
                          label: 'Unread',
                          selected: _chip == _Chip.unread,
                          onTap: () => setState(() => _chip = _Chip.unread),
                        ),
                        const SizedBox(width: 6),
                        ChatChip(
                          label: 'Facebook',
                          icon: Icons.facebook,
                          selected: _chip == _Chip.facebook,
                          onTap: () => setState(() => _chip = _Chip.facebook),
                        ),
                      ],
              ),
            ),
          ),
        Expanded(
          child: Container(
            color: t.surfaceSoft,
            child: _listBody(t, all, entries, view, compact),
          ),
        ),
      ],
    );
  }

  Widget _listBody(
    ChatTokens t,
    List<Conversation> all,
    List<_Entry> entries,
    _View view,
    bool compact,
  ) {
    if (all.isEmpty && widget.inbox.loading) {
      return const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: 56),
          child: SizedBox(
            width: 20,
            height: 20,
            child: TpLoader(
              strokeWidth: 2,
              color: ChatTokens.primary,
            ),
          ),
        ),
      );
    }
    if (entries.isEmpty) {
      Widget empty;
      if (view == _View.requests) {
        empty = ChatEmptyState(
          title: 'No Facebook chats',
          message:
              'New Facebook messages appear here for the access agents to handle.',
          action: _RefreshPill(onTap: _reload),
        );
      } else if (_query.trim().length >= 2) {
        empty = ChatEmptyState(
          title: 'No matches',
          message: 'Nothing found for “${_query.trim()}”',
        );
      } else {
        final msg = switch (_chip) {
          _Chip.priority => 'Star a conversation to see it here.',
          _Chip.unread => 'All caught up.',
          _Chip.facebook => 'No Facebook conversations yet.',
          _Chip.archived => 'Archive a conversation to tuck it away here.',
          _Chip.all => 'Tap + to start one.',
        };
        empty = ChatEmptyState(title: 'No conversations', message: msg);
      }
      return ListView(children: [empty]);
    }
    return MouseRegion(
      onExit: (_) => _hoveredRow.value = null,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: entries.length,
        itemBuilder: (_, i) {
          final e = entries[i];
          final c = e.conversation;
          if (c == null) {
            return _SectionHeader(
              label: e.label,
              count: e.count,
              first: i == 0,
              onRefresh: e.refresh ? _reload : null,
            );
          }
          final livePeerOnline =
              c.peer != null &&
              widget.realtime.onlineUsers.value.contains(c.peer!.id);
          return _ConversationRow(
            key: ValueKey('conv-row-${c.id}'),
            conversation: c,
            meta: _ui.meta(c.id),
            myUserId: widget.myUserId,
            peerOnline: livePeerOnline || (c.peer?.isOnline ?? false),
            active: widget.twoPane && c.id == _selectedId,
            onTap: () => _openThread(c.id),
            onArchive: () => _toggleArchived(c),
            onDelete: () => _confirmHide(c),
            onContextMenu: (pos) => _showRowMenu(c, pos),
            hovered: _hoveredRow,
            onAvatarTap: (c.peer?.id ?? 0) > 0
                ? () => showProfilePanel(
                      context,
                      api: widget.api,
                      userId: c.peer!.id,
                      seedName: c.peer!.displayName.isNotEmpty
                          ? c.peer!.displayName
                          : c.name,
                      seedAvatar: _ui.meta(c.id).peerAvatar,
                    )
                : null,
          );
        },
      ),
    );
  }
}

class _RefreshPill extends StatelessWidget {
  const _RefreshPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.borderSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync, size: 14, color: t.muted),
            const SizedBox(width: 6),
            Text(
              'Refresh',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: t.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.first,
    this.onRefresh,
  });
  final String label;
  final int count;
  final bool first;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    return Container(
      margin: EdgeInsets.only(top: first ? 0 : 6),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: t.borderSoft)),
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.44,
              color: t.subtle,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.muted,
            ),
          ),
          if (onRefresh != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Refresh Facebook chats',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRefresh,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ChatTokens.primarySoft(),
                    border: Border.all(color: ChatTokens.primary),
                  ),
                  child: const Icon(
                    Icons.sync,
                    size: 15,
                    color: ChatTokens.primary,
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

class _ConversationRow extends StatefulWidget {
  const _ConversationRow({
    super.key,
    required this.conversation,
    required this.meta,
    required this.myUserId,
    required this.peerOnline,
    required this.onTap,
    required this.onArchive,
    required this.onDelete,
    required this.onContextMenu,
    required this.hovered,
    this.active = false,
    this.onAvatarTap,
  });

  final ValueNotifier<int?> hovered;
  final Conversation conversation;
  final ChatConvMeta meta;
  final int myUserId;
  final bool peerOnline;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final ValueChanged<Offset> onContextMenu;
  final bool active;
  final VoidCallback? onAvatarTap;

  @override
  State<_ConversationRow> createState() => _ConversationRowState();
}

final _quoteRe = RegExp(
  r'^>\s*@([^\[:\n]+?)(?:\s*\[#(\d+)\])?\s*:[ \t]*([^\n]*?)(?:\r?\n\r?\n([\s\S]+))?$',
);

String _previewText(String body) {
  final m = _quoteRe.firstMatch(body);
  final text = m != null
      ? '↩ ${(m.group(4) ?? '').trim().isEmpty ? '[attachment]' : m.group(4)!.trim()}'
      : body;
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _displayName(Conversation c, ChatConvMeta m) {
  final raw = c.name.trim();
  if (!m.isFacebook) return raw;
  final s = raw
      .replaceAll(
        RegExp(r'\s*\((?:facebook|messenger)\)\s*$', caseSensitive: false),
        '',
      )
      .trim();
  return s.isEmpty ? raw : s;
}

class _ConversationRowState extends State<_ConversationRow> {
  bool get _hover => widget.hovered.value == widget.conversation.id;

  void _onHoverChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.hovered.addListener(_onHoverChanged);
  }

  @override
  void didUpdateWidget(covariant _ConversationRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hovered, widget.hovered)) {
      oldWidget.hovered.removeListener(_onHoverChanged);
      widget.hovered.addListener(_onHoverChanged);
    }
  }

  @override
  void dispose() {
    widget.hovered.removeListener(_onHoverChanged);
    super.dispose();
  }

  Widget _avatarTap(Widget child) {
    final tap = widget.onAvatarTap;
    if (tap == null) return child;
    return Tooltip(
      message: 'View profile',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: tap, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    final c = widget.conversation;
    final m = widget.meta;
    final lastMsg = c.lastMessage;
    final isFromMe = lastMsg?.senderId == widget.myUserId;
    var preview = '—';
    if (lastMsg != null) {
      if (lastMsg.body.trim().isNotEmpty) {
        preview = _previewText(lastMsg.body);
      } else if (lastMsg.attachments.isNotEmpty) {
        final a = lastMsg.attachments.first;
        preview = a.isImage ? '[image]' : '[file: ${a.originalName}]';
      }
    }
    final subtitle = lastMsg == null
        ? 'No messages yet'
        : (isFromMe ? 'You: $preview' : preview);
    final unread = c.unreadCount > 0;
    final active = widget.active;
    final name = _displayName(c, m);
    final showActions = _hover || active;

    final prefix = <Widget>[
      if (m.ticketWaiting)
        Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.only(right: 5),
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ChatTokens.danger,
          ),
          child: const Text(
            '!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      if (m.priority)
        const Padding(
          padding: EdgeInsets.only(right: 5),
          child: Icon(Icons.star, size: 12, color: Color(0xFFF59E0B)),
        ),
      if (m.hidden)
        const ChatMiniPill(
          label: 'Resolved',
          icon: Icons.check,
          bg: Color(0xFFEDEFF2),
          fg: Color(0xFF5A6473),
        ),
      if (m.isFacebook && m.fbAiOwned)
        const ChatMiniPill(
          label: 'AI',
          icon: Icons.smart_toy_outlined,
          bg: Color(0xFFEDE9FE),
          fg: Color(0xFF6D28D9),
        ),
      if (m.isDesktopApp)
        const ChatMiniPill(
          label: 'POS App',
          icon: Icons.desktop_windows_outlined,
          bg: Color(0xFFEEF0FF),
          fg: Color(0xFF3B3ED8),
        ),
      if (m.guestStatus == 'pending')
        const ChatMiniPill(
          label: 'Pending',
          icon: Icons.circle,
          bg: Color(0xFFFFF4E6),
          fg: Color(0xFFB25600),
        )
      else if (m.guestStatus == 'approved' && !m.isDesktopApp)
        const ChatMiniPill(
          label: 'Guest',
          bg: Color(0xFFE6F8EE),
          fg: Color(0xFF1B7A3E),
        ),
      if (c.type != 'dm')
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            c.type == 'channel'
                ? (c.visibility == 'private' ? Icons.lock : Icons.tag)
                : Icons.groups,
            size: 12,
            color: const Color(0xFF6C757D),
          ),
        ),
    ];

    final bg = (active || _hover) ? t.surface : Colors.transparent;
    final borderColor = active
        ? ChatTokens.primary.withValues(alpha: 0.22)
        : (_hover ? t.borderSoft : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => widget.hovered.value = widget.conversation.id,
      onHover: (_) {
        if (widget.hovered.value != widget.conversation.id) {
          widget.hovered.value = widget.conversation.id;
        }
      },
      onExit: (_) {
        if (widget.hovered.value == widget.conversation.id) {
          widget.hovered.value = null;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapUp: (d) => widget.onContextMenu(d.globalPosition),
        onLongPressStart: (d) => widget.onContextMenu(d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: ChatTokens.primary.withValues(alpha: 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : (_hover
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFF0C0A09,
                            ).withValues(alpha: 0.04),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null),
          ),
          child: Stack(
            children: [
              if (active)
                Positioned(
                  left: 0,
                  top: 10,
                  bottom: 10,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      gradient: ChatTokens.gradient,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _avatarTap(
                      ChatAvatar(
                        name: name,
                        size: 40,
                        facebook: c.peer == null && m.isFacebook,
                        online: c.peer != null ? widget.peerOnline : null,
                        imageUrl: m.peerAvatar,
                        ringColor: (active || _hover) ? t.surface : t.surfaceSoft,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ...prefix,
                              Expanded(
                                child: Text(
                                  name.isEmpty ? '—' : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    letterSpacing: -0.14,
                                    fontWeight: unread
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: active ? ChatTokens.primary : t.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: unread ? t.text : t.muted,
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(c.lastActivityAt),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: t.subtle,
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(height: 6),
                          ChatCountBadge(count: c.unreadCount),
                        ],
                        const SizedBox(height: 6),
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 140),
                          opacity: showActions ? 1 : 0,
                          child: IgnorePointer(
                            ignoring: !showActions,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _RowAction(
                                  icon: m.archived
                                      ? Icons.inbox_outlined
                                      : Icons.archive,
                                  tooltip: m.archived
                                      ? 'Move back to inbox'
                                      : 'Archive conversation',
                                  onTap: widget.onArchive,
                                ),
                                if (!m.isFacebook) ...[
                                  const SizedBox(width: 2),
                                  _RowAction(
                                    icon: Icons.delete,
                                    tooltip: 'Delete conversation',
                                    danger: true,
                                    onTap: widget.onDelete,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _RowAction extends StatefulWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_RowAction> createState() => _RowActionState();
}

class _RowActionState extends State<_RowAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    final hc = widget.danger ? ChatTokens.danger : ChatTokens.primary;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _hover ? hc.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, size: 13, color: _hover ? hc : t.subtle),
          ),
        ),
      ),
    );
  }
}

String _formatTime(String iso) {
  if (iso.isEmpty) return '';
  DateTime dt;
  try {
    dt = DateTime.parse(iso.replaceAll(' ', 'T'));
  } catch (_) {
    return '';
  }
  final now = DateTime.now();
  final diff = now.difference(dt);
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(dt.year, dt.month, dt.day);
  final daysAgo = today.difference(thatDay).inDays;

  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (daysAgo == 0) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  if (daysAgo == 1) return 'yday';
  if (diff.inDays < 7) {
    const w = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return w[dt.weekday - 1];
  }
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final dd = dt.day.toString().padLeft(2, '0');
  if (dt.year == now.year) return '$dd ${m[dt.month - 1]}';
  return '$dd ${m[dt.month - 1]} ${dt.year}';
}
