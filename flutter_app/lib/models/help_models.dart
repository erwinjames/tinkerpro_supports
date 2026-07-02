// Domain model for the Help Center feature. Mirrors a row of the `help`
// table as returned by `getHelpTopics` on api.php:
//   { id, title, description, icon, icon_color }
// `icon` is a FontAwesome class string (e.g. "fa-book") and `icon_color`
// a hex string (e.g. "#FF7D00"); both are kept verbatim so topics created
// on mobile render identically in the web admin.

class HelpTopic {
  HelpTopic({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
  });

  final int id;
  final String title;

  /// Topic body. The web editor stores rich HTML here; on mobile we show it
  /// as stripped plain text and edit it as plain text.
  final String description;

  /// FontAwesome icon class, e.g. "fa-book". Defaults handled by the form.
  final String icon;

  /// Hex colour string for the icon, e.g. "#FF7D00".
  final String iconColor;

  factory HelpTopic.fromJson(Map<String, dynamic> json) => HelpTopic(
        id: _asInt(json['id']),
        title: (json['title'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        icon: (json['icon'] ?? '').toString(),
        iconColor:
            (json['icon_color'] ?? json['iconColor'] ?? '').toString(),
      );
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
