import 'dart:convert';

import '../api_client.dart';

class WsResult {
  const WsResult(this.ok, this.message, [this.data = const {}]);
  final bool ok;
  final String message;
  final Map<String, dynamic> data;

  factory WsResult.from(Map<String, dynamic> res, String fallback,
      [String? success]) {
    final ok = res['status'] == 'success' || res['success'] == true;
    final msg = (res['message'] ?? '').toString();
    return WsResult(
        ok, msg.isEmpty ? (ok && success != null ? success : fallback) : msg, res);
  }
}

class SelfSettings {
  const SelfSettings({
    required this.fullName,
    required this.email,
    required this.emailVerified,
    required this.username,
    required this.role,
    required this.chatAlias,
    required this.mfaEnabled,
    required this.profilePicture,
    required this.preferences,
    this.soundSettings,
  });

  final String fullName;
  final String email;
  final bool emailVerified;
  final String username;
  final String role;
  final String chatAlias;
  final bool mfaEnabled;
  final String? profilePicture;
  final Map<String, dynamic> preferences;
  final Object? soundSettings;

  bool get isSuperAdmin => role.toLowerCase() == 'super_admin';
  bool get isAdmin => role.toLowerCase() == 'admin' || isSuperAdmin;
  String get dateFormat => (preferences['dateFormat'] ?? '12h').toString();

  factory SelfSettings.fromJson(Map<String, dynamic> j) {
    final prefs = j['preferences'];
    final pic = (j['profile_picture'] ?? '').toString();
    return SelfSettings(
      fullName: (j['full_name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      emailVerified: '${j['email_verified']}' == '1',
      username: (j['username'] ?? '').toString(),
      role: (j['role'] ?? '').toString(),
      chatAlias: (j['chat_alias'] ?? '').toString(),
      mfaEnabled: '${j['mfa_enabled']}' == '1' || j['mfa_enabled'] == true,
      profilePicture: pic.isEmpty ? null : pic,
      preferences:
          prefs is Map ? Map<String, dynamic>.from(prefs) : <String, dynamic>{},
      soundSettings: j['sound_settings'],
    );
  }
}

class AgentHours {
  const AgentHours(
      {required this.enabled,
      required this.start,
      required this.end,
      required this.tz});
  final bool enabled;
  final String start;
  final String end;
  final String tz;
}

class TicketReminder {
  const TicketReminder({required this.enabled, required this.days});
  final bool enabled;
  final int days;
}

class PosApiKey {
  const PosApiKey({
    required this.id,
    required this.label,
    required this.masked,
    required this.active,
    required this.createdAt,
    required this.lastUsedAt,
    required this.revokedAt,
    required this.requestCount,
  });
  final int id;
  final String label;
  final String masked;
  final bool active;
  final String createdAt;
  final String lastUsedAt;
  final String revokedAt;
  final int requestCount;

  factory PosApiKey.fromJson(Map<String, dynamic> j) => PosApiKey(
        id: int.tryParse('${j['id']}') ?? 0,
        label: (j['label'] ?? '').toString(),
        masked: (j['masked'] ?? '').toString(),
        active: j['active'] == true || '${j['active']}' == '1',
        createdAt: (j['created_at'] ?? '').toString(),
        lastUsedAt: (j['last_used_at'] ?? '').toString(),
        revokedAt: (j['revoked_at'] ?? '').toString(),
        requestCount: int.tryParse('${j['request_count']}') ?? 0,
      );
}

class ReminderUser {
  const ReminderUser(this.id, this.name);
  final int id;
  final String name;
}

class GlobalReminder {
  const GlobalReminder(
      {required this.mode, required this.sourceUserId, required this.users});
  final String mode;
  final int sourceUserId;
  final List<ReminderUser> users;
}

class WebSettingsService {
  WebSettingsService(this.api);
  final ApiClient api;

  String resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    return '${api.baseUrl}/$clean';
  }

  Future<SelfSettings> load() async {
    final res = await api.get('getSelfSettings');
    if (res['status'] != 'success' || res['data'] is! Map) {
      throw Exception((res['message'] ?? 'Failed to load settings.').toString());
    }
    return SelfSettings.fromJson(Map<String, dynamic>.from(res['data'] as Map));
  }

  Future<WsResult> updateAccount({
    required String fullName,
    required String email,
    required String chatAlias,
  }) async {
    final res = await api.post('updateSelfAccount', body: {
      'full_name': fullName,
      'email': email,
      'chat_alias': chatAlias,
    });
    return WsResult.from(res, 'Failed to update account.');
  }

  Future<WsResult> uploadAvatar(String path) async {
    final res = await api.uploadFiles('updateProfilePicture',
        filePaths: [path], fileField: 'profile_picture');
    return WsResult.from(res, 'Could not update picture.');
  }

  Future<WsResult> removeAvatar() async {
    final res = await api.post('removeProfilePicture', body: const {});
    return WsResult.from(res, 'Could not remove picture.');
  }

  Future<WsResult> sendEmailOtp() async {
    final res = await api.post('sendOwnEmailOtp', body: const {});
    return WsResult.from(res, 'Failed to send code.');
  }

  Future<WsResult> verifyEmail(String otp) async {
    final res = await api.post('verifyOwnEmail', body: {'otp': otp});
    return WsResult.from(res, 'Invalid code.');
  }

  Future<WsResult> changePassword({
    required String current,
    required String next,
    required String confirm,
  }) async {
    final res = await api.post('changeOwnPassword', body: {
      'current_password': current,
      'new_password': next,
      'confirm_password': confirm,
    });
    return WsResult.from(res, 'Failed to change password.');
  }

  Future<WsResult> setMfa(bool enabled) async {
    final res =
        await api.post('setOwnMfa', body: {'enabled': enabled ? '1' : '0'});
    return WsResult.from(res, 'Failed to update 2FA.');
  }

  Future<AgentHours?> agentHours() async {
    try {
      final res = await api.get('getAgentHoursSettings');
      if (res['status'] != 'success') return null;
      return AgentHours(
        enabled: '${res['enabled']}' == '1',
        start: (res['start'] ?? '08:00').toString(),
        end: (res['end'] ?? '17:00').toString(),
        tz: (res['tz'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<WsResult> saveAgentHours(
      {required bool enabled,
      required String start,
      required String end}) async {
    final res = await api.post('saveAgentHoursSettings', body: {
      'enabled': enabled ? '1' : '0',
      'start': start,
      'end': end,
    });
    return WsResult.from(res, 'Could not save.', 'Agent hours saved.');
  }

  Future<TicketReminder?> ticketReminder() async {
    try {
      final res = await api.get('getTicketReminderSettings');
      if (res['status'] != 'success') return null;
      return TicketReminder(
        enabled: '${res['enabled']}' == '1',
        days: int.tryParse('${res['days']}') ?? 3,
      );
    } catch (_) {
      return null;
    }
  }

  Future<WsResult> saveTicketReminder(
      {required bool enabled, required String days}) async {
    final res = await api.post('saveTicketReminderSettings', body: {
      'enabled': enabled ? '1' : '0',
      'days': days,
    });
    return WsResult.from(res, 'Could not save.', 'Reminder settings saved.');
  }

  Future<List<PosApiKey>?> posApiKeys() async {
    try {
      final res = await api.get('getPosApiKeys');
      if (res['status'] != 'success') return null;
      final raw = res['keys'];
      if (raw is! List) return <PosApiKey>[];
      return raw
          .whereType<Map>()
          .map((m) => PosApiKey.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<WsResult> createPosApiKey() async {
    try {
      final res =
          await api.post('createPosApiKey', body: {'label': 'TinkerPro POS'});
      return WsResult.from(res, 'Could not create the key.');
    } catch (_) {
      return const WsResult(false, 'Could not create the key.');
    }
  }

  Future<WsResult> revokePosApiKey(int id) async {
    try {
      final res = await api.post('revokePosApiKey', body: {'key_id': '$id'});
      return WsResult.from(res, 'Could not revoke the key.');
    } catch (_) {
      return const WsResult(false, 'Could not revoke the key.');
    }
  }

  Future<WsResult> savePreferences(Map<String, dynamic> prefs) async {
    final res = await api.post('saveSelfPreferences',
        body: {'preferences': jsonEncode(prefs)});
    return WsResult.from(res, 'Failed to save preferences.');
  }

  Future<WsResult> saveGlobalSounds(Map<String, String> sounds) async {
    final res = await api.post('saveGlobalSoundDefaults',
        body: {'sounds': jsonEncode(sounds)});
    return WsResult.from(res, 'Could not save sounds.');
  }

  Future<WsResult> resetOwnSounds() async {
    final res = await api.post('resetOwnSoundPrefs', body: const {});
    return WsResult.from(res, 'Could not restore the system default.');
  }

  Future<WsResult> uploadSound(String event, String path) async {
    final res = await api.uploadFiles('saveUserSound',
        fields: {'event': event}, filePaths: [path], fileField: 'file');
    return WsResult.from(res, 'Upload failed.');
  }

  Future<Map<String, bool>> sidebarHidden() async {
    final res = await api.get('getGlobalSidebarSettings');
    final raw = res['sidebar_hidden'];
    if (raw is! Map) return <String, bool>{};
    return raw.map((k, v) => MapEntry(k.toString(), v == true || '$v' == '1'));
  }

  Future<WsResult> saveSidebarHidden(Map<String, bool> hidden) async {
    final clean = <String, bool>{
      for (final e in hidden.entries)
        if (e.value) e.key: true,
    };
    final res = await api.post('saveGlobalSidebarSettings',
        body: {'sidebar_hidden': jsonEncode(clean)});
    return WsResult.from(res, 'Failed to save global sidebar settings.');
  }

  Future<GlobalReminder?> globalReminder() async {
    try {
      final res = await api.get('getGlobalReminderSetting');
      if (res['status'] != 'success') return null;
      final users = (res['users'] is List ? res['users'] as List : const [])
          .whereType<Map>()
          .map((m) => ReminderUser(
              int.tryParse('${m['id']}') ?? 0, (m['name'] ?? '').toString()))
          .toList();
      return GlobalReminder(
        mode: (res['mode'] ?? 'own').toString(),
        sourceUserId: int.tryParse('${res['source_user_id']}') ?? 0,
        users: users,
      );
    } catch (_) {
      return null;
    }
  }

  Future<WsResult> saveGlobalReminder(
      {required String mode, required int source}) async {
    final res = await api.post('saveGlobalReminderSetting', body: {
      'reminder_mode': mode,
      'reminder_source': '$source',
    });
    return WsResult.from(res, 'Could not save the reminder setting.',
        'Dashboard reminders updated for all accounts.');
  }
}
