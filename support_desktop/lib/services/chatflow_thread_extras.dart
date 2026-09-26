import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'chatflow_service.dart';

class ChatflowThreadExtras extends ChangeNotifier {
  ChatflowThreadExtras(this.flow, this.conversationId) {
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _poll());
  }

  final ChatflowService flow;
  final int conversationId;
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  final Map<int, List<ChatReaction>> _reactions = {};
  final Set<int> _localRemoved = {};
  Set<int> _window = {};
  int _minId = 0;
  int _maxId = 0;
  bool _loaded = false;
  List<PinnedMessage>? _pinned;

  List<PinnedMessage>? get pinned => _pinned;

  bool isPinned(int? id) => id != null && (_pinned ?? const []).any((p) => p.messageId == id);

  List<ChatReaction> reactions(int? id) => id == null ? const [] : (_reactions[id] ?? const []);

  String? myReaction(int? id, int me) {
    for (final r in reactions(id)) {
      if (r.userIds.contains(me)) return r.emoji;
    }
    return null;
  }

  bool isRemoved(int? id) {
    if (id == null) return false;
    if (_localRemoved.contains(id)) return true;
    if (!_loaded) return false;
    return id >= _minId && id <= _maxId && !_window.contains(id);
  }

  void markRemoved(int id) {
    _localRemoved.add(id);
    _notify();
  }

  void applyReactions(int id, List<ChatReaction> list) {
    _reactions[id] = list;
    _notify();
  }

  Future<void> refresh() => _poll();

  Future<void> _poll() async {
    if (_busy || _disposed) return;
    _busy = true;
    try {
      final r = await flow.history(conversationId, limit: 50);
      final raw = r.data['messages'];
      if (r.ok && raw is List) {
        final ids = <int>{};
        var changed = false;
        for (final m in raw) {
          if (m is! Map) continue;
          final id = int.tryParse('${m['id'] ?? ''}');
          if (id == null) continue;
          ids.add(id);
          final list = <ChatReaction>[];
          final rr = m['reactions'];
          if (rr is List) {
            for (final x in rr) {
              if (x is Map) list.add(ChatReaction.fromJson(Map<String, dynamic>.from(x)));
            }
          }
          final prev = _reactions[id];
          if (!_sameReactions(prev, list)) {
            _reactions[id] = list;
            changed = true;
          }
        }
        final minId = ids.isEmpty ? 0 : ids.reduce((a, b) => a < b ? a : b);
        final maxId = ids.isEmpty ? 0 : ids.reduce((a, b) => a > b ? a : b);
        if (!setEquals(ids, _window) || minId != _minId || maxId != _maxId || !_loaded) {
          changed = true;
        }
        _window = ids;
        _minId = minId;
        _maxId = maxId;
        _loaded = true;
        if (changed) _notify();
      }
      final p = await flow.listPinned(conversationId);
      if (p != null) {
        final before = (_pinned ?? const []).map((e) => e.messageId).join(',');
        final after = p.map((e) => e.messageId).join(',');
        final first = _pinned == null;
        _pinned = p;
        if (first || before != after) _notify();
      }
    } finally {
      _busy = false;
    }
  }

  static bool _sameReactions(List<ChatReaction>? a, List<ChatReaction> b) {
    if (a == null) return b.isEmpty;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].emoji != b[i].emoji || !listEquals(a[i].userIds, b[i].userIds)) return false;
    }
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
