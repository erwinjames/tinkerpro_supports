import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'services/live_sync.dart';

class ShellBadge {
  const ShellBadge(this.text, this.color);
  final String text;
  final Color color;
}

class ShellBadges extends ChangeNotifier {
  ShellBadges(this.api);

  final ApiClient api;
  final Map<String, ShellBadge> _badges = {};
  Set<String> _counters = {};
  String _activeKey = '';
  bool _disposed = false;
  final List<VoidCallback> _liveCancels = [];
  final Set<String> _pending = {};
  Timer? _liveDebounce;

  static const Map<String, List<String>> _liveKeys = {
    'ticket': ['ticket'],
    'chat': ['chat'],
    'zreading': ['zreading'],
    'clientOffer': ['clientOffer'],
    'employment': ['employment'],
    'customer': ['customer', 'vendorportal'],
    'client': ['client'],
    'feedback': ['feedbackinbox'],
  };

  static const _orange = Color(0xFFFF7D00);
  static const _blue = Color(0xFF2563EB);
  static const _red = Color(0xFFDC2626);
  static const _danger = Color(0xFFDC3545);

  ShellBadge? badgeFor(String? counter) =>
      counter == null ? null : _badges[counter];

  void setCounters(Iterable<String> counters) {
    final next = counters.toSet();
    if (next.length == _counters.length && next.containsAll(_counters)) return;
    _counters = next;
    _subscribe();
    refresh();
  }

  void _subscribe() {
    for (final c in _liveCancels) {
      c();
    }
    _liveCancels.clear();
    final byKey = <String, Set<String>>{};
    for (final counter in _counters) {
      for (final key in _liveKeys[counter] ?? const <String>[]) {
        byKey.putIfAbsent(key, () => {}).add(counter);
      }
    }
    byKey.forEach((key, counters) {
      _liveCancels.add(LiveSync.instance.listen(key, () => _queue(counters)));
    });
  }

  void _queue(Iterable<String> counters) {
    _pending.addAll(counters);
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 300), () {
      if (_disposed) return;
      final run = _pending.intersection(_counters);
      _pending.clear();
      for (final c in run) {
        _one(c).catchError((_) {});
      }
    });
  }

  void setActive(String key) {
    if (key == _activeKey) return;
    _activeKey = key;
    if (key == 'ticket' || key == 'clientOffer' || key == 'feedbackinbox') {
      refresh();
    }
  }

  String _fmt(int n) => n > 99 ? '99+' : '$n';

  void _set(String counter, ShellBadge? badge) {
    final old = _badges[counter];
    if (badge == null) {
      if (old == null) return;
      _badges.remove(counter);
    } else {
      if (old != null && old.text == badge.text && old.color == badge.color) {
        return;
      }
      _badges[counter] = badge;
    }
    if (!_disposed) notifyListeners();
  }

  int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<void> refresh() async {
    final jobs = <Future<void>>[];
    for (final c in _counters) {
      jobs.add(_one(c).catchError((_) {}));
    }
    await Future.wait(jobs);
  }

  Future<void> _one(String counter) async {
    switch (counter) {
      case 'ticket':
        final r = await api.get('ticketdashboard');
        final count = _int(r['new_ticket']);
        final prefs = await SharedPreferences.getInstance();
        final seen = prefs.getInt('tk_seen_new_tickets') ?? 0;
        if (_activeKey == 'ticket' || count <= seen) {
          await prefs.setInt('tk_seen_new_tickets', count);
          _set(counter, null);
        } else {
          _set(counter, ShellBadge(_fmt(count), _blue));
        }
        return;
      case 'chat':
        final r = await api.get('chat.unreadTotal', {'scope': 'tab'});
        if (r['success'] != true) return;
        _set(counter,
            _int(r['total']) > 0 ? const ShellBadge('New', _orange) : null);
        return;
      case 'zreading':
        final r = await api.get('getZReadingPendingCount');
        if (r['success'] != true) return;
        final n = _int(r['pending']);
        _set(counter, n > 0 ? ShellBadge(_fmt(n), _red) : null);
        return;
      case 'clientOffer':
        final prefs = await SharedPreferences.getInstance();
        final seen = prefs.getInt('tp_leads_seen_id') ?? 0;
        final r = await api.get('getLeadsNewCount', {'since': '$seen'});
        if (r['success'] != true) return;
        final latest = _int(r['latest_id']);
        if (_activeKey == 'clientOffer' || seen == 0) {
          await prefs.setInt('tp_leads_seen_id', latest);
          _set(counter, null);
          return;
        }
        if (latest < seen) await prefs.setInt('tp_leads_seen_id', latest);
        final n = _int(r['new_count']);
        _set(counter, n > 0 ? ShellBadge(_fmt(n), _orange) : null);
        return;
      case 'employment':
        final r = await api.get('employmentPendingCount');
        if (r['status'] != 'success') return;
        final n = _int(r['count']);
        _set(counter, n > 0 ? ShellBadge(_fmt(n), _orange) : null);
        return;
      case 'customer':
        final r = await api.get('vendorNewRegistrations');
        if (r['success'] != true) return;
        final n = _int(r['count']);
        _set(counter, n > 0 ? ShellBadge(_fmt(n), _orange) : null);
        return;
      case 'client':
        final r = await api.get('getDeliveries', {
          'light': '1',
          'status': 'Ready for Delivery',
          'per_page': '1',
        });
        final data = r['data'];
        if (r['error'] != null || data is! List) return;
        _set(counter,
            data.isNotEmpty ? const ShellBadge('New', _orange) : null);
        return;
      case 'feedback':
        final r = await api.get('feedbackNewCount');
        if (r['success'] != true) return;
        final n = _int(r['new_count']);
        _set(counter,
            n > 0 && _activeKey != 'feedbackinbox'
                ? ShellBadge(_fmt(n), _danger)
                : null);
        return;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _liveDebounce?.cancel();
    for (final c in _liveCancels) {
      c();
    }
    _liveCancels.clear();
    super.dispose();
  }
}
