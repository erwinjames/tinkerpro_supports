import 'package:flutter/material.dart';

const Map<String, IconData> _kAnnouncementIcons = {
  'fa-bullhorn': Icons.campaign_rounded,
  'fa-gift': Icons.card_giftcard_rounded,
  'fa-info-circle': Icons.info_rounded,
  'fa-exclamation-triangle': Icons.warning_amber_rounded,
  'fa-tools': Icons.build_rounded,
  'fa-calendar-alt': Icons.event_rounded,
  'fa-shield-alt': Icons.shield_rounded,
  'fa-rocket': Icons.rocket_launch_rounded,
  'fa-graduation-cap': Icons.school_rounded,
  'fa-clock': Icons.schedule_rounded,
  'fa-file-alt': Icons.description_rounded,
  'fa-users': Icons.groups_rounded,
  'fa-star': Icons.star_rounded,
  'fa-lightbulb': Icons.lightbulb_rounded,
  'fa-bug': Icons.bug_report_rounded,
  'fa-server': Icons.dns_rounded,
};

class AnnouncementTone {
  const AnnouncementTone(this.accent, this.glow, this.iconTint);

  final Color accent;
  final Color glow;
  final Color iconTint;

  static const AnnouncementTone info = AnnouncementTone(
    Color(0xFF2563EB),
    Color(0x572563EB),
    Color(0xFFBFDBFE),
  );
  static const AnnouncementTone success = AnnouncementTone(
    Color(0xFF16A34A),
    Color(0x5216A34A),
    Color(0xFFBBF7D0),
  );
  static const AnnouncementTone warning = AnnouncementTone(
    Color(0xFFFF7D00),
    Color(0x52FF7D00),
    Color(0xFFFFCB99),
  );
  static const AnnouncementTone critical = AnnouncementTone(
    Color(0xFFDC2626),
    Color(0x57DC2626),
    Color(0xFFFECACA),
  );

  static AnnouncementTone of(String tone) {
    switch (tone) {
      case 'success':
        return success;
      case 'warning':
        return warning;
      case 'critical':
        return critical;
      default:
        return info;
    }
  }
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    required this.toneLabel,
    required this.linkUrl,
    required this.linkLabel,
    required this.requireAck,
    required this.isRead,
    required this.isAcknowledged,
    required this.author,
    required this.createdAtRaw,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}') ?? 0;
    }

    return Announcement(
      id: asInt(json['id']),
      title: (json['title'] ?? '').toString(),
      body: (json['body'] ?? '').toString(),
      icon: (json['icon'] ?? 'fa-bullhorn').toString(),
      tone: (json['tone'] ?? 'info').toString(),
      toneLabel: (json['tone_label'] ?? 'Information').toString(),
      linkUrl: (json['link_url'] ?? '').toString(),
      linkLabel: (json['link_label'] ?? '').toString(),
      requireAck: asInt(json['require_ack']) == 1,
      isRead: asInt(json['is_read']) == 1,
      isAcknowledged: asInt(json['is_acknowledged']) == 1,
      author: (json['author'] ?? '').toString(),
      createdAtRaw: (json['created_at'] ?? '').toString(),
    );
  }

  final int id;
  final String title;
  final String body;
  final String icon;
  final String tone;
  final String toneLabel;
  final String linkUrl;
  final String linkLabel;
  final bool requireAck;
  final bool isRead;
  final bool isAcknowledged;
  final String author;
  final String createdAtRaw;

  bool get isPending => !isRead || (requireAck && !isAcknowledged);

  IconData get iconData =>
      _kAnnouncementIcons[icon] ?? Icons.campaign_rounded;

  AnnouncementTone get toneColors => AnnouncementTone.of(tone);

  Announcement markedRead({required bool acknowledged}) => Announcement(
        id: id,
        title: title,
        body: body,
        icon: icon,
        tone: tone,
        toneLabel: toneLabel,
        linkUrl: linkUrl,
        linkLabel: linkLabel,
        requireAck: requireAck,
        isRead: true,
        isAcknowledged: isAcknowledged || acknowledged,
        author: author,
        createdAtRaw: createdAtRaw,
      );

  DateTime? postedAt(int dbOffsetSeconds) {
    final raw = createdAtRaw.trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse('${raw.replaceFirst(' ', 'T')}Z');
    if (parsed == null) return null;
    return parsed.subtract(Duration(seconds: dbOffsetSeconds)).toLocal();
  }
}
