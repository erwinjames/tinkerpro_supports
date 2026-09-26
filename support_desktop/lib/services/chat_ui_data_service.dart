import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_client.dart';

int _i(dynamic v) {
  if (v is int) return v;
  if (v is bool) return v ? 1 : 0;
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

class ChatConvMeta {
  const ChatConvMeta({
    this.source = '',
    this.priority = false,
    this.archived = false,
    this.hidden = false,
    this.fbMoved = false,
    this.fbAiOwned = false,
    this.guestStatus = 'none',
    this.isDesktopApp = false,
    this.ticketWaiting = false,
    this.ticketAccepted = false,
    this.peerAvatar,
  });

  final String source;
  final bool priority;
  final bool archived;
  final bool hidden;
  final bool fbMoved;
  final bool fbAiOwned;
  final String guestStatus;
  final bool isDesktopApp;
  final bool ticketWaiting;
  final bool ticketAccepted;
  final String? peerAvatar;

  bool get isFacebook => source == 'facebook';
  bool get isExternal =>
      source == 'customer' ||
      source == 'facebook' ||
      (guestStatus.isNotEmpty && guestStatus != 'none');
  bool get isRequest => isFacebook && !fbMoved && !priority;

  ChatConvMeta copyWith({
    bool? priority,
    bool? archived,
    bool? fbMoved,
    bool? fbAiOwned,
  }) =>
      ChatConvMeta(
        source: source,
        priority: priority ?? this.priority,
        archived: archived ?? this.archived,
        hidden: hidden,
        fbMoved: fbMoved ?? this.fbMoved,
        fbAiOwned: fbAiOwned ?? this.fbAiOwned,
        guestStatus: guestStatus,
        isDesktopApp: isDesktopApp,
        ticketWaiting: ticketWaiting,
        ticketAccepted: ticketAccepted,
        peerAvatar: peerAvatar,
      );

  factory ChatConvMeta.fromJson(Map<String, dynamic> j) {
    final peer = j['peer'];
    String? avatar;
    if (peer is Map) {
      final a = peer['avatar']?.toString() ?? '';
      if (a.isNotEmpty) avatar = a;
    }
    return ChatConvMeta(
      source: (j['source'] ?? '').toString(),
      priority: _i(j['priority']) != 0,
      archived: _i(j['archived']) != 0,
      hidden: _i(j['hidden']) != 0,
      fbMoved: _i(j['fb_moved']) != 0,
      fbAiOwned: _i(j['fb_ai_owned']) != 0,
      guestStatus: (j['guest_status'] ?? 'none').toString(),
      isDesktopApp: _i(j['is_desktop_app']) != 0,
      ticketWaiting: _i(j['ticket_waiting']) != 0,
      ticketAccepted: _i(j['ticket_accepted']) != 0,
      peerAvatar: avatar,
    );
  }
}

class ChatUiDataService extends ChangeNotifier {
  ChatUiDataService(this.api);
  final ApiClient api;

  final Map<int, ChatConvMeta> _meta = {};
  bool canMessageRequests = false;
  bool isSuperAdmin = false;
  bool _loading = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  bool _capsLoaded = false;
  bool _disposed = false;

  ChatConvMeta meta(int id) => _meta[id] ?? const ChatConvMeta();

  Future<void> loadCaps() async {
    if (_capsLoaded) return;
    try {
      final res = await api.get('desktopChatCaps');
      if (res['success'] == true) {
        canMessageRequests = res['can_message_requests'] == true;
        isSuperAdmin = res['is_super_admin'] == true;
        _capsLoaded = true;
        _notify();
      }
    } catch (_) {}
  }

  void maybeRefresh({Duration minGap = const Duration(seconds: 10)}) {
    if (DateTime.now().difference(_last) < minGap) return;
    refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _last = DateTime.now();
    try {
      final res = await api.get('chat.inbox');
      final raw = res['conversations'];
      if (res['success'] == true && raw is List) {
        _meta.clear();
        for (final m in raw.whereType<Map>()) {
          final j = Map<String, dynamic>.from(m);
          _meta[_i(j['id'])] = ChatConvMeta.fromJson(j);
        }
        _notify();
      }
    } catch (_) {}
    _loading = false;
  }

  void patch(int id, {bool? priority, bool? fbMoved, bool? fbAiOwned}) {
    _meta[id] = meta(id).copyWith(
      priority: priority,
      fbMoved: fbMoved,
      fbAiOwned: fbAiOwned,
    );
    _notify();
  }

  Future<String?> setPriority(int id, bool on) async {
    final prev = meta(id);
    _meta[id] = prev.copyWith(priority: on);
    _notify();
    try {
      final res = await api.post('chat.setPriority', body: {
        'conversation_id': '$id',
        'priority': on ? '1' : '0',
      });
      if (res['success'] == true) return null;
      _meta[id] = prev;
      _notify();
      return (res['message'] ?? 'Could not update priority').toString();
    } catch (_) {
      _meta[id] = prev;
      _notify();
      return 'Network error';
    }
  }

  Future<String?> setArchived(int id, bool on) async {
    final prev = meta(id);
    _meta[id] = prev.copyWith(archived: on);
    _notify();
    try {
      final res = await api.post('chat.setConversationArchived', body: {
        'conversation_id': '$id',
        'archived': on ? '1' : '0',
      });
      if (res['success'] == true) return null;
      _meta[id] = prev;
      _notify();
      return (res['message'] ?? 'Could not update').toString();
    } catch (_) {
      _meta[id] = prev;
      _notify();
      return 'Network error';
    }
  }

  Future<String?> hideForMe(int id) async {
    try {
      final res = await api.post('chat.hideConversationForMe', body: {
        'conversation_id': '$id',
      });
      if (res['success'] == true) return null;
      return (res['message'] ?? 'unknown error').toString();
    } catch (_) {
      return 'Network error';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
