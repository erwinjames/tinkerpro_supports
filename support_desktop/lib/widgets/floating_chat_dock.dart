import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../services/chat_prefs.dart';
import '../services/chat_runtime.dart';
import '../theme.dart';
import '../screens/chat_inbox_screen.dart';
import '../screens/chat_ui_widgets.dart';
import 'premium.dart';
import 'tp_loader.dart';

class FloatingChatDock extends StatefulWidget {
  const FloatingChatDock({
    super.key,
    required this.runtime,
    required this.api,
    required this.chatPrefs,
    required this.onSignOut,
    this.onExpand,
  });

  final ChatRuntime runtime;
  final ApiClient api;
  final ChatPrefs chatPrefs;
  final VoidCallback onSignOut;
  final VoidCallback? onExpand;

  @override
  State<FloatingChatDock> createState() => _FloatingChatDockState();
}

enum _Corner { topLeft, topRight, bottomLeft, bottomRight }

class _FloatingChatDockState extends State<FloatingChatDock> {
  static const double _margin = 24;
  static const double _size = 60;
  static const _kCorner = 'tpChatDockCorner';
  static const _kStowed = 'tpChatDockStowed';

  bool _open = false;
  bool _inboxBound = false;
  _Corner _corner = _Corner.bottomRight;
  bool _stowed = false;
  bool _hover = false;
  Offset? _drag;
  SharedPreferences? _prefs;

  bool get _isLeft =>
      _corner == _Corner.topLeft || _corner == _Corner.bottomLeft;
  bool get _isTop => _corner == _Corner.topLeft || _corner == _Corner.topRight;

  Future<void> _loadPlacement() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    final c = p.getString(_kCorner);
    if (!mounted) return;
    setState(() {
      _corner = _Corner.values.firstWhere(
        (e) => e.name == c,
        orElse: () => _Corner.bottomRight,
      );
      _stowed = p.getBool(_kStowed) ?? false;
    });
  }

  void _setStowed(bool v) {
    setState(() {
      _stowed = v;
      if (v) _open = false;
      _hover = false;
    });
    _prefs?.setBool(_kStowed, v);
  }

  Offset _cornerOffset(_Corner c, Size area) {
    final left = c == _Corner.topLeft || c == _Corner.bottomLeft
        ? _margin
        : area.width - _margin - _size;
    final top = c == _Corner.topLeft || c == _Corner.topRight
        ? _margin
        : area.height - _margin - _size;
    return Offset(left, top);
  }

  void _dragStart(Size area) {
    _drag = _cornerOffset(_corner, area);
  }

  void _dragUpdate(DragUpdateDetails e, Size area) {
    final cur = _drag ?? _cornerOffset(_corner, area);
    final next = cur + e.delta;
    setState(() {
      _open = false;
      _drag = Offset(
        next.dx.clamp(0.0, area.width - _size).toDouble(),
        next.dy.clamp(0.0, area.height - _size).toDouble(),
      );
    });
  }

  void _dragEnd(Size area) {
    final pos = _drag;
    if (pos == null) return;
    final center = pos + const Offset(_size / 2, _size / 2);
    final left = center.dx < area.width / 2;
    final top = center.dy < area.height / 2;
    final corner = top
        ? (left ? _Corner.topLeft : _Corner.topRight)
        : (left ? _Corner.bottomLeft : _Corner.bottomRight);
    setState(() {
      _corner = corner;
      _drag = null;
    });
    _prefs?.setString(_kCorner, corner.name);
  }

  final _navKey = GlobalKey<NavigatorState>();

  void _escape() {
    final nav = _navKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else {
      setState(() => _open = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPlacement();
    widget.runtime.addListener(_onRuntimeChange);
    if (!widget.runtime.ready && widget.runtime.error == null) {
      widget.runtime.bootstrap();
    }
    _bindInbox();
    if (kDebugMode && Platform.environment['TP_CHAT_DOCK'] == 'open') {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _open = true);
      });
    }
  }

  @override
  void dispose() {
    widget.runtime.removeListener(_onRuntimeChange);
    if (_inboxBound) widget.runtime.inbox?.removeListener(_onChange);
    super.dispose();
  }

  void _onRuntimeChange() {
    _bindInbox();
    if (mounted) setState(() {});
  }

  void _bindInbox() {
    if (!_inboxBound && widget.runtime.inbox != null) {
      widget.runtime.inbox!.addListener(_onChange);
      _inboxBound = true;
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rt = widget.runtime;
    final unread = rt.inbox?.unreadTotal ?? 0;
    return LayoutBuilder(
      builder: (context, c) {
        final area = Size(c.maxWidth, c.maxHeight);
        if (_stowed) {
          final anchor = _cornerOffset(_corner, area);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: _isLeft ? 0 : null,
                right: _isLeft ? null : 0,
                top: anchor.dy,
                child: _stowHandle(unread),
              ),
            ],
          );
        }
        final pos = _drag ?? _cornerOffset(_corner, area);
        final panelMaxH = (area.height - _size - _margin * 2 - 12)
            .clamp(300.0, 980.0)
            .toDouble();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (_open && _drag == null)
              Positioned(
                left: _isLeft ? _margin : null,
                right: _isLeft ? null : _margin,
                top: _isTop ? _margin + _size + 12 : null,
                bottom: _isTop ? null : _margin + _size + 12,
                child: _panel(rt, panelMaxH),
              ),
            AnimatedPositioned(
              duration: _drag == null
                  ? const Duration(milliseconds: 220)
                  : Duration.zero,
              curve: Curves.easeOutCubic,
              left: pos.dx,
              top: pos.dy,
              child: _launcher(unread, area),
            ),
          ],
        );
      },
    );
  }

  Widget _stowHandle(int unread) {
    final radius = _isLeft
        ? const BorderRadius.horizontal(right: Radius.circular(14))
        : const BorderRadius.horizontal(left: Radius.circular(14));
    return Tooltip(
      message: 'Show chat',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _setStowed(false),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 30,
                height: 56,
                decoration: BoxDecoration(
                  gradient: ChatTokens.gradient,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: ChatTokens.primary.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.sms_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              if (unread > 0)
                Positioned(
                  top: -6,
                  left: _isLeft ? 18 : -6,
                  child: _badge(unread),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(int unread) => Container(
    height: 20,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    constraints: const BoxConstraints(minWidth: 20),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: ChatTokens.danger,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white, width: 2),
    ),
    child: Text(
      unread > 99 ? '99+' : '$unread',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1,
      ),
    ),
  );

  Widget _panel(ChatRuntime rt, double maxHeight) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
      child: Container(
        width: 388,
        height: math.min(
          math.max(MediaQuery.of(context).size.height - 200, 300.0),
          maxHeight,
        ),
        decoration: BoxDecoration(
          color: ChatTokens.of(context).bg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0C233E).withValues(alpha: 0.32),
              blurRadius: 60,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _header(rt.inbox?.unreadTotal ?? 0),
            Expanded(
              child: rt.ready
                  ? Navigator(
                      key: _navKey,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => ChatInboxScreen(
                          service: rt.chatService,
                          realtime: rt.chatRealtime,
                          inbox: rt.inbox!,
                          myUserId: rt.myUserId!,
                          api: widget.api,
                          chatPrefs: widget.chatPrefs,
                          onSignOut: widget.onSignOut,
                          calls: rt.calls,
                        ),
                      ),
                    )
                  : _panelStatus(rt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(int unread) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(gradient: ChatTokens.navyGradient),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ChatTokens.online,
              boxShadow: [
                BoxShadow(
                  color: ChatTokens.online.withValues(alpha: 0.25),
                  spreadRadius: 3,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Chat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.onExpand != null) ...[
            _headBtn(Icons.open_in_full, 'Open full chat', () {
              setState(() => _open = false);
              widget.onExpand!();
            }),
            const SizedBox(width: 10),
          ],
          _headBtn(Icons.close, 'Close', () => setState(() => _open = false)),
        ],
      ),
    );
  }

  Widget _headBtn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.14),
          onTap: onTap,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _panelStatus(ChatRuntime rt) {
    return Center(
      child: rt.error == null
          ? const SizedBox(
              width: 20,
              height: 20,
              child: TpLoader(
                strokeWidth: 2,
                color: Brand.signal,
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rt.error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  GhostButton(
                    label: 'Retry',
                    icon: Icons.refresh,
                    onPressed: rt.bootstrap,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _launcher(int unread, Size area) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Tooltip(
              message: _open ? 'Close chat' : 'Chat — drag to move',
              waitDuration: const Duration(milliseconds: 600),
              child: MouseRegion(
                cursor: _drag != null
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _open = !_open),
                  onPanStart: (_) => _dragStart(area),
                  onPanUpdate: (e) => _dragUpdate(e, area),
                  onPanEnd: (_) => _dragEnd(area),
                  onPanCancel: () => _dragEnd(area),
                  child: Container(
                    width: _size,
                    height: _size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: ChatTokens.gradient,
                      boxShadow: [
                        BoxShadow(
                          color: ChatTokens.primary.withValues(alpha: 0.42),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Icon(
                      _open ? Icons.close : Icons.sms_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
            if (!_open && unread > 0)
              Positioned(right: -2, top: -2, child: _badge(unread)),
            if (_hover && !_open && _drag == null)
              Positioned(
                top: -8,
                left: _isLeft ? null : -8,
                right: _isLeft ? -8 : null,
                child: Tooltip(
                  message: 'Stow to edge',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => _setStowed(true),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Brand.navy,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
