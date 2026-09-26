import 'dart:async';
import 'dart:convert';

import '../shell_notifications.dart';
import 'chat_runtime.dart';
import 'desktop_notifier.dart';
import 'sound_engine.dart';

class DesktopAlerts {
  DesktopAlerts({
    required this.bell,
    required this.chat,
    required this.openPage,
  });

  final ShellNotifications bell;
  final ChatRuntime chat;
  final void Function(String key) openPage;

  static const int _chatIdBase = 1000000000;
  static const int _summaryId = 999999999;
  static const int _maxBurstLines = 4;
  static const int _maxBatch = 3;
  static const Duration _burstWindow = Duration(minutes: 5);

  final Set<String> _seen = <String>{};
  final Map<int, _Burst> _bursts = <int, _Burst>{};
  bool _baselined = false;
  StreamSubscription<Map<String, dynamic>>? _rtSub;
  bool _disposed = false;

  DesktopNotifier get _notifier => DesktopNotifier.instance;

  void start() {
    bell.addListener(_onBell);
    _rtSub = chat.chatRealtime.appNotificationEvents.listen(_onRealtime);
    chat.chatRealtime.currentlyViewedConv.addListener(_onViewedChange);
    _notifier.onOpen = _onOpen;
    _onBell();
  }

  void dispose() {
    _disposed = true;
    bell.removeListener(_onBell);
    _rtSub?.cancel();
    try {
      chat.chatRealtime.currentlyViewedConv.removeListener(_onViewedChange);
    } catch (_) {}
    _notifier.onOpen = null;
  }

  static bool _isChatMessage(String type) =>
      type == 'chat' || type == 'chat_mention';

  static Map<String, dynamic> _meta(ShellNotification n) {
    final m = n.raw['meta'];
    return m is Map ? Map<String, dynamic>.from(m) : const <String, dynamic>{};
  }

  static int _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  static int _convId(ShellNotification n) {
    final meta = _meta(n);
    final c = _int(meta['conversation_id']);
    return c > 0 ? c : _int(n.raw['ref_id']);
  }

  static String _signature(ShellNotification n) {
    if (_isChatMessage(n.type)) {
      final mid = _int(_meta(n)['message_id']);
      if (mid > 0) return 'm:$mid';
      return 'c:${n.id}:${n.createdAt}:${n.body.hashCode}';
    }
    return 'n:${n.id}';
  }

  void _onBell() {
    if (_disposed || !bell.loaded) return;
    if (!_baselined) {
      for (final n in bell.items) {
        _seen.add(_signature(n));
      }
      _baselined = true;
      return;
    }
    final fresh = <ShellNotification>[];
    for (final n in bell.items) {
      if (n.isRead) continue;
      if (_seen.add(_signature(n))) fresh.add(n);
    }
    if (fresh.isEmpty) return;
    _presentBatch(fresh.reversed.toList());
  }

  void _onRealtime(Map<String, dynamic> data) {
    if (_disposed) return;
    final n = ShellNotification(Map<String, dynamic>.from(data));
    final meta = _meta(n);
    if (meta['silent'] == true || n.id <= 0) return;
    if (!_seen.add(_signature(n))) return;
    _presentBatch([n]);
  }

  void _presentBatch(List<ShellNotification> items) {
    SoundEngine.instance.bellItems(items.map((n) => n.raw));
    final chats = items.where((n) => n.isChat).toList();
    final others = items.where((n) => !n.isChat).toList();
    for (final n in chats) {
      unawaited(_presentChat(n));
    }
    if (others.length > _maxBatch) {
      unawaited(_notifier.show(
        id: _summaryId,
        title: 'TinkerPro Support',
        body: '${others.length} new notifications',
        payload: jsonEncode({'t': 'bell'}),
      ));
      return;
    }
    for (final n in others) {
      unawaited(_notifier.show(
        id: n.id,
        title: n.heading,
        body: n.preview,
        payload: jsonEncode({'t': 'page', 'k': n.targetKey ?? '', 'n': n.id}),
      ));
    }
  }

  Future<void> _presentChat(ShellNotification n) async {
    final cid = _convId(n);
    if (n.type == 'chat_fb_moved' || cid <= 0) {
      await _notifier.show(
        id: cid > 0 ? _chatIdBase + cid : n.id,
        title: n.heading,
        body: n.preview,
        payload: jsonEncode({'t': 'chat', 'c': cid, 'n': n.id}),
        chat: true,
      );
      return;
    }
    final meta = _meta(n);
    final me = chat.myUserId;
    final sender = _int(meta['sender_id']);
    if (me != null && sender == me) return;
    if (chat.chatRealtime.currentlyViewedConv.value == cid &&
        await _notifier.appInForeground()) {
      return;
    }
    if (_disposed) return;

    final senderName = n.title.trim().isEmpty ? 'Someone' : n.title.trim();
    final conv = chat.inbox?.find(cid);
    final group = conv != null &&
            conv.type != 'dm' &&
            conv.name.trim().isNotEmpty &&
            conv.name.trim() != senderName
        ? conv.name.trim()
        : null;
    final mention = n.type == 'chat_mention' || meta['mention'] == true;
    final text = chatPreviewText(n.body);

    final now = DateTime.now();
    var burst = _bursts[cid];
    if (burst == null || now.difference(burst.last) > _burstWindow) {
      burst = _Burst();
      _bursts[cid] = burst;
    }
    burst.last = now;
    burst.lines.add(_Line(senderName, text));
    if (burst.lines.length > _maxBurstLines) burst.lines.removeAt(0);
    burst.total++;

    final String title;
    if (mention) {
      title = group == null
          ? '$senderName mentioned you'
          : '$senderName mentioned you in $group';
    } else {
      title = group == null ? senderName : '$senderName · $group';
    }
    final mixed = burst.lines.any((l) => l.sender != senderName);
    final multi = burst.lines.length > 1;
    final lines = [
      for (final l in burst.lines)
        (mixed ? '${l.sender}: ${l.text}' : l.text)
            .replaceAll('\n', multi ? ' ' : '\n')
    ];
    final hidden = burst.total - burst.lines.length;
    final body = [
      if (hidden > 0) '+$hidden earlier',
      ...lines,
    ].join('\n');

    await _notifier.show(
      id: _chatIdBase + cid,
      title: title,
      body: body,
      payload: jsonEncode({'t': 'chat', 'c': cid, 'n': n.id}),
      chat: true,
    );
  }

  void _onViewedChange() {
    final cid = chat.chatRealtime.currentlyViewedConv.value;
    if (cid == null || !_bursts.containsKey(cid)) return;
    _notifier.appInForeground().then((fg) {
      if (!fg || _disposed) return;
      _bursts.remove(cid);
      _notifier.cancel(_chatIdBase + cid);
    });
  }

  void _onOpen(String payload) {
    Map<String, dynamic> p;
    try {
      final d = jsonDecode(payload);
      if (d is! Map) return;
      p = Map<String, dynamic>.from(d);
    } catch (_) {
      return;
    }
    final nid = _int(p['n']);
    if (nid > 0) unawaited(bell.markRead(nid));
    switch (p['t']) {
      case 'chat':
        final cid = _int(p['c']);
        openPage('chat');
        if (cid > 0) {
          _bursts.remove(cid);
          chat.inbox?.requestOpen(cid);
        }
        break;
      case 'page':
        final key = '${p['k'] ?? ''}';
        if (key.isNotEmpty) openPage(key);
        break;
    }
  }
}

class _Burst {
  final List<_Line> lines = <_Line>[];
  DateTime last = DateTime.now();
  int total = 0;
}

class _Line {
  const _Line(this.sender, this.text);
  final String sender;
  final String text;
}

final RegExp _replyQuote = RegExp(
    r'^>\s*@[^\[:\n]+?(?:\s*\[#\d+\])?\s*:[ \t]*[^\n]*?(?:\r?\n\r?\n([\s\S]+))?$');
final RegExp _imageTag = RegExp(r'^\[image\](?:\s*\+(\d+))?$');
final RegExp _fileTag = RegExp(r'^\[file:\s*(.*?)\](?:\s*\+(\d+))?$');

String chatPreviewText(String raw, {int max = 160}) {
  var s = raw.trim();
  final quote = _replyQuote.firstMatch(s);
  if (quote != null) {
    final tail = (quote.group(1) ?? '').trim();
    s = tail.isEmpty ? '[attachment]' : tail;
  }
  s = s.replaceFirst(RegExp('^↩︎?\\s*'), '');
  final img = _imageTag.firstMatch(s);
  final file = _fileTag.firstMatch(s);
  if (img != null) {
    final extra = int.tryParse(img.group(1) ?? '') ?? 0;
    s = extra > 0 ? '📷 ${extra + 1} photos' : '📷 Photo';
  } else if (file != null) {
    final extra = int.tryParse(file.group(2) ?? '') ?? 0;
    final name = (file.group(1) ?? '').trim();
    s = '📎 ${name.isEmpty ? 'Attachment' : name}${extra > 0 ? ' +$extra' : ''}';
  } else if (s == '[attachment]') {
    s = '📎 Attachment';
  }
  s = s.replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n{2,}'), '\n');
  if (s.isEmpty) return 'New message';
  if (s.runes.length > max) {
    s = '${String.fromCharCodes(s.runes.take(max - 1))}…';
  }
  return s;
}
