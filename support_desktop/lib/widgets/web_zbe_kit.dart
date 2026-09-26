import 'package:flutter/material.dart';

import '../theme.dart';
import 'premium.dart';
import 'tp_loader.dart';

Future<bool> zbeConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  bool danger = false,
  IconData? icon,
}) async {
  final ok = await showWebModal<bool>(
    context,
    title: title,
    icon: icon ?? (danger ? Icons.warning_amber_rounded : Icons.help_outline),
    width: 460,
    builder: (_) => Text(message, style: const TextStyle(fontSize: 14)),
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      danger
          ? DangerButton(
              label: confirm,
              onPressed: () => Navigator.pop(ctx, true),
            )
          : SignalButton(
              label: confirm,
              onPressed: () => Navigator.pop(ctx, true),
            ),
    ],
  );
  return ok ?? false;
}

class ZbeChip extends StatelessWidget {
  const ZbeChip(this.label, this.color, {super.key, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class ZbeRow extends StatefulWidget {
  const ZbeRow({
    super.key,
    required this.cells,
    this.onTap,
    this.color,
    this.accent,
    this.opacity = 1,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.hoverColor,
    this.ruleColor,
    this.minHeight = 44,
  });

  final List<Widget> cells;
  final VoidCallback? onTap;
  final Color? color;
  final Color? accent;
  final double opacity;
  final EdgeInsets padding;
  final Color? hoverColor;
  final Color? ruleColor;
  final double minHeight;

  @override
  State<ZbeRow> createState() => _ZbeRowState();
}

class _ZbeRowState extends State<ZbeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? context.brand.surface;
    final bg = _hover
        ? (widget.hoverColor ??
              Color.alphaBlend(
                context.brand.paper.withValues(alpha: 0.035),
                base,
              ))
        : base;
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Opacity(
          opacity: widget.opacity,
          child: Container(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            padding: widget.padding,
            decoration: BoxDecoration(
              color: bg,
              border: Border(
                left: BorderSide(
                  color: widget.accent ?? Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(
                  color: widget.ruleColor ?? context.brand.rule,
                ),
              ),
            ),
            child: Row(children: resizableRowCells(context, widget.cells)),
          ),
        ),
      ),
    );
  }
}

class ZbeHead extends StatelessWidget implements ResizableColumnCell {
  const ZbeHead(this.label, {super.key, this.flex = 1, this.width, this.align});
  final String label;
  final int flex;
  final double? width;
  final TextAlign? align;

  @override
  ColSpec get colSpec =>
      ColSpec(width: width, flex: flex, resizable: label.trim().isNotEmpty);

  @override
  Widget buildColumnContent(BuildContext context) => Text(
    label.toUpperCase(),
    textAlign: align,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
      color: context.brand.paperDim,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = buildColumnContent(context);
    if (width != null) return SizedBox(width: width, child: t);
    return Expanded(flex: flex, child: t);
  }
}

class ZbePager extends StatelessWidget {
  const ZbePager({
    super.key,
    required this.page,
    required this.pages,
    required this.pageSize,
    required this.onPage,
    required this.onPageSize,
    this.sizes = const [10, 15, 25, 50],
    this.summary,
  });

  final int page;
  final int pages;
  final int pageSize;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;
  final List<int> sizes;
  final String? summary;

  @override
  Widget build(BuildContext context) {
    final last = pages < 1 ? 1 : pages;
    var start = page - 2;
    if (start < 1) start = 1;
    var end = start + 4;
    if (end > last) {
      end = last;
      start = (end - 4) < 1 ? 1 : end - 4;
    }
    Widget btn(
      String label,
      int target, {
      bool enabled = true,
      bool on = false,
    }) {
      final active = enabled && !on;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: on ? Brand.signal : context.brand.surface,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            mouseCursor: active
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onTap: active ? () => onPage(target) : null,
            child: Container(
              height: 34,
              constraints: const BoxConstraints(minWidth: 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: on ? Brand.signal : context.brand.rule,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on
                      ? Colors.white
                      : (enabled
                            ? context.brand.paper
                            : context.brand.paperDim.withValues(alpha: 0.6)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        border: Border(top: BorderSide(color: context.brand.rule)),
      ),
      child: Row(
        children: [
          const Text(
            'Page Size',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(width: 10),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: context.brand.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Brand.inputBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: sizes.contains(pageSize) ? pageSize : sizes.first,
                isDense: true,
                style: TextStyle(fontSize: 14, color: context.brand.paper),
                items: [
                  for (final n in sizes)
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: (v) {
                  if (v != null) onPageSize(v);
                },
              ),
            ),
          ),
          if (summary != null) ...[
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                summary!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: context.brand.paperDim),
              ),
            ),
          ],
          const Spacer(),
          btn('First', 1, enabled: page > 1),
          btn('Prev', page - 1, enabled: page > 1),
          for (var p = start; p <= end; p++) btn('$p', p, on: p == page),
          btn('Next', page + 1, enabled: page < last),
        ],
      ),
    );
  }
}

class ZbeSection extends StatelessWidget {
  const ZbeSection({
    super.key,
    required this.title,
    required this.child,
    this.number,
    this.icon,
    this.trailing,
  });

  final String title;
  final Widget child;
  final int? number;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (number != null) ...[
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Brand.signal,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (icon != null) ...[
                Icon(icon, size: 18, color: Brand.signal),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Brand.signal,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.brand.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.brand.rule),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class ZbeStateView extends StatelessWidget {
  const ZbeStateView({
    super.key,
    required this.loading,
    this.error,
    this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: TpLoader());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(
              icon: Icons.cloud_off_outlined,
              size: 48,
              color: Brand.danger,
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.brand.paperDim, fontSize: 13),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              SignalButton(
                label: 'Retry',
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ZbeSelect<T> extends StatelessWidget {
  const ZbeSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 190,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        key: ValueKey(value),
        initialValue: value,
        isDense: true,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class ZbeToggle extends StatelessWidget {
  const ZbeToggle({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.activeColor = Brand.signal,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? activeColor : context.brand.paper;
    return Material(
      color: selected
          ? activeColor.withValues(alpha: 0.1)
          : context.brand.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? activeColor.withValues(alpha: 0.6)
                  : Brand.inputBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
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

class ZbeSegmented<T> extends StatelessWidget {
  const ZbeSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Brand.inputBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            Material(
              color: options[i].$1 == value
                  ? Brand.signal
                  : context.brand.surface,
              child: InkWell(
                onTap: () => onChanged(options[i].$1),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : const Border(
                            left: BorderSide(color: Brand.inputBorder),
                          ),
                  ),
                  child: Text(
                    options[i].$2,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: options[i].$1 == value
                          ? Colors.white
                          : context.brand.paper,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

bool zbeDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color zbeLine(BuildContext context) =>
    zbeDark(context) ? context.brand.rule : const Color(0xFFE2E2E0);

Color zbeSoftLine(BuildContext context) =>
    zbeDark(context) ? context.brand.rule : const Color(0xFFF1F1EF);

Color zbeTint(
  BuildContext context,
  Color light,
  Color accent, [
  double alpha = 0.12,
]) => zbeDark(context)
    ? Color.alphaBlend(accent.withValues(alpha: alpha), context.brand.surface)
    : light;

class ZbeWebChip extends StatelessWidget {
  const ZbeWebChip(
    this.label,
    this.bg,
    this.fg, {
    super.key,
    this.icon,
    this.upper = true,
    this.fontSize = 10.5,
  });
  final String label;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final bool upper;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final back = zbeDark(context) ? fg.withValues(alpha: 0.18) : bg;
    final fore = zbeDark(context) ? Color.lerp(fg, Colors.white, 0.35)! : fg;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
      decoration: BoxDecoration(
        color: back,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 0.5, color: fore),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              upper ? label.toUpperCase() : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: fore,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ZbeCountPill extends StatelessWidget {
  const ZbeCountPill(this.value, {super.key, this.hot = false});
  final String value;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final bg = hot
        ? zbeTint(context, const Color(0xFFFEE2E2), const Color(0xFFB91C1C))
        : zbeTint(context, const Color(0xFFF1F5F9), context.brand.paperDim);
    return Container(
      constraints: const BoxConstraints(minWidth: 30),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: hot ? const Color(0xFFB91C1C) : context.brand.paper,
        ),
      ),
    );
  }
}

class ZbePillButton extends StatefulWidget {
  const ZbePillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.on = false,
    this.dark = false,
    this.height = 40,
    this.fontSize = 12.5,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool on;
  final bool dark;
  final double height;
  final double fontSize;

  @override
  State<ZbePillButton> createState() => _ZbePillButtonState();
}

class _ZbePillButtonState extends State<ZbePillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const orange = Brand.signal;
    Color bg;
    Color fg;
    Color? border;
    if (widget.dark) {
      bg = _hover ? orange : Brand.navy;
      fg = Colors.white;
      border = null;
      if (zbeDark(context) && !_hover) bg = context.brand.surfaceHi;
    } else if (widget.on) {
      bg = zbeTint(context, const Color(0xFFFFF3E6), orange);
      fg = zbeDark(context) ? orange : const Color(0xFFB45309);
      border = orange;
    } else {
      bg = context.brand.surface;
      fg = _hover ? orange : context.brand.paper;
      border = _hover ? orange : zbeLine(context);
    }
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: widget.height,
          padding: EdgeInsets.symmetric(horizontal: widget.dark ? 24 : 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.fontSize + 1.5, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: widget.dark ? 0.6 : 0,
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

class ZbeCircleButton extends StatefulWidget {
  const ZbeCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 32,
    this.active = false,
    this.danger = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool active;
  final bool danger;
  final String? tooltip;

  @override
  State<ZbeCircleButton> createState() => _ZbeCircleButtonState();
}

class _ZbeCircleButtonState extends State<ZbeCircleButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hot = widget.danger ? const Color(0xFFDC2626) : Brand.signal;
    final lit = widget.active || (_hover && widget.onTap != null);
    final fg = widget.onTap == null
        ? context.brand.paperDim.withValues(alpha: 0.5)
        : (lit ? hot : context.brand.paper);
    Widget w = MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.brand.surface,
            shape: BoxShape.circle,
            border: Border.all(color: lit ? hot : zbeLine(context)),
          ),
          child: Icon(widget.icon, size: widget.size * 0.45, color: fg),
        ),
      ),
    );
    if (widget.tooltip != null) {
      w = Tooltip(message: widget.tooltip!, child: w);
    }
    return w;
  }
}

class ZbePillSearch extends StatelessWidget {
  const ZbePillSearch({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.height = 44,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: zbeLine(context)),
    );
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: context.brand.surface,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13.5, color: context.brand.paperDim),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: Icon(Icons.search, size: 18, color: context.brand.paperDim),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: Brand.signal),
          ),
        ),
      ),
    );
  }
}

class ZbePillSelect<T> extends StatelessWidget {
  const ZbePillSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 160,
    this.height = 44,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    DropdownMenuItem<T>? sel;
    for (final it in items) {
      if (it.value == value) sel = it;
    }
    final label = sel?.child is Text ? ((sel!.child as Text).data ?? '') : '';
    return PopupMenuButton<T>(
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final it in items)
          PopupMenuItem<T>(
            value: it.value,
            height: 38,
            child: DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: it.value == value
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: it.value == value ? Brand.signal : context.brand.paper,
              ),
              child: it.child,
            ),
          ),
      ],
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.only(left: 18, right: 12),
        decoration: BoxDecoration(
          color: context.brand.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: zbeLine(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: context.brand.paper),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: context.brand.paper,
            ),
          ],
        ),
      ),
    );
  }
}
