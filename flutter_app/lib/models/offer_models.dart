// Domain models for the Offers feature. Mirrors the `getOffers` /
// `getOfferById` row shapes returned by `api.php` (offer-facade.php):
//   getOffers     → {data:[{id,title,slug,description,category_id,category_name,image}], totalRecords, limit, page}
//   getOfferById  → {..., sections:[{id, offer_id, content, image, sort_order}]}
//   getCategories → {success:true, data:[{id, name, ...}]}

class Offer {
  Offer({
    required this.id,
    required this.title,
    required this.slug,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    required this.image,
    this.sections = const [],
  });

  final int id;
  final String title;
  final String slug;
  final String description;
  final int? categoryId;
  final String categoryName;

  /// Relative path (e.g. `assets/uploads/offers/x.jpg`) or empty.
  final String image;

  /// Content blocks, only populated by `getOfferById`.
  final List<OfferSection> sections;

  bool get hasImage => image.isNotEmpty;

  factory Offer.fromJson(Map<String, dynamic> json) {
    final rawSections = json['sections'];
    return Offer(
      id: _asInt(json['id']),
      title: (json['title'] ?? '').toString(),
      slug: (json['slug'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      categoryId: _asIntOrNull(json['category_id']),
      categoryName: (json['category_name'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
      sections: rawSections is List
          ? rawSections
              .whereType<Map>()
              .map((e) => OfferSection.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class OfferSection {
  OfferSection({
    this.id,
    required this.content,
    required this.image,
    required this.sortOrder,
  });

  /// Existing row id (null for new sections added in the form).
  final int? id;
  final String content;

  /// Relative path of an already-uploaded section image, or empty.
  final String image;
  final int sortOrder;

  factory OfferSection.fromJson(Map<String, dynamic> json) => OfferSection(
        id: _asIntOrNull(json['id']),
        content: (json['content'] ?? '').toString(),
        image: (json['image'] ?? '').toString(),
        sortOrder: _asInt(json['sort_order']),
      );
}

class OfferCategory {
  OfferCategory({required this.id, required this.name});

  final int id;
  final String name;

  factory OfferCategory.fromJson(Map<String, dynamic> json) => OfferCategory(
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

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    if (value.isEmpty) return null;
    return int.tryParse(value);
  }
  return null;
}
