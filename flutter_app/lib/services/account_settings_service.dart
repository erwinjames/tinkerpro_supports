import 'dart:convert';

import '../api_client.dart';
import '../models/account_settings_models.dart';

class AccountSettingsService {
  AccountSettingsService(this._api);
  final ApiClient _api;

  String get _role => _api.userRole.trim().toLowerCase();

  bool get isSuperAdmin => _role == 'super_admin';

  bool get canEditGlobalSidebar => _role == 'super_admin';

  bool get canManagePosApiKey =>
      _role == 'admin' || _role == 'super_admin' || _role == 'developer';

  bool get canEditAgentOps => isSuperAdmin;

  String get posApiEndpoint => '${_api.baseUrl}/open-api';

  Future<SelfSettings?> load() async {
    try {
      final res = await _api.get('getSelfSettings');
      final data = res['data'];
      if (res['status'] == 'success' && data is Map) {
        return SelfSettings.fromJson(data.cast<String, dynamic>());
      }
    } catch (_) {}
    return null;
  }

  Future<SettingsResult> updateAccount({
    required String fullName,
    required String email,
    String? chatAlias,
  }) => _post('updateSelfAccount', {
    'full_name': fullName.trim(),
    'email': email.trim(),
    'chat_alias': ?chatAlias?.trim(),
  });

  Future<SettingsResult> sendEmailCode() => _post('sendOwnEmailOtp', const {});

  Future<SettingsResult> verifyEmail(String otp) =>
      _post('verifyOwnEmail', {'otp': otp.trim()});

  Future<SettingsResult> changePassword({
    required String current,
    required String next,
    required String confirm,
  }) => _post('changeOwnPassword', {
    'current_password': current,
    'new_password': next,
    'confirm_password': confirm,
  });

  Future<SettingsResult> setMfa(bool enabled) =>
      _post('setOwnMfa', {'enabled': enabled ? '1' : '0'});

  Future<AgentHours?> agentHours() async {
    try {
      final res = await _api.get('getAgentHoursSettings');
      if (res['status'] != 'success') return null;
      return AgentHours(
        enabled: settingsFlag(res['enabled']),
        start: (res['start'] ?? '08:00').toString(),
        end: (res['end'] ?? '17:00').toString(),
        timezone: (res['tz'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<SettingsResult> saveAgentHours({
    required bool enabled,
    required String start,
    required String end,
  }) => _post('saveAgentHoursSettings', {
    'enabled': enabled ? '1' : '0',
    'start': start,
    'end': end,
  });

  Future<TicketReminder?> ticketReminder() async {
    try {
      final res = await _api.get('getTicketReminderSettings');
      if (res['status'] != 'success') return null;
      final days = settingsInt(res['days']);
      return TicketReminder(
        enabled: settingsFlag(res['enabled']),
        days: days <= 0 ? 3 : days,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SettingsResult> saveTicketReminder({
    required bool enabled,
    required int days,
  }) => _post('saveTicketReminderSettings', {
    'enabled': enabled ? '1' : '0',
    'days': '$days',
  });

  Future<List<PosApiKey>?> posKeys() async {
    try {
      final res = await _api.get('getPosApiKeys');
      if (res['status'] != 'success') return null;
      final raw = res['keys'];
      return raw is List
          ? raw
                .whereType<Map>()
                .map((e) => PosApiKey.fromJson(e.cast<String, dynamic>()))
                .toList()
          : const [];
    } catch (_) {
      return null;
    }
  }

  Future<({bool ok, String? token, String? message})> createPosKey(
    String label,
  ) async {
    final res = await _post('createPosApiKey', {'label': label.trim()});
    return (
      ok: res.ok,
      token: res.data?['token']?.toString(),
      message: res.message,
    );
  }

  Future<SettingsResult> revokePosKey(int id) =>
      _post('revokePosApiKey', {'key_id': '$id'});

  Future<Set<String>?> sidebarHidden() async {
    try {
      final res = await _api.get('getGlobalSidebarSettings');
      if (res['status'] != 'success') return null;
      final raw = res['sidebar_hidden'];
      if (raw is Map) {
        return {
          for (final e in raw.entries)
            if (e.value == true || e.value == 1 || e.value == '1')
              e.key.toString(),
        };
      }
      return <String>{};
    } catch (_) {
      return null;
    }
  }

  Future<SettingsResult> saveSidebarHidden(Set<String> hidden) =>
      _post('saveGlobalSidebarSettings', {
        'sidebar_hidden': jsonEncode({for (final k in hidden) k: true}),
      });

  Future<GlobalReminder?> globalReminder() async {
    try {
      final res = await _api.get('getGlobalReminderSetting');
      if (res['status'] != 'success') return null;
      final raw = res['users'];
      return GlobalReminder(
        mode: (res['mode'] ?? 'own').toString(),
        sourceUserId: settingsInt(res['source_user_id']),
        users: raw is List
            ? raw
                  .whereType<Map>()
                  .map(
                    (e) => ReminderOption(
                      id: settingsInt(e['id']),
                      name: (e['name'] ?? '').toString(),
                    ),
                  )
                  .toList()
            : const [],
      );
    } catch (_) {
      return null;
    }
  }

  Future<SettingsResult> saveGlobalReminder({
    required String mode,
    required int sourceUserId,
  }) => _post('saveGlobalReminderSetting', {
    'reminder_mode': mode,
    'reminder_source': '$sourceUserId',
  });

  Future<SettingsResult> _post(String action, Map<String, String> body) async {
    try {
      final res = await _api.post(action, body: body);
      return SettingsResult(
        ok: res['status'] == 'success',
        message: res['message']?.toString(),
        data: res,
      );
    } catch (e) {
      final text = e.toString();
      return SettingsResult(
        ok: false,
        message: text.contains('Not allowed') || text.contains('403')
            ? 'You do not have access to this setting.'
            : 'Network error — please try again.',
      );
    }
  }
}
