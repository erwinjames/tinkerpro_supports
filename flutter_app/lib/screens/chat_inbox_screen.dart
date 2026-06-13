import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/chat_models.dart';
import '../services/chat_prefs.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/chat_state.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'chat_new_conversation_screen.dart';
import 'chat_thread_screen.dart';

/// Station 05 · CHAT — the inbox. Replaces the placeholder ChatScreen.
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
  });

  final ChatService service;
  final ChatRealtimeService realtime;
  final ChatInbox inbox;
  final int myUserId;
  final ApiClient api;
  final ChatPrefs chatPrefs;

  /// Optional — when present, the thread screen exposes voice/video call
  /// buttons. Null until [HomeShell] has bootstrapped the user id.
  final CallService? calls;

  /// Called when the user taps the sign-out affordance on this screen.
  /// HomeShell wires this to the full-logout path that wipes FCM,
  /// caches, and routes to the LoginScreen.
  final VoidCallback onSignOut;

  /// Optional back affordance. Set when this screen is *pushed* (so the
  /// header shows a back arrow); left null when it's a root bottom-nav tab,
  /// where the nav bar itself is the way out.
  final VoidCallback? onBack;

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  @override
  void initState() {
    super.initState();
    widget.inbox.addListener(_onChange);
    widget.realtime.onlineUsers.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.inbox.removeListener(_onChange);
    widget.realtime.onlineUsers.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        shape: const RoundedRectangleBorder(),
        title: Text('SIGN OUT',
            style: Theme.of(context).textTheme.labelLarge),
        content: Text(
          "You'll be returned to the sign-in screen. "
          'Cached chat data on this device will be cleared.',
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
            child: Text('SIGN OUT',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Brand.signal)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.onSignOut();
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

  /// Long-press on a conversation row → bottom sheet with destructive
  /// actions. Currently only "delete" — leave + add-members live in the
  /// participants screen for non-DMs.
  Future<void> _showRowActions(Conversation c) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Brand.surface,
      builder: (_) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Brand.surface,
            border: Border(top: BorderSide(color: Brand.signal, width: 2)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(c.name.isEmpty ? '—' : c.name,
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              const Hairline(),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Brand.signal),
                title: const Text('Delete conversation'),
                subtitle: const Text(
                    'Removes every message and attachment for everyone.'),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || picked != 'delete') return;
    await _confirmAndDelete(c);
  }

  Future<void> _confirmAndDelete(Conversation c) async {
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

    final result = await widget.service.deleteConversation(c.id);
    if (!mounted) return;
    if (result.ok) {
      // Optimistic local removal — the conversation.removed broadcast
      // will also fire and reach this listener, but applying it here
      // makes the row vanish immediately on the actor's device.
      widget.inbox.removeLocally(c.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          'COULD NOT DELETE · ${result.error?.toUpperCase() ?? ""}'.trim(),
        )),
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
    final conversations = widget.inbox.conversations;

    final activeName = widget.api.username;
    final displayName =
        (activeName == null || activeName.isEmpty) ? null : activeName;
    final you =
        displayName == null ? 'YOU' : 'YOU=${displayName.toUpperCase()}';
    return StationScaffold(
      stationNumber: '05',
      stationLabel: 'CHAT · INBOX · $you',
      title: 'Direct messages.',
      showBottomBrand: false,
      onBack: widget.onBack,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StationAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: widget.inbox.reload,
          ),
          const SizedBox(width: 4),
          StationAction(
            icon: Icons.logout,
            tooltip: 'Sign out',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      belowRule: StationAction(
        icon: Icons.edit_outlined,
        tooltip: 'New conversation',
        onPressed: _openNewConversation,
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
        onRefresh: widget.inbox.reload,
        child: conversations.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 48),
                  // No loading spinner here on purpose — the inbox is warmed
                  // at app startup, so by the time this screen opens it's
                  // already hydrated. Show the empty state directly; pull to
                  // refresh shows the RefreshIndicator if the user wants it.
                  Column(
                    children: [
                      const EmptyState(
                        label: 'No conversations',
                        hint:
                            'Start a direct message by tapping the pencil above.',
                      ),
                      const SizedBox(height: 28),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Wrong account? You are signed in as '
                          '${displayName ?? 'this account'}. Tap the logout '
                          'icon in the header (top right) to switch.',
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
                itemCount: conversations.length,
                separatorBuilder: (_, _) => const Hairline(),
                itemBuilder: (_, i) {
                  final c = conversations[i];
                  // Live presence — if the realtime set knows the peer is
                  // online, trust it; otherwise fall back to the inbox
                  // payload's snapshot.
                  final livePeerOnline = c.peer != null &&
                      widget.realtime.onlineUsers.value.contains(c.peer!.id);
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
    final preview = lastMsg == null
        ? '—'
        : (lastMsg.body.trim().isNotEmpty
            ? lastMsg.body
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
            _PresenceDot(online: peerOnline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name.isEmpty ? '—' : c.name,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                Text(
                  _formatTime(c.lastActivityAt),
                  style: text.labelMedium,
                ),
                if (c.unreadCount > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Brand.signal,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      c.unreadCount > 99 ? '99+' : c.unreadCount.toString(),
                      style: const TextStyle(
                        color: Brand.canvas,
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
        color: online ? Brand.signal : Brand.rule,
      ),
    );
  }
}

/// Compact timestamp for inbox rows. Prioritises recency:
///   < 60s          → 'NOW'
///   < 60m          → '12m'
///   same day       → '14:22'
///   yesterday      → 'YDAY'
///   this week      → 'Mon' (abbreviated weekday)
///   this year      → '05 Apr'
///   older          → '05 Apr 2024'
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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final dd = dt.day.toString().padLeft(2, '0');
  if (dt.year == now.year) return '$dd ${m[dt.month - 1]}';
  return '$dd ${m[dt.month - 1]} ${dt.year}';
}
