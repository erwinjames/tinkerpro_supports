class HelpTopic {
  HelpTopic({
    required this.id,
    required this.title,
    required this.description,
    this.subtitle = '',
    required this.icon,
    required this.iconColor,
    this.category = '',
    this.subcategory = '',
    this.subsubcategory = '',
  });

  final int id;
  final String title;
  final String description;
  final String subtitle;
  final String icon;
  final String iconColor;
  final String category;
  final String subcategory;
  final String subsubcategory;

  factory HelpTopic.fromJson(Map<String, dynamic> json) => HelpTopic(
    id: _asInt(json['id']),
    title: (json['title'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
    subtitle: (json['subtitle'] ?? '').toString(),
    icon: (json['icon'] ?? '').toString(),
    iconColor: (json['icon_color'] ?? json['iconColor'] ?? '').toString(),
    category: (json['category'] ?? '').toString(),
    subcategory: (json['subcategory'] ?? '').toString(),
    subsubcategory: (json['subsubcategory'] ?? '').toString(),
  );
}

class HelpCategoryNode {
  const HelpCategoryNode({
    required this.slug,
    required this.name,
    this.path = '',
    this.children = const [],
  });

  final String slug;
  final String name;
  final String path;
  final List<HelpCategoryNode> children;

  String get fullPath => path.isEmpty ? slug : '$path/$slug';

  HelpCategoryNode? child(String slug) {
    if (slug.isEmpty) return null;
    for (final c in children) {
      if (c.slug == slug) return c;
    }
    return null;
  }

  factory HelpCategoryNode.fromJson(
    Map<String, dynamic> json, {
    String path = '',
  }) {
    final slug = (json['slug'] ?? '').toString();
    final name = (json['name'] ?? '').toString();
    final own = path.isEmpty ? slug : '$path/$slug';
    final raw = json['subcategories'];
    return HelpCategoryNode(
      slug: slug,
      name: name.isEmpty ? slug : name,
      path: path,
      children: raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (e) => HelpCategoryNode.fromJson(
                    Map<String, dynamic>.from(e),
                    path: own,
                  ),
                )
                .where((n) => n.slug.isNotEmpty)
                .toList()
          : const [],
    );
  }
}

const String kDefaultHelpSystem = 'v1';

const List<HelpCategoryNode> kDefaultHelpSystems = [
  HelpCategoryNode(slug: 'v1', name: 'V1'),
  HelpCategoryNode(slug: 'v2', name: 'V2'),
  HelpCategoryNode(slug: 'invoice', name: 'Invoice'),
  HelpCategoryNode(slug: 'crm', name: 'CRM'),
];

class HelpCategoryTree {
  const HelpCategoryTree(this.systems, {this.loaded = true});

  const HelpCategoryTree.fallback()
    : systems = kDefaultHelpSystems,
      loaded = false;

  final List<HelpCategoryNode> systems;
  final bool loaded;

  HelpCategoryNode? system(String slug) {
    for (final s in systems) {
      if (s.slug == slug) return s;
    }
    return null;
  }

  String normalizeSystem(String value) {
    final key = value.trim().toLowerCase();
    return system(key) != null ? key : kDefaultHelpSystem;
  }

  String normalizeCategory(String system, String value) {
    final key = value.trim().toLowerCase();
    if (key.isEmpty) return '';
    return this.system(normalizeSystem(system))?.child(key) != null ? key : '';
  }

  String normalizeSubcategory(String system, String category, String value) {
    final key = value.trim().toLowerCase();
    if (key.isEmpty) return '';
    final sys = normalizeSystem(system);
    final cat = this.system(sys)?.child(normalizeCategory(sys, category));
    return cat?.child(key) != null ? key : '';
  }

  List<String> labels(String system, String category, String subcategory) {
    final sys = normalizeSystem(system);
    final sysNode = this.system(sys);
    final out = <String>[sysNode?.name ?? sys.toUpperCase()];
    if (!loaded) {
      for (final raw in [category, subcategory]) {
        final v = raw.trim();
        if (v.isEmpty) break;
        out.add(_humanize(v));
      }
      return out;
    }
    final cat = normalizeCategory(sys, category);
    if (cat.isEmpty) return out;
    final catNode = sysNode!.child(cat)!;
    out.add(catNode.name);
    final sub = normalizeSubcategory(sys, cat, subcategory);
    if (sub.isNotEmpty) out.add(catNode.child(sub)!.name);
    return out;
  }
}

String _humanize(String slug) => slug
    .split(RegExp(r'[-_\s]+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
