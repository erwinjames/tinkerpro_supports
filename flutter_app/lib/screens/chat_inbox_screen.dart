import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/chat_models.dart';
import '../services/chat_prefs.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../services/notification_center.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'chat_new_conversation_screen.dart';
import 'notification_panel.dart';
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
    this.sharedNotifications,
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

  final AppNotificationCenter? notifications;
  final NotificationCenter? sharedNotifications;

  final VoidCallback? onBack;

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

enum _InboxView { inbox, requests, archived }

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  _InboxView _view = _InboxView.inbox;
  final _search = TextEditingController();
  String _query = '';
  late bool _settled = widget.inbox.conversations.isNotEmpty;

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
        return widget.inbox.conversations
            .where(
              (c) =>
                  !c.isArchived &&
                  !c.isFacebookRequest &&
                  c.lastMessage != null,
            )
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
        persist: false,
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
    _search.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {
      if (!widget.inbox.loading) _settled = true;
    });
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          "You'll be returned to the sign-in screen. "
          'Cached chat data on this device will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.onSignOut();
  }

  Future<void> _openNotifications() async {
    final shared = widget.sharedNotifications;
    if (shared == null) return;
    await NotificationPanel.show(context, shared);
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
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    AppAvatar(name: c.name.isEmpty ? '?' : c.name, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        c.name.isEmpty ? '—' : c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const Hairline(),
              if (c.isFacebook && _canMessageRequests && _canMoveFacebook(c))
                ListTile(
                  leading: Icon(
                    c.fbMoved == 1
                        ? Icons.reply_rounded
                        : Icons.move_to_inbox_rounded,
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
                  onTap: () => Navigator.of(
                    context,
                  ).pop(c.fbMoved == 1 ? 'fb_return' : 'fb_move'),
                ),
              ListTile(
                leading: Icon(
                  c.isArchived
                      ? Icons.unarchive_rounded
                      : Icons.archive_rounded,
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
                    Icons.delete_outline_rounded,
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
      message =
          'Returned to Page Chat — removed $removed '
          '${removed == 1 ? 'member' : 'members'} without Facebook access';
    } else {
      message = 'Returned to Page Chat';
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmAndDelete(Conversation c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: const Text(
          'This will permanently remove every message and attachment '
          'in this conversation for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
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
            'Could not delete conversation${result.error == null || result.error!.isEmpty ? '' : ' · ${result.error}'}',
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

  List<Conversation> _filtered(List<Conversation> rows) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              (c.peer?.username.toLowerCase().contains(q) ?? false) ||
              _previewOf(c).toLowerCase().contains(q),
        )
        .toList();
  }

  String _labelOf(_InboxView v) => switch (v) {
    _InboxView.inbox => 'Inbox',
    _InboxView.requests => 'Page Chat',
    _InboxView.archived => 'Archived',
  };

  int? _countOf(_InboxView v) {
    final n = switch (v) {
      _InboxView.inbox =>
        widget.inbox.conversations
            .where(
              (c) =>
                  !c.isArchived &&
                  !c.isFacebookRequest &&
                  c.lastMessage != null &&
                  c.unreadCount > 0,
            )
            .length,
      _InboxView.requests => _requestsUnread,
      _InboxView.archived => _archived.length,
    };
    return n > 0 ? n : null;
  }

  String? _avatarUrl(String? relPath) {
    if (relPath == null || relPath.isEmpty) return null;
    final clean = relPath.replaceAll(RegExp(r'^/+'), '');
    return '${widget.api.baseUrl}/$clean';
  }

  Widget _buildMenu(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      position: PopupMenuPosition.under,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        foregroundColor: Colors.white,
        fixedSize: const Size(44, 44),
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
      icon: const Icon(Icons.more_vert_rounded, size: 21, color: Colors.white),
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
            leading: Icon(Icons.refresh_rounded, size: 20),
            title: Text('Refresh'),
          ),
        ),
        const PopupMenuItem(
          value: 'archived',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.archive_rounded, size: 20),
            title: Text('Archived'),
          ),
        ),
        if (widget.onOpenSettings != null)
          const PopupMenuItem(
            value: 'settings',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.settings_rounded, size: 20),
              title: Text('Settings'),
            ),
          ),
        const PopupMenuItem(
          value: 'signout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, size: 20),
            title: Text('Sign out'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, String? displayName) {
    if (_query.trim().isNotEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        label: 'No matches',
        hint: 'Nothing matches “${_query.trim()}”.',
        action: GhostButton(
          label: 'Clear search',
          icon: Icons.close_rounded,
          onPressed: () => setState(() {
            _search.clear();
            _query = '';
          }),
        ),
      );
    }
    if (widget.inbox.authFailed) {
      return EmptyState(
        icon: Icons.lock_outline_rounded,
        label: 'Could not load messages',
        hint:
            widget.inbox.authFailedMessage ??
            'Your session may have expired. Try again or sign in again.',
        action: GhostButton(
          label: 'Retry',
          icon: Icons.refresh_rounded,
          onPressed: widget.inbox.reload,
        ),
      );
    }
    switch (_view) {
      case _InboxView.archived:
        return const EmptyState(
          icon: Icons.archive_rounded,
          label: 'No archived chats',
          hint: 'Long-press a conversation to archive it.',
        );
      case _InboxView.requests:
        return const EmptyState(
          icon: Icons.facebook_rounded,
          label: 'No page chats',
          hint: 'Unclaimed Messenger threads land here as they arrive.',
        );
      case _InboxView.inbox:
        return Column(
          children: [
            const EmptyState(
              icon: Icons.forum_rounded,
              label: 'No conversations',
              hint: 'Start a direct message with the compose button.',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Wrong account? You are signed in as '
                '${displayName ?? 'this account'}. '
                'Sign out from the menu in the header.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered(_visibleRows);

    final activeName = widget.api.username;
    final displayName = (activeName == null || activeName.isEmpty)
        ? null
        : activeName;
    final unread = widget.inbox.unreadTotal;
    final views = [
      _InboxView.inbox,
      if (_canMessageRequests) _InboxView.requests,
      _InboxView.archived,
    ];
    final showSkeleton = !_settled && widget.inbox.conversations.isEmpty;
    return StationScaffold(
      stationLabel: 'Chat',
      title: 'Messages',
      subtitle: unread == 0
          ? 'All caught up'
          : '$unread unread ${unread == 1 ? 'message' : 'messages'}',
      showBottomBrand: false,
      onBack: widget.onBack,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.sharedNotifications != null) ...[
            ListenableBuilder(
              listenable: widget.sharedNotifications!,
              builder: (context, _) => NotificationBell(
                count: widget.sharedNotifications!.unseenCount,
                onPressed: _openNotifications,
              ),
            ),
            const SizedBox(width: 8),
          ],
          _buildMenu(context),
        ],
      ),
      fab: _view != _InboxView.inbox
          ? null
          : FloatingActionButton(
              onPressed: _openNewConversation,
              tooltip: 'New conversation',
              elevation: 2,
              child: const Icon(Icons.edit_rounded),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _search,
            hint: 'Search conversations',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          ChoicePills<_InboxView>(
            options: views,
            value: _view,
            onChanged: (v) => setState(() => _view = v),
            labelOf: _labelOf,
            countOf: _countOf,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: showSkeleton
                ? const SkeletonList(count: 7)
                : RefreshIndicator(
                    color: Brand.signal,
                    backgroundColor: context.brand.surface,
                    onRefresh: widget.inbox.reload,
                    child: rows.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 24),
                              _buildEmpty(context, displayName),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final c = rows[i];

                              final livePeerOnline =
                                  c.peer != null &&
                                  widget.realtime.onlineUsers.value.contains(
                                    c.peer!.id,
                                  );
                              return _Stagger(
                                index: i,
                                child: _ConversationRow(
                                  conversation: c,
                                  myUserId: widget.myUserId,
                                  peerOnline:
                                      livePeerOnline ||
                                      (c.peer?.isOnline ?? false),
                                  avatarUrl: _avatarUrl(c.peer?.avatar),
                                  headers: widget.api.authHeaders(),
                                  onTap: () => _openThread(c.id),
                                  onLongPress: () => _showRowActions(c),
                                ),
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

String _previewOf(Conversation c) {
  final lastMsg = c.lastMessage;
  if (lastMsg == null) return '';
  final quoted = parseQuotedBody(lastMsg.body);
  final bodyText = (quoted?.reply ?? lastMsg.body).trim();
  if (bodyText.isNotEmpty) return quoted != null ? '↩ $bodyText' : bodyText;
  if (lastMsg.attachments.isNotEmpty) {
    return lastMsg.attachments.first.isImage
        ? 'Photo'
        : 'File: ${lastMsg.attachments.first.originalName}';
  }
  return '—';
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: brand.paperDim,
        ),
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({
    required this.conversation,
    required this.online,
    this.url,
    this.headers,
  });

  static const Color _fbBlue = Color(0xFF0866FF);
  static const double _size = 46;

  final Conversation conversation;
  final bool online;
  final String? url;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final c = conversation;
    final isGroup = c.type == 'group' || c.type == 'channel';
    final Widget base;
    if (isGroup && (url == null)) {
      base = Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: b.tint(Brand.navy, b.isDark ? 0.4 : 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          c.type == 'channel' ? Icons.tag_rounded : Icons.group_rounded,
          size: 22,
          color: b.isDark ? Colors.white : Brand.navy,
        ),
      );
    } else {
      base = AppAvatar(
        name: c.name.isEmpty ? '?' : c.name,
        size: _size,
        imageUrl: url,
        headers: headers,
      );
    }
    Widget? badge;
    if (c.isFacebook) {
      badge = Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: _fbBlue,
          shape: BoxShape.circle,
          border: Border.all(color: b.surface, width: 2),
        ),
        child: const Icon(
          Icons.facebook_rounded,
          size: 12,
          color: Colors.white,
        ),
      );
    } else if (c.type == 'dm' && c.peer != null) {
      badge = Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: online ? Brand.success : b.rule,
          shape: BoxShape.circle,
          border: Border.all(color: b.surface, width: 2.5),
        ),
      );
    }
    return Semantics(
      label: c.type == 'dm' && c.peer != null && !c.isFacebook
          ? (online ? 'Online' : 'Offline')
          : null,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            base,
            if (badge != null) Positioned(right: -1, bottom: -1, child: badge),
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
    this.avatarUrl,
    this.headers,
    this.onLongPress,
  });

  final Conversation conversation;
  final int myUserId;
  final bool peerOnline;
  final String? avatarUrl;
  final Map<String, String>? headers;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final c = conversation;
    final lastMsg = c.lastMessage;
    final isFromMe = lastMsg?.senderId == myUserId;
    final preview = _previewOf(c);
    final subtitle = lastMsg == null
        ? 'No messages yet'
        : (isFromMe ? 'You: $preview' : preview);
    final unread = c.unreadCount > 0;

    return Semantics(
      button: true,
      label: unread ? '${c.name}, ${c.unreadCount} unread' : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          boxShadow: b.shadow,
        ),
        child: AppCard(
          padding: EdgeInsets.zero,
          radius: Brand.radiusLg,
          color: unread
              ? Color.alphaBlend(b.signal.withValues(alpha: 0.06), b.surface)
              : null,
          borderColor: unread ? b.signal.withValues(alpha: 0.45) : null,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _ConversationAvatar(
                      conversation: c,
                      online: peerOnline,
                      url: avatarUrl,
                      headers: headers,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  c.name.isEmpty ? '—' : c.name,
                                  style: text.titleSmall?.copyWith(
                                    fontWeight: unread
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
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
                                const Icon(
                                  Icons.flag_rounded,
                                  size: 14,
                                  color: Brand.danger,
                                  semanticLabel: 'Priority',
                                ),
                              ],
                              const SizedBox(width: 8),
                              Text(
                                _formatTime(c.lastActivityAt),
                                style: text.labelMedium?.copyWith(
                                  color: unread ? b.signalInk : b.paperDim,
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  subtitle,
                                  style: text.bodySmall?.copyWith(
                                    color: unread ? b.paper : b.paperDim,
                                    fontWeight: unread
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (unread) ...[
                                const SizedBox(width: 8),
                                _UnreadBadge(count: c.unreadCount),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatefulWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  State<_UnreadBadge> createState() => _UnreadBadgeState();
}

class _UnreadBadgeState extends State<_UnreadBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  bool get _reduce => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void didUpdateWidget(covariant _UnreadBadge old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count && !_reduce) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.count > 99 ? '99+' : widget.count.toString();
    return ScaleTransition(
      scale: Tween<double>(
        begin: 1.28,
        end: 1,
      ).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOutBack)),
      child: Container(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Brand.orange,
          borderRadius: BorderRadius.circular(11),
        ),
        child: AnimatedSwitcher(
          duration: _reduce ? Duration.zero : const Duration(milliseconds: 220),
          child: Text(
            label,
            key: ValueKey(label),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _Stagger extends StatefulWidget {
  const _Stagger({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<_Stagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
      return;
    }
    Future<void>.delayed(
      Duration(milliseconds: 40 * (widget.index.clamp(0, 6))),
      () {
        if (mounted) _c.forward();
      },
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
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

  if (diff.inSeconds < 60) return 'Now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (daysAgo == 0) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  if (daysAgo == 1) return 'Yesterday';
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
