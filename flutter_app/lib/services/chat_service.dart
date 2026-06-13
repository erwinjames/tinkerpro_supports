import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../api_client.dart';
import '../models/chat_models.dart';

String _basename(String path) {
  final i = path.lastIndexOf(Platform.pathSeparator);
  if (i < 0) {
    final j = path.lastIndexOf('/');
    return j < 0 ? path : path.substring(j + 1);
  }
  return path.substring(i + 1);
}

Map<String, dynamic>? _safeJson(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return null;
}

/// Thrown by [ChatService] when the server says the caller isn't
/// authenticated. The bootstrap flow uses this to detect a stale cookie
/// (e.g. session expired, or the device upgraded from an older build that
/// stored the wrong cookie) and route back to the login screen.
class ChatAuthException implements Exception {
  ChatAuthException(this.message);
  final String message;
  @override
  String toString() => 'ChatAuthException: $message';
}

/// REST wrapper for `api.php?action=chat.*`. Stateless, same pattern as
/// [LeadService] / [CustomerService]. All methods swallow network errors
/// and return empty/failed results — the UI stays renderable on every path.
class ChatService {
  ChatService(this.api);
  final ApiClient api;

  static final _rng = Random();

  /// Lightweight session probe. Returns `true` if the cookie still
  /// authenticates against the backend, `false` otherwise. Used by the
  /// chat bootstrap to detect a stale cookie before we silently render
  /// an empty inbox.
  Future<bool> sessionAlive() async {
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 6));
      return res['success'] == true;
    } catch (_) {
      // Network error — assume alive (don't punish flaky connections).
      // True auth failures show up later as ChatAuthException on
      // chat.inbox / chat.directory which has its own error UI.
      return true;
    }
  }

  static bool _looksUnauthorized(Map<String, dynamic> res) {
    if (res['success'] == true) return false;
    final m = (res['message'] ?? '').toString().toLowerCase();
    return m.contains('unauth');
  }

  /// Crockford-base32 ULID-ish nonce (26 chars). Good enough for client
  /// de-dup; server only cares that it's unique per (conv, sender).
  static String newNonce() {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final buf = StringBuffer();
    // Time component (first 10 chars, millis-ish)
    var ts = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 10; i++) {
      buf.write(alphabet[ts & 0x1F]);
      ts >>= 5;
    }
    // Random tail
    for (var i = 0; i < 16; i++) {
      buf.write(alphabet[_rng.nextInt(32)]);
    }
    return buf.toString();
  }

  Future<List<Conversation>> inbox() async {
    try {
      final res = await api.get('chat.inbox');
      if (_looksUnauthorized(res)) {
        throw ChatAuthException((res['message'] ?? '').toString());
      }
      if (res['success'] != true) return const [];
      final raw = res['conversations'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((m) => Conversation.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } on ChatAuthException {
      rethrow;
    } catch (_) {}
    return const [];
  }

  Future<List<ChatUser>> directory({String? search}) async {
    try {
      final query = (search != null && search.isNotEmpty)
          ? <String, String>{'search': search}
          : null;
      final res = await api.get('chat.directory', query);
      if (_looksUnauthorized(res)) {
        throw ChatAuthException((res['message'] ?? '').toString());
      }
      if (res['success'] != true) return const [];
      final raw = res['users'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((m) => ChatUser.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } on ChatAuthException {
      rethrow;
    } catch (_) {}
    return const [];
  }

  /// Get-or-create a DM with [peerUserId]. Returns the conversation id, or
  /// null on failure.
  Future<int?> createDirect(int peerUserId) async {
    try {
      final res = await api.post('chat.createDirect',
          body: {'peer_user_id': peerUserId.toString()});
      if (res['success'] == true && res['conversation_id'] != null) {
        return (res['conversation_id'] as num).toInt();
      }
    } catch (_) {}
    return null;
  }

  Future<MessagePage> history(int conversationId,
      {int? beforeId, int limit = 50}) async {
    try {
      final res = await api.get('chat.history', {
        'conversation_id': conversationId.toString(),
        'limit': limit.toString(),
        if (beforeId != null) 'before_id': beforeId.toString(),
      });
      if (res['success'] == true) {
        final raw = res['messages'];
        final messages = <Message>[];
        if (raw is List) {
          for (final m in raw) {
            if (m is Map) {
              messages.add(Message.fromJson(Map<String, dynamic>.from(m)));
            }
          }
        }
        return MessagePage(
          messages: messages,
          hasMore: res['has_more'] == true,
        );
      }
    } catch (_) {}
    return MessagePage(messages: const [], hasMore: false);
  }

  /// Send a message. Returns the server-shaped [Message] on success, or
  /// null on failure. Retries with the same [clientNonce] are idempotent
  /// server-side. [attachmentIds] reference rows pre-uploaded via
  /// [uploadAttachment].
  Future<Message?> send({
    required int conversationId,
    required String body,
    required String clientNonce,
    List<int> attachmentIds = const [],
  }) async {
    try {
      final res = await api.post('chat.send', body: {
        'conversation_id': conversationId.toString(),
        'body': body,
        'client_nonce': clientNonce,
        if (attachmentIds.isNotEmpty)
          'attachment_ids': attachmentIds.join(','),
      });
      if (res['success'] == true && res['message'] is Map) {
        return Message.fromJson(
            Map<String, dynamic>.from(res['message'] as Map));
      }
    } catch (_) {}
    return null;
  }

  /// Pinned messages for a conversation, newest pin first. Returns an empty
  /// list on any failure.
  Future<List<PinnedMessage>> listPinned(int conversationId) async {
    try {
      final res = await api.get(
          'chat.listPinned', {'conversation_id': conversationId.toString()});
      if (res['success'] == true && res['pinned'] is List) {
        return [
          for (final p in (res['pinned'] as List))
            if (p is Map)
              PinnedMessage.fromJson(Map<String, dynamic>.from(p)),
        ];
      }
    } catch (_) {}
    return const [];
  }

  /// Pin a message (staff-only server-side). Returns the created pin entry
  /// on success, or null on failure.
  Future<PinnedMessage?> pinMessage(int messageId) async {
    try {
      final res = await api
          .post('chat.pinMessage', body: {'message_id': messageId.toString()});
      if (res['success'] == true && res['pinned'] is Map) {
        return PinnedMessage.fromJson(
            Map<String, dynamic>.from(res['pinned'] as Map));
      }
    } catch (_) {}
    return null;
  }

  /// Unpin a message (staff-only server-side). Returns true on success.
  Future<bool> unpinMessage(int messageId) async {
    try {
      final res = await api.post('chat.unpinMessage',
          body: {'message_id': messageId.toString()});
      return res['success'] == true;
    } catch (_) {}
    return false;
  }

  /// URL for an attachment. Cookie-authed via [ApiClient.authHeaders] when
  /// passed to a network image / download client.
  String attachmentUrl(int attachmentId) {
    return api.actionUrl(
        'chat.downloadAttachment', {'id': attachmentId.toString()});
  }

  /// Forward a WebRTC signaling frame to [peerId]. Stateless from the
  /// server's perspective — the call lifecycle lives on the two clients.
  /// [kind] is one of: offer | answer | ice | ringing | accept | decline | end | busy.
  /// [media] is 'voice' or 'video'. [payload] is SDP, ICE candidate, or null.
  Future<bool> signal({
    required int peerId,
    required String kind,
    required String callId,
    required String media,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final res = await api.post('chat.signal', body: {
        'peer_id': peerId.toString(),
        'kind': kind,
        'call_id': callId,
        'media': media,
        'payload': payload == null ? '' : jsonEncode(payload),
      });
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// After a CallKit accept on a killed-app push, the original Soketi
  /// `call.signal` offer was missed. The server cached it in
  /// `pending_call_offers` (see chat-facade.signal); this fetches it so we
  /// can complete the WebRTC handshake. Returns null if no pending offer
  /// exists for the current user (caller hung up while we were launching).
  Future<Map<String, dynamic>?> fetchPendingOffer() async {
    try {
      final res = await api.post('chat.fetchPendingOffer', body: {});
      if (res['success'] != true) return null;
      final offer = res['offer'];
      if (offer is Map) return Map<String, dynamic>.from(offer);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Notify other participants that the caller is composing. Server
  /// broadcasts a `typing` event on `private-conv-{id}`. Callers should
  /// debounce (~2s) before calling again.
  Future<void> notifyTyping(int conversationId) async {
    try {
      await api.post('chat.typing', body: {
        'conversation_id': conversationId.toString(),
      });
    } catch (_) {
      // Typing is lossy by design — drop silently if it fails.
    }
  }

  /// Advance the caller's read cursor in a conversation. Server rejects any
  /// cursor that's smaller than the current value, so retries / out-of-order
  /// calls are safe.
  Future<bool> markRead(int conversationId, int lastReadMessageId) async {
    if (lastReadMessageId <= 0) return false;
    try {
      final res = await api.post('chat.markRead', body: {
        'conversation_id': conversationId.toString(),
        'last_read_message_id': lastReadMessageId.toString(),
      });
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ───────────────────────────────────── Phase 2 ─────────────────────────────

  /// Create a named group. Returns the new conversation id, or null on fail.
  Future<int?> createGroup(String name, List<int> participantIds) async {
    try {
      final body = <String, String>{
        'name': name,
        // PHP's $_POST parses key[]=1&key[]=2 into a real array — but http's
        // `body: Map<String, String>` can't do repeated keys. Fall back to
        // the comma-separated form, which the facade also accepts.
        'participant_ids': participantIds.join(','),
      };
      final res = await api.post('chat.createGroup', body: body);
      if (res['success'] == true && res['conversation_id'] != null) {
        return (res['conversation_id'] as num).toInt();
      }
    } catch (_) {}
    return null;
  }

  /// Create a named channel. [visibility] is 'public' or 'private'.
  Future<int?> createChannel({
    required String name,
    String? topic,
    String visibility = 'public',
  }) async {
    try {
      final body = <String, String>{
        'name': name,
        'visibility': visibility,
        if (topic != null && topic.isNotEmpty) 'topic': topic,
      };
      final res = await api.post('chat.createChannel', body: body);
      if (res['success'] == true && res['conversation_id'] != null) {
        return (res['conversation_id'] as num).toInt();
      }
    } catch (_) {}
    return null;
  }

  /// Self-join a public channel. Returns true if now a member.
  Future<bool> joinChannel(int conversationId) async {
    try {
      final res = await api.post('chat.joinChannel',
          body: {'conversation_id': conversationId.toString()});
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Self-leave. Returns true on success.
  Future<bool> leaveConversation(int conversationId) async {
    try {
      final res = await api.post('chat.leaveConversation',
          body: {'conversation_id': conversationId.toString()});
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Delete the entire conversation — including every message and
  /// attachment, for every participant. Authorisation is enforced
  /// server-side: DM either party; group/channel only the creator.
  /// Returns the server's [message] on failure for surface UX.
  Future<({bool ok, String? error})> deleteConversation(
      int conversationId) async {
    try {
      final res = await api.post('chat.deleteConversation', body: {
        'conversation_id': conversationId.toString(),
      });
      if (res['success'] == true) return (ok: true, error: null);
      return (
        ok: false,
        error: (res['message'] ?? 'Could not delete').toString(),
      );
    } catch (_) {
      return (ok: false, error: 'Network error');
    }
  }

  /// Add users to a group or private channel. Returns the list of
  /// actually-added user ids (duplicates / already-members are skipped
  /// server-side).
  Future<List<int>> addParticipants(
      int conversationId, List<int> userIds) async {
    try {
      final res = await api.post('chat.addParticipants', body: {
        'conversation_id': conversationId.toString(),
        'user_ids': userIds.join(','),
      });
      if (res['success'] == true && res['added'] is List) {
        return (res['added'] as List)
            .map((e) => int.tryParse(e.toString()) ?? 0)
            .where((e) => e > 0)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Browse discoverable channels. Returns public channels + joined
  /// private channels (the server filters).
  Future<List<ChannelBrief>> channels({String? search}) async {
    try {
      final query = (search != null && search.isNotEmpty)
          ? <String, String>{'search': search}
          : null;
      final res = await api.get('chat.channels', query);
      if (res['success'] != true) return const [];
      final raw = res['channels'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((m) => ChannelBrief.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Pre-upload a file. Returns a record carrying either the bound
  /// [Attachment] or a human-readable error string — never null. Callers
  /// can surface the error in a snack-bar so the user knows *why* the
  /// upload failed instead of just seeing a generic retry icon.
  Future<({Attachment? attachment, String? error})> uploadAttachment({
    required File file,
    required int conversationId,
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final url = Uri.parse(api.actionUrl('chat.uploadAttachment'));
      final req = http.MultipartRequest('POST', url);
      api.authHeaders().forEach((k, v) => req.headers[k] = v);
      req.fields['conversation_id'] = conversationId.toString();
      req.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: _basename(file.path),
      ));

      // We don't get true streaming progress out of http.MultipartRequest
      // without a custom Client, but invoking the callback at start/end gives
      // composer chips a non-flickering "uploading" state.
      onProgress?.call(0, await file.length());

      final streamed = await req.send();
      final responseBody = await streamed.stream.bytesToString();

      onProgress?.call(await file.length(), await file.length());

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        return (
          attachment: null,
          error: 'HTTP ${streamed.statusCode}',
        );
      }
      final decoded = _safeJson(responseBody);
      if (decoded == null) {
        return (attachment: null, error: 'Bad server response');
      }
      if (decoded['success'] != true) {
        final msg = (decoded['message'] ?? 'Upload failed').toString();
        return (attachment: null, error: msg);
      }
      final att = decoded['attachment'];
      if (att is Map) {
        return (
          attachment:
              Attachment.fromJson(Map<String, dynamic>.from(att)),
          error: null,
        );
      }
      return (attachment: null, error: 'Malformed response');
    } catch (e) {
      return (attachment: null, error: 'Network error');
    }
  }

  /// Fetch conversation metadata + full participant list. Used by the
  /// participants screen.
  Future<ConversationDetail?> conversation(int id) async {
    try {
      final res = await api.get('chat.conversation', {'id': id.toString()});
      if (res['success'] == true && res['conversation'] is Map) {
        final conv = Map<String, dynamic>.from(res['conversation'] as Map);
        final partsRaw = res['participants'];
        final parts = <ConversationMember>[];
        if (partsRaw is List) {
          for (final p in partsRaw) {
            if (p is Map) {
              parts.add(
                  ConversationMember.fromJson(Map<String, dynamic>.from(p)));
            }
          }
        }
        return ConversationDetail(conversation: conv, participants: parts);
      }
    } catch (_) {}
    return null;
  }

  // ───────────────────────────────────────────────── tickets ──────────────
  // These reuse the SAME backend actions the web chat uses (api.php). The
  // server posts the 👋 / ✅ announcement bubble itself (via the chat
  // pipeline + Soketi), so we only fire the action and refresh status.

  /// Bulk status for the tickets referenced in a thread. Maps the public
  /// ticket number → its live status. Empty on no ids / failure.
  Future<Map<int, TicketStatusInfo>> ticketStatuses(List<int> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final res = await api.get('getTicketsByIds', {'ids': ids.join(',')});
      final out = <int, TicketStatusInfo>{};
      if (res['status'] == 'success' && res['tickets'] is Map) {
        (res['tickets'] as Map).forEach((k, v) {
          final id = int.tryParse(k.toString());
          if (id != null && v is Map) {
            out[id] =
                TicketStatusInfo.fromJson(Map<String, dynamic>.from(v));
          }
        });
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Accept (claim) a ticket as [agentId]. Returns true on success. The
  /// server moves it to in_progress and posts the 👋 announcement.
  Future<bool> acceptTicket(int ticketId, int agentId) async {
    try {
      final res = await api.post('accept_ticket', body: {
        'ticket_id': ticketId.toString(),
        'agent_id': agentId.toString(),
      });
      return res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  /// Mark a ticket resolved as [agentId]. Returns true on success. The
  /// server moves it to resolved and posts the ✅ announcement.
  Future<bool> resolveTicket(int ticketId, int agentId) async {
    try {
      final res = await api.post('markresolved', body: {
        'ticketId': ticketId.toString(),
        'agent_id': agentId.toString(),
      });
      return res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

  /// Full ticket row for the detail sheet, or null on failure.
  Future<TicketDetail?> ticketDetail(int ticketId) async {
    try {
      final res = await api.get('chat.getTicketDetail', {
        'id': ticketId.toString(),
      });
      if (res['success'] == true && res['ticket'] is Map) {
        return TicketDetail.fromJson(
            Map<String, dynamic>.from(res['ticket'] as Map));
      }
    } catch (_) {}
    return null;
  }
}
