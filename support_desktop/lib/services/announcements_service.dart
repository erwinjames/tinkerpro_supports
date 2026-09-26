import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_client.dart';

const _endpoint = 'announcement-ajax.php';

class AnnResult {
  const AnnResult(this.ok, this.message, [this.data = const {}]);
  final bool ok;
  final String message;
  final Map<String, dynamic> data;
}

int _int(dynamic v) => int.tryParse('$v') ?? 0;
String _str(dynamic v) => v == null ? '' : v.toString();

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    required this.linkUrl,
    required this.linkLabel,
    required this.audienceType,
    required this.audienceRoles,
    required this.audienceUsers,
    required this.status,
    required this.requireAck,
    required this.startsAt,
    required this.expiresAt,
    required this.lifecycle,
    required this.reach,
    required this.readCount,
    required this.audienceLabel,
    required this.createdAt,
  });

  final int id;
  final String title;
  final String body;
  final String icon;
  final String tone;
  final String linkUrl;
  final String linkLabel;
  final String audienceType;
  final List<String> audienceRoles;
  final List<int> audienceUsers;
  final String status;
  final bool requireAck;
  final String startsAt;
  final String expiresAt;
  final String lifecycle;
  final int reach;
  final int readCount;
  final String audienceLabel;
  final String createdAt;

  bool get published => status == 'published';

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: _int(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        icon: _str(j['icon']).isEmpty ? 'fa-bullhorn' : _str(j['icon']),
        tone: _str(j['tone']).isEmpty ? 'info' : _str(j['tone']),
        linkUrl: _str(j['link_url']),
        linkLabel: _str(j['link_label']),
        audienceType:
            _str(j['audience_type']).isEmpty ? 'all' : _str(j['audience_type']),
        audienceRoles: (j['audience_roles'] is List
                ? j['audience_roles'] as List
                : const [])
            .map((e) => e.toString())
            .toList(),
        audienceUsers: (j['audience_users'] is List
                ? j['audience_users'] as List
                : const [])
            .map(_int)
            .toList(),
        status: _str(j['status']),
        requireAck: _int(j['require_ack']) == 1,
        startsAt: _str(j['starts_at']),
        expiresAt: _str(j['expires_at']),
        lifecycle:
            _str(j['lifecycle']).isEmpty ? 'draft' : _str(j['lifecycle']),
        reach: _int(j['reach']),
        readCount: _int(j['read_count']),
        audienceLabel: _str(j['audience_label']),
        createdAt: _str(j['created_at']),
      );
}

class AnnList {
  const AnnList(
      {required this.items, required this.counts, required this.dbOffset});
  final List<Announcement> items;
  final Map<String, int> counts;
  final int dbOffset;
}

class AnnStaff {
  const AnnStaff(
      {required this.id,
      required this.name,
      required this.username,
      required this.roleLabel});
  final int id;
  final String name;
  final String username;
  final String roleLabel;

  bool matches(String needle) {
    final hay = '$name $username $roleLabel'.toLowerCase();
    return hay.contains(needle.toLowerCase());
  }
}

class AnnOptions {
  const AnnOptions({
    required this.tones,
    required this.icons,
    required this.roles,
    required this.staff,
    required this.staffError,
    required this.dbOffset,
  });
  final Map<String, String> tones;
  final List<String> icons;
  final Map<String, String> roles;
  final List<AnnStaff> staff;
  final String staffError;
  final int dbOffset;
}

class AnnReader {
  const AnnReader(
      {required this.userId,
      required this.name,
      required this.acknowledged,
      required this.readAt});
  final int userId;
  final String name;
  final bool acknowledged;
  final String readAt;
}

class InboxItem {
  InboxItem({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    required this.toneLabel,
    required this.linkUrl,
    required this.linkLabel,
    required this.requireAck,
    required this.isRead,
    required this.isAcknowledged,
    required this.isPending,
    required this.author,
    required this.createdAt,
    required this.expiresAt,
  });

  final int id;
  final String title;
  final String body;
  final String icon;
  final String tone;
  final String toneLabel;
  final String linkUrl;
  final String linkLabel;
  final bool requireAck;
  bool isRead;
  bool isAcknowledged;
  bool isPending;
  final String author;
  final String createdAt;
  final String expiresAt;

  bool get needsAck => requireAck && isPending;

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: _int(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        icon: _str(j['icon']).isEmpty ? 'fa-bullhorn' : _str(j['icon']),
        tone: _str(j['tone']).isEmpty ? 'info' : _str(j['tone']),
        toneLabel: _str(j['tone_label']),
        linkUrl: _str(j['link_url']),
        linkLabel: _str(j['link_label']),
        requireAck: _int(j['require_ack']) == 1,
        isRead: _int(j['is_read']) == 1,
        isAcknowledged: _int(j['is_acknowledged']) == 1,
        isPending: _int(j['is_pending']) == 1,
        author: _str(j['author']),
        createdAt: _str(j['created_at']),
        expiresAt: _str(j['expires_at']),
      );
}

class AnnInbox {
  const AnnInbox({required this.items, required this.dbOffset});
  final List<InboxItem> items;
  final int dbOffset;
}

class AnnouncementsService {
  AnnouncementsService(this.api);
  final ApiClient api;

  Uri _uri([Map<String, String>? query]) {
    return Uri.parse('${api.baseUrl}/$_endpoint').replace(queryParameters: query);
  }

  Map<String, dynamic> _decode(http.Response r) {
    final body = r.body.trim();
    if (body.isEmpty) {
      return {'success': false, 'message': 'HTTP ${r.statusCode}'};
    }
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return {'success': false, 'message': 'Unexpected response (HTTP ${r.statusCode}).'};
  }

  Future<Map<String, dynamic>> _get(Map<String, String> query) async {
    final r = await http.get(_uri(query),
        headers: {...api.authHeaders(), 'Accept': 'application/json'});
    return _decode(r);
  }

  Future<Map<String, dynamic>> _post(String action, Map<String, String> body) async {
    final r = await http.post(_uri(),
        headers: {...api.authHeaders(), 'Accept': 'application/json'},
        body: {'action': action, ...body});
    return _decode(r);
  }

  AnnResult _result(Map<String, dynamic> res, String fallback) {
    final ok = res['success'] == true;
    final msg = _str(res['message']);
    return AnnResult(ok, msg.isEmpty ? fallback : msg, res);
  }

  Future<AnnList> list({String status = 'all', String q = ''}) async {
    final res = await _get({'action': 'list', 'status': status, 'q': q});
    if (res['success'] != true) {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not load announcements.'
          : _str(res['message']));
    }
    final counts = <String, int>{};
    if (res['counts'] is Map) {
      (res['counts'] as Map).forEach((k, v) => counts[k.toString()] = _int(v));
    }
    return AnnList(
      items: (res['items'] is List ? res['items'] as List : const [])
          .whereType<Map>()
          .map((m) => Announcement.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      counts: counts,
      dbOffset: _int(res['db_offset']),
    );
  }

  Future<AnnOptions> options() async {
    final res = await api.get('announcementComposeOptions');
    if (res['success'] != true) {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not load the announcement options.'
          : _str(res['message']));
    }
    Map<String, String> strMap(dynamic raw) => raw is Map
        ? raw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};
    return AnnOptions(
      tones: strMap(res['tones']),
      icons: (res['icons'] is List ? res['icons'] as List : const [])
          .map((e) => e.toString())
          .toList(),
      roles: strMap(res['roles']),
      staff: (res['staff'] is List ? res['staff'] as List : const [])
          .whereType<Map>()
          .map((m) => AnnStaff(
                id: _int(m['id']),
                name: _str(m['name']),
                username: _str(m['username']),
                roleLabel: _str(m['role_label']),
              ))
          .toList(),
      staffError: _str(res['staff_error']),
      dbOffset: _int(res['db_offset']),
    );
  }

  Future<Announcement?> get(int id) async {
    final res = await _get({'action': 'get', 'id': '$id'});
    if (res['success'] != true || res['announcement'] is! Map) return null;
    return Announcement.fromJson(
        Map<String, dynamic>.from(res['announcement'] as Map));
  }

  Future<AnnResult> save({
    required int id,
    required String title,
    required String body,
    required String icon,
    required String tone,
    required String linkUrl,
    required String linkLabel,
    required String audienceType,
    required List<String> audienceRoles,
    required List<int> audienceUsers,
    required String status,
    required bool requireAck,
    required String startsAt,
    required String expiresAt,
  }) async {
    final res = await _post('save', {
      'id': '$id',
      'title': title,
      'body': body,
      'icon': icon,
      'tone': tone,
      'link_url': linkUrl,
      'link_label': linkLabel,
      'audience_type': audienceType,
      'audience_roles': jsonEncode(audienceRoles),
      'audience_users': jsonEncode(audienceUsers),
      'status': status,
      'require_ack': requireAck ? '1' : '0',
      'starts_at': startsAt,
      'expires_at': expiresAt,
    });
    return _result(res, 'Could not save the announcement.');
  }

  Future<int?> previewReach({
    required String audienceType,
    required List<String> roles,
    required List<int> users,
  }) async {
    final res = await _post('preview_reach', {
      'audience_type': audienceType,
      'audience_roles': jsonEncode(roles),
      'audience_users': jsonEncode(users),
    });
    if (res['success'] != true) return null;
    return _int(res['reach']);
  }

  Future<AnnResult> setStatus(int id, String status) async {
    final res = await _post('set_status', {'id': '$id', 'status': status});
    return _result(res, 'Could not update the announcement.');
  }

  Future<AnnResult> delete(int id) async {
    final res = await _post('delete', {'id': '$id'});
    return _result(res, 'Could not delete the announcement.');
  }

  Future<AnnResult> resetReads(int id) async {
    final res = await _post('reset_reads', {'id': '$id'});
    return _result(res, 'Could not reset the read status.');
  }

  Future<({List<AnnReader> readers, int reach})?> readers(int id) async {
    final res = await _get({'action': 'readers', 'id': '$id'});
    if (res['success'] != true) return null;
    final list = (res['readers'] is List ? res['readers'] as List : const [])
        .whereType<Map>()
        .map((m) => AnnReader(
              userId: _int(m['user_id']),
              name: _str(m['full_name']),
              acknowledged: _int(m['acknowledged']) == 1,
              readAt: _str(m['read_at']),
            ))
        .toList();
    return (readers: list, reach: _int(res['reach']));
  }

  Future<AnnInbox> inbox() async {
    final res = await _get({'action': 'inbox'});
    if (res['success'] != true) {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not load announcements.'
          : _str(res['message']));
    }
    return AnnInbox(
      items: (res['items'] is List ? res['items'] as List : const [])
          .whereType<Map>()
          .map((m) => InboxItem.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      dbOffset: _int(res['db_offset']),
    );
  }

  Future<bool> markRead(int id, {required bool acknowledged}) async {
    try {
      final r = await http.post(_uri(),
          headers: {...api.authHeaders(), 'Accept': 'application/json'},
          body: {
            'action': 'mark_read',
            'id': '$id',
            'acknowledged': acknowledged ? '1' : '0',
          });
      if (r.statusCode < 200 || r.statusCode >= 300) return false;
      return _decode(r)['success'] == true;
    } catch (_) {
      return false;
    }
  }

  static DateTime? fromDb(String raw, int dbOffset) {
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
    if (parsed == null) return null;
    return parsed.subtract(Duration(seconds: dbOffset)).toLocal();
  }

  static String toDb(DateTime? local, int dbOffset) {
    if (local == null) return '';
    final shifted = local.toUtc().add(Duration(seconds: dbOffset));
    String p(int n) => n.toString().padLeft(2, '0');
    return '${shifted.year}-${p(shifted.month)}-${p(shifted.day)} ${p(shifted.hour)}:${p(shifted.minute)}:00';
  }
}
