import '../api_client.dart';

String _str(dynamic v) => v == null ? '' : v.toString();

class WhatsNewGuide {
  const WhatsNewGuide(
      {required this.intro, required this.steps, required this.tip});
  final String intro;
  final List<String> steps;
  final String tip;
}

class WhatsNewFeature {
  const WhatsNewFeature({
    required this.title,
    required this.icon,
    required this.pill,
    required this.pillBeta,
    required this.description,
    required this.guide,
  });
  final String title;
  final String icon;
  final String pill;
  final bool pillBeta;
  final String description;
  final WhatsNewGuide? guide;

  factory WhatsNewFeature.fromJson(Map<String, dynamic> j) {
    final g = j['guide'];
    return WhatsNewFeature(
      title: _str(j['title']),
      icon: _str(j['icon']),
      pill: _str(j['pill']),
      pillBeta: j['pill_beta'] == true,
      description: _str(j['description']),
      guide: g is Map
          ? WhatsNewGuide(
              intro: _str(g['intro']),
              steps: (g['steps'] is List ? g['steps'] as List : const [])
                  .map((e) => e.toString())
                  .toList(),
              tip: _str(g['tip']),
            )
          : null,
    );
  }
}

class WhatsNew {
  const WhatsNew({
    required this.version,
    required this.expires,
    required this.expired,
    required this.title,
    required this.subtitle,
    required this.sectionLabel,
    required this.features,
  });
  final String version;
  final String expires;
  final bool expired;
  final String title;
  final String subtitle;
  final String sectionLabel;
  final List<WhatsNewFeature> features;
}

class WhatsNewService {
  WhatsNewService(this.api);
  final ApiClient api;

  Future<WhatsNew> load() async {
    final res = await api.get('getWhatsNew');
    if (res['success'] != true) {
      throw Exception(_str(res['message']).isEmpty
          ? 'Could not load the changelog.'
          : _str(res['message']));
    }
    return WhatsNew(
      version: _str(res['version']),
      expires: _str(res['expires']),
      expired: res['expired'] == true,
      title: _str(res['title']),
      subtitle: _str(res['subtitle']),
      sectionLabel: _str(res['section_label']),
      features: (res['features'] is List ? res['features'] as List : const [])
          .whereType<Map>()
          .map((m) => WhatsNewFeature.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }
}
