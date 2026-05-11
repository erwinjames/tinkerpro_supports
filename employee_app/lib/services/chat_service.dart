import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' as dio;

import '../api_client.dart';
import '../models/chat_models.dart';

/// HTTP-only operations against the chat layer. Real-time delivery
/// (`message.new`, `typing`, etc.) lives in [ChatRealtimeService] —
/// this file is just the request/response surface.
///
/// Every call goes through [ApiClient.postChat] / [getChat] which
/// auto-stamps `as_guest=1` so chatResolveActor() resolves to the
/// employee's guest shadow user (created/looked-up by store name via
/// `chat.employeeStart`).
class ChatService {
  ChatService(this.api);
  final ApiClient api;

  /// Boots / resumes this store's dedicated support thread.
  ///
  /// Idempotent on the server: a re-installed app calls this with the same
  /// store_name and gets back the SAME user_id + conversation_id, so the
  /// chat history persists across reinstalls. The PHPSESSID cookie that
  /// PHP returns on this call is what authenticates every subsequent
  /// chat/call request — Dio's cookie jar persists it to disk.
  Future<EmployeeChatInfo?> employeeStart(String storeName) async {
    final res = await api.postChat('chat.employeeStart',
        body: {'store_name': storeName});
    if (res['success'] != true || res['conversation_id'] == null) return null;
    final me = (res['me'] is Map)
        ? Map<String, dynamic>.from(res['me'] as Map)
        : const <String, dynamic>{};
    final parts = <ChatParticipant>[];
    final rawParts = res['participants'];
    if (rawParts is List) {
      for (final p in rawParts) {
        if (p is Map) {
          parts.add(ChatParticipant.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }
    return EmployeeChatInfo(
      conversationId:
          int.tryParse((res['conversation_id'] ?? 0).toString()) ?? 0,
      meId: int.tryParse((me['user_id'] ?? 0).toString()) ?? 0,
      meName: (me['display_name'] ?? storeName).toString(),
      storeName: storeName,
      participants: parts,
    );
  }

  /// Latest [limit] messages for the conversation, oldest first when we
  /// reverse the server's DESC ordering on the way in.
  Future<List<ChatMessage>> history(
    int convId, {
    int limit = 100,
    int? beforeId,
  }) async {
    final res = await api.getChat('chat.history', params: {
      'conversation_id': convId.toString(),
      'limit': limit.toString(),
      if (beforeId != null && beforeId > 0) 'before_id': beforeId.toString(),
    });
    final raw = res['messages'];
    if (raw is! List) return const [];
    final list = <ChatMessage>[];
    for (final m in raw) {
      if (m is Map) {
        list.add(ChatMessage.fromJson(Map<String, dynamic>.from(m)));
      }
    }
    list.sort((a, b) {
      final ai = (a.persistedId ?? 0);
      final bi = (b.persistedId ?? 0);
      return ai.compareTo(bi);
    });
    return list;
  }

  /// Posts a message + binds any pre-uploaded attachments. Server returns
  /// the canonical row (with attachments inflated) that the UI swaps in
  /// for the optimistic placeholder.
  Future<ChatMessage?> send({
    required int convId,
    required String body,
    required String clientNonce,
    List<int> attachmentIds = const [],
  }) async {
    final res = await api.postChat('chat.send', body: {
      'conversation_id': convId.toString(),
      'body': body,
      'client_nonce': clientNonce,
      'attachment_ids': attachmentIds.join(','),
    });
    if (res['success'] != true || res['message'] is! Map) return null;
    return ChatMessage.fromJson(Map<String, dynamic>.from(res['message']));
  }

  /// Server-side unsend (delete for everyone). Only the original
  /// sender can call this, and only if no one else has read the
  /// message yet — server enforces both. Soketi broadcasts
  /// `message.deleted` on the conv channel so peers drop the bubble
  /// live. Returns the raw response so callers can show the
  /// "already seen" friendly error.
  Future<Map<String, dynamic>> deleteMessage(int messageId) async {
    final res = await api.postChat('chat.deleteMessage', body: {
      'message_id': messageId.toString(),
    });
    return res;
  }

  /// Per-account "Remove for me" — hides this one message on this
  /// account only. Other participants still see it. Server returns
  /// `{success: true}` on a successful hide.
  Future<bool> hideMessageForMe(int messageId) async {
    final res = await api.postChat('chat.hideMessageForMe', body: {
      'message_id': messageId.toString(),
    });
    return res['success'] == true;
  }

  Future<bool> markRead(int convId, int lastReadId) async {
    final res = await api.postChat('chat.markRead', body: {
      'conversation_id': convId.toString(),
      'last_read_message_id': lastReadId.toString(),
    });
    return res['success'] == true;
  }

  Future<void> notifyTyping(int convId) async {
    try {
      await api.postChat('chat.typing', body: {
        'conversation_id': convId.toString(),
      });
    } catch (_) {/* lossy by design */}
  }

  /// Upload + claim. Returns the attachment id ready to be cited by
  /// the next [send] call. Throws [UploadException] with the server's
  /// human-readable message on failure so the UI can show it.
  Future<ChatAttachment> uploadAttachment(int convId, File file) async {
    if (!await file.exists()) {
      throw UploadException('File no longer exists on disk');
    }
    final size = await file.length();
    if (size <= 0) {
      throw UploadException(
          'File is empty (0 bytes) — likely a cloud-storage placeholder');
    }

    // Use the basename for filename — `file.uri.pathSegments.last` returns
    // an empty string on some Windows paths that end with a drive letter,
    // and Pusher/Dio falls over with empty filenames.
    final filename = file.path.split(Platform.pathSeparator).last;

    final mp = await dio.MultipartFile.fromFile(file.path, filename: filename);
    final res = await api.uploadChat('chat.uploadAttachment',
        fields: {'conversation_id': convId.toString()}, file: mp);
    if (res['success'] != true || res['attachment'] is! Map) {
      throw UploadException(
          (res['message'] as String?)?.trim().isNotEmpty == true
              ? res['message'] as String
              : 'Server returned no attachment');
    }
    return ChatAttachment.fromJson(
        Map<String, dynamic>.from(res['attachment']));
  }

  /// Build a download URL for an attachment; PHP streams it with the
  /// session's permission check baked in. Cookie auth carries via the
  /// shared cookie jar when the platform's image loader uses our
  /// HttpClient.
  String attachmentUrl(int attachmentId) {
    return api.actionUrl(
        'chat.downloadAttachment', {'id': attachmentId.toString()});
  }

  // ── Voice call signaling ──────────────────────────────────────────────

  /// Forward a WebRTC signaling frame to a single peer via the server.
  /// Used by the call service's per-peer fan-out — the customer rings
  /// every admin participant in parallel and the first answer wins.
  /// Pull participant list + metadata for a conversation we're a member
  /// of. Used when B's app switches its primary thread after accepting
  /// an Add-Participant invite — we need the admin participant list of
  /// the new conv to render the AppBar subtitle and seed call peers.
  Future<List<ChatParticipant>> fetchParticipants(int convId) async {
    try {
      final res = await api
          .getChat('chat.conversation', params: {'id': convId.toString()});
      if (res['success'] != true) return const [];
      final raw = res['participants'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => ChatParticipant.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// "Add participant" — A invites B (LAN-discovered colleague) into
  /// the conversation A is currently in. Server adds B to
  /// chat_participants AND fires a `conversation.created` event on B's
  /// private-user channel so B's app can prompt + switch its primary
  /// thread. Returns true on success.
  Future<bool> addToConversation({
    required int conversationId,
    required int peerUserId,
  }) async {
    final res = await api.postChat('chat.addToConversation', body: {
      'conversation_id': conversationId.toString(),
      'peer_user_id': peerUserId.toString(),
    });
    return res['success'] == true;
  }

  Future<bool> signal({
    required int peerId,
    required String kind,
    required String callId,
    required String media,
    Map<String, dynamic>? payload,
  }) async {
    final res = await api.postChat('chat.signal', body: {
      'peer_id': peerId.toString(),
      'kind': kind,
      'call_id': callId,
      'media': media,
      'payload': payload == null ? '' : jsonEncode(payload),
    });
    return res['success'] == true;
  }

  /// Tell every other participant of [conversationId] that this
  /// terminal is now `'busy'` (call in progress) or `'free'` (call
  /// ended). The server fan-outs to `private-conv-{convId}`; other
  /// colleagues on the same conversation pick it up via
  /// [ChatRealtimeService.callPresenceEvents] and grey out their own
  /// call buttons + show a banner. Best-effort — a failure here
  /// shouldn't block the call itself.
  Future<bool> callPresence({
    required int conversationId,
    required String state, // 'busy' | 'free'
    required String media, // 'voice' | 'video'
    required String callId,
  }) async {
    try {
      final res = await api.postChat('chat.callPresence', body: {
        'conversation_id': conversationId.toString(),
        'state': state,
        'media': media,
        'call_id': callId,
      });
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }
}

/// Snapshot of the employee's support thread, returned by
/// [ChatService.employeeStart]. Holds everything the chat + call screens
/// need: which conversation to subscribe to, who "me" is, and the list
/// of admin peers we can fan-ring on a voice call.
class EmployeeChatInfo {
  EmployeeChatInfo({
    required this.conversationId,
    required this.meId,
    required this.meName,
    required this.storeName,
    required this.participants,
  });

  final int conversationId;
  final int meId;
  final String meName;
  final String storeName;
  final List<ChatParticipant> participants;
}

class UploadException implements Exception {
  UploadException(this.message);
  final String message;
  @override
  String toString() => message;
}
