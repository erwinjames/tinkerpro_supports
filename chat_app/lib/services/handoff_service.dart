import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../models/handoff_models.dart';

class HandoffOffer {
  const HandoffOffer({
    required this.token,
    required this.account,
    this.conversationId,
  });

  final String token;
  final HandoffAccount account;
  final int? conversationId;
}

class HandoffService extends ChangeNotifier {
  HandoffService(this._api);

  final ApiClient _api;

  static const MethodChannel _channel =
      MethodChannel('com.tinkerpro.support/app_link');

  HandoffOffer? _offer;
  bool _busy = false;
  String? _message;

  HandoffOffer? get offer => _offer;
  bool get busy => _busy;
  String? get message => _message;

  Future<void> bootstrap() async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        await _consume(call.arguments);
      }
      return null;
    });
    try {
      final initial = await _channel.invokeMethod<dynamic>('consumeInitialLink');
      await _consume(initial);
    } catch (_) {}
  }

  Future<void> _consume(dynamic raw) async {
    if (raw is! Map) return;
    final token = (raw['handoff'] ?? '').toString();
    if (token.isEmpty) return;
    final convRaw = raw['conversationId'];
    final conversationId = int.tryParse((convRaw ?? '0').toString()) ?? 0;
    await _peek(token, conversationId > 0 ? conversationId : null);
  }

  Future<void> _peek(String token, int? conversationId) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      final res = await _api
          .post('peekAppHandoff', body: {'token': token})
          .timeout(const Duration(seconds: 10));
      if (res['success'] == true && res['account'] is Map) {
        final account = HandoffAccount.fromJson(
          Map<String, dynamic>.from(res['account'] as Map),
        );
        if (account.userId > 0 && account.userId != (_api.userId ?? 0)) {
          _offer = HandoffOffer(
            token: token,
            account: account,
            conversationId: conversationId,
          );
        } else {
          _offer = null;
        }
      } else {
        _offer = null;
        _message = (res['message'] ?? '').toString();
      }
    } catch (_) {
      _offer = null;
      _message = 'Could not reach the server to confirm that account.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void dismiss() {
    if (_offer == null && _message == null) return;
    _offer = null;
    _message = null;
    notifyListeners();
  }

  void clearMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }
}
