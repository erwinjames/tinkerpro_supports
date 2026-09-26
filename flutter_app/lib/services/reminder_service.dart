import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../api_client.dart';
import '../models/reminder_models.dart';

class ReminderService {
  ReminderService(this._api);

  final ApiClient _api;

  static final ValueNotifier<int> badge = ValueNotifier<int>(0);
  static final ValueNotifier<ReminderFeed?> latest =
      ValueNotifier<ReminderFeed?>(null);

  Future<ReminderFeed> load() async {
    final res =
        await _api.get('mobileReminders').timeout(const Duration(seconds: 15));
    if (res['success'] != true) {
      throw Exception(
          (res['message'] ?? 'Could not load your reminders.').toString());
    }
    final feed = ReminderFeed.fromJson(res);
    latest.value = feed;
    badge.value = feed.badge;
    unawaited(ReminderWidget.publish(feed));
    return feed;
  }

  Future<ReminderFeed?> refreshQuietly() async {
    if (!_api.hasSession) return null;
    try {
      return await load();
    } catch (_) {
      return null;
    }
  }

  String _dueParam(DateTime? due) {
    if (due == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${due.year}-${two(due.month)}-${two(due.day)}';
  }

  Future<void> addNote({
    required String title,
    String body = '',
    DateTime? due,
  }) async {
    final res = await _api.post('addStickyNote', body: {
      'title': title,
      'body': body,
      'due_date': _dueParam(due),
    });
    if (res['success'] != true) {
      throw Exception((res['message'] ?? 'Could not save that note.').toString());
    }
  }

  Future<void> updateNote({
    required int id,
    required String title,
    String body = '',
    DateTime? due,
  }) async {
    final res = await _api.post('updateStickyNote', body: {
      'id': '$id',
      'title': title,
      'body': body,
      'due_date': _dueParam(due),
    });
    if (res['success'] != true) {
      throw Exception((res['message'] ?? 'Could not save that note.').toString());
    }
  }

  Future<void> deleteNote(int id) async {
    final res = await _api.post('deleteStickyNote', body: {'id': '$id'});
    if (res['success'] != true) {
      throw Exception((res['message'] ?? 'Could not delete that note.').toString());
    }
  }

  Future<void> dismissPtu(int customerId) async {
    final res =
        await _api.post('dismissPtuReminder', body: {'customer_id': '$customerId'});
    if (res['success'] != true) {
      throw Exception(
          (res['message'] ?? 'Could not update that reminder.').toString());
    }
  }
}

class ReminderWidget {
  ReminderWidget._();

  static const String androidProvider = 'RemindersWidgetProvider';
  static const int maxLines = 4;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  static List<String> _lines(ReminderFeed feed) {
    final out = <String>[];
    void add(String line) {
      if (out.length < maxLines) out.add(line);
    }

    for (final t in feed.tasks) {
      if (t.bucket == ReminderBucket.overdue) add('Overdue · ${t.title}');
    }
    for (final n in feed.notes) {
      if (n.bucket == ReminderBucket.overdue) add('Note overdue · ${n.title}');
    }
    for (final t in feed.tasks) {
      if (t.bucket == ReminderBucket.today) add('Today · ${t.title}');
    }
    for (final n in feed.notes) {
      if (n.bucket == ReminderBucket.today) add('Note today · ${n.title}');
    }
    for (final p in feed.ptuPending) {
      add('Upload PTU · ${p.name}');
    }
    for (final t in feed.tasks) {
      if (t.bucket == ReminderBucket.week) add('${t.label} · ${t.title}');
    }
    for (final n in feed.notes) {
      if (n.bucket == ReminderBucket.week) add('Note ${n.label.toLowerCase()} · ${n.title}');
    }
    for (final t in feed.tasks) {
      if (t.bucket == ReminderBucket.undated) add('Task · ${t.title}');
    }
    for (final n in feed.notes) {
      if (n.bucket == ReminderBucket.later || n.bucket == ReminderBucket.undated) {
        add('Note · ${n.title}');
      }
    }
    return out;
  }

  static String _summary(ReminderFeed feed) {
    final parts = <String>[];
    final taskDue = feed.taskOverdue + feed.taskToday;
    if (taskDue > 0) parts.add('$taskDue task${taskDue == 1 ? '' : 's'} due');
    if (feed.ptuActive > 0) parts.add('${feed.ptuActive} PTU to upload');
    if (feed.notesDue > 0) {
      parts.add('${feed.notesDue} note${feed.notesDue == 1 ? '' : 's'} due');
    }
    if (parts.isEmpty && feed.taskOpen > 0) {
      parts.add('${feed.taskOpen} open task${feed.taskOpen == 1 ? '' : 's'}');
    }
    return parts.isEmpty ? 'All caught up' : parts.join(' · ');
  }

  static Future<void> _save(Map<String, Object?> data) async {
    for (final e in data.entries) {
      await HomeWidget.saveWidgetData(e.key, e.value);
    }
    await HomeWidget.updateWidget(androidName: androidProvider);
  }

  static Future<void> publish(ReminderFeed feed) async {
    if (!_supported) return;
    try {
      final lines = _lines(feed);
      await _save({
        'rem_state': 'ok',
        'rem_badge': '${feed.badge}',
        'rem_fetched_at': '${DateTime.now().millisecondsSinceEpoch}',
        'rem_summary': _summary(feed),
        for (var i = 0; i < maxLines; i++)
          'rem_line_$i': i < lines.length ? lines[i] : '',
        'rem_updated': 'Updated ${_clock(DateTime.now())}',
      });
    } catch (_) {}
  }

  static Future<void> publishSignedOut() async {
    if (!_supported) return;
    try {
      await _save({
        'rem_state': 'signed_out',
        'rem_badge': '0',
        'rem_fetched_at': '${DateTime.now().millisecondsSinceEpoch}',
        'rem_summary': 'Sign in to TinkerPro Support to see your reminders',
        for (var i = 0; i < maxLines; i++) 'rem_line_$i': '',
        'rem_updated': '',
      });
    } catch (_) {}
  }

  static Future<void> refreshFromNetwork() async {
    final api = await ApiClient.load();
    if (!api.hasSession) {
      await publishSignedOut();
      return;
    }
    try {
      await ReminderService(api).load();
    } catch (_) {
      try {
        await HomeWidget.saveWidgetData(
            'rem_fetched_at', '${DateTime.now().millisecondsSinceEpoch}');
        await HomeWidget.saveWidgetData(
            'rem_updated', 'Could not refresh · tap to open');
        await HomeWidget.updateWidget(androidName: androidProvider);
      } catch (_) {}
    }
  }

  static Future<void> register() async {
    if (!_supported) return;
    try {
      await HomeWidget.registerInteractivityCallback(reminderWidgetCallback);
    } catch (_) {}
  }

  static bool isRemindersUri(Uri? uri) =>
      uri != null && uri.host == 'reminders';
}

@pragma('vm:entry-point')
Future<void> reminderWidgetCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderWidget.refreshFromNetwork();
}
