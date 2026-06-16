// Shared chat bootstrap for the desktop shell. The full Chat page AND the
// floating chat dock both render against this single runtime, so there is
// exactly one realtime (Soketi) connection, one inbox, and one CallService
// for the whole app — no double-subscribe, no duplicate incoming-call sheets.
//
// Lifted out of ChatPage (which used to own the bootstrap) so the dock can
// reuse it on every other page. The shell owns the lifecycle.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_client.dart';
import 'call_service.dart';
import 'chat_realtime.dart';
import 'chat_service.dart';
import 'chat_state.dart';
import 'services.dart';

class ChatRuntime extends ChangeNotifier {
  ChatRuntime({required this.api, required this.auth});

  final ApiClient api;
  final AuthService auth;

  late final ChatService chatService = ChatService(api);
  late final ChatRealtimeService chatRealtime = ChatRealtimeService(api);

  ChatInbox? inbox;
  CallService? calls;
  int? myUserId;
  String? error;

  bool _booting = false;
  bool _disposed = false;

  /// True once the user id resolved and the inbox/services are wired.
  bool get ready => inbox != null && myUserId != null;

  /// Resolve the signed-in user, then stand up the inbox, call service, and
  /// realtime connection. Idempotent and safe to retry after an error.
  Future<void> bootstrap() async {
    if (_booting || ready || _disposed) return;
    _booting = true;
    error = null;
    notifyListeners();

    final probe = await auth.currentUserIdWithReason();
    if (_disposed) return;
    final uid = probe.userId;
    if (uid == null) {
      _booting = false;
      error = probe.error ??
          'Could not load chat. Check your connection or sign in again.';
      notifyListeners();
      return;
    }

    final ib = ChatInbox(chatService, chatRealtime);
    final cl = CallService(
      realtime: chatRealtime,
      chat: chatService,
      myUserId: uid,
    );

    myUserId = uid;
    inbox = ib;
    calls = cl;
    _booting = false;
    notifyListeners();

    unawaited(chatRealtime.connect(uid));
    unawaited(ib.load());
  }

  @override
  void dispose() {
    _disposed = true;
    calls?.dispose();
    chatRealtime.dispose();
    inbox?.dispose();
    super.dispose();
  }
}
