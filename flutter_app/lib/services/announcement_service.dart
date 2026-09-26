import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../models/announcement_models.dart';

class AnnouncementService extends ChangeNotifier {
  AnnouncementService(this._api);

  static const String _endpoint = 'announcement-ajax.php';

  final ApiClient _api;

  final List<Announcement> _pending = <Announcement>[];
  int _dbOffsetSeconds = 0;
  bool _loading = false;
  String _lastStatus = 'Not checked yet';
  int _lastLiveCount = 0;

  List<Announcement> get pending => List.unmodifiable(_pending);

  int get dbOffsetSeconds => _dbOffsetSeconds;

  bool get hasPending => _pending.isNotEmpty;

  String get lastStatus => _lastStatus;

  int get lastLiveCount => _lastLiveCount;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final res = await _api.getPath(_endpoint, {'action': 'pending'});
      if (res['success'] != true) {
        _lastStatus = 'Server refused: ${res['message'] ?? 'unknown reason'}';
        notifyListeners();
        return;
      }

      final offset = res['db_offset'];
      if (offset is num) _dbOffsetSeconds = offset.toInt();

      final raw = res['items'];
      if (raw is! List) {
        _lastStatus = 'Server sent no announcement list.';
        notifyListeners();
        return;
      }

      _lastLiveCount = raw.length;
      for (final entry in raw) {
        if (entry is! Map) continue;
        _upsert(Announcement.fromJson(Map<String, dynamic>.from(entry)));
      }
      _lastStatus = raw.isEmpty
          ? 'Connected — none addressed to you'
          : 'Connected — ${raw.length} waiting';
      notifyListeners();
    } catch (e) {
      _lastStatus = _describe(e);
      debugPrint('[announcements] refresh failed: $e');
      notifyListeners();
    } finally {
      _loading = false;
    }
  }

  static String _describe(Object e) {
    final text = e.toString();
    if (text.contains('Not authenticated')) {
      return 'Signed out on the server — sign in again';
    }
    if (text.contains('404')) {
      return 'This server has no announcements feature';
    }
    if (text.contains('SocketException') || text.contains('Failed host')) {
      return 'Cannot reach the server';
    }
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }

  void ingest(Map<String, dynamic> data) {
    final offset = data['db_offset'];
    if (offset is num) _dbOffsetSeconds = offset.toInt();

    final item = Announcement.fromJson(data);
    if (item.id <= 0) return;
    if (_upsert(item)) notifyListeners();
  }

  bool _upsert(Announcement item) {
    if (!item.isPending) return false;
    final index = _pending.indexWhere((a) => a.id == item.id);
    if (index == -1) {
      _pending.add(item);
      return true;
    }
    _pending[index] = item;
    return false;
  }

  Future<void> markRead(int id, {required bool acknowledged}) async {
    final index = _pending.indexWhere((a) => a.id == id);
    if (index == -1) return;

    final previous = _pending[index];
    final updated = previous.markedRead(acknowledged: acknowledged);
    if (updated.isPending) {
      _pending[index] = updated;
    } else {
      _pending.removeAt(index);
    }
    notifyListeners();

    try {
      final res = await _api.postPath(
        _endpoint,
        body: {
          'action': 'mark_read',
          'id': '$id',
          'acknowledged': acknowledged ? '1' : '0',
        },
      );
      if (res['success'] == true) return;
      throw StateError('server rejected mark_read');
    } catch (e) {
      debugPrint('[announcements] mark_read failed: $e');
      if (_pending.indexWhere((a) => a.id == id) == -1) {
        _pending.insert(index.clamp(0, _pending.length), previous);
      } else {
        _pending[_pending.indexWhere((a) => a.id == id)] = previous;
      }
      notifyListeners();
    }
  }
}
