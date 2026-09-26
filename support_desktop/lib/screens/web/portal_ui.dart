import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/resizable_columns.dart';
import '../../widgets/tp_loader.dart';

const portalMuted = Color(0xFF64748B);
const portalOrange = Color(0xFFFF7D00);
const portalOk = Color(0xFF16A34A);

class PortalTone {
  const PortalTone(this.bg, this.fg);
  final Color bg;
  final Color fg;
  static const ok = PortalTone(Color(0xFFDCFCE7), Color(0xFF166534));
  static const warn = PortalTone(Color(0xFFFFF7ED), Color(0xFFC2410C));
  static const muted = PortalTone(Color(0xFFF1F5F9), Color(0xFF475569));
  static const bad = PortalTone(Color(0xFFFEE2E2), Color(0xFFB91C1C));
  static const indigo = PortalTone(Color(0xFFE0E7FF), Color(0xFF4338CA));
}

class PortalPage extends StatelessWidget {
  const PortalPage({super.key, required this.children, this.onRefresh});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scroll = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(11, 16, 11, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return Scaffold(
      backgroundColor: context.brand.canvas,
      body: onRefresh == null
          ? scroll
          : RefreshIndicator(
              color: portalOrange,
              onRefresh: onRefresh!,
              child: scroll,
            ),
    );
  }
}

class PortalHeader extends StatelessWidget {
  const PortalHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.sub,
    this.subMaxWidth = 440,
    this.trailing,
    this.alignEnd = false,
    this.bottom = 20,
  });
  final String eyebrow;
  final String title;
  final String? sub;
  final double subMaxWidth;
  final Widget? trailing;
  final bool alignEnd;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.7,
            color: portalOrange,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: context.brand.paper,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 5),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: subMaxWidth),
            child: Text(
              sub!,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: context.brand.paperDim,
              ),
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: LayoutBuilder(
        builder: (context, box) {
          if (trailing != null && box.maxWidth < 1000) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                head,
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: trailing!,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: alignEnd
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Expanded(child: head),
              if (trailing != null) ...[const SizedBox(width: 16), trailing!],
            ],
          );
        },
      ),
    );
  }
}

class PortalStat extends StatelessWidget {
  const PortalStat({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 146,
      constraints: const BoxConstraints(minHeight: 72),
      margin: const EdgeInsets.only(left: 10),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.brand.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20.5,
              fontWeight: FontWeight.w700,
              color: context.brand.paper,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: context.brand.paperDim,
            ),
          ),
        ],
      ),
    );
  }
}

class PortalStats extends StatelessWidget {
  const PortalStats({super.key, required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final s in items) PortalStat(value: s.$1, label: s.$2)],
      ),
    );
  }
}

class PortalButton extends StatefulWidget {
  const PortalButton({
    super.key,
    required this.label,
    this.icon,
    this.trailingIcon,
    this.onPressed,
    this.primary = false,
    this.danger = false,
    this.big = false,
    this.tooltip,
  });
  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final bool big;
  final String? tooltip;

  @override
  State<PortalButton> createState() => _PortalButtonState();
}

class _PortalButtonState extends State<PortalButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final fg = widget.primary
        ? Colors.white
        : widget.danger
        ? const Color(0xFFDC2626)
        : context.brand.paper;
    final bg = widget.primary ? portalOrange : context.brand.surface;
    final border = widget.primary
        ? portalOrange
        : _hover && enabled
        ? (widget.danger ? const Color(0xFFFECACA) : const Color(0xFFCBD5E1))
        : context.brand.rule;
    final fs = widget.big ? 13.0 : 12.5;
    final child = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Container(
            constraints: BoxConstraints(minHeight: widget.big ? 40 : 32),
            padding: EdgeInsets.symmetric(
              horizontal: widget.big ? 15 : 12,
              vertical: widget.big ? 8 : 6,
            ),
            decoration: BoxDecoration(
              color: widget.primary && _hover && enabled
                  ? const Color(0xFFFF8A1A)
                  : bg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: fs + 1, color: fg),
                  if (widget.label.isNotEmpty) const SizedBox(width: 6),
                ],
                if (widget.label.isNotEmpty)
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fs,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 6),
                  Icon(widget.trailingIcon, size: fs + 1, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? child
        : Tooltip(message: widget.tooltip!, child: child);
  }
}

class PortalTab extends StatelessWidget {
  const PortalTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.onColor,
    this.fontSize = 12.8,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Color? onColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final on = onColor ?? Brand.navy;
    final fg = selected ? Colors.white : context.brand.paperDim;
    return Material(
      color: selected ? on : context.brand.surface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? on : context.brand.rule),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.22)
                        : portalMuted.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PortalSearch extends StatelessWidget {
  const PortalSearch({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.icon = true,
    this.height = 42,
  });
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: context.brand.rule),
    );
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(fontSize: 14, color: context.brand.paper),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: 14, color: context.brand.paperDim),
          isDense: true,
          filled: true,
          fillColor: context.brand.surface,
          contentPadding: EdgeInsets.symmetric(
            horizontal: icon ? 0 : 14,
            vertical: 12,
          ),
          prefixIcon: icon
              ? Icon(Icons.search, size: 18, color: context.brand.paperDim)
              : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: const BorderSide(color: portalOrange),
          ),
        ),
      ),
    );
  }
}

class PortalCard extends StatelessWidget {
  const PortalCard({
    super.key,
    required this.child,
    this.radius = 16,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final double radius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: context.brand.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class PortalCol {
  const PortalCol(this.label, {this.flex = 1, this.right = false, this.width});
  final String label;
  final int flex;
  final bool right;
  final double? width;
}

class PortalTable extends StatelessWidget {
  const PortalTable({
    super.key,
    required this.columns,
    required this.rows,
    this.empty = 'Nothing here.',
    this.loading = false,
    this.onRowTap,
    this.headerLetterSpacing = 0.9,
    this.cellPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    this.headerBg,
    this.tableId = 'portal',
  });
  final String tableId;
  final List<PortalCol> columns;
  final List<List<Widget>> rows;
  final String empty;
  final bool loading;
  final void Function(int index)? onRowTap;
  final double headerLetterSpacing;
  final EdgeInsets cellPadding;
  final Color? headerBg;

  ColSpec _spec(PortalCol c) =>
      ColSpec(
        width: c.width,
        flex: c.flex,
        resizable: c.label.trim().isNotEmpty,
      );

  Widget _cell(
    BuildContext context,
    int i,
    PortalCol c,
    Widget w, {
    bool header = false,
  }) => resizableCell(
    context,
    i,
    _spec(c),
    Padding(
      padding: EdgeInsets.symmetric(horizontal: cellPadding.left),
      child: Align(
        alignment: c.right ? Alignment.centerRight : Alignment.centerLeft,
        child: w,
      ),
    ),
    header: header,
    headerPadding: EdgeInsets.symmetric(vertical: cellPadding.top),
  );

  @override
  Widget build(BuildContext context) {
    return ColumnResizeScope(
      tableId: tableId,
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final rule = context.brand.rule;
    registerColumns(context, [for (final c in columns) _spec(c)]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: headerBg ?? context.brand.surfaceHi,
          child: Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                _cell(
                  context,
                  i,
                  columns[i],
                  Text(
                    columns[i].label.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11.2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: headerLetterSpacing,
                      color: context.brand.paperDim,
                    ),
                  ),
                  header: true,
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: rule),
        if (loading && rows.isNotEmpty)
          const LinearProgressIndicator(minHeight: 2, color: portalOrange),
        if (loading && rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: TpLoader()),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Text(
              empty,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.brand.paper),
            ),
          )
        else
          for (var i = 0; i < rows.length; i++)
            _HoverRow(
              last: i == rows.length - 1,
              onTap: onRowTap == null ? null : () => onRowTap!(i),
              padding: cellPadding.top,
              child: Row(
                children: [
                  for (var j = 0; j < columns.length; j++)
                    _cell(context, j, columns[j], rows[i][j]),
                ],
              ),
            ),
      ],
    );
  }
}

class _HoverRow extends StatefulWidget {
  const _HoverRow({
    required this.child,
    required this.last,
    required this.padding,
    this.onTap,
  });
  final Widget child;
  final bool last;
  final double padding;
  final VoidCallback? onTap;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: widget.padding),
          decoration: BoxDecoration(
            color: _hover
                ? (dark
                      ? portalOrange.withValues(alpha: 0.06)
                      : const Color(0xFFFFFAF5))
                : null,
            border: widget.last
                ? null
                : Border(bottom: BorderSide(color: context.brand.rule)),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class PortalPager extends StatelessWidget {
  const PortalPager({
    super.key,
    required this.info,
    required this.onPrev,
    required this.onNext,
  });
  final String info;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.brand.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            info,
            style: TextStyle(fontSize: 12.8, color: context.brand.paperDim),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PortalButton(
                label: 'Prev',
                icon: Icons.chevron_left,
                onPressed: onPrev,
              ),
              const SizedBox(width: 6),
              PortalButton(
                label: 'Next',
                trailingIcon: Icons.chevron_right,
                onPressed: onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PortalPill extends StatelessWidget {
  const PortalPill(
    this.text,
    this.tone, {
    super.key,
    this.icon,
    this.caps = false,
  });
  final String text;
  final PortalTone tone;
  final IconData? icon;
  final bool caps;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: caps ? 9 : 10,
        vertical: caps ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: tone.fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              caps ? text.toUpperCase() : text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: caps ? 10.9 : 11.8,
                fontWeight: FontWeight.w700,
                letterSpacing: caps ? 0.45 : 0,
                color: tone.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle portalName(BuildContext context) => TextStyle(
  fontSize: 13.6,
  fontWeight: FontWeight.w700,
  color: context.brand.paper,
);

TextStyle portalCell(BuildContext context) =>
    TextStyle(fontSize: 13.6, color: context.brand.paper);

TextStyle portalMeta(BuildContext context) =>
    TextStyle(fontSize: 12.5, color: context.brand.paperDim);

class PortalPasswordRules extends StatelessWidget {
  const PortalPasswordRules(this.pw, this.confirm, {super.key});
  final String pw;
  final String confirm;

  @override
  Widget build(BuildContext context) {
    final rules = [
      ('8+ characters', pw.length >= 8),
      (
        'Letters and numbers',
        RegExp(r'[A-Za-z]').hasMatch(pw) && RegExp(r'[0-9]').hasMatch(pw),
      ),
      ('Passwords match', pw.isNotEmpty && pw == confirm),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final r in rules)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                r.$2 ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14,
                color: r.$2 ? portalOk : context.brand.paperDim,
              ),
              const SizedBox(width: 4),
              Text(
                r.$1,
                style: TextStyle(
                  fontSize: 12,
                  color: r.$2 ? portalOk : context.brand.paperDim,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

String portalPasswordError(String pw, String confirm) {
  if (pw.length < 8) return 'Use at least 8 characters.';
  if (!RegExp(r'[A-Za-z]').hasMatch(pw) || !RegExp(r'[0-9]').hasMatch(pw)) {
    return 'Use both letters and numbers in the password.';
  }
  if (pw != confirm) return 'The two passwords do not match.';
  return '';
}
