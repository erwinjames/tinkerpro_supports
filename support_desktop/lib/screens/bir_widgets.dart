import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/tp_loader.dart';

class BirSolidButton extends StatelessWidget {
  const BirSolidButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = Brand.signal,
    this.icon,
    this.busy = false,
    this.height = 45,
    this.fontSize = 14.4,
    this.fontWeight = FontWeight.w700,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;
  final bool busy;
  final double height;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return SizedBox(
      height: height,
      child: TextButton(
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          backgroundColor: enabled ? color : color.withValues(alpha: 0.5),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: TextStyle(fontSize: fontSize, fontWeight: fontWeight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: TpLoader(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 16),
            if (busy || icon != null) const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class BirOutlineButton extends StatelessWidget {
  const BirOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailing,
    this.height = 40,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFF475569);
    return SizedBox(
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF6C757D)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class BirStageSteps extends StatelessWidget {
  const BirStageSteps({super.key, required this.current, this.allDone = false});

  final int current;
  final bool allDone;

  static const _stages = [
    ('Pending Registration', 'Documents submitted'),
    ('Continue Registration', 'Software & hardware'),
    ('Upload PTU', 'PTU document'),
    ('Completed', 'Registration done'),
  ];

  @override
  Widget build(BuildContext context) {
    const grey = Color(0xFFE5E5E5);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth / _stages.length;
        return SizedBox(
          height: 76,
          child: Stack(
            children: [
              for (var i = 0; i < _stages.length - 1; i++)
                Positioned(
                  left: w * i + w / 2,
                  width: w,
                  top: 16,
                  height: 2,
                  child: ColoredBox(
                    color: (allDone || i + 1 < current) ? Brand.signal : grey,
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < _stages.length; i++)
                    SizedBox(width: w, child: _step(i + 1, _stages[i])),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _step(int n, (String, String) s) {
    final done = allDone || n < current;
    final active = !done && n == current;
    final on = done || active;
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? Brand.signal : Colors.white,
            border: Border.all(
              color: on ? Brand.signal : const Color(0xFFE5E5E5),
              width: 2,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Brand.signal.withValues(alpha: 0.15),
                      spreadRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text(
                  '$n',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: on ? Colors.white : const Color(0xFF9A9A9A),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          s.$1,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.2,
            fontWeight: FontWeight.w700,
            color: on ? Colors.black : const Color(0xFF9A9A9A),
            height: 1.2,
          ),
        ),
        Text(
          s.$2,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10.6,
            color: Color(0xFFB5B5B5),
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class BirBadge extends StatelessWidget {
  const BirBadge({
    super.key,
    required this.label,
    required this.bg,
    this.fg = Colors.white,
    this.fontSize = 13.6,
  });

  final String label;
  final Color bg;
  final Color fg;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: fg,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class BirPager extends StatelessWidget {
  const BirPager({
    super.key,
    required this.page,
    required this.lastPage,
    required this.pageSize,
    required this.pageSizes,
    required this.onPage,
    required this.onPageSize,
  });

  final int page;
  final int lastPage;
  final int pageSize;
  final List<int> pageSizes;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;

  @override
  Widget build(BuildContext context) {
    final start = (page - 2).clamp(1, lastPage);
    final end = (start + 4).clamp(1, lastPage);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border(top: BorderSide(color: context.brand.rule)),
      ),
      child: Row(
        children: [
          Text(
            'Page Size',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: context.brand.paper,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            height: 30,
            padding: const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              color: context.brand.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF9CA3AF)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: pageSize,
                isDense: true,
                iconSize: 18,
                style: TextStyle(fontSize: 14, color: context.brand.paper),
                items: [
                  for (final s in pageSizes)
                    DropdownMenuItem(value: s, child: Text('$s')),
                ],
                onChanged: (v) {
                  if (v != null) onPageSize(v);
                },
              ),
            ),
          ),
          const Spacer(),
          _btn(context, 'First', page > 1 ? () => onPage(1) : null),
          _btn(context, 'Prev', page > 1 ? () => onPage(page - 1) : null),
          for (var p = start; p <= end; p++)
            _btn(context, '$p', () => onPage(p), active: p == page),
          _btn(
            context,
            'Next',
            page < lastPage ? () => onPage(page + 1) : null,
          ),
          _btn(
            context,
            'Last',
            page < lastPage ? () => onPage(lastPage) : null,
          ),
        ],
      ),
    );
  }

  Widget _btn(
    BuildContext context,
    String label,
    VoidCallback? onTap, {
    bool active = false,
  }) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: active ? null : onTap,
        mouseCursor: enabled && !active
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          constraints: const BoxConstraints(minWidth: 34),
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Brand.signal : context.brand.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? Brand.signal : context.brand.rule,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              color: active
                  ? Colors.white
                  : (enabled
                        ? context.brand.paper
                        : context.brand.paperDim.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ),
    );
  }
}

class BirCloseButton extends StatelessWidget {
  const BirCloseButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4EA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.close, color: Brand.signal, size: 24),
      ),
    );
  }
}

class BirDialogShell extends StatelessWidget {
  const BirDialogShell({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.width = 500,
    this.footer,
    this.onClose,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final double width;
  final Widget? footer;
  final VoidCallback? onClose;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final close = onClose ?? () => Navigator.of(context).maybePop();
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          minWidth: width.clamp(0, screen.width - 48).toDouble(),
          maxHeight: screen.height - 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 16, 18),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Brand.signal, size: 26),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Brand.navy,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: Color(0xFF64748B),
                            ),
                          ),
                      ],
                    ),
                  ),
                  BirCloseButton(onPressed: close),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                      child: child,
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                      child: child,
                    ),
            ),
            if (footer != null) ...[
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 16, 16, 16),
                child: footer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
