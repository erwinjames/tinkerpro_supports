import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'chat_realtime.dart';
import 'chat_service.dart';
import 'ringtone_service.dart';

/// Always-on inbox state. Seeded via REST on construction and kept in
/// sync by `conversation.activity` events streamed from [ChatRealtimeService].
///
/// Widgets listen via [addListener]; the CHAT tab badge listens to
/// [unreadTotal] to decide whether to render its red-dot overlay.
class ChatInbox extends ChangeNotifier {
  ChatInbox(this._service, this._realtime) {
    _activitySub = _realtime.inboxEvents.listen(_applyActivity);
    _lifecycleSub = _realtime.lifecycleEvents.listen(_applyLifecycle);
    _startPolling();
  }

  final ChatService _service;
  final ChatRealtimeService _realtime;
  StreamSubscription<ConversationActivity>? _activitySub;
  StreamSubscription<ConversationLifecycle>? _lifecycleSub;
  Timer? _pollTimer;

  /// Polling fallback — keeps the inbox fresh even when the Pusher /
  /// Soketi WebSocket is unreachable. `load()` is already idempotent and
  /// no-ops when another load is in flight, so this is safe to fire on a
  /// timer alongside realtime.
  static const Duration kPollInterval = Duration(seconds: 5);
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(kPollInterval, (_) => load());
  }

  List<Conversation> _conversations = const [];
  bool _loading = false;

  List<Conversation> get conversations => _conversations;
  bool get loading => _loading;

  int get unreadTotal =>
      _conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

  /// Set whenever a chat REST call returned Unauthorized — surfaces the
  /// stale-session state to whoever is listening (HomeShell consumes it
  /// to bounce the user back to login).
  bool _authFailed = false;
  bool get authFailed => _authFailed;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      _conversations = await _service.inbox();
      _authFailed = false;
    } on ChatAuthException {
      _authFailed = true;
      _conversations = const [];
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> reload() => load();

  /// The caller has just opened (or scrolled through) the conversation, so
  /// locally zero its unread badge. Server-side cursor advancement is a
  /// Phase 4 concern (`chat.markRead`).
  void markLocallyRead(int conversationId) {
    var changed = false;
    _conversations = _conversations.map((c) {
      if (c.id == conversationId && c.unreadCount != 0) {
        changed = true;
        return c.copyWith(unreadCount: 0);
      }
      return c;
    }).toList();
    if (changed) notifyListeners();
  }

  void _applyLifecycle(ConversationLifecycle event) {
    if (event.added) {
      // We were just added to a conversation — REST-hydrate to get full
      // metadata (peer/name/last_message). Cheap at this scale and avoids
      // shipping full conv JSON over Pusher.
      final already =
          _conversations.any((c) => c.id == event.conversationId);
      if (!already) load();
    } else {
      final next =
          _conversations.where((c) => c.id != event.conversationId).toList();
      if (next.length != _conversations.length) {
        _conversations = next;
        notifyListeners();
      }
    }
  }

  /// Remove a conversation from the local list without a REST round-trip.
  /// Called immediately after chat.leaveConversation succeeds — the server
  /// also broadcasts conversation.removed, which would trigger the same
  /// path, but we apply it locally too for instant UI.
  void removeLocally(int conversationId) {
    final next =
        _conversations.where((c) => c.id != conversationId).toList();
    if (next.length != _conversations.length) {
      _conversations = next;
      notifyListeners();
    }
  }

  void _applyActivity(ConversationActivity activity) {
    final idx =
        _conversations.indexWhere((c) => c.id == activity.conversationId);
    if (idx == -1) {
      // Unknown conversation — the server has added us to one we don't
      // yet know about. Hydrate from REST to get full metadata.
      // Fire-and-forget; the reload will re-sort naturally.
      load();
      return;
    }

    final existing = _conversations[idx];
    final updated = existing.copyWith(
      lastMessage: Message(
        id: activity.lastMessageId,
        conversationId: activity.conversationId,
        senderId: activity.lastSenderId,
        body: activity.preview,
        clientNonce: '',
        createdAt: activity.createdAt,
      ),
      unreadCount: activity.unreadCount,
      lastActivityAt: activity.createdAt,
    );

    // Re-sort: bump this conversation to the top (most-recent activity).
    final next = List<Conversation>.from(_conversations)..removeAt(idx);
    next.insert(0, updated);
    _conversations = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _activitySub?.cancel();
    _lifecycleSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// Per-thread state. Created by ChatThreadScreen, disposed with it.
/// Subscribes to the conversation channel on construction and filters
/// `message.new` events to this conversation.
class ChatThread extends ChangeNotifier {
  ChatThread({
    required this.conversationId,
    required this.myUserId,
    required ChatService service,
    required ChatRealtimeService realtime,
  })  : _service = service,
        _realtime = realtime {
    _messageSub = _realtime.messageEvents
        .where((m) => m.conversationId == conversationId)
        .listen(_applyIncoming);
    _readSub = _realtime.readEvents.listen(_applyRead);
    _typingSub = _realtime.typingEvents
        .where((e) => e.conversationId == conversationId)
        .listen(_applyTyping);
    _realtime.subscribeConversation(conversationId);
    _hydrateReadCursors();
    _startPolling();
  }

  /// Polling fallback for incoming messages — runs alongside the realtime
  /// subscription so the open thread stays fresh even when the WebSocket is
  /// unreachable. Each fetched message is funnelled through [_applyIncoming]
  /// which de-dupes by `clientNonce` / `id`, so this is idempotent against
  /// realtime delivery.
  Timer? _pollTimer;
  bool _polling = false;
  static const Duration kPollInterval = Duration(milliseconds: 1500);

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(kPollInterval, (_) => _pollNew());
  }

  Future<void> _pollNew() async {
    if (_polling || _loading) return;
    _polling = true;
    try {
      final page = await _service.history(conversationId, limit: 30);
      for (final m in page.messages) {
        _applyIncoming(m);
      }
    } finally {
      _polling = false;
    }
  }

  final int conversationId;
  final int myUserId;
  final ChatService _service;
  final ChatRealtimeService _realtime;
  StreamSubscription<Message>? _messageSub;
  StreamSubscription<MessageRead>? _readSub;
  StreamSubscription<TypingEvent>? _typingSub;

  /// Other participants currently typing, keyed by user id. Value is an
  /// (expiry timestamp, display name) pair — expired entries are swept
  /// out on a short timer.
  final Map<int, _TypingInfo> _typing = {};
  Timer? _typingSweep;

  /// Debounced outbound typing notification. We only hit the server at
  /// most once per [kTypingNotifyInterval] while the user is actively
  /// typing — any further calls during that window are silenced.
  DateTime? _lastTypingNotifySentAt;
  static const Duration kTypingNotifyInterval = Duration(seconds: 2);
  static const Duration kTypingExpireAfter = Duration(seconds: 4);

  /// Snapshot of who is currently typing — names only, no ids. Used by
  /// the thread UI to render "Alice is typing…" / "Alice and Bob…".
  List<String> get typingNames {
    final now = DateTime.now();
    return _typing.values
        .where((t) => t.expiresAt.isAfter(now))
        .map((t) => t.username)
        .toList();
  }

  /// Other participants' read cursors, keyed by user_id. Used to render
  /// "Seen" / "Seen by N" indicators. Excludes our own user.
  final Map<int, int> _readCursors = <int, int>{};

  /// Total participant count from chat.conversation (used to size the
  /// "Seen by N of M" denominator if we ever want it). For now we only
  /// surface counts in groups/channels.
  int _totalParticipants = 0;

  Map<int, int> get readCursors => Map.unmodifiable(_readCursors);
  int get totalParticipants => _totalParticipants;

  /// The newest message id we've already reported as read to the server.
  /// Used by the debouncer to ensure we never POST the same value twice.
  int _lastReportedReadId = 0;
  Timer? _markReadTimer;

  /// Messages sorted NEWEST-FIRST (id DESC). The thread renders reversed
  /// so the newest message appears at the bottom.
  List<Message> _messages = const [];
  bool _loading = false;
  bool _hasMore = true;

  List<Message> get messages => _messages;
  bool get loading => _loading;
  bool get hasMore => _hasMore;

  Future<void> loadInitial() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    final page = await _service.history(conversationId, limit: 50);
    _messages = page.messages;
    _hasMore = page.hasMore;
    _loading = false;
    notifyListeners();
  }

  Future<void> loadOlder() async {
    if (_loading || !_hasMore || _messages.isEmpty) return;
    _loading = true;
    notifyListeners();
    final oldest = _messages.last.id ?? 0;
    final page =
        await _service.history(conversationId, beforeId: oldest, limit: 50);
    _messages = [..._messages, ...page.messages];
    _hasMore = page.hasMore;
    _loading = false;
    notifyListeners();
  }

  /// Optimistic send. Prepends a sending-state message, fires the REST
  /// call, then reconciles the optimistic row by `clientNonce`. Empty
  /// [body] is allowed if at least one attachment id is supplied.
  Future<void> send(String body, {List<Attachment> attachments = const []}) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    final nonce = ChatService.newNonce();
    final optimistic = Message(
      id: null,
      conversationId: conversationId,
      senderId: myUserId,
      body: trimmed,
      clientNonce: nonce,
      createdAt: DateTime.now().toIso8601String(),
      attachments: attachments,
      status: MessageStatus.sending,
    );
    _messages = [optimistic, ..._messages];
    notifyListeners();

    final server = await _service.send(
      conversationId: conversationId,
      body: trimmed,
      clientNonce: nonce,
      attachmentIds: attachments.map((a) => a.id).toList(),
    );
    if (server != null) {
      _reconcile(server);
    } else {
      _messages = _messages.map((m) {
        if (m.clientNonce == nonce && m.id == null) {
          return m.copyWith(status: MessageStatus.failed);
        }
        return m;
      }).toList();
      notifyListeners();
    }
  }

  Future<void> retry(Message failed) async {
    if (failed.status != MessageStatus.failed) return;
    // Flip back to sending and retry with the same nonce.
    _messages = _messages.map((m) {
      if (m.clientNonce == failed.clientNonce && m.id == null) {
        return m.copyWith(status: MessageStatus.sending);
      }
      return m;
    }).toList();
    notifyListeners();

    final server = await _service.send(
      conversationId: conversationId,
      body: failed.body,
      clientNonce: failed.clientNonce,
      attachmentIds: failed.attachments.map((a) => a.id).toList(),
    );
    if (server != null) {
      _reconcile(server);
    } else {
      _messages = _messages.map((m) {
        if (m.clientNonce == failed.clientNonce && m.id == null) {
          return m.copyWith(status: MessageStatus.failed);
        }
        return m;
      }).toList();
      notifyListeners();
    }
  }

  /// One-shot hydrate of other participants' read cursors. Falls back to
  /// an empty map if the call fails — the indicator just won't render.
  /// `chat.conversation` returns participants but not their cursors today;
  /// for MVP we treat the indicator as "live only" — it starts empty and
  /// fills in as `message.read` events arrive. We still call
  /// `chat.conversation` to count total participants for the "Seen by N" UI.
  Future<void> _hydrateReadCursors() async {
    final detail = await _service.conversation(conversationId);
    if (detail == null) return;
    _totalParticipants = detail.participants.length;
    notifyListeners();
  }

  /// Schedule a debounced mark-read for the newest visible message id.
  /// No-ops if the requested id is not greater than the last one we
  /// already reported.
  void scheduleMarkRead(int newestVisibleId) {
    if (newestVisibleId <= _lastReportedReadId) return;
    _markReadTimer?.cancel();
    _markReadTimer = Timer(const Duration(milliseconds: 500), () {
      _flushMarkRead(newestVisibleId);
    });
  }

  Future<void> _flushMarkRead(int targetId) async {
    if (targetId <= _lastReportedReadId) return;
    _lastReportedReadId = targetId;
    // Optimistic — if the server rejects we just won't re-fire (server is
    // monotonic anyway).
    await _service.markRead(conversationId, targetId);
  }

  void _applyRead(MessageRead event) {
    if (event.userId == myUserId) return; // ignore my own cursor advances
    final current = _readCursors[event.userId] ?? 0;
    if (event.messageId > current) {
      _readCursors[event.userId] = event.messageId;
      notifyListeners();
    }
  }

  void _applyTyping(TypingEvent event) {
    if (event.userId == myUserId) return; // never show myself
    _typing[event.userId] = _TypingInfo(
      username: event.username,
      expiresAt: DateTime.now().add(kTypingExpireAfter),
    );
    notifyListeners();
    _ensureTypingSweep();
  }

  void _ensureTypingSweep() {
    _typingSweep?.cancel();
    _typingSweep = Timer(const Duration(seconds: 1), () {
      final now = DateTime.now();
      final before = _typing.length;
      _typing.removeWhere((_, t) => t.expiresAt.isBefore(now));
      if (_typing.length != before) notifyListeners();
      if (_typing.isNotEmpty) _ensureTypingSweep();
    });
  }

  /// Called by the composer on every keystroke. Fires at most once per
  /// [kTypingNotifyInterval] so the server sees ~30 req/min per user during
  /// sustained typing — light enough to skip rate-limiting.
  void notifyTyping() {
    final now = DateTime.now();
    if (_lastTypingNotifySentAt != null &&
        now.difference(_lastTypingNotifySentAt!) < kTypingNotifyInterval) {
      return;
    }
    _lastTypingNotifySentAt = now;
    _service.notifyTyping(conversationId);
  }

  void _applyIncoming(Message m) {
    // Dedup by client_nonce (our own send arrives here too) or by id.
    final byNonce = m.clientNonce.isNotEmpty &&
        _messages.any((x) => x.clientNonce == m.clientNonce);
    final byId = m.id != null && _messages.any((x) => x.id == m.id);
    if (byNonce) {
      _reconcile(m);
      return;
    }
    if (byId) return;
    _messages = [m, ..._messages];
    if (m.senderId != myUserId) {
      unawaited(RingtoneService.instance.ping());
    }
    notifyListeners();
  }

  void _reconcile(Message server) {
    var changed = false;
    _messages = _messages.map((m) {
      if (m.clientNonce == server.clientNonce && m.id == null) {
        changed = true;
        return server;
      }
      return m;
    }).toList();
    if (!changed && !_messages.any((m) => m.id == server.id)) {
      _messages = [server, ..._messages];
      changed = true;
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _readSub?.cancel();
    _typingSub?.cancel();
    _typingSweep?.cancel();
    _markReadTimer?.cancel();
    _pollTimer?.cancel();
    _realtime.unsubscribeConversation(conversationId);
    super.dispose();
  }
}

class _TypingInfo {
  _TypingInfo({required this.username, required this.expiresAt});
  final String username;
  final DateTime expiresAt;
}
