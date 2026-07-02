// API layer for the Offers feature. All endpoints live on `api.php`:
//   * getOffers     GET   page,limit,search,category_id?  → {data:[...], totalRecords, limit, page}
//   * getOfferById  GET   id                              → {..., sections:[...]}
//   * getCategories GET                                   → {success, data:[...]}
//   * addOffer      POST(multipart)  title, slug, description, category_id,
//                   sections[i][content], image(file)     → {success, message}
//   * updateOffer   POST(multipart)  id, ..., sections[i][id|content|existing_image]
//   * deleteOffer   POST  id, title?                       → {success, message}
//
// NOTE ON SECTIONS: api.php reads `$_POST['sections']` as a nested array and
// section images from `$_FILES['sections']['name'][$i]['image']`. PHP only
// builds those nested arrays from bracket-notation multipart field/file names
// (`sections[0][content]`, `sections[0][image]`), NOT from a JSON string — so
// we encode each section as discrete bracket-notation fields/files here.

import '../api_client.dart';
import '../models/offer_models.dart';

class OfferResult {
  OfferResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

/// A section as the form holds it before submit: text content, an optional
/// freshly-picked local image file, and (on edit) the existing row id + path.
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

class OfferService {
  OfferService(this._api);
  final ApiClient _api;

  ApiClient get api => _api;

  /// Build a full image URL from a backend path (relative or absolute).
  String imageUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    return '${_api.baseUrl}/$clean';
  }

  /// Fetch a page of offers. Returns an empty list on any failure so the UI
  /// still renders.
  Future<List<Offer>> list({
    int page = 1,
    int limit = 100,
    String search = '',
    int? categoryId,
  }) async {
    try {
      final res = await _api.get('getOffers', {
        'page': '$page',
        'limit': '$limit',
        if (search.isNotEmpty) 'search': search,
        if (categoryId != null) 'category_id': '$categoryId',
      });
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => Offer.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Fetch a single offer with its content sections.
  Future<Offer?> detail(int id) async {
    try {
      final res = await _api.get('getOfferById', {'id': '$id'});
      if (res['id'] != null) return Offer.fromJson(res);
    } catch (_) {}
    return null;
  }

  /// Category dropdown source. Empty list on failure.
  Future<List<OfferCategory>> listCategories() async {
    try {
      final res = await _api.get('getCategories');
      final raw = res['data'];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((e) => OfferCategory.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<OfferResult> add({
    required String title,
    required String slug,
    required String description,
    int? categoryId,
    required List<OfferSectionInput> sections,
    String? imagePath,
  }) async {
    final fields = <String, String>{
      'title': title.trim(),
      'slug': slug.trim(),
      'description': description.trim(),
      if (categoryId != null) 'category_id': '$categoryId',
    };
    final files = <String, String>{};
    _encodeSections(sections, fields, files, isEdit: false);
    if (imagePath != null && imagePath.isNotEmpty) files['image'] = imagePath;
    return _mutate('addOffer', fields, files);
  }

  Future<OfferResult> update({
    required int id,
    required String title,
    required String slug,
    required String description,
    int? categoryId,
    required List<OfferSectionInput> sections,
    String? imagePath,
  }) async {
    final fields = <String, String>{
      'id': '$id',
      'title': title.trim(),
      'slug': slug.trim(),
      'description': description.trim(),
      if (categoryId != null) 'category_id': '$categoryId',
    };
    final files = <String, String>{};
    _encodeSections(sections, fields, files, isEdit: true);
    if (imagePath != null && imagePath.isNotEmpty) files['image'] = imagePath;
    return _mutate('updateOffer', fields, files);
  }

  Future<OfferResult> delete(int id, {String? title}) =>
      _mutate('deleteOffer', {
        'id': '$id',
        'title': ?title,
      }, const {});

  /// Encode each section as bracket-notation multipart fields/files so PHP
  /// rebuilds `$_POST['sections']` / `$_FILES['sections']` as nested arrays.
  void _encodeSections(
    List<OfferSectionInput> sections,
    Map<String, String> fields,
    Map<String, String> files, {
    required bool isEdit,
  }) {
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      fields['sections[$i][content]'] = s.content;
      if (isEdit) {
        if (s.id != null) fields['sections[$i][id]'] = '${s.id}';
        if (s.existingImage.isNotEmpty) {
          fields['sections[$i][existing_image]'] = s.existingImage;
        }
      }
      if (s.localImagePath != null && s.localImagePath!.isNotEmpty) {
        files['sections[$i][image]'] = s.localImagePath!;
      }
    }
  }

  Future<OfferResult> _mutate(
    String action,
    Map<String, String> fields,
    Map<String, String> files,
  ) async {
    try {
      final res = await _api.postMultipart(action, fields: fields, files: files);
      final ok = res['success'] == true || res['status'] == 'success';
      return OfferResult(ok: ok, message: res['message']?.toString());
    } catch (e) {
      return OfferResult(ok: false, message: 'Network error');
    }
  }
}
