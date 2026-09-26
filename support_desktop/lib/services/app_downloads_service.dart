import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api_client.dart';

int _int(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

String _str(dynamic v) => v == null ? '' : '$v';

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : <Map<String, dynamic>>[];

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => '$e').toList() : const <String>[];

class AdApp {
  const AdApp(this.file, this.label);
  final String file;
  final String label;
}

class AdSummary {
  const AdSummary({
    required this.file,
    required this.label,
    required this.total,
    required this.users,
    required this.last7,
    required this.lastAt,
  });
  final String file;
  final String label;
  final int total;
  final int users;
  final int last7;
  final String lastAt;

  factory AdSummary.fromJson(Map<String, dynamic> j) => AdSummary(
        file: _str(j['file']),
        label: _str(j['label']),
        total: _int(j['total']),
        users: _int(j['users']),
        last7: _int(j['last7']),
        lastAt: _str(j['last_at']),
      );
}

class AdUserRow {
  const AdUserRow({
    required this.name,
    required this.email,
    required this.role,
    required this.supportCount,
    required this.chatCount,
    required this.total,
    required this.firstAt,
    required this.lastAt,
    required this.apps,
    required this.search,
  });
  final String name;
  final String email;
  final String role;
  final int supportCount;
  final int chatCount;
  final int total;
  final String firstAt;
  final String lastAt;
  final List<String> apps;
  final String search;

  factory AdUserRow.fromJson(Map<String, dynamic> j) => AdUserRow(
        name: _str(j['name']),
        email: _str(j['email']),
        role: _str(j['role']),
        supportCount: _int(j['support_count']),
        chatCount: _int(j['chat_count']),
        total: _int(j['total']),
        firstAt: _str(j['first_at']),
        lastAt: _str(j['last_at']),
        apps: _strings(j['apps']),
        search: _str(j['search']),
      );
}

class AdLogRow {
  const AdLogRow({
    required this.date,
    required this.name,
    required this.role,
    required this.app,
    required this.isChat,
    required this.source,
    required this.device,
    required this.userAgent,
    required this.ip,
    required this.apps,
    required this.search,
  });
  final String date;
  final String name;
  final String role;
  final String app;
  final bool isChat;
  final String source;
  final String device;
  final String userAgent;
  final String ip;
  final List<String> apps;
  final String search;

  factory AdLogRow.fromJson(Map<String, dynamic> j) => AdLogRow(
        date: _str(j['date']),
        name: _str(j['name']),
        role: _str(j['role']),
        app: _str(j['app']),
        isChat: j['is_chat'] == true,
        source: _str(j['source']),
        device: _str(j['device']),
        userAgent: _str(j['user_agent']),
        ip: _str(j['ip_address']),
        apps: _strings(j['apps']),
        search: _str(j['search']),
      );
}

class AdData {
  const AdData({
    required this.apps,
    required this.summary,
    required this.users,
    required this.recent,
  });
  final List<AdApp> apps;
  final List<AdSummary> summary;
  final List<AdUserRow> users;
  final List<AdLogRow> recent;
}

class AppDownloadsService {
  AppDownloadsService(this.api);
  final ApiClient api;

  Future<AdData> load() async {
    final uri = Uri.parse('${api.baseUrl}/api.php')
        .replace(queryParameters: {'action': 'getAppDownloads'});
    final res = await http.get(uri,
        headers: {...api.authHeaders(), 'Accept': 'application/json'});
    Map<String, dynamic> body;
    try {
      final d = jsonDecode(res.body.trim());
      body = d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } catch (_) {
      throw Exception(res.statusCode >= 400
          ? 'HTTP ${res.statusCode}'
          : 'Unexpected response from server.');
    }
    if (body['success'] != true) {
      final msg = _str(body['message']);
      if (msg.contains('Invalid or missing action')) {
        throw Exception(
            'The server does not support this yet. Deploy the latest api.php.');
      }
      throw Exception(msg.isEmpty ? 'Could not load download records.' : msg);
    }
    return AdData(
      apps: _maps(body['apps'])
          .map((m) => AdApp(_str(m['file']), _str(m['label'])))
          .toList(),
      summary: _maps(body['summary']).map(AdSummary.fromJson).toList(),
      users: _maps(body['users']).map(AdUserRow.fromJson).toList(),
      recent: _maps(body['recent']).map(AdLogRow.fromJson).toList(),
    );
  }
}
