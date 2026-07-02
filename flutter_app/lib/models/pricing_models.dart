// Domain models for the Pricing feature. These mirror the row shapes returned
// by the STANDALONE `utils/models/pricing-facade.php` dispatcher (which keys
// off an `action` param, NOT api.php). A pricing plan belongs to a business
// type and carries a list of features, each optionally tagged with a feature
// category.

class Pricing {
  Pricing({
    required this.id,
    required this.title,
    required this.price,
    required this.image,
    required this.businessTypeId,
    required this.businessTypeName,
    required this.features,
  });

  final int id;
  final String title;
  final String price;

  /// Relative upload filename (lives under `uploads/`). Empty when no image.
  final String image;
  final int businessTypeId;
  final String businessTypeName;
  final List<PricingFeature> features;

  bool get hasImage => image.isNotEmpty;

  factory Pricing.fromJson(Map<String, dynamic> json) => Pricing(
        id: _asInt(json['id']),
        title: (json['title'] ?? '').toString(),
        price: (json['price'] ?? '').toString(),
        image: (json['image'] ?? '').toString(),
        businessTypeId: _asInt(json['business_type_id']),
        businessTypeName: (json['business_type_name'] ?? '').toString(),
        features: _features(json['features']),
      );

  static List<PricingFeature> _features(Object? raw) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => PricingFeature.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return const [];
  }
}

class PricingFeature {
  PricingFeature({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.categoryName,
  });

  final int id;
  final String name;

  /// null when the feature isn't tied to a category.
  final int? categoryId;
  final String categoryName;

  factory PricingFeature.fromJson(Map<String, dynamic> json) => PricingFeature(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        categoryId: json['category_id'] == null
            ? null
            : _asInt(json['category_id']),
        categoryName: (json['category_name'] ?? '').toString(),
      );
}

class PricingCategory {
  PricingCategory({
    required this.id,
    required this.name,
    required this.subtitle,
  });

  final int id;
  final String name;
  final String subtitle;

  factory PricingCategory.fromJson(Map<String, dynamic> json) =>
      PricingCategory(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
        subtitle: (json['subtitle'] ?? '').toString(),
      );
}

class BusinessType {
  BusinessType({required this.id, required this.name});

  final int id;
  final String name;

  factory BusinessType.fromJson(Map<String, dynamic> json) => BusinessType(
        id: _asInt(json['id']),
        name: (json['name'] ?? '').toString(),
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
