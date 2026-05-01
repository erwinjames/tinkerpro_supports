import 'package:flutter/material.dart';

import 'api_client.dart';
import 'services/call_service.dart';
import 'services/chat_realtime.dart';
import 'services/chat_service.dart';
import 'services/lan_presence.dart';
import 'services/session_store.dart';
import 'screens/chat_screen.dart';
import 'screens/store_setup_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await ApiClient.create();
  final store = await SessionStore.open();
  runApp(EmployeeApp(api: api, store: store));
}

class EmployeeApp extends StatelessWidget {
  const EmployeeApp({super.key, required this.api, required this.store});

  final ApiClient api;
  final SessionStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TinkerPro Employee',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _Bootstrap(api: api, store: store),
    );
  }
}

/// Decides which screen to show on launch:
///   - no store_name in prefs        → StoreSetupScreen
///   - store_name present            → call chat.employeeStart, then chat
///
/// On a re-install where the cookie jar was wiped, calling
/// chat.employeeStart with the same store name re-binds the session to
/// the existing guest user on the server (per
/// findOrCreateEmployeeConversation), so chat history resumes.
class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.api, required this.store});

  final ApiClient api;
  final SessionStore store;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final ChatService _chat;
  ChatRealtimeService? _realtime;
  CallService? _calls;
  LanPresence? _lan;
  EmployeeChatInfo? _info;
  String? _error;
  bool _resolving = false;

  @override
  void dispose() {
    _lan?.stop();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _chat = ChatService(widget.api);
    if (widget.store.isConfigured) {
      _resumeFromStoredName();
    }
  }

  Future<void> _resumeFromStoredName() async {
    final name = widget.store.storeName ?? '';
    if (name.isEmpty) return;
    setState(() {
      _resolving = true;
      _error = null;
    });
    final info = await _chat.employeeStart(name);
    if (!mounted) return;
    if (info == null) {
      setState(() {
        _resolving = false;
        _error = 'Could not resume session. Check your connection and retry.';
      });
      return;
    }
    await widget.store.saveIdentity(
      userId: info.meId,
      convId: info.conversationId,
    );
    _wireRealtimeAndCalls(info);
  }

  void _wireRealtimeAndCalls(EmployeeChatInfo info) {
    final realtime = ChatRealtimeService(widget.api);
    final calls = CallService(
      realtime: realtime,
      chat: _chat,
      shadowUserId: info.meId,
    );
    realtime.connect(
      shadowUserId: info.meId,
      conversationId: info.conversationId,
    );

    // Same-store LAN discovery for the chat's "Add participant" picker.
    final lan = LanPresence(userId: info.meId, storeName: info.storeName);
    lan.start();

    setState(() {
      _info = info;
      _realtime = realtime;
      _calls = calls;
      _lan = lan;
      _resolving = false;
    });
  }

  void _onSetupReady(EmployeeChatInfo info) {
    _wireRealtimeAndCalls(info);
  }

  @override
  Widget build(BuildContext context) {
    // Not configured yet — first-launch screen.
    if (!widget.store.isConfigured) {
      return StoreSetupScreen(
        chat: _chat,
        store: widget.store,
        onReady: _onSetupReady,
      );
    }

    // Configured but bootstrap failed — show retry.
    if (_error != null) {
      return Scaffold(
        backgroundColor: Brand.surface,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off,
                    size: 48, color: Brand.textMuted),
                const SizedBox(height: 16),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _resolving ? null : _resumeFromStoredName,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Still resolving on warm start.
    if (_info == null || _realtime == null || _calls == null) {
      return const Scaffold(
        backgroundColor: Brand.surface,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return EmployeeChatScreen(
      api: widget.api,
      chat: _chat,
      realtime: _realtime!,
      calls: _calls!,
      lan: _lan!,
      store: widget.store,
      info: _info!,
    );
  }
}
