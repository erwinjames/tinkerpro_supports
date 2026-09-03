import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'chat_realtime.dart';
import 'chat_service.dart';
import 'ringtone_service.dart';

class ChatInbox extends ChangeNotifier {
  ChatInbox(this._service, this._realtime) {
    _activitySub = _realtime.inboxEvents.listen(_applyActivity);
    _lifecycleSub = _realtime.lifecycleEvents.listen(_applyLifecycle);
    _readSyncSub = _realtime.readSyncEvents.listen(_applyReadSync);
    _startPolling();
  }

  final ChatService _service;
  final ChatRealtimeService _realtime;
  StreamSubscription<ConversationActivity>? _activitySub;
  StreamSubscription<ConversationLifecycle>? _lifecycleSub;
  StreamSubscription<ConversationReadSync>? _readSyncSub;
  Timer? _pollTimer;

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

  void setArchivedLocally(int conversationId, bool archived) {
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx < 0) return;
    final next = List<Conversation>.from(_conversations);
    next[idx] = next[idx].copyWith(archived: archived ? 1 : 0);
    _conversations = next;
    notifyListeners();
  }

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

    final next = List<Conversation>.from(_conversations)..removeAt(idx);
    next.insert(0, updated);
    _conversations = next;
    notifyListeners();
  }

  void _applyReadSync(ConversationReadSync sync) {
    final idx = _conversations.indexWhere((c) => c.id == sync.conversationId);
    if (idx == -1) return;
    final existing = _conversations[idx];
    if (existing.unreadCount == sync.unreadCount) return;
    final next = List<Conversation>.from(_conversations);
    next[idx] = existing.copyWith(unreadCount: sync.unreadCount);
    _conversations = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _activitySub?.cancel();
    _lifecycleSub?.cancel();
    _readSyncSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}

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
    _pinSub = _realtime.pinEvents
        .where((e) => e.conversationId == conversationId)
        .listen(_applyPin);
    _realtime.subscribeConversation(conversationId);
    _hydrateReadCursors();
    _startPolling();
  }

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

  ConversationDetail? _detail;

  /// Server-side conversation row, hydrated shortly after open. Lets the
  /// screen answer questions the inbox summary can't when a thread is
  /// opened by id alone (e.g. from a notification tap).
  ConversationDetail? get detail => _detail;
  final int myUserId;
  final ChatService _service;
  final ChatRealtimeService _realtime;
  StreamSubscription<Message>? _messageSub;
  StreamSubscription<MessageRead>? _readSub;
  StreamSubscription<TypingEvent>? _typingSub;
  StreamSubscription<PinUpdate>? _pinSub;

  final Map<int, _TypingInfo> _typing = {};
  Timer? _typingSweep;

  DateTime? _lastTypingNotifySentAt;
  static const Duration kTypingNotifyInterval = Duration(seconds: 2);
  static const Duration kTypingExpireAfter = Duration(seconds: 4);

  List<String> get typingNames {
    final now = DateTime.now();
    return _typing.values
        .where((t) => t.expiresAt.isAfter(now))
        .map((t) => t.username)
        .toList();
  }

  final Map<int, int> _readCursors = <int, int>{};

  int _totalParticipants = 0;

  Map<int, int> get readCursors => Map.unmodifiable(_readCursors);
  int get totalParticipants => _totalParticipants;

  int _lastReportedReadId = 0;
  Timer? _markReadTimer;

  List<Message> _messages = const [];
  bool _loading = false;
  bool _hasMore = true;

  List<Message> get messages => _messages;
  bool get loading => _loading;
  bool get hasMore => _hasMore;

  List<PinnedMessage> _pinned = const [];
  List<PinnedMessage> get pinned => _pinned;

  bool isPinned(int? messageId) =>
      messageId != null && _pinned.any((p) => p.messageId == messageId);

  Future<void> loadInitial() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    final page = await _service.history(conversationId, limit: 50);
    _messages = page.messages;
    _hasMore = page.hasMore;
    _loading = false;
    notifyListeners();
    unawaited(_loadPinned());
  }

  Future<void> _loadPinned() async {
    final pins = await _service.listPinned(conversationId);
    _pinned = pins;
    notifyListeners();
  }

  Future<bool> pin(int messageId) async {
    final entry = await _service.pinMessage(messageId);
    if (entry == null) return false;
    _applyPin(PinUpdate(
      conversationId: conversationId,
      messageId: messageId,
      pinned: entry,
    ));
    return true;
  }

  Future<bool> unpin(int messageId) async {
    final ok = await _service.unpinMessage(messageId);
    if (!ok) return false;
    _applyPin(PinUpdate(
      conversationId: conversationId,
      messageId: messageId,
      pinned: null,
    ));
    return true;
  }

  void _applyPin(PinUpdate e) {
    if (e.isPinned) {
      if (_pinned.any((p) => p.messageId == e.messageId)) return;
      _pinned = [e.pinned!, ..._pinned];
    } else {
      final next =
          _pinned.where((p) => p.messageId != e.messageId).toList();
      if (next.length == _pinned.length) return;
      _pinned = next;
    }
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

  Future<void> _hydrateReadCursors() async {
    final detail = await _service.conversation(conversationId);
    if (detail == null) return;
    _detail = detail;
    _totalParticipants = detail.participants.length;
    notifyListeners();
  }

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

    await _service.markRead(conversationId, targetId);
  }

  void _applyRead(MessageRead event) {
    if (event.userId == myUserId) return;
    final current = _readCursors[event.userId] ?? 0;
    if (event.messageId > current) {
      _readCursors[event.userId] = event.messageId;
      notifyListeners();
    }
  }

  void _applyTyping(TypingEvent event) {
    if (event.userId == myUserId) return;
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
    _pinSub?.cancel();
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
