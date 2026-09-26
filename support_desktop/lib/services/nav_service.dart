import '../api_client.dart';

class NavItem {
  const NavItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.page,
    this.tag,
    this.mode,
    this.action,
    this.counter,
    this.badge,
    this.children = const [],
    this.isChild = false,
  });

  final String key;
  final String label;
  final String icon;
  final String page;
  final String? tag;
  final String? mode;
  final String? action;
  final String? counter;
  final String? badge;
  final List<NavItem> children;
  final bool isChild;

  bool get isModal => action == 'modal';

  factory NavItem.fromJson(Map<String, dynamic> j, {bool isChild = false}) {
    String? opt(String k) {
      final v = j[k];
      if (v == null) return null;
      final s = v.toString();
      return s.isEmpty ? null : s;
    }

    final kids = j['children'];
    return NavItem(
      key: j['key']?.toString() ?? '',
      label: j['label']?.toString() ?? '',
      icon: j['icon']?.toString() ?? '',
      page: j['page']?.toString() ?? '',
      tag: opt('tag'),
      mode: opt('mode'),
      action: opt('action'),
      counter: opt('counter'),
      badge: opt('badge'),
      isChild: isChild,
      children: kids is List
          ? [
              for (final k in kids)
                if (k is Map)
                  NavItem.fromJson(Map<String, dynamic>.from(k), isChild: true)
            ]
          : const [],
    );
  }
}

class NavGroup {
  const NavGroup(this.label, this.items);
  final String label;
  final List<NavItem> items;
}

class NavService {
  NavService(this.api);
  final ApiClient api;
  String? role;

  Future<List<NavGroup>?> fetch() async {
    try {
      final res =
          await api.get('getDesktopNav').timeout(const Duration(seconds: 10));
      if (res['success'] != true || res['groups'] is! List) return null;
      role = res['role']?.toString();
      return [
        for (final g in res['groups'] as List)
          if (g is Map)
            NavGroup(
              g['label']?.toString() ?? '',
              [
                for (final i in (g['items'] as List? ?? const []))
                  if (i is Map) NavItem.fromJson(Map<String, dynamic>.from(i))
              ],
            )
      ];
    } catch (_) {
      return null;
    }
  }
}
