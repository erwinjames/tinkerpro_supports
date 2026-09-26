import 'package:flutter/material.dart';

import '../../theme.dart';

class OpPage extends StatelessWidget {
  const OpPage({
    super.key,
    required this.header,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(17, 24, 17, 20),
  });

  final Widget header;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brand.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

class OpPageHeader extends StatelessWidget {
  const OpPageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.actions = const [],
  });

  final String eyebrow;
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 24, 8, 20),
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: Brand.signal,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                    height: 1,
                    color: Brand.signal,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: context.brand.paper,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            actions[i],
          ],
        ],
      ),
    );
  }
}

class OpPillButton extends StatefulWidget {
  const OpPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool dense;

  @override
  State<OpPillButton> createState() => _OpPillButtonState();
}

class _OpPillButtonState extends State<OpPillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    final fg = primary
        ? Colors.white
        : (_hover ? Brand.signal : context.brand.paper);
    final bg = primary
        ? (_hover ? const Color(0xFFE67000) : Brand.signal)
        : context.brand.surface;
    return MouseRegion(
      cursor: widget.onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 14 : 22,
            vertical: widget.dense ? 8 : 11,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.dense ? 10 : 999),
            border: Border.all(
              color: primary
                  ? Colors.transparent
                  : (_hover && widget.dense
                        ? Brand.signal
                        : context.brand.rule),
            ),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: Brand.signal.withValues(alpha: _hover ? 0.3 : 0.2),
                      blurRadius: _hover ? 15 : 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 15, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.dense ? 12.8 : 13.6,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OpPanel extends StatelessWidget {
  const OpPanel({super.key, required this.child, this.radius = 16});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: context.brand.rule),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
