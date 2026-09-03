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

class ChatAuthException implements Exception {
  ChatAuthException(this.message);
  final String message;
  @override
  String toString() => 'ChatAuthException: $message';
}

class ChatService {
  ChatService(this.api);
  final ApiClient api;

  static final _rng = Random();

  Future<bool> sessionAlive() async {
    try {
      final res = await api
          .get('getMobileAuthSession')
          .timeout(const Duration(seconds: 6));
      return res['success'] == true;
    } catch (_) {

      return true;
    }
  }

  static bool _looksUnauthorized(Map<String, dynamic> res) {
    if (res['success'] == true) return false;
    final m = (res['message'] ?? '').toString().toLowerCase();
    return m.contains('unauth');
  }

  static String newNonce() {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final buf = StringBuffer();

    var ts = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 10; i++) {
      buf.write(alphabet[ts & 0x1F]);
      ts >>= 5;
    }

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

  Future<bool> unpinMessage(int messageId) async {
    try {
      final res = await api.post('chat.unpinMessage',
          body: {'message_id': messageId.toString()});
      return res['success'] == true;
    } catch (_) {}
    return false;
  }

  String attachmentUrl(int attachmentId) {
    return api.actionUrl(
        'chat.downloadAttachment', {'id': attachmentId.toString()});
  }

  Future<Map<String, dynamic>?> iceServers() async {
    try {
      final res = await api.post('chat.iceServers', body: {});
      if (res['success'] == true && res['iceServers'] is List) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return null;
  }

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

  Future<void> notifyTyping(int conversationId) async {
    try {
      await api.post('chat.typing', body: {
        'conversation_id': conversationId.toString(),
      });
    } catch (_) {

    }
  }

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

  Future<int?> createGroup(String name, List<int> participantIds) async {
    try {
      final body = <String, String>{
        'name': name,

        'participant_ids': participantIds.join(','),
      };
      final res = await api.post('chat.createGroup', body: body);
      if (res['success'] == true && res['conversation_id'] != null) {
        return (res['conversation_id'] as num).toInt();
      }
    } catch (_) {}
    return null;
  }

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

  Future<bool> joinChannel(int conversationId) async {
    try {
      final res = await api.post('chat.joinChannel',
          body: {'conversation_id': conversationId.toString()});
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> leaveConversation(int conversationId) async {
    try {
      final res = await api.post('chat.leaveConversation',
          body: {'conversation_id': conversationId.toString()});
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

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

  /// Alias the customer sees for this agent: the per-conversation override
  /// if one is set, otherwise the account default. Mirrors the web accept
  /// modal's prefill.
  Future<({String? alias, String? defaultAlias})> myAlias(
      int conversationId) async {
    try {
      final res = await api.get('chat.myAlias', {
        'conversation_id': conversationId.toString(),
      });
      if (res['success'] != true) return (alias: null, defaultAlias: null);
      return (
        alias: res['alias']?.toString(),
        defaultAlias: res['default_alias']?.toString(),
      );
    } catch (_) {
      return (alias: null, defaultAlias: null);
    }
  }

  /// Moves a Facebook page thread out of the request queue and into the
  /// shared inbox. The server adds every active staff member as a
  /// participant and broadcasts the conversation so it appears live for
  /// whoever is entitled to see it.
  Future<bool> moveRequestToInbox(int conversationId) async {
    try {
      final res = await api.post('chat.moveRequestToInbox', body: {
        'conversation_id': conversationId.toString(),
      });
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Reverse of [moveRequestToInbox]: returns the thread to the Page Chat
  /// queue and drops members without Facebook access.
  /// Returns `removed` — how many members the server pruned for lacking
  /// Facebook access — so the caller can say what actually happened.
  Future<({bool ok, int removed})> returnRequestToFacebook(
      int conversationId) async {
    try {
      final res = await api.post('chat.returnRequestToFacebook', body: {
        'conversation_id': conversationId.toString(),
      });
      if (res['success'] != true) return (ok: false, removed: 0);
      final removed = res['removed'];
      return (
        ok: true,
        removed: removed is int ? removed : int.tryParse('${removed ?? 0}') ?? 0,
      );
    } catch (_) {
      return (ok: false, removed: 0);
    }
  }

  Future<bool> setConversationArchived(int conversationId, bool archived) async {
    try {
      final res = await api.post('chat.setConversationArchived', body: {
        'conversation_id': conversationId.toString(),
        'archived': archived ? '1' : '0',
      });
      return res['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> acceptTicket(
    int ticketId,
    int agentId, {
    String? alias,
    bool saveAliasDefault = false,
    String? greetingMessage,
  }) async {
    try {
      final res = await api.post('accept_ticket', body: {
        'ticket_id': ticketId.toString(),
        'agent_id': agentId.toString(),
        'chat_alias': ?alias,
        if (saveAliasDefault) 'save_alias_default': '1',
        if (greetingMessage != null && greetingMessage.isNotEmpty)
          'greeting_message': greetingMessage,
      });
      return res['status'] == 'success';
    } catch (_) {
      return false;
    }
  }

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
