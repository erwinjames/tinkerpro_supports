// API layer for the Help Center feature. Endpoints on api.php:
//   * getHelpTopics   GET                                   → {success, data:[...]}
//   * addHelpTopic    POST (JSON body) title,description,icon,iconColor
//                                                            → {success, data}
//   * updateHelpTopic POST (form)  id,title,description,icon,iconColor
//                                                            → {success, updated}
//   * deleteHelpTopic POST (form)  id                        → {success, message}
//
// Note the mismatched body encodings on the server: addHelpTopic reads the
// raw JSON body (php://input) while updateHelpTopic / deleteHelpTopic read
// $_POST, so add() uses postJson and the rest use form-encoded post().

import '../api_client.dart';
import '../models/help_models.dart';

class HelpResult {
  HelpResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class HelpService {
  HelpService(this._api);
  final ApiClient _api;

  /// Fetch every help topic (server returns them id-desc). Returns an empty
  /// list on any failure so the UI still renders.
  Future<List<HelpTopic>> list() async {
    try {
      final res = await _api.get('getHelpTopics');
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => HelpTopic.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<HelpResult> add({
    required String title,
    required String description,
    required String icon,
    required String iconColor,
  }) async {
    try {
      final res = await _api.postJson('addHelpTopic', body: {
        'title': title.trim(),
        'description': description.trim(),
        'icon': icon,
        'iconColor': iconColor,
      });
      return _resultOf(res);
    } catch (_) {
      return HelpResult(ok: false, message: 'Network error');
    }
  }

  Future<HelpResult> update({
    required int id,
    required String title,
    required String description,
    required String icon,
    required String iconColor,
  }) async {
    return _formMutate('updateHelpTopic', {
      'id': '$id',
      'title': title.trim(),
      'description': description.trim(),
      'icon': icon,
      'iconColor': iconColor,
    });
  }

  Future<HelpResult> delete(int id) =>
      _formMutate('deleteHelpTopic', {'id': '$id'});

  Future<HelpResult> _formMutate(
      String action, Map<String, String> body) async {
    try {
      final res = await _api.post(action, body: body);
      return _resultOf(res);
    } catch (_) {
      return HelpResult(ok: false, message: 'Network error');
    }
  }

  HelpResult _resultOf(Map<String, dynamic> res) {
    final ok = res['success'] == true || res['status'] == 'success';
    return HelpResult(ok: ok, message: res['message']?.toString());
  }
}
