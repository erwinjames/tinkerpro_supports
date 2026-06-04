import 'dart:convert';
import 'dart:io' show File;

import 'package:dio/dio.dart';

import 'session_store.dart';

/// Thin client for the tinker-chat backend (the manager-created chatbot
/// living under [employee_app/tinker-chat]). It speaks the same public
/// `/api/chat/*` surface as the embeddable widget — POSTing a question,
/// receiving an answer, and optionally rating the reply.
///
/// Configuration is supplied at build time so a single binary can target
/// either the local dev server or the production tinkerchat.io instance
/// without a rebuild of the rest of the app:
///
///   flutter run \
///     --dart-define=TINKER_CHAT_URL=https://tinkerchat.io \
///     --dart-define=TINKER_CHAT_API_KEY=tk_live_...
///
/// Defaults point at localhost so it's obvious when the build is missing
/// the production values. Until the API key is configured the service
/// surfaces a friendly "not configured yet" answer instead of throwing —
/// makes the UI usable while QA wires the manager's key into the build.
class TinkerChatService {
  TinkerChatService({Dio? dio, SessionStore? store})
      : _store = store,
        _runtimeApiKey = store?.tinkerChatApiKey,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 45),
              validateStatus: (s) => s != null && s < 500,
            ));

  final Dio _dio;
  final SessionStore? _store;

  /// Runtime override — populated from [SessionStore] at construction
  /// and any time [setApiKey] succeeds. Takes precedence over
  /// [_buildTimeApiKey] so a cashier can paste in a fresh tenant key
  /// (issued via the tinker-chat admin panel's "Regenerate" action)
  /// without a rebuild.
  String? _runtimeApiKey;

  static const String serverUrl = String.fromEnvironment(
    'TINKER_CHAT_URL',
    defaultValue: 'http://localhost:8000',
  );

  static const String _buildTimeApiKey = String.fromEnvironment(
    'TINKER_CHAT_API_KEY',
    defaultValue: '',
  );

  String get apiKey {
    final r = _runtimeApiKey;
    if (r != null && r.isNotEmpty) return r;
    return _buildTimeApiKey;
  }

  bool get isConfigured => apiKey.isNotEmpty;

  /// Persist [key] in [SessionStore] and refresh the in-memory copy
  /// so subsequent requests pick it up without a restart. Pass an
  /// empty string to clear and fall back to the build-time key.
  Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    _runtimeApiKey = trimmed.isEmpty ? null : trimmed;
    await _store?.setTinkerChatApiKey(trimmed);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
      };

  /// GET /api/chat/config — branding (business name, greeting, etc.).
  /// Returns null on any error so callers can fall back to a static
  /// greeting rather than blanking out the screen.
  Future<TinkerChatConfig?> loadConfig() async {
    if (!isConfigured) return null;
    try {
      final res = await _dio.get<dynamic>(
        '$serverUrl/api/chat/config',
        options: Options(headers: _headers),
      );
      final data = res.data;
      if (data is! Map) return null;
      return TinkerChatConfig(
        businessName: (data['business_name'] as String?) ?? '',
        greeting: (data['greeting'] as String?) ?? '',
        logoUrl: (data['logo_url'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// POST /api/chat/ask. Returns a parsed reply or null on transport
  /// failure. Caller decides whether to retry or surface an error.
  Future<TinkerChatReply?> ask({
    required String question,
    required String sessionId,
    List<Map<String, String>> history = const [],
    String category = '',
  }) async {
    if (!isConfigured) {
      return TinkerChatReply(
        answer: "I'm not configured yet — ask your admin to set "
            "TINKER_CHAT_API_KEY in the build. In the meantime tap "
            "Help articles or Submit ticket above.",
        matched: false,
        escalation: null,
        logId: null,
      );
    }
    try {
      final res = await _dio.post<dynamic>(
        '$serverUrl/api/chat/ask',
        options: Options(headers: _headers),
        data: jsonEncode({
          'question': question,
          'session_id': sessionId,
          'category': category,
          'history': history,
        }),
      );
      final data = res.data;
      if (data is! Map) return null;
      // Rate-limit / auth errors come back as { detail: "..." } from FastAPI.
      if (res.statusCode != null && res.statusCode! >= 400) {
        return TinkerChatReply(
          answer: (data['detail'] as String?) ?? 'Sorry, I hit an error.',
          matched: false,
          escalation: null,
          logId: null,
          // 401/403 → the configured key is missing or rejected; the UI
          // surfaces a "Set API key" pill so the cashier can paste a fresh
          // one instead of being stuck behind a bad build-time key.
          authError: res.statusCode == 401 || res.statusCode == 403,
        );
      }
      return TinkerChatReply(
        answer: (data['answer'] as String?) ?? '',
        matched: (data['matched'] as bool?) ?? false,
        escalation: data['escalation'] as String?,
        logId: (data['log_id'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// POST /api/chat/ask-with-image — multipart upload of a screenshot
  /// plus an optional caption. Used by the paperclip button.
  Future<TinkerChatReply?> askWithImage({
    required File image,
    required String sessionId,
    String question = 'What is this? Help me with what you see.',
    List<Map<String, String>> history = const [],
  }) async {
    if (!isConfigured) {
      return TinkerChatReply(
        answer: "Image questions need the chatbot configured first.",
        matched: false,
        escalation: null,
        logId: null,
      );
    }
    try {
      final form = FormData.fromMap({
        'question': question,
        'session_id': sessionId,
        'history': jsonEncode(history),
        'image': await MultipartFile.fromFile(image.path),
      });
      final res = await _dio.post<dynamic>(
        '$serverUrl/api/chat/ask-with-image',
        options: Options(headers: {
          if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
        }),
        data: form,
      );
      final data = res.data;
      if (data is! Map) return null;
      if (res.statusCode != null && res.statusCode! >= 400) {
        return TinkerChatReply(
          answer: (data['detail'] as String?) ?? 'Sorry, I hit an error.',
          matched: false,
          escalation: null,
          logId: null,
          authError: res.statusCode == 401 || res.statusCode == 403,
        );
      }
      return TinkerChatReply(
        answer: (data['answer'] as String?) ?? '',
        matched: (data['matched'] as bool?) ?? false,
        escalation: data['escalation'] as String?,
        logId: (data['log_id'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// POST /api/chat/feedback — thumbs up/down on a specific reply.
  /// Best-effort: failures are swallowed so a rating tap never throws
  /// at the user.
  Future<bool> sendFeedback({
    required int logId,
    required String sessionId,
    required bool helpful,
  }) async {
    if (!isConfigured) return false;
    try {
      final res = await _dio.post<dynamic>(
        '$serverUrl/api/chat/feedback',
        options: Options(headers: _headers),
        data: jsonEncode({
          'log_id': logId,
          'session_id': sessionId,
          'helpful': helpful,
        }),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class TinkerChatConfig {
  const TinkerChatConfig({
    required this.businessName,
    required this.greeting,
    required this.logoUrl,
  });

  final String businessName;
  final String greeting;
  final String logoUrl;
}

class TinkerChatReply {
  const TinkerChatReply({
    required this.answer,
    required this.matched,
    required this.escalation,
    required this.logId,
    this.authError = false,
  });

  final String answer;
  final bool matched;
  final String? escalation;
  final int? logId;

  /// True when the backend rejected the request with 401/403 — the
  /// tenant API key is missing or invalid. The chat screen uses this
  /// to offer a "Set API key" pill even when a (wrong) key is present.
  final bool authError;

  /// Concatenated body the UI renders: the AI answer followed by the
  /// optional escalation note. The backend only fills `escalation`
  /// when no high-confidence KB match was found.
  String get displayBody {
    final esc = _stripSupportContact(escalation);
    if (esc == null || esc.trim().isEmpty) return answer;
    return '$answer\n\n$esc';
  }

  /// The tinker-chat backend appends a SUPPORT_CONTACT line (e.g.
  /// "Message us on Viber: 0917-xxx-xxxx") after the escalation message.
  /// The employee app escalates through its own "File a ticket" flow, so
  /// we drop that external Viber contact line here — cashiers should stay
  /// in-app rather than be sent off-channel. Backend/.env is left intact
  /// so the public web widget keeps showing it.
  static String? _stripSupportContact(String? esc) {
    if (esc == null) return null;
    final kept = esc.split('\n').where((line) {
      final l = line.trim().toLowerCase();
      return !l.contains('viber') && !l.startsWith('message us on');
    }).join('\n');
    return kept.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
