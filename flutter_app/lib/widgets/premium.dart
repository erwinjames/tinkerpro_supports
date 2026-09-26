import 'package:flutter/material.dart';

import '../theme.dart';

class StationScaffold extends StatefulWidget {
  const StationScaffold({
    super.key,
    this.stationNumber = '',
    this.stationLabel = '',
    required this.title,
    required this.child,
    this.subtitle = '',
    this.trailing,
    this.belowRule,
    this.onBack,
    this.backAlways = false,
    this.showBottomBrand = true,
    this.bottomBar,
    this.fab,
    this.compact = false,
  });

  final String stationNumber;
  final String stationLabel;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  final Widget? belowRule;
  final VoidCallback? onBack;
  final bool backAlways;
  final bool showBottomBrand;
  final Widget? bottomBar;
  final Widget? fab;
  final bool compact;

  @override
  State<StationScaffold> createState() => _StationScaffoldState();
}

class _StationScaffoldState extends State<StationScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.02),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  String get _eyebrow {
    final raw = widget.stationLabel.trim();
    if (raw.isEmpty) return '';
    return raw
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final title = widget.title.replaceAll('\n', ' ').trim();
    final showBack =
        widget.onBack != null &&
        (widget.backAlways || Navigator.of(context).canPop());
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final header = HeaderTone(
      child: AppHeaderBand(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showBack) ...[
                  AppIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_eyebrow.isNotEmpty)
                        Text(
                          _eyebrow,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium?.copyWith(
                            color: Brand.orange,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      if (title.isNotEmpty)
                        Semantics(
                          header: true,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (widget.compact
                                        ? text.titleLarge
                                        : text.headlineLarge)
                                    ?.copyWith(color: Colors.white),
                          ),
                        ),
                      if (widget.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 8),
                  widget.trailing!,
                ],
              ],
            ),
            if (widget.belowRule != null) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: widget.belowRule!),
            ],
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: b.canvas,
      bottomNavigationBar: widget.bottomBar,
      floatingActionButton: widget.fab,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: SafeArea(
              top: false,
              bottom: widget.bottomBar == null,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  widget.bottomBar == null ? 16 : 0,
                ),
                child: reduceMotion
                    ? widget.child
                    : FadeTransition(
                        opacity: _fade,
                        child: SlideTransition(
                          position: _slide,
                          child: widget.child,
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

class HeaderTone extends InheritedWidget {
  const HeaderTone({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeaderTone>() != null;

  @override
  bool updateShouldNotify(HeaderTone oldWidget) => false;
}

class AppHeaderBand extends StatelessWidget {
  const AppHeaderBand({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final bandColor = b.isDark ? const Color(0xFF12304F) : Brand.navy;
    return Container(
      decoration: BoxDecoration(
        color: bandColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        border: Border(
          bottom: BorderSide(color: Brand.orange.withValues(alpha: 0.35)),
        ),
        boxShadow: [
          BoxShadow(
            color: Brand.navy.withValues(alpha: b.isDark ? 0.5 : 0.22),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: padding,
          child: HeaderTone(child: child),
        ),
      ),
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final onHeader = HeaderTone.of(context);
    final bg = onHeader ? Colors.white.withValues(alpha: 0.12) : b.surface;
    final border = onHeader ? Colors.white.withValues(alpha: 0.18) : b.rule;
    final fg = onPressed == null
        ? (onHeader ? Colors.white.withValues(alpha: 0.4) : b.paperDim)
        : (color ?? (onHeader ? Colors.white : b.paper));
    final button = Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 21, color: fg),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
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
    return AppIconButton(icon: icon, tooltip: tooltip, onPressed: onPressed);
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
    final b = context.brand;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
        if (count > 0)
          Positioned(
            top: -4,
            right: -4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Brand.orange,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: HeaderTone.of(context) ? Brand.navy : b.canvas,
                    width: 2,
                  ),
                ),
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class SignalButton extends StatelessWidget {
  const SignalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final disabled = onPressed == null || busy;
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: disabled ? null : onPressed,
        style: FilledButton.styleFrom(
          disabledBackgroundColor: busy
              ? b.signal.withValues(alpha: 0.7)
              : b.surfaceHi,
          disabledForegroundColor: busy ? Brand.onSignal : b.paperDim,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Brand.onSignal,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (icon != null && !busy) ...[
              const SizedBox(width: 8),
              Icon(icon, size: 18),
            ],
          ],
        ),
      ),
    );
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
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = Brand.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? b.rule),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: b.shadow,
      ),
      child: Material(
        color: color ?? b.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
  }
}

class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.color,
    this.size = 40,
    this.iconSize = 20,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final c = color ?? b.signal;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: b.tint(c),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, size: iconSize, color: c),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool dot;

  static Color colorFor(String status) {
    final s = status.toLowerCase();
    if (s.contains('close') ||
        s.contains('done') ||
        s.contains('complete') ||
        s.contains('resolved') ||
        s.contains('active') ||
        s.contains('paid') ||
        s.contains('approved') ||
        s.contains('online')) {
      return Brand.success;
    }
    if (s.contains('pending') ||
        s.contains('progress') ||
        s.contains('wait') ||
        s.contains('hold') ||
        s.contains('review')) {
      return Brand.warning;
    }
    if (s.contains('cancel') ||
        s.contains('reject') ||
        s.contains('expired') ||
        s.contains('fail') ||
        s.contains('overdue') ||
        s.contains('urgent') ||
        s.contains('high')) {
      return Brand.danger;
    }
    if (s.contains('new') || s.contains('open')) return Brand.info;
    return Brand.signal;
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final c = color ?? colorFor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: b.tint(c, 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: 10),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.imageUrl,
    this.headers,
  });

  final String name;
  final double size;
  final String? imageUrl;
  final Map<String, String>? headers;

  static const _palette = [
    Color(0xFFFF7D00),
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF0EA5E9),
    Color(0xFFF59E0B),
    Color(0xFF14B8A6),
  ];

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'[\s._@-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final color = _palette[name.hashCode.abs() % _palette.length];
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: b.tint(color, 0.16),
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials,
        style: TextStyle(
          color: color,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final url = imageUrl;
    if (url == null || url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        headers: headers,
        errorBuilder: (_, _, _) => fallback,
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
    final b = context.brand;
    final effectiveValueStyle =
        valueStyle ??
        text.bodyMedium?.copyWith(
          color: onTap != null ? b.signal : b.paper,
          fontWeight: FontWeight.w500,
        );

    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: text.bodySmall)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: effectiveValueStyle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailingIcon != null && onTap != null) ...[
            const SizedBox(width: 8),
            Icon(trailingIcon, size: 18, color: b.signal),
          ],
        ],
      ),
    );

    final row = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: b.rule)),
      ),
      child: body,
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
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
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final String? delta;
  final bool positive;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final accent = color ?? b.signal;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                IconTile(icon: icon!, color: accent, size: 34, iconSize: 18),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: text.displaySmall?.copyWith(fontSize: 26)),
          if (delta != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  positive
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 14,
                  color: positive ? Brand.success : b.paperDim,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    delta!,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      color: positive ? Brand.success : b.paperDim,
                    ),
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
    this.icon,
    this.iconColor,
  });

  final String title;
  final String subtitle;
  final String meta;
  final String? trailingText;
  final bool showSignalDot;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconTile(
                  icon: icon!,
                  color: iconColor ?? (showSignalDot ? b.signal : b.paperDim),
                  size: 38,
                  iconSize: 19,
                ),
              )
            else
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: showSignalDot ? b.signal : b.rule,
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
                Text(meta, style: text.labelMedium),
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
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  final String label;
  final String hint;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: b.surfaceHi,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: b.paperDim),
            ),
            const SizedBox(height: 16),
            Text(label, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(hint, style: text.bodySmall, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 32});

  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = context.brand.isDark;
    return Image.asset(
      dark
          ? 'assets/brand/tinkerpro-wordmark-dark.png'
          : 'assets/brand/tinkerpro-wordmark.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'TinkerPro',
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/tinkerpro-mark.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'TinkerPro',
    );
  }
}

class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final base = b.surfaceHi;
    final hi = b.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.75);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 2 - 0.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 2, 0),
              end: Alignment(t * 2, 0),
              colors: [base, Color.alphaBlend(hi, base), base],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
        );
      },
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 6,
    this.avatar = true,
    this.padding = EdgeInsets.zero,
  });

  final int count;
  final bool avatar;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => AppCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (avatar) ...[
                const Skeleton(width: 42, height: 42, radius: 12),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(width: i.isEven ? 170 : 130, height: 14),
                    const SizedBox(height: 8),
                    Skeleton(width: i.isEven ? 110 : 150, height: 11),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Skeleton(width: 58, height: 22, radius: 11),
            ],
          ),
        ),
      ),
    );
  }
}

class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          fillColor: b.surface,
          prefixIcon: const Icon(Icons.search_rounded, size: 21),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, size: 19),
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
      ),
    );
  }
}

class ChoicePills<T> extends StatelessWidget {
  const ChoicePills({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labelOf,
    this.countOf,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T)? labelOf;
  final int? Function(T)? countOf;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final o = options[i];
          final selected = o == value;
          final count = countOf?.call(o);
          return Semantics(
            button: true,
            selected: selected,
            child: Material(
              color: selected ? Brand.navy : b.surface,
              shape: StadiumBorder(
                side: BorderSide(color: selected ? Brand.navy : b.rule),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onChanged(o),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        labelOf?.call(o) ?? '$o',
                        style: text.labelLarge?.copyWith(
                          color: selected ? Colors.white : b.paper,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
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
                            color: selected ? Brand.orange : b.surfaceHi,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$count',
                            style: text.labelSmall?.copyWith(
                              color: selected ? Colors.white : b.paperDim,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Brand.radiusLg,
    this.onTap,
    this.accent,
    this.blur = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? accent;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final tint = accent ?? b.signal;
    final border = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: border, boxShadow: b.shadow),
      child: Material(
        color: b.surface,
        shape: RoundedRectangleBorder(
          borderRadius: border,
          side: BorderSide(color: tint.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class GlowBadge extends StatelessWidget {
  const GlowBadge({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.maxLabelWidth = 200,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final c = color ?? b.signal;
    final hsl = HSLColor.fromColor(c);
    final ink = b.isDark
        ? (hsl.lightness < 0.55
              ? hsl
                    .withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0))
                    .toColor()
              : c)
        : (hsl.lightness > 0.42
              ? hsl
                    .withLightness((hsl.lightness - 0.18).clamp(0.0, 1.0))
                    .toColor()
              : c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: c.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxLabelWidth + (icon == null ? 0 : 18),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              if (icon != null) ...[
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(icon, size: 13, color: ink),
                ),
                const WidgetSpan(child: SizedBox(width: 5)),
              ],
              TextSpan(text: label),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: ink,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
