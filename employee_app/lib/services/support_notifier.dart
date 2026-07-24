import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'chat_realtime.dart';
import 'os_notifications.dart';
import 'ringtone_service.dart';

/// Global "support agent is trying to reach you" notifier.
///
/// One place subscribes to [ChatRealtimeService.messageEvents] for the
/// store conversation and, whenever a message from someone OTHER than
/// this employee arrives while they're not actively looking at the chat,
/// it:
///   • bumps [unread] (drives the header badge / chat-entry dot),
///   • plays the chat chime,
///   • fires an OS/system notification (via [OsNotifications]),
///   • and notifies listeners so the landing screen can drop an in-app
///     banner.
///
/// [chatOpen] is flipped by [EmployeeChatScreen] while it's on screen so
/// none of the above fires (and the count clears) while the cashier is
/// already reading the thread — the chat screen surfaces new messages
/// inline and plays its own ping.
///
/// A [ChangeNotifier] so widgets can `addListener` to rebuild the badge.
class SupportNotifier extends ChangeNotifier {
  SupportNotifier._();
  static final SupportNotifier instance = SupportNotifier._();

  StreamSubscription<ChatMessage>? _sub;
  int _meId = 0;
  int _convId = 0;

  int _unread = 0;
  bool _chatOpen = false;
  ChatMessage? _lastMessage;

  int get unread => _unread;
  bool get hasUnread => _unread > 0;
  ChatMessage? get lastMessage => _lastMessage;
  bool get chatOpen => _chatOpen;

  /// Set by the app to bring the support chat to the foreground when a
  /// notification (in-app banner or OS toast) is tapped.
  VoidCallback? onOpenChat;

  /// Begin watching [realtime] for messages in the [convId] conversation.
  /// Idempotent for the same (meId, convId) — re-attaching after a mobile
  /// QR re-sync swaps the subscription.
  void attach({
    required ChatRealtimeService realtime,
    required int meId,
    required int convId,
  }) {
    if (_sub != null && _meId == meId && _convId == convId) return;
    _sub?.cancel();
    _meId = meId;
    _convId = convId;
    _sub = realtime.messageEvents.listen(_onMessage);
  }

  /// Tear down on session end (mobile idle logout, store reset).
  void detach() {
    _sub?.cancel();
    _sub = null;
    _meId = 0;
    _convId = 0;
    final had = _unread != 0 || _lastMessage != null;
    _unread = 0;
    _lastMessage = null;
    if (had) notifyListeners();
  }

  /// True while a chat view is on screen. Setting it true clears the
  /// unread count (they're reading it now) and suppresses further
  /// notifications until the chat is closed again.
  set chatOpen(bool value) {
    _chatOpen = value;
    if (value && _unread != 0) {
      _unread = 0;
      notifyListeners();
    }
  }

  /// Clear the unread badge without changing [chatOpen] — e.g. the user
  /// dismissed the banner or opened the thread from the landing.
  void markAllRead() {
    if (_unread == 0) return;
    _unread = 0;
    notifyListeners();
  }

  void _onMessage(ChatMessage m) {
    // Only the store's own conversation, and never our own echo.
    if (m.conversationId != _convId) return;
    if (m.senderId == _meId) return;
    _lastMessage = m;
    // Already reading the thread — the chat screen handles it (inline +
    // its own ping). Don't double-notify.
    if (_chatOpen) return;
    _unread++;
    notifyListeners();
    unawaited(RingtoneService.instance.ping());
    unawaited(OsNotifications.instance
        .show('TinkerPro support', messagePreview(m.body)));
  }

  /// A short, single-line preview of a message body for a notification.
  /// Collapses whitespace and trims to a sane length.
  static String messagePreview(String body) {
    final oneLine = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.isEmpty) return 'You have a new message from support.';
    const max = 120;
    return oneLine.length <= max ? oneLine : '${oneLine.substring(0, max - 1)}…';
  }
}
