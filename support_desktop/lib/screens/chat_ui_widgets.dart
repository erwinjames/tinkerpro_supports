import 'package:flutter/material.dart';

import '../theme.dart';

class ChatTokens {
  const ChatTokens({
    required this.bg,
    required this.surface,
    required this.surfaceSoft,
    required this.text,
    required this.muted,
    required this.subtle,
    required this.border,
    required this.borderSoft,
    required this.mine,
    required this.dark,
  });

  final Color bg;
  final Color surface;
  final Color surfaceSoft;
  final Color text;
  final Color muted;
  final Color subtle;
  final Color border;
  final Color borderSoft;
  final Color mine;
  final bool dark;

  static const primary = Color(0xFFFF7D00);
  static const primaryLight = Color(0xFFFF9433);
  static const online = Color(0xFF10B981);
  static const danger = Color(0xFFDC2626);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primary],
  );
  static const fbGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00B2FF), Color(0xFF006AFF)],
  );
  static const navyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C233E), Color(0xFF163A64)],
  );
  static Color primarySoft([double a = 0.10]) =>
      primary.withValues(alpha: a);

  static ChatTokens of(BuildContext context) {
    final b = context.brand;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return ChatTokens(
        bg: b.canvas,
        surface: b.surface,
        surfaceSoft: b.surfaceHi,
        text: b.paper,
        muted: b.paperDim,
        subtle: b.paperDim,
        border: b.rule,
        borderSoft: b.rule,
        mine: const Color(0xFF1C1917),
        dark: true,
      );
    }
    return const ChatTokens(
      bg: Color(0xFFFAFAF9),
      surface: Color(0xFFFFFFFF),
      surfaceSoft: Color(0xFFF7F7F5),
      text: Color(0xFF0C0A09),
      muted: Color(0xFF57534E),
      subtle: Color(0xFFA8A29E),
      border: Color(0xFFE7E5E4),
      borderSoft: Color(0xFFF1EFED),
      mine: Color(0xFF0C0A09),
      dark: false,
    );
  }
}

class ChatIconBtn extends StatefulWidget {
  const ChatIconBtn({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.primary = false,
    this.size = 38,
    this.iconSize = 15,
    this.badge = 0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool primary;
  final double size;
  final double iconSize;
  final int badge;

  @override
  State<ChatIconBtn> createState() => _ChatIconBtnState();
}

class _ChatIconBtnState extends State<ChatIconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    final enabled = widget.onPressed != null;
    final Color fg;
    final BoxDecoration deco;
    if (widget.primary) {
      fg = Colors.white;
      deco = BoxDecoration(
        shape: BoxShape.circle,
        gradient: ChatTokens.gradient,
        boxShadow: [
          BoxShadow(
            color: ChatTokens.primary.withValues(alpha: _hover ? 0.36 : 0.28),
            blurRadius: _hover ? 16 : 12,
            offset: Offset(0, _hover ? 6 : 4),
          ),
        ],
      );
    } else {
      fg = _hover && enabled ? ChatTokens.primary : t.muted;
      deco = BoxDecoration(
        shape: BoxShape.circle,
        color: _hover && enabled ? ChatTokens.primarySoft() : t.surface,
        border: Border.all(
          color: _hover && enabled
              ? ChatTokens.primary.withValues(alpha: 0.22)
              : t.border,
        ),
      );
    }
    Widget btn = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: widget.size,
            height: widget.size,
            decoration: deco,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
    if (widget.badge > 0) {
      btn = Stack(
        clipBehavior: Clip.none,
        children: [
          btn,
          Positioned(
            top: -5,
            right: -5,
            child: ChatCountBadge(count: widget.badge, red: true),
          ),
        ],
      );
    }
    if (widget.tooltip != null) {
      btn = Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

class ChatCountBadge extends StatelessWidget {
  const ChatCountBadge({super.key, required this.count, this.red = false});
  final int count;
  final bool red;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: red ? 18 : 20,
      constraints: BoxConstraints(minWidth: red ? 18 : 20),
      padding: EdgeInsets.symmetric(horizontal: red ? 5 : 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: red ? null : ChatTokens.gradient,
        color: red ? ChatTokens.danger : null,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (red ? ChatTokens.danger : ChatTokens.primary)
                .withValues(alpha: 0.32),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: Colors.white,
          fontSize: red ? 10 : 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class ChatChip extends StatefulWidget {
  const ChatChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<ChatChip> createState() => _ChatChipState();
}

class _ChatChipState extends State<ChatChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    final sel = widget.selected;
    final fg = sel
        ? Colors.white
        : (_hover ? ChatTokens.primary : t.muted);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: sel ? ChatTokens.gradient : null,
            color: sel ? null : t.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: sel
                  ? Colors.transparent
                  : (_hover
                      ? ChatTokens.primary.withValues(alpha: 0.30)
                      : t.border),
            ),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: ChatTokens.primary.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 11, color: fg),
                const SizedBox(width: 5),
              ],
              Text(widget.label,
                  style: TextStyle(
                      color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatTab extends StatefulWidget {
  const ChatTab({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final int badge;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    final fg = widget.active
        ? ChatTokens.primary
        : (_hover ? t.text : t.muted);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.active ? ChatTokens.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 13, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              if (widget.badge > 0) ...[
                const SizedBox(width: 6),
                ChatCountBadge(count: widget.badge, red: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.online,
    this.facebook = false,
    this.imageUrl,
    this.ringColor,
  });

  final String name;
  final double size;
  final bool? online;
  final bool facebook;
  final String? imageUrl;
  final Color? ringColor;

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.map((p) => p[0]).take(2).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    final img = imageUrl;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient:
                  facebook ? ChatTokens.fbGradient : ChatTokens.gradient,
              boxShadow: facebook
                  ? [
                      BoxShadow(
                        color: const Color(0xFF006AFF).withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: facebook
                ? Icon(Icons.chat_bubble_rounded,
                    color: Colors.white, size: size * 0.4)
                : Text(
                    initialsOf(name),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: size * 0.325,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
          if (img != null && img.isNotEmpty)
            ClipOval(
              child: Image.network(
                img,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          if (online != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.3,
                height: size * 0.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online! ? ChatTokens.online : const Color(0xFFCBD5E1),
                  border: Border.all(
                      color: ringColor ?? t.surfaceSoft, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ChatMiniPill extends StatelessWidget {
  const ChatMiniPill({
    super.key,
    required this.label,
    required this.bg,
    required this.fg,
    this.icon,
  });
  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 9, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: fg,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMenuEntry {
  const ChatMenuEntry(this.value, this.label, {this.danger = false});
  final String value;
  final String label;
  final bool danger;
}

Future<String?> showChatMenu(
  BuildContext context,
  Offset position,
  List<ChatMenuEntry> items,
) {
  final t = ChatTokens.of(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  return showMenu<String>(
    context: context,
    color: t.surface,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: t.border),
    ),
    constraints: const BoxConstraints(minWidth: 222),
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final i in items)
        PopupMenuItem<String>(
          value: i.value,
          height: 40,
          child: Text(
            i.label,
            style: TextStyle(
              fontSize: 13,
              color: i.danger ? ChatTokens.danger : t.text,
            ),
          ),
        ),
    ],
  );
}

class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                  letterSpacing: -0.15)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: t.muted)),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

class ChatHeaderTitle extends StatelessWidget {
  const ChatHeaderTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.dotColor,
    this.online = false,
    this.compact = false,
  });
  final String title;
  final String subtitle;
  final Color? dotColor;
  final bool online;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = ChatTokens.of(context);
    final dc = dotColor ?? (online ? ChatTokens.online : const Color(0xFFCBD5E1));
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 15 : 17,
            fontWeight: FontWeight.w700,
            color: t.text,
            letterSpacing: -0.25,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dc,
                boxShadow: online
                    ? [
                        BoxShadow(
                          color: ChatTokens.online.withValues(alpha: 0.18),
                          spreadRadius: 3,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500, color: t.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
