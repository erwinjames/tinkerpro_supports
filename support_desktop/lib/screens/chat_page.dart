// Desktop chat page. Renders the inbox against the shell-owned [ChatRuntime]
// (a single shared realtime connection / inbox / CallService). Incoming-call
// handling lives in the shell now, so it works on any page — see
// DesktopShell, which listens to runtime.calls.

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/chat_prefs.dart';
import '../services/chat_runtime.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'chat_inbox_screen.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
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
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  @override
  void initState() {
    super.initState();
    widget.runtime.addListener(_onChange);
    if (!widget.runtime.ready && widget.runtime.error == null) {
      widget.runtime.bootstrap();
    }
  }

  @override
  void dispose() {
    widget.runtime.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rt = widget.runtime;
    if (!rt.ready) {
      return Scaffold(
        backgroundColor: Brand.canvas,
        body: Center(
          child: rt.error == null
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.signal))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('CHAT UNAVAILABLE',
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      const Hairline(),
                      const SizedBox(height: 16),
                      Text(rt.error!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: 200,
                        child: SignalButton(
                            label: 'Retry',
                            icon: Icons.refresh,
                            onPressed: rt.bootstrap),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    return ChatInboxScreen(
      service: rt.chatService,
      realtime: rt.chatRealtime,
      inbox: rt.inbox!,
      myUserId: rt.myUserId!,
      api: widget.api,
      chatPrefs: widget.chatPrefs,
      onSignOut: widget.onSignOut,
      calls: rt.calls,
    );
  }
}
