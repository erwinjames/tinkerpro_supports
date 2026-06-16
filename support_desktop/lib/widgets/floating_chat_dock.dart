// Messenger-style floating chat dock. Anchored bottom-right, it shows on every
// page EXCEPT the full Chat page (the shell hides it there). Collapsed it's a
// round launcher with an unread badge; expanded it's a compact panel that hosts
// the real inbox inside its OWN Navigator — so tapping a conversation opens the
// thread *inside the box*, just like a chat popup, instead of taking over the
// whole window.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../services/chat_prefs.dart';
import '../services/chat_runtime.dart';
import '../theme.dart';
import '../screens/chat_inbox_screen.dart';

class FloatingChatDock extends StatefulWidget {
  const FloatingChatDock({
    super.key,
    required this.runtime,
    required this.api,
    required this.chatPrefs,
    required this.onSignOut,
  });

  final ChatRuntime runtime;
  final ApiClient api;
  final ChatPrefs chatPrefs;
  final VoidCallback onSignOut;

  @override
  State<FloatingChatDock> createState() => _FloatingChatDockState();
}

class _FloatingChatDockState extends State<FloatingChatDock> {
  bool _open = false;
  bool _inboxBound = false;
  final _navKey = GlobalKey<NavigatorState>();

  /// Esc inside the dock: step back to the inbox if a thread is open,
  /// otherwise collapse the dock.
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
    widget.runtime.addListener(_onRuntimeChange);
    if (!widget.runtime.ready && widget.runtime.error == null) {
      widget.runtime.bootstrap();
    }
    _bindInbox();
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

  /// The inbox only exists after bootstrap; start listening for the unread
  /// badge the moment it appears.
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open) _panel(rt),
        const SizedBox(height: 12),
        _launcher(unread),
      ],
    );
  }

  Widget _panel(ChatRuntime rt) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: Material(
      elevation: 14,
      borderRadius: BorderRadius.circular(14),
      color: Brand.surface,
      shadowColor: Colors.black.withValues(alpha: 0.5),
      child: Container(
        width: 360,
        height: 520,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.rule),
        ),
        child: Column(
          children: [
            _header(),
            const Divider(height: 1, thickness: 1, color: Brand.rule),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14)),
                child: rt.ready
                    ? Navigator(
                        key: _navKey,
                        // Threads/new-conversation push onto THIS navigator,
                        // so they render inside the dock, not full-screen.
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
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _header() {
    final text = Theme.of(context).textTheme;
    return Container(
      height: 46,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: const BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          const Icon(Icons.forum_outlined, size: 18, color: Brand.signal),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Messages',
                style: text.titleSmall?.copyWith(letterSpacing: 0.2)),
          ),
          IconButton(
            tooltip: 'Minimize',
            splashRadius: 18,
            icon: const Icon(Icons.remove, size: 18, color: Brand.paperDim),
            onPressed: () => setState(() => _open = false),
          ),
        ],
      ),
    );
  }

  Widget _panelStatus(ChatRuntime rt) {
    return Center(
      child: rt.error == null
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Brand.signal))
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(rt.error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: rt.bootstrap,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _launcher(int unread) {
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Brand.signal,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.5),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _open = !_open),
              child: Center(
                child: Icon(
                  _open ? Icons.close : Icons.chat_bubble,
                  color: Brand.canvas,
                  size: 24,
                ),
              ),
            ),
          ),
          if (!_open && unread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                constraints: const BoxConstraints(minWidth: 20),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Brand.canvas, width: 2),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
