import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/chat_prefs.dart';
import '../services/chat_runtime.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'chat_inbox_screen.dart';
import '../widgets/tp_loader.dart';

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
        backgroundColor: context.brand.canvas,
        body: Center(
          child: rt.error == null
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: TpLoader(
                      strokeWidth: 2, color: Brand.signal))
              : SizedBox(
                  width: 440,
                  child: WebCard(
                    title: 'Chat unavailable',
                    icon: Icons.forum_outlined,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rt.error!,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SignalButton(
                              label: 'Retry',
                              icon: Icons.refresh,
                              onPressed: rt.bootstrap),
                        ),
                      ],
                    ),
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
      twoPane: true,
    );
  }
}
