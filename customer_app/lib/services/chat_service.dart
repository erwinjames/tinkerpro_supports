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
/// auto-stamps `as_portal=1` so chatResolveActor() resolves to the
/// customer's shadow user, not whatever staff session the device may
/// also have.
class ChatService {
  ChatService(this.api);
  final ApiClient api;

  /// Boots / re-syncs the customer's dedicated support group.
  /// Returns the canonical conversation_id, the group display name, the
  /// shadow user id we should treat as "me", participants, and read
  /// cursors. Called once on screen open and after any mid-session
  /// changes (e.g., a customer logged in via TIN without a relaunch).
  Future<PortalGroupInfo?> portalGroup() async {
    final res = await api.getChat('chat.portalGroup');
    if (res['success'] != true || res['conversation_id'] == null) return null;
    final me = (res['me'] is Map)
        ? Map<String, dynamic>.from(res['me'] as Map)
        : const <String, dynamic>{};
    final readCursors = <int, int>{};
    final rawCursors = res['read_cursors'];
    if (rawCursors is Map) {
      rawCursors.forEach((k, v) {
        final uid = int.tryParse(k.toString()) ?? 0;
        final cur = int.tryParse(v.toString()) ?? 0;
        if (uid > 0) readCursors[uid] = cur;
      });
    }
    final parts = <ChatParticipant>[];
    final rawParts = res['participants'];
    if (rawParts is List) {
      for (final p in rawParts) {
        if (p is Map) {
          parts.add(ChatParticipant.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }
    return PortalGroupInfo(
      conversationId:
          int.tryParse((res['conversation_id'] ?? 0).toString()) ?? 0,
      groupName: (res['group_name'] ?? 'Support').toString(),
      meId: int.tryParse((me['user_id'] ?? 0).toString()) ?? 0,
      meName: (me['display_name'] ?? '').toString(),
      participants: parts,
      readCursors: readCursors,
    );
  }

  /// Latest [limit] messages for the conversation, oldest first when we
  /// reverse the server's DESC ordering on the way in.
  Future<List<ChatMessage>> history(int convId, {int limit = 100}) async {
    final res = await api.getChat('chat.history', params: {
      'conversation_id': convId.toString(),
      'limit': limit.toString(),
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

  /// Server-side delete ("unsend"). Only the original sender can call this
  /// — server enforces. Soketi broadcasts `message.deleted` on the conv
  /// channel so peers drop the bubble live.
  Future<bool> deleteMessage(int messageId) async {
    final res = await api.postChat('chat.deleteMessage', body: {
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

  Future<bool> updateDisplayName(String name) async {
    final res = await api.postChat('chat.portalUpdateName', body: {
      'name': name,
    });
    return res['success'] == true;
  }

  /// Upload + claim. Returns the attachment id ready to be cited by
  /// the next [send] call.
  Future<ChatAttachment?> uploadAttachment(int convId, File file) async {
    final mp = await dio.MultipartFile.fromFile(file.path,
        filename: file.uri.pathSegments.last);
    final res = await api.uploadChat('chat.uploadAttachment',
        fields: {'conversation_id': convId.toString()}, file: mp);
    if (res['success'] != true || res['attachment'] is! Map) return null;
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
  Future<bool> signal({
    required int peerId,
    required String kind,
    required String callId,
    required String media,
    Map<String, dynamic>? payload,
    int? conversationId,
  }) async {
    final res = await api.postChat('chat.signal', body: {
      'peer_id': peerId.toString(),
      'kind': kind,
      'call_id': callId,
      'media': media,
      'payload': payload == null ? '' : jsonEncode(payload),
      // When set, the server rings only the admin(s) who CLAIMED the ticket
      // on this conversation instead of every admin in the support group.
      if (conversationId != null && conversationId > 0)
        'conversation_id': conversationId.toString(),
    });
    return res['success'] == true;
  }
}

class PortalGroupInfo {
  PortalGroupInfo({
    required this.conversationId,
    required this.groupName,
    required this.meId,
    required this.meName,
    required this.participants,
    required this.readCursors,
  });

  final int conversationId;
  final String groupName;
  final int meId;
  final String meName;
  final List<ChatParticipant> participants;
  final Map<int, int> readCursors;
}
