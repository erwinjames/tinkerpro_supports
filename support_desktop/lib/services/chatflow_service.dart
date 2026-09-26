import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../api_client.dart';
import '../models/chat_models.dart';

class ChatflowResult {
  const ChatflowResult(this.ok, this.message, [this.data = const {}]);
  final bool ok;
  final String? message;
  final Map<String, dynamic> data;

  int? get conversationId {
    final v = data['conversation_id'];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }
}

class ChatReaction {
  const ChatReaction({required this.emoji, required this.count, required this.userIds});
  final String emoji;
  final int count;
  final List<int> userIds;

  factory ChatReaction.fromJson(Map<String, dynamic> j) {
    final ids = <int>[];
    final raw = j['user_ids'];
    if (raw is List) {
      for (final e in raw) {
        final v = int.tryParse('$e');
        if (v != null) ids.add(v);
      }
    }
    return ChatReaction(
      emoji: '${j['emoji'] ?? ''}',
      count: int.tryParse('${j['count'] ?? ids.length}') ?? ids.length,
      userIds: ids,
    );
  }
}

class FacebookContact {
  const FacebookContact({required this.conversationId, required this.name, required this.withinWindow});
  final int conversationId;
  final String name;
  final bool withinWindow;

  factory FacebookContact.fromJson(Map<String, dynamic> j) => FacebookContact(
        conversationId: int.tryParse('${j['conversation_id'] ?? 0}') ?? 0,
        name: '${j['name'] ?? ''}',
        withinWindow: j['within_window'] == true || '${j['within_window']}' == '1',
      );
}

class GreetingTemplate {
  const GreetingTemplate({required this.label, required this.value, this.text});
  final String label;
  final String value;
  final String? text;
}

const List<String> kChatReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '😡'];

class ChatflowService {
  ChatflowService(this.api);
  final ApiClient api;

  static const int chunkSize = 20 * 1024 * 1024;
  static const int maxUploadBytes = 1024 * 1024 * 1024;

  static bool _ok(Map<String, dynamic> r) => r['success'] == true || r['status'] == 'success';

  static String? _msg(Map<String, dynamic> r) {
    final m = r['message'];
    if (m == null) return null;
    final s = '$m'.trim();
    return s.isEmpty ? null : s;
  }

  Future<ChatflowResult> _post(String action, Map<String, String> body) async {
    try {
      final r = await api.post(action, body: body);
      return ChatflowResult(_ok(r), _msg(r), r);
    } catch (_) {
      return const ChatflowResult(false, 'Network error');
    }
  }

  Future<ChatflowResult> _get(String action, [Map<String, String>? q]) async {
    try {
      final r = await api.get(action, q);
      return ChatflowResult(_ok(r), _msg(r), r);
    } catch (_) {
      return const ChatflowResult(false, 'Network error');
    }
  }

  Future<ChatflowResult> createDirect(int peerUserId) =>
      _post('chat.createDirect', {'peer_user_id': '$peerUserId'});

  Future<ChatflowResult> createGroup(String name, List<int> ids) =>
      _post('chat.createGroup', {'name': name, 'participant_ids': ids.join(',')});

  Future<ChatflowResult> createChannel(String name, String visibility, String topic) =>
      _post('chat.createChannel', {
        'name': name,
        'visibility': visibility,
        if (topic.isNotEmpty) 'topic': topic,
      });

  Future<ChatflowResult> joinChannel(int id) =>
      _post('chat.joinChannel', {'conversation_id': '$id'});

  Future<List<FacebookContact>> facebookContacts(String search) async {
    final r = await _get('chat.facebookContacts', search.isEmpty ? null : {'search': search});
    final raw = r.data['contacts'];
    if (!r.ok || raw is! List) return const [];
    return [
      for (final c in raw)
        if (c is Map) FacebookContact.fromJson(Map<String, dynamic>.from(c)),
    ];
  }

  Future<ChatflowResult> conversation(int id) => _get('chat.conversation', {'id': '$id'});

  Future<ChatflowResult> leaveConversation(int id) =>
      _post('chat.leaveConversation', {'conversation_id': '$id'});

  Future<ChatflowResult> addParticipants(int id, List<int> userIds) =>
      _post('chat.addParticipants', {'conversation_id': '$id', 'user_ids': userIds.join(',')});

  Future<ChatflowResult> renameConversation(int id, String name) =>
      _post('chat.renameConversation', {'conversation_id': '$id', 'name': name});

  Future<ChatflowResult> replyBody({required int conversationId, required int replyToId, required String body}) =>
      _post('desktopChatReplyBody', {
        'conversation_id': '$conversationId',
        'reply_to_message_id': '$replyToId',
        'body': body,
      });

  Future<ChatflowResult> react(int messageId, String emoji) =>
      _post('chat.react', {'message_id': '$messageId', 'emoji': emoji});

  Future<ChatflowResult> hideMessageForMe(int messageId) =>
      _post('chat.hideMessageForMe', {'message_id': '$messageId'});

  Future<ChatflowResult> deleteMessage(int messageId) =>
      _post('chat.deleteMessage', {'message_id': '$messageId'});

  Future<ChatflowResult> pinMessage(int messageId) =>
      _post('chat.pinMessage', {'message_id': '$messageId'});

  Future<ChatflowResult> unpinMessage(int messageId) =>
      _post('chat.unpinMessage', {'message_id': '$messageId'});

  Future<List<PinnedMessage>?> listPinned(int conversationId) async {
    final r = await _get('chat.listPinned', {'conversation_id': '$conversationId'});
    final raw = r.data['pinned'];
    if (!r.ok || raw is! List) return null;
    return [
      for (final p in raw)
        if (p is Map) PinnedMessage.fromJson(Map<String, dynamic>.from(p)),
    ];
  }

  Future<ChatflowResult> forward(int messageId, int targetConversationId) =>
      _post('chat.forward', {
        'message_id': '$messageId',
        'target_conversation_id': '$targetConversationId',
      });

  Future<ChatflowResult> history(int conversationId, {int limit = 50}) =>
      _get('chat.history', {'conversation_id': '$conversationId', 'limit': '$limit'});

  Future<ChatflowResult> myAlias(int conversationId) =>
      _get('chat.myAlias', {'conversation_id': '$conversationId'});

  Future<({String ticketNo, List<GreetingTemplate> templates})> acceptGreetings(int ticketId, String alias) async {
    final r = await _get('desktopChatAcceptGreetings', {'ticket_id': '$ticketId', 'alias': alias});
    final out = <GreetingTemplate>[];
    final raw = r.data['templates'];
    if (raw is List) {
      for (final t in raw) {
        if (t is Map) {
          out.add(GreetingTemplate(
            label: '${t['label'] ?? ''}',
            value: '${t['value'] ?? ''}',
            text: t['text']?.toString(),
          ));
        }
      }
    }
    return (ticketNo: '${r.data['ticket_no'] ?? '#$ticketId'}', templates: out);
  }

  Future<ChatflowResult> acceptTicket({
    required int ticketId,
    required int agentId,
    required String alias,
    required bool saveDefault,
    String? greetingMessage,
  }) =>
      _post('accept_ticket', {
        'ticket_id': '$ticketId',
        'agent_id': '$agentId',
        'chat_alias': alias,
        'save_alias_default': saveDefault ? '1' : '0',
        'greeting_message': ?greetingMessage,
      });

  Future<ChatflowResult> resolveTicket(int ticketId, int agentId) =>
      _post('markresolved', {'ticketId': '$ticketId', 'agent_id': '$agentId'});

  Future<ChatflowResult> reopenTicketAsAgent(int conversationId) =>
      _post('chat.reopenTicketAsAgent', {'conversation_id': '$conversationId'});

  Future<ChatflowResult> moveRequestToInbox(int id) =>
      _post('chat.moveRequestToInbox', {'conversation_id': '$id'});

  Future<ChatflowResult> returnRequestToFacebook(int id) =>
      _post('chat.returnRequestToFacebook', {'conversation_id': '$id'});

  Future<ChatflowResult> fbTakeOver(int id) =>
      _post('chat.fbTakeOver', {'conversation_id': '$id'});

  Future<ChatflowResult> fbReturnToAi(int id) =>
      _post('chat.fbReturnToAi', {'conversation_id': '$id'});

  Future<Map<String, dynamic>> _multipart(String action, Map<String, String> fields,
      {String? fileField, List<int>? bytes, String? filename, String? path}) async {
    final req = http.MultipartRequest('POST', Uri.parse(api.actionUrl(action)));
    api.authHeaders().forEach((k, v) => req.headers[k] = v);
    req.headers['Accept'] = 'application/json';
    req.fields.addAll(fields);
    if (fileField != null && bytes != null) {
      req.files.add(http.MultipartFile.fromBytes(fileField, bytes, filename: filename ?? 'blob'));
    } else if (fileField != null && path != null) {
      req.files.add(await http.MultipartFile.fromPath(fileField, path, filename: filename));
    }
    final res = await http.Response.fromStream(await req.send());
    try {
      final d = jsonDecode(res.body);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return {'success': false, 'message': res.statusCode >= 400 ? 'HTTP ${res.statusCode}' : 'Bad server response'};
  }

  static String _basename(String path) {
    final s = path.replaceAll('\\', '/');
    final i = s.lastIndexOf('/');
    return i < 0 ? s : s.substring(i + 1);
  }

  Future<({Attachment? attachment, String? error})> upload(File file, int conversationId) async {
    try {
      final size = await file.length();
      final name = _basename(file.path);
      Map<String, dynamic> res;
      if (size > chunkSize) {
        res = await _uploadChunked(file, conversationId, size, name);
      } else {
        res = await _multipart('chat.uploadAttachment', {'conversation_id': '$conversationId'},
            fileField: 'file', path: file.path, filename: name);
      }
      final att = res['attachment'];
      if (res['success'] == true && att is Map) {
        return (attachment: Attachment.fromJson(Map<String, dynamic>.from(att)), error: null);
      }
      return (attachment: null, error: _msg(res) ?? 'unknown error');
    } catch (_) {
      return (attachment: null, error: 'Network error');
    }
  }

  Future<Map<String, dynamic>> _uploadChunked(File file, int convId, int size, String name) async {
    final rng = Random.secure();
    final uploadId = List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final total = (size / chunkSize).ceil();
    final raf = await file.open();
    try {
      for (var i = 0; i < total; i++) {
        final start = i * chunkSize;
        final end = min(size, (i + 1) * chunkSize);
        await raf.setPosition(start);
        final bytes = await raf.read(end - start);
        final r = await _multipart('chat.uploadAttachmentChunk', {
          'conversation_id': '$convId',
          'upload_id': uploadId,
          'chunk_index': '$i',
          'total_chunks': '$total',
        }, fileField: 'chunk', bytes: bytes, filename: 'blob');
        if (r['success'] != true) {
          return {'success': false, 'message': _msg(r) ?? 'Chunk upload failed'};
        }
      }
    } finally {
      await raf.close();
    }
    return _multipart('chat.finalizeAttachmentUpload', {
      'conversation_id': '$convId',
      'upload_id': uploadId,
      'total_chunks': '$total',
      'original_name': name,
      'size': '$size',
    });
  }
}
