import 'dart:convert';

import '../api_client.dart';
import '../models/announcement_admin_models.dart';

class AnnouncementSaveResult {
  const AnnouncementSaveResult({
    required this.ok,
    required this.id,
    required this.message,
    required this.reach,
    required this.delivered,
  });

  final bool ok;
  final int id;
  final String message;
  final int reach;
  final int delivered;
}

class AnnouncementAdminService {
  AnnouncementAdminService(this._api);

  static const String _endpoint = 'announcement-ajax.php';

  final ApiClient _api;

  List<AnnouncementStaffPick>? _staffCache;

  String _fail(Object e, String fallback) {
    final msg = e is HttpException ? e.message.trim() : '';
    if (msg.isEmpty || msg.startsWith('HTTP ') || msg.startsWith('Non-JSON')) {
      return fallback;
    }
    return msg;
  }

  Future<AdminAnnouncementPage> list({
    String status = 'all',
    String query = '',
  }) async {
    try {
      final res = await _api.getPath(_endpoint, {
        'action': 'list',
        'status': status,
        'q': query.trim(),
      });
      if (res['success'] != true) {
        throw HttpException(
          res['message']?.toString() ?? 'Could not load announcements.',
        );
      }
      final raw = res['items'];
      final items = raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) =>
                      AdminAnnouncement.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : <AdminAnnouncement>[];
      final counts = <String, int>{};
      final rawCounts = res['counts'];
      if (rawCounts is Map) {
        rawCounts.forEach((key, value) {
          counts['$key'] = int.tryParse('$value') ?? 0;
        });
      }
      final offset = res['db_offset'];
      return AdminAnnouncementPage(
        items: items,
        counts: counts,
        dbOffsetSeconds: offset is num ? offset.toInt() : 0,
      );
    } catch (e) {
      throw HttpException(_fail(e, 'Could not load announcements.'));
    }
  }

  Future<AdminAnnouncement> get(int id) async {
    try {
      final res = await _api.getPath(_endpoint, {'action': 'get', 'id': '$id'});
      if (res['success'] != true || res['announcement'] is! Map) {
        throw HttpException(
          res['message']?.toString() ?? 'Could not load that announcement.',
        );
      }
      return AdminAnnouncement.fromJson(
        Map<String, dynamic>.from(res['announcement'] as Map),
      );
    } catch (e) {
      throw HttpException(_fail(e, 'Could not load that announcement.'));
    }
  }

  Future<AnnouncementSaveResult> save(
    AnnouncementDraft draft, {
    required String status,
    required int dbOffsetSeconds,
  }) async {
    try {
      final res = await _api.postPath(
        _endpoint,
        body: {
          'action': 'save',
          'id': '${draft.id}',
          'title': draft.title.trim(),
          'body': draft.body.trim(),
          'icon': draft.icon,
          'tone': draft.tone,
          'link_url': draft.linkUrl.trim(),
          'link_label': draft.linkLabel.trim(),
          'audience_type': draft.audienceType,
          'audience_roles': jsonEncode(draft.roles.toList()),
          'audience_users': jsonEncode(draft.users.toList()),
          'status': status,
          'require_ack': draft.requireAck ? '1' : '0',
          'starts_at': announcementToDb(draft.startsAt, dbOffsetSeconds),
          'expires_at': announcementToDb(draft.expiresAt, dbOffsetSeconds),
        },
      );
      return AnnouncementSaveResult(
        ok: res['success'] == true,
        id: int.tryParse('${res['id']}') ?? draft.id,
        message:
            res['message']?.toString() ?? 'Could not save the announcement.',
        reach: int.tryParse('${res['reach']}') ?? 0,
        delivered: int.tryParse('${res['delivered']}') ?? 0,
      );
    } catch (e) {
      return AnnouncementSaveResult(
        ok: false,
        id: draft.id,
        message: _fail(e, 'Could not reach the server.'),
        reach: 0,
        delivered: 0,
      );
    }
  }

  Future<bool> setStatus(int id, String status) async {
    try {
      final res = await _api.postPath(
        _endpoint,
        body: {'action': 'set_status', 'id': '$id', 'status': status},
      );
      if (res['success'] != true) {
        throw HttpException(
          res['message']?.toString() ?? 'Could not update the announcement.',
        );
      }
      return true;
    } catch (e) {
      throw HttpException(_fail(e, 'Could not update the announcement.'));
    }
  }

  Future<void> delete(int id) async {
    try {
      final res = await _api.postPath(
        _endpoint,
        body: {'action': 'delete', 'id': '$id'},
      );
      if (res['success'] != true) {
        throw HttpException(
          res['message']?.toString() ?? 'Could not delete the announcement.',
        );
      }
    } catch (e) {
      throw HttpException(_fail(e, 'Could not delete the announcement.'));
    }
  }

  Future<void> resetReads(int id) async {
    try {
      final res = await _api.postPath(
        _endpoint,
        body: {'action': 'reset_reads', 'id': '$id'},
      );
      if (res['success'] != true) {
        throw HttpException(
          res['message']?.toString() ?? 'Could not reset the read status.',
        );
      }
    } catch (e) {
      throw HttpException(_fail(e, 'Could not reset the read status.'));
    }
  }

  Future<AnnouncementReaders> readers(int id) async {
    try {
      final res = await _api.getPath(_endpoint, {
        'action': 'readers',
        'id': '$id',
      });
      if (res['success'] != true) {
        throw HttpException(
          res['message']?.toString() ?? 'Could not load readers.',
        );
      }
      final raw = res['readers'];
      return AnnouncementReaders(
        readers: raw is List
            ? raw
                  .whereType<Map>()
                  .map(
                    (e) => AnnouncementReader.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
            : const <AnnouncementReader>[],
        reach: int.tryParse('${res['reach']}') ?? 0,
      );
    } catch (e) {
      throw HttpException(_fail(e, 'Could not load readers.'));
    }
  }

  Future<int> previewReach({
    required String audienceType,
    required Set<String> roles,
    required Set<int> users,
  }) async {
    final res = await _api.postPath(
      _endpoint,
      body: {
        'action': 'preview_reach',
        'audience_type': audienceType,
        'audience_roles': jsonEncode(roles.toList()),
        'audience_users': jsonEncode(users.toList()),
      },
    );
    if (res['success'] != true) return 0;
    return int.tryParse('${res['reach']}') ?? 0;
  }

  Future<List<AnnouncementStaffPick>> staff({bool refresh = false}) async {
    final cached = _staffCache;
    if (cached != null && !refresh) return cached;

    final roles = <int, String>{};
    try {
      final res = await _api.get('users', {'page': '1', 'limit': '500'});
      final raw = res['data'] ?? res;
      if (raw is List) {
        for (final entry in raw.whereType<Map>()) {
          final id = int.tryParse('${entry['id']}') ?? 0;
          if (id <= 0) continue;
          roles[id] = (entry['role'] ?? '').toString();
        }
      }
    } catch (_) {}

    final out = <AnnouncementStaffPick>[];
    try {
      final res = await _api.get('getAssignableUsers');
      final raw = res['users'];
      if (raw is List) {
        for (final entry in raw.whereType<Map>()) {
          final id = int.tryParse('${entry['user_id']}') ?? 0;
          if (id <= 0) continue;
          final name = (entry['name'] ?? '').toString().trim();
          out.add(
            AnnouncementStaffPick(
              id: id,
              name: name.isEmpty ? 'User #$id' : name,
              role: roles[id] ?? '',
            ),
          );
        }
      }
    } catch (e) {
      throw HttpException(_fail(e, 'The staff list could not be loaded.'));
    }

    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _staffCache = out;
    return out;
  }
}
