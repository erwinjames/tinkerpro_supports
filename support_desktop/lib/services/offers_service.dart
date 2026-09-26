import 'dart:convert';

import '../api_client.dart';

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

List<String> _jsonStringList(Object? raw) {
  if (raw is List) return raw.map((e) => '$e').toList();
  final s = _str(raw).trim();
  if (s.isEmpty) return const [];
  try {
    final decoded = jsonDecode(s);
    if (decoded is List) return decoded.map((e) => '$e').toList();
  } catch (_) {}
  return const [];
}

class OfferResult {
  const OfferResult(this.ok, this.message);
  final bool ok;
  final String message;
}

class OfferCategory {
  OfferCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.sortOrder,
  });

  final int id;
  final String name;
  final String slug;
  final int sortOrder;

  factory OfferCategory.fromJson(Map<String, dynamic> j) => OfferCategory(
        id: _asInt(j['id']),
        name: _str(j['name']),
        slug: _str(j['slug']),
        sortOrder: _asInt(j['sort_order']),
      );
}

class OfferSection {
  OfferSection({this.id, required this.content, required this.image});

  final int? id;
  final String content;
  final String image;

  factory OfferSection.fromJson(Map<String, dynamic> j) => OfferSection(
        id: _asIntOrNull(j['id']),
        content: _str(j['content']),
        image: _str(j['image']),
      );
}

class Offer {
  Offer({
    required this.id,
    required this.title,
    required this.slug,
    required this.description,
    required this.image,
    required this.categoryId,
    required this.categoryName,
    required this.forYou,
    required this.notForYou,
    required this.sections,
  });

  final int id;
  final String title;
  final String slug;
  final String description;
  final String image;
  final int? categoryId;
  final String categoryName;
  final List<String> forYou;
  final List<String> notForYou;
  final List<OfferSection> sections;

  factory Offer.fromJson(Map<String, dynamic> j) {
    final rawSections = j['sections'];
    return Offer(
      id: _asInt(j['id']),
      title: _str(j['title']),
      slug: _str(j['slug']),
      description: _str(j['description']),
      image: _str(j['image']),
      categoryId: _asIntOrNull(j['category_id']),
      categoryName: _str(j['category_name']),
      forYou: _jsonStringList(j['for_you']),
      notForYou: _jsonStringList(j['not_for_you']),
      sections: rawSections is List
          ? rawSections
              .whereType<Map>()
              .map((e) => OfferSection.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}

class OfferPage {
  const OfferPage(this.items, this.total);
  final List<Offer> items;
  final int total;
}

class OfferPackage {
  OfferPackage({
    required this.id,
    required this.offerId,
    required this.title,
    required this.price,
    required this.originalPrice,
    required this.savingsLabel,
    required this.description,
    required this.inclusions,
    required this.paymentOptions,
    required this.footerText,
    required this.isPopular,
    required this.image,
  });

  final int id;
  final int offerId;
  final String title;
  final String price;
  final String originalPrice;
  final String savingsLabel;
  final String description;
  final List<String> inclusions;
  final List<String> paymentOptions;
  final String footerText;
  final bool isPopular;
  final String image;

  factory OfferPackage.fromJson(Map<String, dynamic> j) => OfferPackage(
        id: _asInt(j['id']),
        offerId: _asInt(j['offer_id']),
        title: _str(j['title']),
        price: _str(j['price']),
        originalPrice: _str(j['original_price']),
        savingsLabel: _str(j['savings_label']),
        description: _str(j['description']),
        inclusions: _str(j['inclusions'])
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        paymentOptions: _jsonStringList(j['payment_options'])
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        footerText: _str(j['footer_text']),
        isPopular: _asInt(j['is_popular']) == 1,
        image: _str(j['image']),
      );
}

class OfferSectionInput {
  OfferSectionInput({
    this.id,
    required this.content,
    this.existingImage = '',
    this.localImagePath,
  });

  final int? id;
  final String content;
  final String existingImage;
  final String? localImagePath;
}

class OffersService {
  OffersService(this.api);
  final ApiClient api;

  String mediaUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${api.baseUrl}/${path.replaceAll(RegExp(r'^/+'), '')}';
  }

  Future<OfferPage> list({
    int page = 1,
    int limit = 15,
    String search = '',
    int? categoryId,
    bool withPackagesOnly = false,
  }) async {
    final res = await api.get('getOffers', {
      'page': '$page',
      'limit': '$limit',
      'search': search,
      'category_id': categoryId == null ? '' : '$categoryId',
      'has_packages': withPackagesOnly ? '1' : '',
    });
    final raw = res['data'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => Offer.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Offer>[];
    return OfferPage(items, _asInt(res['totalRecords']));
  }

  Future<Offer?> getById(int id) async {
    final res = await api.get('getOfferById', {'id': '$id'});
    if (res['id'] == null) return null;
    return Offer.fromJson(res);
  }

  Future<List<OfferCategory>> categories() async {
    final res = await api.get('getCategories');
    final raw = res['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => OfferCategory.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<OfferResult> saveOffer({
    int? id,
    required String title,
    required String slug,
    int? categoryId,
    required List<String> forYou,
    required List<String> notForYou,
    required List<OfferSectionInput> sections,
    String? imagePath,
  }) async {
    final fields = <String, String>{
      if (id != null) 'id': '$id',
      'title': title,
      'slug': slug,
      'category_id': categoryId == null ? '' : '$categoryId',
      'for_you': jsonEncode(forYou),
      'not_for_you': jsonEncode(notForYou),
    };
    final files = <String, String>{};
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      fields['sections[$i][content]'] = s.content;
      if (s.id != null) fields['sections[$i][id]'] = '${s.id}';
      if (s.existingImage.isNotEmpty) {
        fields['sections[$i][existing_image]'] = s.existingImage;
      }
      final local = s.localImagePath;
      if (local != null && local.isNotEmpty) {
        files['sections[$i][image]'] = local;
      }
    }
    if (imagePath != null && imagePath.isNotEmpty) files['image'] = imagePath;
    return _multipart(id == null ? 'addOffer' : 'updateOffer', fields, files);
  }

  Future<String?> slugify(String text) async {
    try {
      final res = await api.get('desktopSlugify', {'text': text});
      if (res['success'] != true) return null;
      return _str(res['slug']);
    } catch (_) {
      return null;
    }
  }

  Future<OfferResult> deleteOffer(int id) =>
      _post('deleteOffer', {'id': '$id'});

  Future<List<OfferPackage>> packages(int offerId) async {
    final res = await api.get('getPackages', {'offer_id': '$offerId'});
    final raw = res['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => OfferPackage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<OfferPackage?> packageById(int id) async {
    final res = await api.get('getPackageById', {'id': '$id'});
    if (res['id'] == null) return null;
    return OfferPackage.fromJson(res);
  }

  Future<OfferResult> savePackage({
    int? id,
    required int offerId,
    required String title,
    required String price,
    required String originalPrice,
    required String savingsLabel,
    required String description,
    required List<String> inclusions,
    required List<String> paymentOptions,
    required String footerText,
    required bool isPopular,
    String? imagePath,
  }) {
    final fields = <String, String>{
      if (id != null) 'id': '$id',
      'offer_id': '$offerId',
      'title': title,
      'price': price,
      'original_price': originalPrice,
      'savings_label': savingsLabel,
      'description': description,
      'inclusions': inclusions.join(', '),
      'payment_options': jsonEncode(paymentOptions),
      'footer_text': footerText,
      if (isPopular) 'is_popular': '1',
    };
    return _multipart(
      id == null ? 'addPackage' : 'updatePackage',
      fields,
      {if (imagePath != null && imagePath.isNotEmpty) 'image': imagePath},
    );
  }

  Future<OfferResult> deletePackage(int id) =>
      _post('deletePackage', {'id': '$id'});

  Future<OfferCategory?> categoryById(int id) async {
    final res = await api.get('getCategoryById', {'id': '$id'});
    if (res['id'] == null) return null;
    return OfferCategory.fromJson(res);
  }

  Future<OfferResult> saveCategory({
    int? id,
    required String name,
    required String slug,
  }) =>
      _post(id == null ? 'addCategory' : 'updateCategory', {
        'id': id == null ? '' : '$id',
        'name': name,
        'slug': slug,
      });

  Future<OfferResult> deleteCategory(int id) =>
      _post('deleteCategory', {'id': '$id'});

  Future<OfferResult> updateCategoryOrder(List<int> orderedIds) {
    final orders = [
      for (var i = 0; i < orderedIds.length; i++)
        {'id': orderedIds[i], 'sort_order': i},
    ];
    return _post('updateCategoryOrder', {'orders': jsonEncode(orders)});
  }

  Future<OfferResult> _post(String action, Map<String, String> body) async {
    try {
      return _result(await api.post(action, body: body));
    } catch (e) {
      return OfferResult(false, e.toString());
    }
  }

  Future<OfferResult> _multipart(
    String action,
    Map<String, String> fields,
    Map<String, String> files,
  ) async {
    try {
      final res = await api.postPathMultipart(
        'api.php',
        query: {'action': action},
        fields: fields,
        files: files,
      );
      return _result(res);
    } catch (e) {
      return OfferResult(false, e.toString());
    }
  }

  OfferResult _result(Map<String, dynamic> res) {
    final ok = res['success'] == true || res['status'] == 'success';
    final msg = _str(res['message']);
    return OfferResult(ok, msg.isNotEmpty ? msg : (ok ? 'Saved' : 'Request failed'));
  }
}
