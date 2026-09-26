import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../models/chat_models.dart';
import 'chat_prefs.dart';
import 'chat_service.dart';

const MethodChannel _nativeChannel =
    MethodChannel('com.tinkerpro.support/chat_bubble');

const String _kStateKey = 'chat_head_state';
const String _kExpandedKey = 'chat_head_expanded';
const double _kHeadDp = 60;
const double _kWindowDp = 72;
const Color _kNavy = Color(0xFF0C233E);
const Color _kSurface = Color(0xFF12304F);
const Color _kSurfaceHi = Color(0xFF1B3D62);
const Color _kPaper = Color(0xFFEAF0F7);
const Color _kPaperDim = Color(0xFF9DB0C6);
const Color _kOrange = Color(0xFFFF7D00);

class ChatHeadState {
  const ChatHeadState({
    required this.conversationId,
    required this.senderName,
    required this.preview,
    required this.unread,
  });

  final int conversationId;
  final String senderName;
  final String preview;
  final int unread;

  ChatHeadState withUnread(int value) => ChatHeadState(
        conversationId: conversationId,
        senderName: senderName,
        preview: preview,
        unread: value,
      );

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'sender_name': senderName,
        'preview': preview,
        'unread': unread,
      };

  static ChatHeadState? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final id = int.tryParse('${map['conversation_id']}') ?? 0;
      if (id <= 0) return null;
      return ChatHeadState(
        conversationId: id,
        senderName: '${map['sender_name'] ?? ''}',
        preview: '${map['preview'] ?? ''}',
        unread: int.tryParse('${map['unread']}') ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class ChatHead {
  ChatHead._();

  static bool get platformSupported => Platform.isAndroid;

  static Future<bool> hasPermission() async {
    if (!platformSupported) return false;
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    if (!platformSupported) return false;
    try {
      await FlutterOverlayWindow.requestPermission();
    } catch (_) {}
    return hasPermission();
  }

  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  static Future<ChatHeadState?> readState() async {
    try {
      final prefs = await _prefs();
      return ChatHeadState.fromJson(prefs.getString(_kStateKey));
    } catch (_) {
      return null;
    }
  }

  static Future<bool> isExpanded() async {
    try {
      final prefs = await _prefs();
      return prefs.getBool(_kExpandedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setExpanded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kExpandedKey, value);
  }

  static Future<void> writeState(ChatHeadState? state) async {
    final prefs = await SharedPreferences.getInstance();
    if (state == null) {
      await prefs.remove(_kStateKey);
    } else {
      await prefs.setString(_kStateKey, jsonEncode(state.toJson()));
    }
  }

  static Future<void> _refreshOverlay() async {
    try {
      await FlutterOverlayWindow.shareData('refresh')
          .timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  static Future<void> showForMessage(Map<String, dynamic> data) async {
    if (!platformSupported) return;
    try {
      if (!await ChatPrefs.bubbleEnabledFromDisk()) return;
      if (!await hasPermission()) return;
      final convId =
          int.tryParse((data['conversation_id'] ?? '').toString()) ?? 0;
      if (convId <= 0) return;

      final active = await FlutterOverlayWindow.isActive();
      final previous = await readState();
      final expanded = active && await isExpanded();
      final sameThread = previous?.conversationId == convId;
      if (expanded && !sameThread) return;

      final unread = expanded
          ? 0
          : (sameThread ? (previous?.unread ?? 0) : 0) + 1;
      await writeState(ChatHeadState(
        conversationId: convId,
        senderName: (data['sender_name'] ?? 'New message').toString(),
        preview: (data['preview'] ?? '').toString(),
        unread: unread,
      ));

      if (active) {
        await _refreshOverlay();
        return;
      }

      await setExpanded(false);
      await _refreshOverlay();

      final metrics =
          await _nativeChannel.invokeMapMethod<String, dynamic>('screenMetrics');
      final density = (metrics?['density'] as num?)?.toDouble() ?? 2.75;
      final widthPx = (metrics?['width'] as num?)?.toDouble() ?? 1080;
      final heightPx = (metrics?['height'] as num?)?.toDouble() ?? 2400;
      final sizePx = (_kWindowDp * density).round();

      await FlutterOverlayWindow.showOverlay(
        width: sizePx,
        height: sizePx,
        alignment: OverlayAlignment.topLeft,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        positionGravity: PositionGravity.auto,
        visibility: NotificationVisibility.visibilitySecret,
        overlayTitle: 'TinkerPro Chat',
        overlayContent: 'Chat head is on',
        startPosition: OverlayPosition(
          widthPx / density - _kWindowDp,
          heightPx / density * 0.22,
        ),
      );
    } catch (e) {
      debugPrint('[chat_head] show failed: $e');
    }
  }

  static Future<void> markConversationRead(int conversationId) async {
    if (!platformSupported) return;
    final state = await readState();
    if (state == null ||
        state.conversationId != conversationId ||
        state.unread == 0) {
      return;
    }
    await writeState(state.withUnread(0));
    await _refreshOverlay();
  }

  static Future<void> dismissConversation(int conversationId) async {
    if (!platformSupported) return;
    final state = await readState();
    if (state == null || state.conversationId != conversationId) return;
    await close();
  }

  static Future<void> close() async {
    if (!platformSupported) return;
    try {
      await writeState(null);
      await setExpanded(false);
      try {
        await _nativeChannel.invokeMethod('hideCloseTarget');
      } catch (_) {}
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
      unawaited(_refreshOverlay());
    } catch (_) {}
  }
}

class ChatHeadOverlayApp extends StatelessWidget {
  const ChatHeadOverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _kOrange,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: const Material(
        type: MaterialType.transparency,
        child: _ChatHeadRoot(),
      ),
    );
  }
}

class _ChatHeadRoot extends StatefulWidget {
  const _ChatHeadRoot();

  @override
  State<_ChatHeadRoot> createState() => _ChatHeadRootState();
}

class _ChatHeadRootState extends State<_ChatHeadRoot> {
  ChatHeadState? _state;
  bool _expanded = false;
  bool _busy = false;
  OverlayPosition? _collapsedAt;
  StreamSubscription<dynamic>? _sub;
  final GlobalKey<_ChatPanelState> _panelKey = GlobalKey<_ChatPanelState>();

  OverlayPosition? _downPos;
  bool _dragging = false;
  bool _nearClose = false;
  bool _polling = false;
  bool _pressed = false;
  double _screenW = 0;
  double _screenH = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadMetrics();
    _sub = FlutterOverlayWindow.overlayListener.listen((_) => _load());
  }

  Future<void> _loadMetrics() async {
    try {
      final m =
          await _nativeChannel.invokeMapMethod<String, dynamic>('screenMetrics');
      final density = (m?['density'] as num?)?.toDouble() ?? 2.75;
      _screenW = ((m?['width'] as num?)?.toDouble() ?? 1080) / density;
      _screenH = ((m?['height'] as num?)?.toDouble() ?? 2400) / density;
    } catch (_) {}
  }

  Future<OverlayPosition?> _position() async {
    try {
      return await FlutterOverlayWindow.getOverlayPosition();
    } catch (_) {
      return null;
    }
  }

  bool _isNearClose(OverlayPosition pos) {
    if (_screenW <= 0 || _screenH <= 0) return false;
    final headX = pos.x + _kWindowDp / 2;
    final headY = pos.y + _kWindowDp / 2;
    final targetX = _screenW / 2;
    final targetY = _screenH - 72 - 32 - 24;
    final dx = headX - targetX;
    final dy = headY - targetY;
    return dx * dx + dy * dy < 95 * 95;
  }

  int _gesture = 0;
  bool _pointerDown = false;
  Future<void>? _pendingPoll;
  OverlayPosition? _lastPos;

  Future<void> _setTarget({bool? visible, bool? active}) async {
    try {
      if (visible == true) {
        await _nativeChannel.invokeMethod('showCloseTarget');
      } else if (visible == false) {
        await _nativeChannel.invokeMethod('hideCloseTarget');
      }
      if (active != null) {
        await _nativeChannel
            .invokeMethod('setCloseTargetActive', {'active': active});
      }
    } catch (_) {}
  }

  Future<void> _onPointerDown(PointerDownEvent _) async {
    final gesture = ++_gesture;
    _pointerDown = true;
    _dragging = false;
    _nearClose = false;
    setState(() => _pressed = true);
    final pos = await _position();
    if (gesture == _gesture) {
      _downPos = pos;
      _lastPos = pos;
    }
  }

  void _onPointerMove(PointerMoveEvent _) {
    if (_polling || !_pointerDown) return;
    _polling = true;
    final gesture = _gesture;
    _pendingPoll = _poll(gesture).whenComplete(() => _polling = false);
  }

  Future<void> _poll(int gesture) async {
    final pos = await _position();
    final start = _downPos;
    if (gesture != _gesture || !_pointerDown || pos == null || start == null) {
      return;
    }
    _lastPos = pos;
    if (!_dragging) {
      final dx = pos.x - start.x;
      final dy = pos.y - start.y;
      if (dx * dx + dy * dy < 64) return;
      _dragging = true;
      if (mounted) setState(() => _pressed = false);
      await _setTarget(visible: true);
      if (gesture != _gesture || !_pointerDown) {
        await _setTarget(visible: false);
        return;
      }
    }
    final near = _isNearClose(pos);
    if (near != _nearClose) {
      _nearClose = near;
      if (near) HapticFeedback.mediumImpact();
      await _setTarget(active: near);
    }
  }

  Future<void> _onPointerUp(PointerUpEvent _) async {
    _pointerDown = false;
    final gesture = _gesture;
    final releasePos = _position();
    if (mounted) setState(() => _pressed = false);
    await _pendingPoll;
    if (gesture != _gesture) return;
    var dragged = _dragging;
    final start = _downPos;
    final pos = await releasePos;
    if (!dragged && pos != null && start != null) {
      final dx = pos.x - start.x;
      final dy = pos.y - start.y;
      dragged = dx * dx + dy * dy >= 64;
    }
    final last = _lastPos;
    final near = dragged &&
        (_nearClose ||
            (pos != null && _isNearClose(pos)) ||
            (last != null && _isNearClose(last)));
    _dragging = false;
    _nearClose = false;
    await _setTarget(visible: false);
    if (!dragged) {
      await _expand();
    } else if (near) {
      await ChatHead.close();
    }
  }

  Future<void> _onPointerCancel(PointerCancelEvent _) async {
    _pointerDown = false;
    _gesture++;
    if (mounted) setState(() => _pressed = false);
    _dragging = false;
    _nearClose = false;
    await _setTarget(visible: false);
  }


  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final state = await ChatHead.readState();
    final expanded = await ChatHead.isExpanded();
    if (!mounted) return;
    final threadChanged = state?.conversationId != _state?.conversationId;
    setState(() {
      _state = state;
      _expanded = expanded && state != null;
    });
    if (_expanded) {
      _panelKey.currentState?.reload(resetList: threadChanged);
    }
  }

  Future<void> _expand() async {
    if (_busy || _state == null) return;
    _busy = true;
    try {
      try {
        _collapsedAt = await FlutterOverlayWindow.getOverlayPosition();
      } catch (_) {}
      final metrics =
          await _nativeChannel.invokeMapMethod<String, dynamic>('screenMetrics');
      final density = (metrics?['density'] as num?)?.toDouble() ?? 2.75;
      final heightPx = (metrics?['height'] as num?)?.toDouble() ?? 2400;
      final panelDp = (heightPx / density - 28 - 40).clamp(320.0, 4000.0);
      await ChatHead.setExpanded(true);
      final state = _state;
      if (state != null && state.unread > 0) {
        await ChatHead.writeState(state.withUnread(0));
      }
      await FlutterOverlayWindow.resizeOverlay(-1, panelDp.round(), false);
      await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 28));
      await FlutterOverlayWindow.updateFlag(OverlayFlag.focusPointer);
      if (!mounted) return;
      setState(() {
        _expanded = true;
        _state = _state?.withUnread(0);
      });
    } catch (e) {
      debugPrint('[chat_head] expand failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _collapse() async {
    if (_busy) return;
    _busy = true;
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      await ChatHead.setExpanded(false);
      if (mounted) setState(() => _expanded = false);
      await FlutterOverlayWindow.updateFlag(OverlayFlag.defaultFlag);
      await FlutterOverlayWindow.resizeOverlay(
          _kWindowDp.round(), _kWindowDp.round(), true);
      await FlutterOverlayWindow.moveOverlay(
          _collapsedAt ?? const OverlayPosition(0, 160));
    } catch (e) {
      debugPrint('[chat_head] collapse failed: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _openInApp() async {
    final state = _state;
    try {
      await _nativeChannel.invokeMethod('openConversation', {
        'conversationId': state?.conversationId ?? 0,
      });
    } catch (_) {}
    await _collapse();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) return const SizedBox.shrink();
    if (!_expanded) {
      return Center(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: _HeadCircle(state: state, pressed: _pressed),
        ),
      );
    }
    return _ChatPanel(
      key: _panelKey,
      state: state,
      onMinimize: _collapse,
      onClose: ChatHead.close,
      onOpenInApp: _openInApp,
    );
  }
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0A254D), _kOrange],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: initials.isEmpty
          ? Image.asset('assets/brand/tinkerpro-icon-192.png', fit: BoxFit.cover)
          : Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
    );
  }
}

class _HeadCircle extends StatelessWidget {
  const _HeadCircle({required this.state, required this.pressed});

  final ChatHeadState state;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final unread = state.unread;
    return AnimatedScale(
      scale: pressed ? 0.92 : 1,
      duration: const Duration(milliseconds: 120),
      child: SizedBox(
        width: _kWindowDp,
        height: _kWindowDp,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: _Avatar(name: state.senderName, size: _kHeadDp),
            ),
            if (unread > 0)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
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

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({
    super.key,
    required this.state,
    required this.onMinimize,
    required this.onClose,
    required this.onOpenInApp,
  });

  final ChatHeadState state;
  final VoidCallback onMinimize;
  final VoidCallback onClose;
  final VoidCallback onOpenInApp;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  ApiClient? _api;
  ChatService? _service;
  List<Message> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  Timer? _poll;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastReadSent = 0;

  @override
  void initState() {
    super.initState();
    reload(resetList: true);
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => reload());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<ChatService> _chat() async {
    final existing = _service;
    if (existing != null) return existing;
    final api = await ApiClient.load();
    _api = api;
    return _service = ChatService(api);
  }

  Future<void> reload({bool resetList = false}) async {
    final convId = widget.state.conversationId;
    if (resetList) _service = null;
    if (resetList && mounted) {
      setState(() {
        _loading = true;
        _messages = const [];
        _lastReadSent = 0;
      });
    }
    try {
      final service = await _chat();
      final page = await service.history(convId, limit: 40);
      if (!mounted || convId != widget.state.conversationId) return;
      final sorted = [...page.messages]
        ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
      final grew = sorted.length != _messages.length ||
          (sorted.isNotEmpty &&
              _messages.isNotEmpty &&
              sorted.last.id != _messages.last.id);
      setState(() {
        _messages = sorted;
        _loading = false;
        _error = page.messages.isEmpty && !_api!.hasSession
            ? 'Sign in to TinkerPro Chat first.'
            : null;
      });
      if (grew || resetList) _scrollToEnd();
      final lastId = sorted.isEmpty ? 0 : (sorted.last.id ?? 0);
      if (lastId > _lastReadSent) {
        _lastReadSent = lastId;
        unawaited(service.markRead(convId, lastId));
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final service = await _chat();
      final nonce =
          '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
      final sent = await service.send(
        conversationId: widget.state.conversationId,
        body: text,
        clientNonce: nonce,
      );
      if (!mounted) return;
      if (sent != null) {
        _input.clear();
        setState(() => _messages = [..._messages, sent]);
        _scrollToEnd();
      } else {
        setState(() => _error = 'Message not sent. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _api?.userId ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          10, 0, 10, MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: _kNavy,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kSurfaceHi),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _header(),
            Expanded(child: _body(me)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
                ),
              ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      color: _kSurface,
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onMinimize,
            child: _Avatar(name: widget.state.senderName, size: 38),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.state.senderName.isEmpty
                  ? 'TinkerPro Chat'
                  : widget.state.senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kPaper,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Open in app',
            onPressed: widget.onOpenInApp,
            icon: const Icon(Icons.open_in_new, color: _kPaperDim, size: 20),
          ),
          IconButton(
            tooltip: 'Minimize',
            onPressed: widget.onMinimize,
            icon: const Icon(Icons.remove, color: _kPaperDim),
          ),
          IconButton(
            tooltip: 'Close chat head',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: _kPaperDim),
          ),
        ],
      ),
    );
  }

  Widget _body(int me) {
    if (_loading && _messages.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: _kOrange),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text('No messages yet.', style: TextStyle(color: _kPaperDim)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final mine = me > 0 && m.senderId == me;
        final showName = !mine &&
            m.senderAlias.isNotEmpty &&
            (i == 0 || _messages[i - 1].senderId != m.senderId);
        final text = m.body.trim().isNotEmpty
            ? m.body.trim()
            : (m.hasAttachments
                ? 'Attachment: ${m.attachments.first.originalName}'
                : '');
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showName)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 4, bottom: 2),
                  child: Text(
                    m.senderAlias,
                    style: const TextStyle(color: _kPaperDim, fontSize: 11),
                  ),
                ),
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: mine ? _kOrange : _kSurfaceHi,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  text,
                  style: TextStyle(
                    color: mine ? Colors.white : _kPaper,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _composer() {
    return Container(
      color: _kSurface,
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: _kPaper, fontSize: 14),
              cursorColor: _kOrange,
              decoration: InputDecoration(
                hintText: 'Reply…',
                hintStyle: const TextStyle(color: _kPaperDim),
                isDense: true,
                filled: true,
                fillColor: _kNavy,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kOrange),
                  )
                : const Icon(Icons.send_rounded, color: _kOrange),
          ),
        ],
      ),
    );
  }
}
