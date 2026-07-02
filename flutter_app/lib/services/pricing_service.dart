// API layer for the Pricing feature. Pricing uses a STANDALONE facade
// (`utils/models/pricing-facade.php`) that dispatches on an `action` param —
// it is NOT routed through api.php. Every call therefore carries `action`
// either in the query (GET) or the body (POST). Business types come from a
// sibling facade (`utils/models/business-type-facade.php?action=get`).
//
//   * get_pricings   GET   action, [business_type_id]    → {success, data:[...]}
//   * get_categories GET   action                        → {success, data:[...]}
//   * add_pricing    POST(multipart) action, business_type_id, title, price,
//                                     features(JSON), image(file?)
//   * update_pricing POST(multipart) action, id, business_type_id, title,
//                                     price, features(JSON), image(file?)
//   * delete_pricing POST  action, id                    → {success, message}

import 'dart:convert';

import '../api_client.dart';
import '../models/pricing_models.dart';

const String _kPricingPath = 'utils/models/pricing-facade.php';
const String _kBusinessTypePath = 'utils/models/business-type-facade.php';

class PricingResult {
  PricingResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

class PricingService {
  PricingService(this._api);
  final ApiClient _api;

  /// Fetch pricing plans, optionally scoped to one business type. Returns an
  /// empty list on any failure so the UI still renders.
  Future<List<Pricing>> listPricings({int? businessTypeId}) async {
    try {
      final res = await _api.getPath(_kPricingPath, {
        'action': 'get_pricings',
        if (businessTypeId != null) 'business_type_id': '$businessTypeId',
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Pricing.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Feature categories used to tag individual features.
  Future<List<PricingCategory>> listCategories() async {
    try {
      final res = await _api.getPath(_kPricingPath, {
        'action': 'get_categories',
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => PricingCategory.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Business types for the plan's required dropdown. Served by a sibling
  /// facade (`action=get`), not the pricing facade.
  Future<List<BusinessType>> listBusinessTypes() async {
    try {
      final res = await _api.getPath(_kBusinessTypePath, {'action': 'get'});
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => BusinessType.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Create a plan. [features] is a list of {category_id, name} maps, encoded
  /// as a JSON string the way the facade expects. [imagePath] is an optional
  /// local file path to upload.
  Future<PricingResult> add({
    required int businessTypeId,
    required String title,
    required String price,
    required List<Map<String, dynamic>> features,
    String? imagePath,
  }) async {
    return _mutateMultipart(
      action: 'add_pricing',
      fields: {
        'business_type_id': '$businessTypeId',
        'title': title.trim(),
        'price': price.trim(),
        'features': jsonEncode(features),
      },
      imagePath: imagePath,
    );
  }

  Future<PricingResult> update({
    required int id,
    required int businessTypeId,
    required String title,
    required String price,
    required List<Map<String, dynamic>> features,
    String? imagePath,
  }) async {
    return _mutateMultipart(
      action: 'update_pricing',
      fields: {
        'id': '$id',
        'business_type_id': '$businessTypeId',
        'title': title.trim(),
        'price': price.trim(),
        'features': jsonEncode(features),
      },
      imagePath: imagePath,
    );
  }

  Future<PricingResult> delete(int id) async {
    try {
      final res = await _api.postPath(_kPricingPath, body: {
        'action': 'delete_pricing',
        'id': '$id',
      });
      return _result(res);
    } catch (_) {
      return PricingResult(ok: false, message: 'Network error');
    }
  }

  Future<PricingResult> _mutateMultipart({
    required String action,
    required Map<String, String> fields,
    String? imagePath,
  }) async {
    try {
      final res = await _api.postPathMultipart(
        _kPricingPath,
        fields: {'action': action, ...fields},
        files: {
          if (imagePath != null && imagePath.isNotEmpty) 'image': imagePath,
        },
      );
      return _result(res);
    } catch (_) {
      return PricingResult(ok: false, message: 'Network error');
    }
  }

  PricingResult _result(Map<String, dynamic> res) {
    final ok = res['success'] == true || res['status'] == 'success';
    return PricingResult(ok: ok, message: res['message']?.toString());
  }
}
