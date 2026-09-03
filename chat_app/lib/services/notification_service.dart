import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../models/notification_models.dart';
import 'chat_realtime.dart';

class NotificationService {
  NotificationService(this.api);

  final ApiClient api;

  Future<({List<AppNotification> items, int unread})> fetch() async {
    try {
      final res = await api.get('getNotifications');
      if (res['success'] != true) {
        return (items: const <AppNotification>[], unread: 0);
      }
      final raw = res['notifications'];
      final items = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => AppNotification.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList()
          : <AppNotification>[];
      final unread = res['unread_count'];
      return (
        items: items,
        unread: unread is int
            ? unread
            : int.tryParse('${unread ?? 0}') ?? 0,
      );
    } catch (_) {
      return (items: const <AppNotification>[], unread: 0);
    }
  }

  Future<bool> markRead(int id) async {
    try {
      final res = await api.post('markNotificationRead',
          body: {'id': id.toString()});
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> markAllRead() async {
    try {
      final res = await api.post('markAllNotificationsRead');
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }
}

class NotificationCenter extends ChangeNotifier {
  NotificationCenter(this._service, this._realtime) {
    _sub = _realtime.appNotificationEvents.listen(_onLive);
  }

  final NotificationService _service;
  final ChatRealtimeService _realtime;
  StreamSubscription<AppNotification>? _sub;

  List<AppNotification> _items = const [];
  int _unread = 0;
  bool _loading = false;
  bool _disposed = false;

  List<AppNotification> get items => _items;
  int get unread => _unread;
  bool get loading => _loading;

  List<AppNotification> get birItems =>
      _items.where((n) => n.isBirStatus).toList();

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _safeNotify();
    final result = await _service.fetch();
    _items = result.items;
    _unread = result.unread;
    _loading = false;
    _safeNotify();
  }

  void _onLive(AppNotification incoming) {
    if (_items.any((n) => n.id == incoming.id && incoming.id != 0)) return;
    _items = [incoming, ..._items];
    if (!incoming.isRead) _unread += 1;
    _safeNotify();
  }

  Future<void> markRead(AppNotification item) async {
    if (item.isRead) return;
    _items = [
      for (final n in _items) n.id == item.id ? n.copyWith(isRead: true) : n,
    ];
    if (_unread > 0) _unread -= 1;
    _safeNotify();
    await _service.markRead(item.id);
  }

  Future<void> markAllRead() async {
    if (_unread == 0 && _items.every((n) => n.isRead)) return;
    _items = [for (final n in _items) n.copyWith(isRead: true)];
    _unread = 0;
    _safeNotify();
    await _service.markAllRead();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
