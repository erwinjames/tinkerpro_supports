import 'dart:convert';

import '../api_client.dart';

const String _kPricingPath = 'utils/models/pricing-facade.php';
const String _kBusinessTypePath = 'utils/models/business-type-facade.php';

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

int? _asIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  return int.tryParse(s);
}

String _str(Object? v) => v == null ? '' : '$v';

class PricingResult {
  const PricingResult(this.ok, this.message);
  final bool ok;
  final String message;
}

class BusinessType {
  BusinessType({
    required this.id,
    required this.name,
    required this.icon,
    required this.sortOrder,
  });

  final int id;
  final String name;
  final String icon;
  final int sortOrder;

  factory BusinessType.fromJson(Map<String, dynamic> j) => BusinessType(
        id: _asInt(j['id']),
        name: _str(j['name']),
        icon: _str(j['icon']),
        sortOrder: _asInt(j['sort_order']),
      );
}

class FeatureCategory {
  FeatureCategory({
    required this.id,
    required this.name,
    required this.subtitle,
  });

  final int id;
  final String name;
  final String subtitle;

  factory FeatureCategory.fromJson(Map<String, dynamic> j) => FeatureCategory(
        id: _asInt(j['id']),
        name: _str(j['name']),
        subtitle: _str(j['subtitle']),
      );
}

class PlanFeature {
  PlanFeature({
    required this.categoryId,
    required this.categoryName,
    required this.name,
  });

  final int? categoryId;
  final String categoryName;
  final String name;

  factory PlanFeature.fromJson(Map<String, dynamic> j) => PlanFeature(
        categoryId: _asIntOrNull(j['category_id']),
        categoryName: _str(j['category_name']),
        name: _str(j['name']),
      );
}

class PricingPlan {
  PricingPlan({
    required this.id,
    required this.businessTypeId,
    required this.businessTypeName,
    required this.title,
    required this.price,
    required this.image,
    required this.features,
  });

  final int id;
  final int businessTypeId;
  final String businessTypeName;
  final String title;
  final String price;
  final String image;
  final List<PlanFeature> features;

  factory PricingPlan.fromJson(Map<String, dynamic> j) {
    final raw = j['features'];
    return PricingPlan(
      id: _asInt(j['id']),
      businessTypeId: _asInt(j['business_type_id']),
      businessTypeName: _str(j['business_type_name']),
      title: _str(j['title']),
      price: _str(j['price']),
      image: _str(j['image']),
      features: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => PlanFeature.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class PricingService {
  PricingService(this.api);
  final ApiClient api;

  String uploadUrl(String image) {
    if (image.isEmpty) return '';
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return image;
    }
    return '${api.baseUrl}/uploads/$image';
  }

  String assetUrl(String path) =>
      '${api.baseUrl}/${path.replaceAll(RegExp(r'^/+'), '')}';

  Future<List<BusinessType>> businessTypes() async {
    final res = await api.getPath(_kBusinessTypePath, {'action': 'get'});
    final raw = res['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => BusinessType.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PricingResult> saveBusinessType({
    int? id,
    required String name,
    required String icon,
  }) =>
      _post(_kBusinessTypePath, id == null ? 'add' : 'update', {
        'id': id == null ? '' : '$id',
        'name': name,
        'icon': icon,
      });

  Future<PricingResult> deleteBusinessType(int id) =>
      _post(_kBusinessTypePath, 'delete', {'id': '$id'});

  Future<PricingResult> reorderBusinessTypes(List<int> orderedIds) =>
      _post(_kBusinessTypePath, 'update_order', {
        for (var i = 0; i < orderedIds.length; i++)
          'order[$i]': '${orderedIds[i]}',
      });

  Future<List<FeatureCategory>> categories() async {
    final res =
        await api.getPath(_kPricingPath, {'action': 'get_categories'});
    final raw = res['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => FeatureCategory.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PricingResult> saveCategory({
    int? id,
    required String name,
    required String subtitle,
  }) =>
      _post(_kPricingPath, id == null ? 'add_category' : 'update_category', {
        'id': id == null ? '' : '$id',
        'name': name,
        'subtitle': subtitle,
      });

  Future<PricingResult> deleteCategory(int id) =>
      _post(_kPricingPath, 'delete_category', {'id': '$id'});

  Future<List<PricingPlan>> pricings({int? businessTypeId}) async {
    final res = await api.getPath(_kPricingPath, {
      'action': 'get_pricings',
      if (businessTypeId != null) 'business_type_id': '$businessTypeId',
    });
    final raw = res['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => PricingPlan.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<PricingResult> savePricing({
    int? id,
    required int businessTypeId,
    required String title,
    required String price,
    required List<({int? categoryId, String name})> features,
    String? imagePath,
  }) async {
    final action = id == null ? 'add_pricing' : 'update_pricing';
    try {
      final res = await api.postPathMultipart(
        _kPricingPath,
        query: {'action': action},
        fields: {
          if (id != null) 'id': '$id',
          'business_type_id': '$businessTypeId',
          'title': title,
          'price': price,
          'features': jsonEncode([
            for (final f in features)
              {'category_id': f.categoryId, 'name': f.name},
          ]),
        },
        files: {
          if (imagePath != null && imagePath.isNotEmpty) 'image': imagePath,
        },
      );
      return _result(res);
    } catch (e) {
      return PricingResult(false, e.toString());
    }
  }

  Future<PricingResult> deletePricing(int id) =>
      _post(_kPricingPath, 'delete_pricing', {'id': '$id'});

  Future<PricingResult> _post(
      String path, String action, Map<String, String> body) async {
    try {
      final res = await api.postPath('$path?action=$action', body: body);
      return _result(res);
    } catch (e) {
      return PricingResult(false, e.toString());
    }
  }

  PricingResult _result(Map<String, dynamic> res) {
    final ok = res['success'] == true || res['status'] == 'success';
    final msg = _str(res['message']);
    return PricingResult(
        ok, msg.isNotEmpty ? msg : (ok ? 'Saved' : 'Request failed'));
  }
}
