import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'resizable_columns.dart';
import 'tp_loader.dart';

export 'resizable_columns.dart';

class StationScaffold extends StatelessWidget {
  const StationScaffold({
    super.key,
    required this.stationNumber,
    required this.stationLabel,
    required this.title,
    required this.child,
    this.trailing,
    this.belowRule,
    this.onBack,
    this.showBottomBrand = true,
    this.bottomBar,
    this.leading,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 20),
  });

  final String stationNumber;
  final String stationLabel;
  final String title;
  final Widget child;
  final Widget? trailing;
  final Widget? belowRule;
  final VoidCallback? onBack;
  final bool showBottomBrand;
  final Widget? bottomBar;
  final Widget? leading;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final showTitle = onBack != null;
    final hasBar =
        showTitle || trailing != null || belowRule != null || leading != null;
    return Scaffold(
      backgroundColor: context.brand.canvas,
      bottomNavigationBar: bottomBar,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasBar)
            PageToolbar(
              leading: showTitle
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed: onBack,
                          icon: const Icon(Icons.arrow_back, size: 20),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    )
                  : leading,
              actions: [?belowRule, ?trailing],
            ),
          Expanded(
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    );
  }
}

class PageToolbar extends StatelessWidget {
  const PageToolbar({super.key, this.leading, this.actions = const []});
  final Widget? leading;
  final List<Widget> actions;

  static Widget _cell(Widget child) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 56),
    child: Align(widthFactor: 1, alignment: Alignment.centerLeft, child: child),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: leading == null ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: Wrap(
        alignment: leading == null
            ? WrapAlignment.end
            : WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        children: [
          if (leading != null) _cell(leading!),
          if (actions.isNotEmpty)
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              children: [for (final a in actions) _cell(a)],
            ),
        ],
      ),
    );
  }
}

class StationAction extends StatelessWidget {
  const StationAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

class OutlinedIconButton extends StatelessWidget {
  const OutlinedIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.size = 38,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: context.brand.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          mouseCursor: SystemMouseCursors.click,
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 18, color: color ?? context.brand.paperDim),
          ),
        ),
      ),
    );
  }
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.count,
    required this.onPressed,
    this.tooltip = 'Notifications',
  });

  final int count;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        OutlinedIconButton(
          icon: Icons.notifications_none_outlined,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
        if (count > 0)
          Positioned(top: -5, right: -5, child: CountBadge(count: count)),
      ],
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.color});
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color ?? Brand.signal,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.brand.surface, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
      ),
    );
  }
}

class SignalButton extends StatelessWidget {
  const SignalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton(
      onPressed: busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 40),
        disabledBackgroundColor: Brand.signal.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(
              width: 14,
              height: 14,
              child: TpLoader(strokeWidth: 2, color: Colors.white),
            )
          else if (icon != null)
            Icon(icon, size: 16),
          if (busy || icon != null) const SizedBox(width: 8),
          Text(label.toUpperCase()),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
          Text(label),
        ],
      ),
    );
  }
}

class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Brand.danger,
        minimumSize: const Size(0, 40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
          Text(label.toUpperCase()),
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    this.controller,
    this.hint = 'Search…',
    this.onChanged,
    this.onSubmitted,
    this.width = 320,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final double? width;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 38),
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

class WebCard extends StatelessWidget {
  const WebCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    this.expandChild = false,
  });

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsets padding;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  if (icon != null) ...[
                    IconTile(icon: icon!, size: 30),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            Divider(height: 1, color: context.brand.rule),
          ],
          if (expandChild) Expanded(child: body) else body,
        ],
      ),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 36, this.color});
  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Brand.signal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(icon, size: size * 0.52, color: c),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.brand.paperDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items});
  final List<StatItem> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return WebCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Wrap(
        spacing: 48,
        runSpacing: 12,
        children: [
          for (final s in items)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (s.icon != null) ...[
                      Icon(s.icon, size: 13, color: s.color ?? Brand.signal),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      s.label.toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: s.color ?? Brand.signal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  s.value,
                  style: text.headlineMedium?.copyWith(fontSize: 18),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 220,
    this.spacing = 16,
    this.runSpacing,
    this.maxColumns,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final double minItemWidth;
  final double spacing;
  final double? runSpacing;
  final int? maxColumns;
  final CrossAxisAlignment crossAxisAlignment;

  static int columnsFor(int count, double width, double minItem, double gap,
      {int? max}) {
    if (count <= 1) return 1;
    var cols = ((width + gap) / (minItem + gap)).floor();
    cols = cols.clamp(1, max ?? count);
    if (cols >= count) return count;
    if (count % cols != 0) {
      for (var c = cols; c >= 1; c--) {
        if (count % c == 0) return c;
      }
    }
    return cols;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cols = columnsFor(
          children.length,
          box.maxWidth,
          minItemWidth,
          spacing,
          max: maxColumns,
        );
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          if (rows.isNotEmpty) {
            rows.add(SizedBox(height: runSpacing ?? spacing));
          }
          final cells = <Widget>[];
          for (var j = 0; j < cols; j++) {
            if (j > 0) cells.add(SizedBox(width: spacing));
            final k = i + j;
            cells.add(
              Expanded(
                child: k < children.length ? children[k] : const SizedBox(),
              ),
            );
          }
          rows.add(
            crossAxisAlignment == CrossAxisAlignment.stretch
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: cells,
                    ),
                  )
                : Row(crossAxisAlignment: crossAxisAlignment, children: cells),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }
}

class StatItem {
  const StatItem(this.label, this.value, {this.icon, this.color});
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
}

Future<T?> showWebModal<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
  String? subtitle,
  IconData? icon,
  List<Widget> Function(BuildContext)? actions,
  double width = 640,
  double? height,
  bool scrollable = true,
  bool barrierDismissible = true,
  EdgeInsets bodyPadding = const EdgeInsets.all(20),
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => WebModal(
      title: title,
      subtitle: subtitle,
      icon: icon,
      width: width,
      height: height,
      scrollable: scrollable,
      bodyPadding: bodyPadding,
      actions: actions?.call(ctx),
      child: Builder(builder: builder),
    ),
  );
}

class WebModal extends StatelessWidget {
  const WebModal({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.actions,
    this.width = 640,
    this.height,
    this.scrollable = true,
    this.bodyPadding = const EdgeInsets.all(20),
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final List<Widget>? actions;
  final double width;
  final double? height;
  final bool scrollable;
  final EdgeInsets bodyPadding;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final screen = MediaQuery.sizeOf(context);
    final inset = screen.width < 900 || screen.height < 640 ? 12.0 : 32.0;
    final maxH = screen.height - inset * 2;
    final w = width.clamp(280.0, screen.width - inset * 2).toDouble();
    final close = onClose ?? () => Navigator.of(context).maybePop();
    final body = Padding(padding: bodyPadding, child: child);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Dialog(
        insetPadding: EdgeInsets.all(inset),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: w,
            minWidth: w,
            maxHeight: height == null ? maxH : height!.clamp(160, maxH),
            minHeight: height == null ? 0 : height!.clamp(160, maxH),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      IconTile(icon: icon!, size: 38),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: text.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Text(
                              subtitle!,
                              style: text.bodySmall,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: close,
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: context.brand.paperDim,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: context.brand.rule),
              Flexible(
                fit: height == null ? FlexFit.loose : FlexFit.tight,
                child: scrollable ? SingleChildScrollView(child: body) : body,
              ),
              if (actions != null && actions!.isNotEmpty) ...[
                Divider(height: 1, color: context.brand.rule),
                Container(
                  color: context.brand.surfaceHi,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: _ModalActionBar(actions: actions!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModalActionBar extends StatelessWidget {
  const _ModalActionBar({required this.actions});
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final flexible = [
      for (final a in actions)
        if (a is Flexible) a.child,
    ];
    final hasFlex = flexible.isNotEmpty || actions.any((a) => a is Spacer);
    final rest = [
      for (final a in actions)
        if (a is! Flexible && a is! Spacer) a,
    ];
    final wrap = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: rest,
    );
    if (!hasFlex) return wrap;
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 720) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                actions[i],
              ],
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final f in flexible) ...[f, const SizedBox(height: 8)],
            Align(alignment: Alignment.centerRight, child: wrap),
          ],
        );
      },
    );
  }
}

class FormRow extends StatelessWidget {
  const FormRow({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.icon,
    this.labelWidth = 200,
  });

  final String label;
  final Widget child;
  final bool required;
  final IconData? icon;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: Brand.signal),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(color: Brand.danger, fontWeight: FontWeight.w700),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < labelWidth + 280) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [labelRow, const SizedBox(height: 6), child],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: labelWidth, child: labelRow),
              const SizedBox(width: 16),
              Expanded(child: child),
            ],
          );
        },
      ),
    );
  }
}

class StationDataRow extends StatelessWidget {
  const StationDataRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
    this.onTap,
    this.trailingIcon,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final effectiveValueStyle =
        valueStyle ??
        text.bodyMedium?.copyWith(
          color: onTap != null ? Brand.signal : context.brand.paper,
          fontWeight: FontWeight.w600,
        );
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 170, child: Text(label, style: text.bodySmall)),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: effectiveValueStyle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailingIcon != null && onTap != null) ...[
            const SizedBox(width: 8),
            Icon(trailingIcon, size: 16, color: Brand.signal),
          ],
        ],
      ),
    );
    final row = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: body,
    );
    if (onTap == null) return row;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: row,
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.positive = true,
    this.icon,
  });

  final String label;
  final String value;
  final String? delta;
  final bool positive;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                IconTile(icon: icon!, size: 26),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(label.toUpperCase(), style: text.labelSmall),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: text.displayMedium?.copyWith(fontSize: 28, height: 1),
          ),
          if (delta != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  positive ? Icons.trending_up : Icons.trending_down,
                  size: 14,
                  color: positive ? Brand.success : context.brand.paperDim,
                ),
                const SizedBox(width: 6),
                Text(
                  delta!,
                  style: text.bodySmall?.copyWith(
                    color: positive ? Brand.success : context.brand.paperDim,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ActivityRow extends StatelessWidget {
  const ActivityRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.meta,
    this.onTap,
    this.trailingText,
    this.showSignalDot = false,
  });

  final String title;
  final String subtitle;
  final String meta;
  final String? trailingText;
  final bool showSignalDot;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      mouseCursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: showSignalDot ? Brand.signal : context.brand.rule,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(meta, style: text.labelSmall),
                if (trailingText != null) ...[
                  const SizedBox(height: 4),
                  Text(trailingText!, style: text.bodySmall),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: context.brand.rule);
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.label,
    required this.hint,
    this.icon = Icons.inbox_outlined,
  });

  final String label;
  final String hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(icon: icon, size: 52, color: context.brand.paperDim),
            const SizedBox(height: 14),
            Text(label, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(hint, style: text.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class WebTableHeader extends StatelessWidget {
  const WebTableHeader({super.key, required this.cells});
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    final scoped = ColumnResizeScope.maybeOf(context) != null;
    return Container(
      padding: scoped
          ? const EdgeInsets.symmetric(horizontal: 16)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.brand.surfaceHi,
        border: Border(bottom: BorderSide(color: context.brand.rule)),
      ),
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.labelLarge!,
        child: Row(
          children: resizableRowCells(
            context,
            cells,
            header: true,
            extra: 32,
            headerPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }
}

class WebTableRow extends StatefulWidget {
  const WebTableRow({
    super.key,
    required this.cells,
    this.onTap,
    this.selected = false,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> cells;
  final VoidCallback? onTap;
  final bool selected;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<WebTableRow> createState() => _WebTableRowState();
}

class _WebTableRowState extends State<WebTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.selected
        ? Brand.signalGlow(0.08)
        : (_hover ? context.brand.surfaceHi : context.brand.surface);
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: bg,
            border: Border(bottom: BorderSide(color: context.brand.rule)),
          ),
          child: Row(
            crossAxisAlignment: widget.crossAxisAlignment,
            children: resizableRowCells(context, widget.cells),
          ),
        ),
      ),
    );
  }
}
