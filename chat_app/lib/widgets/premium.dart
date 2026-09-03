import 'package:flutter/material.dart';

import '../theme.dart';

class StationScaffold extends StatefulWidget {
  const StationScaffold({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.child,
    this.trailing,
    this.onBack,
    this.showBottomBrand = true,
    this.bottomBar,
    this.fab,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  final VoidCallback? onBack;
  final bool showBottomBrand;
  final Widget? bottomBar;
  final Widget? fab;

  /// Smaller title, for screens whose title is user data rather than a
  /// fixed label — conversation and business names run long.
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
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.012),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final brand = context.brand;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final header = Container(
      color: brand.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.onBack != null) ...[
                _RoundIconButton(
                  icon: Icons.arrow_back,
                  onTap: widget.onBack,
                  tooltip: 'Back',
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: widget.compact
                          ? text.titleMedium?.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            )
                          : text.headlineLarge
                              ?.copyWith(fontSize: 20, letterSpacing: -0.2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        widget.subtitle,
                        style: text.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
        ],
      ),
    );

    final body = Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        widget.showBottomBrand ? 56 : 12,
      ),
      child: widget.child,
    );

    return Scaffold(
      backgroundColor: brand.canvas,
      bottomNavigationBar: widget.bottomBar,
      floatingActionButton: widget.fab,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Divider(height: 1, color: brand.rule),
                Expanded(
                  child: reduceMotion
                      ? body
                      : FadeTransition(
                          opacity: _fade,
                          child: SlideTransition(position: _slide, child: body),
                        ),
                ),
              ],
            ),
            if (widget.showBottomBrand)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/brand/tinkerpro_chat_mark.png',
                      width: 14,
                      height: 14,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'TinkerPro Chat',
                      style: text.labelMedium?.copyWith(color: brand.paperDim),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/brand/tinkerpro_chat_mark.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, _, _) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: context.brand.surfaceHi,
              borderRadius: BorderRadius.circular(size * 0.22),
            ),
            child: Icon(
              Icons.forum_outlined,
              size: size * 0.5,
              color: context.brand.paperDim,
            ),
          ),
        ),
        SizedBox(height: size * 0.22),
        Text(
          'TinkerPro Chat',
          style: text.headlineLarge?.copyWith(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: context.brand.paper,
        minimumSize: const Size(44, 44),
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
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: context.brand.paperDim,
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
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
    final brand = context.brand;
    final label = count > 99 ? '99+' : '$count';
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: brand.paperDim,
        minimumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none, size: 21),
          if (count > 0)
            Positioned(
              top: -3,
              right: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Brand.danger,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: brand.surface, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
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

class SignalButton extends StatelessWidget {
  const SignalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || busy;
    return FilledButton(
      onPressed: disabled ? null : onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) ...[
            const SizedBox(
              width: 15,
              height: 15,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 8),
            Icon(icon, size: 17),
          ],
        ],
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final brand = context.brand;
    final effectiveValueStyle = valueStyle ??
        (onTap != null
            ? text.bodyMedium?.copyWith(
                color: brand.signal,
                fontWeight: FontWeight.w600,
              )
            : text.bodyMedium);

    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.labelMedium),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: effectiveValueStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailingIcon != null && onTap != null) ...[
            const SizedBox(width: 12),
            Icon(trailingIcon, size: 18, color: brand.signal),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radiusSm),
      child: body,
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
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: brand.surfaceHi,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: brand.paperDim),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: text.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(hint, style: text.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
