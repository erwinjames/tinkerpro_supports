import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/chat_models.dart';
import '../services/chat_prefs.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'chat_new_conversation_screen.dart';
import 'notification_panel_screen.dart';
import 'chat_thread_screen.dart';

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
    this.onOpenSettings,
    this.notifications,
    this.calls,
    this.onBack,
  });

  final ChatService service;
  final ChatRealtimeService realtime;
  final ChatInbox inbox;
  final int myUserId;
  final ApiClient api;
  final ChatPrefs chatPrefs;

  final CallService? calls;

  final VoidCallback onSignOut;

  final VoidCallback? onOpenSettings;

  final NotificationCenter? notifications;

  final VoidCallback? onBack;

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

enum _InboxView { inbox, requests, archived }

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  _InboxView _view = _InboxView.inbox;

  bool get _canMessageRequests =>
      widget.api.hasPermission('chat') &&
      widget.api.hasPermission('messageRequests');

  List<Conversation> get _requests => widget.inbox.conversations
      .where((c) => c.isFacebookRequest && !c.isArchived)
      .toList();

  int get _requestsUnread => _requests.where((c) => c.unreadCount > 0).length;

  List<Conversation> get _archived =>
      widget.inbox.conversations.where((c) => c.isArchived).toList();

  List<Conversation> get _visibleRows {
    switch (_view) {
      case _InboxView.requests:
        return _requests;
      case _InboxView.archived:
        return _archived;
      case _InboxView.inbox:
        // A conversation nobody has written in yet is noise — it carries no
        // preview and nothing to read. It reappears the moment it has a
        // message. Requests and archived views are left unfiltered so
        // nothing silently vanishes from them.
        return widget.inbox.conversations
            .where((c) =>
                !c.isArchived && !c.isFacebookRequest && c.lastMessage != null)
            .toList();
    }
  }

  Future<void> _setArchived(Conversation c, bool archived) async {
    widget.inbox.setArchivedLocally(c.id, archived);
    final ok = await widget.service.setConversationArchived(c.id, archived);
    if (!mounted) return;
    if (!ok) {
      widget.inbox.setArchivedLocally(c.id, !archived);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(archived ? 'Could not archive' : 'Could not unarchive'),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(archived ? 'Conversation archived' : 'Moved to inbox'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _setArchived(c, !archived),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.inbox.addListener(_onChange);
    widget.realtime.onlineUsers.addListener(_onChange);
    widget.notifications?.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.inbox.removeListener(_onChange);
    widget.realtime.onlineUsers.removeListener(_onChange);
    widget.notifications?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.brand.surface,
        shape: const RoundedRectangleBorder(),
        title: Text('SIGN OUT', style: Theme.of(context).textTheme.labelLarge),
        content: Text(
          "You'll be returned to the sign-in screen. "
          'Cached chat data on this device will be cleared.',
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
              'SIGN OUT',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: Brand.signal),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.onSignOut();
  }

  Future<void> _openNotifications() async {
    final center = widget.notifications;
    if (center == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationPanelScreen(center: center),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openNewConversation() async {
    final convId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ChatNewConversationScreen(service: widget.service),
      ),
    );
    if (!mounted || convId == null) return;
    await widget.inbox.reload();
    _openThread(convId);
  }

  Future<void> _showRowActions(Conversation c) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.brand.surface,
      builder: (_) => SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: context.brand.surface,
            border: Border(top: BorderSide(color: Brand.signal, width: 2)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  c.name.isEmpty ? '—' : c.name,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const Hairline(),
              if (c.isFacebook && _canMessageRequests && _canMoveFacebook(c))
                ListTile(
                  leading: Icon(
                    c.fbMoved == 1 ? Icons.reply : Icons.move_to_inbox,
                    color: context.brand.signal,
                  ),
                  title: Text(
                    c.fbMoved == 1 ? 'Back to Page Chat' : 'Move to inbox',
                  ),
                  subtitle: Text(
                    c.fbMoved == 1
                        ? 'Returns it to the queue and drops members without '
                            'Facebook access.'
                        : 'Shares it with the support team and moves it out '
                            'of the queue.',
                  ),
                  onTap: () => Navigator.of(context)
                      .pop(c.fbMoved == 1 ? 'fb_return' : 'fb_move'),
                ),
              ListTile(
                leading: Icon(
                  c.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  color: context.brand.paperDim,
                ),
                title: Text(
                  c.isArchived ? 'Move to inbox' : 'Archive conversation',
                ),
                subtitle: Text(
                  c.isArchived
                      ? 'Show it in your inbox again.'
                      : 'Hides it from your inbox. Only affects you.',
                ),
                onTap: () => Navigator.of(context).pop('archive'),
              ),
              if (!c.isFacebook)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Brand.danger,
                  ),
                  title: const Text('Delete conversation'),
                  subtitle: const Text(
                    'Removes every message and attachment for everyone.',
                  ),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked == null) return;
    if (picked == 'archive') {
      await _setArchived(c, !c.isArchived);
      return;
    }
    if (picked == 'fb_move') {
      await _moveFacebook(c, toInbox: true);
      return;
    }
    if (picked == 'fb_return') {
      await _moveFacebook(c, toInbox: false);
      return;
    }
    if (picked == 'delete') await _confirmAndDelete(c);
  }

  /// Moving a page thread into the inbox is open to anyone handling the
  /// queue; sending one back is reserved for super admins, since it drops
  /// every member without Facebook access.
  bool _canMoveFacebook(Conversation c) =>
      c.fbMoved == 1 ? widget.api.isSuperAdmin : true;

  Future<void> _moveFacebook(Conversation c, {required bool toInbox}) async {
    bool ok;
    int removed = 0;
    if (toInbox) {
      ok = await widget.service.moveRequestToInbox(c.id);
    } else {
      final res = await widget.service.returnRequestToFacebook(c.id);
      ok = res.ok;
      removed = res.removed;
    }
    if (!mounted) return;
    if (ok) {
      await widget.inbox.reload();
      if (!mounted) return;
      setState(() => _view = toInbox ? _InboxView.inbox : _InboxView.requests);
    }

    final String message;
    if (!ok) {
      message = 'Could not move this conversation';
    } else if (toInbox) {
      message = 'Moved to inbox — the support team can see it now';
    } else if (removed > 0) {
      message = 'Returned to Page Chat — removed $removed '
          '${removed == 1 ? 'member' : 'members'} without Facebook access';
    } else {
      message = 'Returned to Page Chat';
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmAndDelete(Conversation c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.brand.surface,
        shape: const RoundedRectangleBorder(),
        title: Text(
          'DELETE CONVERSATION',
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

    final result = await widget.service.deleteConversation(c.id);
    if (!mounted) return;
    if (result.ok) {
      widget.inbox.removeLocally(c.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'COULD NOT DELETE · ${result.error?.toUpperCase() ?? ""}'.trim(),
          ),
        ),
      );
    }
  }

  void _openThread(int conversationId) {
    final match = widget.inbox.conversations
        .where((c) => c.id == conversationId)
        .toList();
    final conversation = match.isNotEmpty ? match.first : null;
    widget.inbox.markLocallyRead(conversationId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          conversationId: conversationId,
          conversation: conversation,
          myUserId: widget.myUserId,
          service: widget.service,
          realtime: widget.realtime,
          api: widget.api,
          chatPrefs: widget.chatPrefs,
          calls: widget.calls,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;

    final activeName = widget.api.username;
    final displayName = (activeName == null || activeName.isEmpty)
        ? null
        : activeName;
    return StationScaffold(
      title: 'Messages',
      showBottomBrand: false,
      onBack: widget.onBack,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NotificationBell(
            count: widget.notifications?.unread ?? 0,
            onPressed: _openNotifications,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, size: 21),
            position: PopupMenuPosition.under,
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  widget.inbox.reload();
                  break;
                case 'archived':
                  setState(() => _view = _InboxView.archived);
                  break;
                case 'settings':
                  widget.onOpenSettings?.call();
                  break;
                case 'signout':
                  _confirmSignOut();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.refresh, size: 20),
                  title: Text('Refresh'),
                ),
              ),
              const PopupMenuItem(
                value: 'archived',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.archive_outlined, size: 20),
                  title: Text('Archived'),
                ),
              ),
              if (widget.onOpenSettings != null)
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.settings_outlined, size: 20),
                    title: Text('Settings'),
                  ),
                ),
              const PopupMenuItem(
                value: 'signout',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout, size: 20),
                  title: Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
      fab: _view != _InboxView.inbox
          ? null
          : FloatingActionButton(
              onPressed: _openNewConversation,
              tooltip: 'New conversation',
              elevation: 2,
              child: const Icon(Icons.edit_outlined),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_view == _InboxView.archived) ...[
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to inbox',
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => setState(() => _view = _InboxView.inbox),
                  style: IconButton.styleFrom(
                    foregroundColor: context.brand.paper,
                    minimumSize: const Size(40, 40),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Archived',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '${_archived.length}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else if (_canMessageRequests) ...[
            _InboxTabs(
              view: _view,
              requestsUnread: _requestsUnread,
              onChanged: (v) => setState(() => _view = v),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: RefreshIndicator(
              color: Brand.signal,
              backgroundColor: context.brand.surface,
              onRefresh: widget.inbox.reload,
              child: rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 40),
                        if (_view == _InboxView.archived)
                          const EmptyState(
                            icon: Icons.archive_outlined,
                            label: 'No archived chats',
                            hint: 'Long-press a conversation to archive it.',
                          )
                        else if (_view == _InboxView.requests)
                          const EmptyState(
                            icon: Icons.facebook,
                            label: 'No page chats',
                            hint:
                                'Unclaimed Messenger threads land here as they arrive.',
                          )
                        else
                          Column(
                            children: [
                              const EmptyState(
                                label: 'No conversations',
                                hint:
                                    'Start a direct message with the compose button.',
                              ),
                              const SizedBox(height: 24),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                ),
                                child: Text(
                                  'Wrong account? You are signed in as '
                                  '${displayName ?? 'this account'}. '
                                  'Sign out from the menu in the header.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Hairline(),
                      itemBuilder: (_, i) {
                        final c = rows[i];

                        final livePeerOnline =
                            c.peer != null &&
                            widget.realtime.onlineUsers.value.contains(
                              c.peer!.id,
                            );
                        return _ConversationRow(
                          conversation: c,
                          myUserId: widget.myUserId,
                          peerOnline:
                              livePeerOnline || (c.peer?.isOnline ?? false),
                          onTap: () => _openThread(c.id),
                          onLongPress: () => _showRowActions(c),
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

class _MessengerBadge extends StatelessWidget {
  const _MessengerBadge();

  static const Color _fbBlue = Color(0xFF0866FF);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: _fbBlue.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.facebook, size: 16, color: _fbBlue),
    );
  }
}

class _AiPill extends StatelessWidget {
  const _AiPill();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: brand.surfaceHi,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: brand.rule),
      ),
      child: Text(
        'AI',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: brand.paperDim,
        ),
      ),
    );
  }
}

class _InboxTabs extends StatelessWidget {
  const _InboxTabs({
    required this.view,
    required this.requestsUnread,
    required this.onChanged,
  });

  final _InboxView view;
  final int requestsUnread;
  final ValueChanged<_InboxView> onChanged;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: brand.surfaceHi,
        borderRadius: BorderRadius.circular(Brand.radius),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tab(
              context,
              label: 'Inbox',
              selected: view == _InboxView.inbox,
              onTap: () => onChanged(_InboxView.inbox),
            ),
          ),
          Expanded(
            child: _tab(
              context,
              label: 'Page Chat',
              badge: requestsUnread,
              selected: view == _InboxView.requests,
              onTap: () => onChanged(_InboxView.requests),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    final brand = context.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radiusSm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? brand.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          border: Border.all(color: selected ? brand.rule : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? brand.paper : brand.paperDim,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Brand.danger,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversation,
    required this.myUserId,
    required this.peerOnline,
    required this.onTap,
    this.onLongPress,
  });

  final Conversation conversation;
  final int myUserId;
  final bool peerOnline;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = conversation;
    final lastMsg = c.lastMessage;
    final isFromMe = lastMsg?.senderId == myUserId;
    // A reply carries the quote marker in its body; show only what was
    // actually typed, as the web inbox does.
    final quoted = lastMsg == null ? null : parseQuotedBody(lastMsg.body);
    final bodyText = (quoted?.reply ?? lastMsg?.body ?? '').trim();
    final preview = lastMsg == null
        ? '—'
        : (bodyText.isNotEmpty
              ? (quoted != null ? '↩ $bodyText' : bodyText)
              : (lastMsg.attachments.isNotEmpty
                    ? (lastMsg.attachments.first.isImage
                          ? '[image]'
                          : '[file: ${lastMsg.attachments.first.originalName}]')
                    : '—'));
    final subtitle = lastMsg == null
        ? 'No messages yet'
        : (isFromMe ? 'You: $preview' : preview);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.isFacebook)
              const _MessengerBadge()
            else
              _PresenceDot(online: peerOnline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.name.isEmpty ? '—' : c.name,
                          style: text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (c.isAiOwned) ...[
                        const SizedBox(width: 6),
                        const _AiPill(),
                      ],
                      if (c.isPriority) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.flag, size: 13, color: Brand.danger),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_formatTime(c.lastActivityAt), style: text.labelMedium),
                if (c.unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Brand.signal,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      c.unreadCount > 99 ? '99+' : c.unreadCount.toString(),
                      style: const TextStyle(
                        color: Brand.onSignal,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(top: 7),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? Brand.signal : context.brand.rule,
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

  if (diff.inSeconds < 60) return 'NOW';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (daysAgo == 0) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  if (daysAgo == 1) return 'YDAY';
  if (daysAgo < 7) {
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
