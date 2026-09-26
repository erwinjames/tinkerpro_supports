import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'services/live_sync.dart';
import 'shell_icons.dart';

class ShellNotification {
  ShellNotification(this.raw);
  final Map<String, dynamic> raw;

  int get id => raw['id'] is num
      ? (raw['id'] as num).toInt()
      : int.tryParse('${raw['id']}') ?? 0;
  String get type => '${raw['type'] ?? ''}';
  String get title => '${raw['title'] ?? ''}';
  String get body => '${raw['body'] ?? ''}';
  String get createdAt => '${raw['created_at'] ?? ''}';
  bool get isRead {
    final v = raw['is_read'];
    return v == true || v == 1 || v == '1';
  }

  set isRead(bool v) => raw['is_read'] = v ? 1 : 0;

  bool get isChat =>
      type == 'chat' || type == 'chat_mention' || type == 'chat_fb_moved';

  String get heading {
    switch (type) {
      case 'chat_mention':
        return '${title.isEmpty ? 'Someone' : title} mentioned you';
      case 'chat_fb_moved':
        return '${title.isEmpty ? 'Facebook chat' : title} — moved';
      case 'chat':
        return title.isEmpty ? 'New Chat Message' : title;
      case 'feedback':
      case 'ticket':
      case 'zread_request':
      case 'customer_status':
      case 'portal_password_reset':
        return title.isEmpty ? _typeTitle(type) : title;
    }
    return _typeTitle(type);
  }

  static String _typeTitle(String type) {
    switch (type) {
      case 'lead':
        return 'New Lead / Form';
      case 'sms_reply':
        return 'New SMS Reply';
      case 'task_assigned':
        return 'Task assigned to you';
      case 'subtask_assigned':
        return 'Subtask assigned to you';
      case 'task_completed':
        return 'Task completed';
      case 'task_reminder':
        return 'Task reminder';
      case 'subtask_completed':
        return 'Subtask completed';
      case 'chat':
        return 'New Chat Message';
      case 'chat_mention':
        return 'You were mentioned';
      case 'chat_fb_moved':
        return 'Facebook chat moved';
      case 'zread_request':
        return 'Z-Reading unlock request';
      case 'feedback':
        return 'New feedback';
      case 'ticket':
        return 'New Support Ticket';
      case 'customer_status':
        return 'BIR Registration Status';
      case 'portal_password_reset':
        return 'Taxpayer password reset requested';
    }
    return 'New Client Registration';
  }

  String get preview {
    final raw0 = body.isEmpty ? title : body;
    if (!isChat) return raw0;
    final m = RegExp(
            r'^>\s*@[^\[:\n]+?(?:\s*\[#\d+\])?\s*:[ \t]*[^\n]*?(?:\r?\n\r?\n([\s\S]+))?$')
        .firstMatch(raw0);
    final text = m != null
        ? '↩ ${(m.group(1) ?? '').trim().isEmpty ? '[attachment]' : m.group(1)!.trim()}'
        : raw0;
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  IconData get icon {
    switch (type) {
      case 'lead':
        return Fa.bullhorn;
      case 'sms_reply':
        return Fa.sms;
      case 'chat_mention':
        return Fa.at;
      case 'chat_fb_moved':
        return Fa.shareSquare;
      case 'chat':
        return Fa.comments;
      case 'task_assigned':
      case 'subtask_assigned':
        return Fa.userTag;
      case 'task_reminder':
        return Fa.bellSolid;
      case 'task_completed':
      case 'subtask_completed':
        return Fa.checkCircleSolid;
      case 'zread_request':
        return Fa.receipt;
      case 'ticket':
        return Fa.ticketAlt;
      case 'feedback':
        return Fa.commentDots;
      case 'customer_status':
        return Fa.clipboardCheck;
      case 'portal_password_reset':
        return Fa.userLock;
    }
    return Fa.userPlus;
  }

  String? get targetKey {
    switch (type) {
      case 'customer':
      case 'customer_status':
        return 'customer';
      case 'lead':
      case 'sms_reply':
        return 'clientOffer';
      case 'task_assigned':
      case 'task_completed':
      case 'subtask_assigned':
      case 'subtask_completed':
      case 'task_reminder':
        return 'task';
      case 'chat':
      case 'chat_mention':
      case 'chat_fb_moved':
        return 'chat';
      case 'zread_request':
        return 'zreading';
      case 'feedback':
        return 'feedbackinbox';
      case 'ticket':
        return 'ticket';
      case 'portal_password_reset':
        return 'activitylogs';
    }
    return null;
  }

  String get timeAgo {
    final d = DateTime.tryParse(createdAt.replaceFirst(' ', 'T'));
    if (d == null) return createdAt;
    final diff = DateTime.now().difference(d).inSeconds.clamp(0, 1 << 31);
    if (diff < 60) return 'just now';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    if (diff < 86400) return '${diff ~/ 3600}h ago';
    return '${diff ~/ 86400}d ago';
  }
}

class ShellNotifications extends ChangeNotifier {
  ShellNotifications(this.api) {
    fetch();
    _liveCancel = LiveSync.instance.listen('notifications', fetch);
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => fetch());
  }

  final ApiClient api;
  Timer? _timer;
  VoidCallback? _liveCancel;
  bool _fetching = false;
  bool _again = false;
  bool _disposed = false;
  bool loaded = false;
  int unread = 0;
  List<ShellNotification> items = const [];

  Future<void> fetch() async {
    if (_disposed) return;
    if (_fetching) {
      _again = true;
      return;
    }
    _fetching = true;
    try {
      final r = await api.get('getNotifications');
      if (r['success'] != true) return;
      final list = r['notifications'];
      items = [
        if (list is List)
          for (final n in list)
            if (n is Map) ShellNotification(Map<String, dynamic>.from(n))
      ];
      final u = r['unread_count'];
      unread = u is num ? u.toInt() : int.tryParse('$u') ?? 0;
      loaded = true;
      if (!_disposed) notifyListeners();
    } catch (_) {
    } finally {
      _fetching = false;
      if (_again) {
        _again = false;
        fetch();
      }
    }
  }

  Future<String?> markRead(int id) async {
    String? error;
    try {
      final r = await api.post('markNotificationRead', body: {'id': '$id'});
      error = _failure(r);
    } catch (_) {}
    await fetch();
    return error;
  }

  Future<String?> markAll() async {
    String? error;
    try {
      final r = await api.post('markAllNotificationsRead');
      error = _failure(r);
    } catch (_) {}
    await fetch();
    return error;
  }

  String? _failure(Map<String, dynamic> r) {
    if (r['success'] == true) return null;
    final m = '${r['message'] ?? ''}'.trim();
    return m.isEmpty ? null : m;
  }

  void markReadLocally(ShellNotification n) {
    if (n.isRead) return;
    n.isRead = true;
    if (unread > 0) unread--;
    if (!_disposed) notifyListeners();
  }

  void clearUnreadLocally() {
    for (final n in items) {
      n.isRead = true;
    }
    unread = 0;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _liveCancel?.call();
    super.dispose();
  }
}

class ShellBell extends StatefulWidget {
  const ShellBell({super.key, required this.center, required this.onOpenPage});

  final ShellNotifications center;
  final ValueChanged<String> onOpenPage;

  @override
  State<ShellBell> createState() => _ShellBellState();
}

class _ShellBellState extends State<ShellBell> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    if (kDebugMode && Platform.environment['TP_SHELL_OPEN'] == 'bell') {
      Timer(const Duration(seconds: 4), () {
        if (mounted && !_portal.isShowing) _toggle();
      });
    }
  }

  void _toggle() {
    if (_portal.isShowing) {
      _close();
    } else {
      _portal.show();
      widget.center.fetch();
      setState(() {});
    }
  }

  void _close() {
    if (!_portal.isShowing) return;
    _portal.hide();
    setState(() {});
    final c = widget.center;
    if (c.items.any((n) => !n.isRead)) {
      c.clearUnreadLocally();
      c.markAll().then(_report);
    }
  }

  void _report(String? error) {
    if (error == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _openItem(ShellNotification n) async {
    final target = n.targetKey;
    final error = await widget.center.markRead(n.id);
    if (!mounted) return;
    _report(error);
    if (target == null) return;
    _portal.hide();
    setState(() {});
    widget.onOpenPage(target);
  }

  void _dismissItem(ShellNotification n) {
    widget.center.markReadLocally(n);
    widget.center.markRead(n.id).then(_report);
  }

  void _markAll() {
    widget.center.markAll().then(_report);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.center,
      builder: (context, _) {
        final unread = widget.center.unread;
        final has = unread > 0;
        final bg = has
            ? (_hover ? const Color(0xFFFFEDD5) : const Color(0xFFFFF7ED))
            : (_hover || _portal.isShowing
                ? const Color(0xFFF1F5F9)
                : Colors.transparent);
        final border = has
            ? (_hover ? const Color(0xFFFDBA74) : const Color(0xFFFDE3C3))
            : (_hover || _portal.isShowing
                ? const Color(0xFFE7ECF3)
                : Colors.transparent);
        final fg = has
            ? const Color(0xFFB45309)
            : (_hover ? const Color(0xFF0B1B30) : const Color(0xFF55647A));
        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (_) => _dropdown(),
            child: Tooltip(
              message: 'Notifications',
              waitDuration: const Duration(milliseconds: 600),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: GestureDetector(
                  onTap: _toggle,
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: border),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Fa.bell, size: 16, color: fg),
                        ),
                      ),
                      if (has)
                        Positioned(
                          top: 2,
                          right: 1,
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFB45309),
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.9,
                                    height: 1,
                                    fontWeight: FontWeight.w700),
                              ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dropdown() {
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _close,
        ),
      ),
      CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, 6),
        child: Align(
          alignment: Alignment.topRight,
          child: _DropdownCard(
            center: widget.center,
            onOpen: _openItem,
            onDismiss: _dismissItem,
            onMarkAll: _markAll,
          ),
        ),
      ),
    ]);
  }
}

class _DropdownCard extends StatelessWidget {
  const _DropdownCard({
    required this.center,
    required this.onOpen,
    required this.onDismiss,
    required this.onMarkAll,
  });
  final ShellNotifications center;
  final ValueChanged<ShellNotification> onOpen;
  final ValueChanged<ShellNotification> onDismiss;
  final VoidCallback onMarkAll;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x140F172A)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x2E0F172A), blurRadius: 40, offset: Offset(0, 18)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: AnimatedBuilder(
          animation: center,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Row(children: [
                  const Expanded(
                    child: Text('Notifications',
                        style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                  _MarkAll(onTap: onMarkAll),
                ]),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 380),
                child: !center.loaded
                    ? _empty('Loading...')
                    : center.items.isEmpty
                        ? _empty('No notifications yet')
                        : ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: [
                              for (final n in center.items)
                                _NotifRow(
                                  n: n,
                                  onTap: () => onOpen(n),
                                  onDismiss: () => onDismiss(n),
                                ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Text(t,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.6)),
      );
}

class _MarkAll extends StatefulWidget {
  const _MarkAll({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_MarkAll> createState() => _MarkAllState();
}

class _MarkAllState extends State<_MarkAll> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text('Mark all as read',
            style: TextStyle(
                fontSize: 12.8,
                color: _hover ? const Color(0xFFE67000) : const Color(0xFFFF7D00),
                decoration: _hover ? TextDecoration.underline : null,
                decorationColor: const Color(0xFFE67000))),
      ),
    );
  }
}

class _NotifRow extends StatefulWidget {
  const _NotifRow(
      {required this.n, required this.onTap, required this.onDismiss});
  final ShellNotification n;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<_NotifRow> createState() => _NotifRowState();
}

class _NotifRowState extends State<_NotifRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.n;
    final unread = !n.isRead;
    final bg = unread
        ? (_hover ? const Color(0xFFFFEDD5) : const Color(0xFFFFF7ED))
        : (_hover ? const Color(0xFFF8FAFC) : Colors.white);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Stack(clipBehavior: Clip.none, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: n.type == 'lead'
                      ? const Color(0xFF0EA5E9)
                      : const Color(0xFFFF7D00),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(n.icon, size: 15, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.heading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 13.6,
                            fontWeight: FontWeight.w600)),
                    Text(n.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF475569), fontSize: 12.8)),
                    const SizedBox(height: 2),
                    Text(n.timeAgo,
                        style: const TextStyle(
                            color: Color(0xFF94A3B8), fontSize: 11.5)),
                  ],
                ),
              ),
            ]),
            if (_hover)
              Positioned(
                top: -4,
                right: -8,
                child: _Dismiss(onTap: widget.onDismiss),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Dismiss extends StatefulWidget {
  const _Dismiss({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_Dismiss> createState() => _DismissState();
}

class _DismissState extends State<_Dismiss> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Mark as read',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _hover ? const Color(0xFFE2E8F0) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Fa.times,
                size: 12,
                color:
                    _hover ? const Color(0xFF0F172A) : const Color(0xFF94A3B8)),
          ),
        ),
      ),
    );
  }
}
