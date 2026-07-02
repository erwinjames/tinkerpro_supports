import 'package:flutter/material.dart';

import '../theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Structural chrome
// ─────────────────────────────────────────────────────────────────────────────

/// Every primary screen in the app uses StationScaffold. It provides:
///  * the oversized faint station numeral watermark
///  * the "STATION NN · LABEL" mono tag
///  * an animated draw-in hairline under the tag
///  * the big serif title
///  * an optional back affordance and a trailing action slot
///  * a globe+wordmark tag pinned to the bottom-left gutter
///
/// The animation sequence (numeral → rule → content) runs once per mount.
class StationScaffold extends StatefulWidget {
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
  });

  final String stationNumber;
  final String stationLabel;
  final String title;
  final Widget child;
  final Widget? trailing;

  /// Optional right-aligned widget rendered immediately below the animated
  /// hairline rule. Used by list screens to host a notification bell that
  /// shouldn't crowd the trailing slot next to STATION NN · LABEL.
  final Widget? belowRule;
  final VoidCallback? onBack;
  final bool showBottomBrand;
  final Widget? bottomBar;

  @override
  State<StationScaffold> createState() => _StationScaffoldState();
}

class _StationScaffoldState extends State<StationScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _numeralFade;
  late final Animation<double> _ruleDraw;
  late final Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _numeralFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.27, curve: Curves.easeOut),
    );
    _ruleDraw = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.27, 0.67, curve: Curves.easeOutCubic),
    );
    _contentFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
    );
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
    return Scaffold(
      bottomNavigationBar: widget.bottomBar,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Numeral watermark ────────────────────────────────────────
            Positioned(
              top: -18,
              right: -26,
              child: FadeTransition(
                opacity: _numeralFade,
                child: Text(
                  widget.stationNumber,
                  style: text.displayLarge,
                ),
              ),
            ),

            // ── Bottom gutter wordmark ───────────────────────────────────
            if (widget.showBottomBrand)
              Positioned(
                bottom: 20,
                left: 24,
                child: FadeTransition(
                  opacity: _contentFade,
                  child: Row(
                    children: [
                      Image.asset(
                        'assets/brand/tinkerpro-icon-192.png',
                        width: 16,
                        height: 16,
                      ),
                      const SizedBox(width: 8),
                      Text('TINKERPRO · SUPPORT',
                          style: text.labelMedium?.copyWith(
                            color: Brand.paperDim,
                            letterSpacing: 2.4,
                          )),
                    ],
                  ),
                ),
              ),

            // ── Foreground column ────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                widget.showBottomBrand ? 72 : 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.onBack != null) ...[
                        _SquareIconButton(
                          icon: Icons.arrow_back,
                          onTap: widget.onBack,
                          tooltip: 'Back',
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          'STATION ${widget.stationNumber} · ${widget.stationLabel}',
                          style: text.labelLarge,
                        ),
                      ),
                      if (widget.trailing != null) widget.trailing!,
                    ],
                  ),
                  const SizedBox(height: 12),
                  AnimatedBuilder(
                    animation: _ruleDraw,
                    builder: (_, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _ruleDraw.value,
                        child: Container(height: 1, color: context.brand.paper),
                      ),
                    ),
                  ),
                  if (widget.belowRule != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: widget.belowRule!,
                    ),
                    const SizedBox(height: 24),
                  ] else
                    const SizedBox(height: 40),
                  FadeTransition(
                    opacity: _contentFade,
                    child: Text(widget.title, style: text.headlineLarge),
                  ),
                  const SizedBox(height: 28),
                  Expanded(
                    child: FadeTransition(
                      opacity: _contentFade,
                      child: widget.child,
                    ),
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

/// A flat, square, monospaced icon button. No ripple circle.
class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({required this.icon, this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Icon(icon, size: 18, color: context.brand.paper),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Trailing icon action for the station header.
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
      icon: Icon(icon, size: 20, color: context.brand.paper),
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Bell icon with a small orange badge in the top-right corner whenever
/// [count] is greater than zero. Footprint matches [StationAction] so it can
/// stack cleanly under the refresh button.
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
    final hasUnseen = count > 0;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  Icons.notifications_none_outlined,
                  size: 20,
                  color: context.brand.paper,
                ),
              ),
              if (hasUnseen)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 14, minHeight: 14),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Brand.signal,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.brand.canvas, width: 1.2),
                    ),
                    child: Text(
                      count > 99 ? '99+' : count.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Brand.canvas,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions
// ─────────────────────────────────────────────────────────────────────────────

/// Primary CTA. Flat orange rectangle with outline; inverts to ink on press.
class SignalButton extends StatefulWidget {
  const SignalButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon = Icons.arrow_forward,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  State<SignalButton> createState() => _SignalButtonState();
}

class _SignalButtonState extends State<SignalButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.busy;
    // `Brand.canvas` (dark) stays the fg on the orange fill so the label reads
    // as dark-on-orange in BOTH themes; pressed/disabled surfaces follow theme.
    final bg = _pressed
        ? context.brand.canvas
        : (disabled ? context.brand.surfaceHi : Brand.signal);
    final fg = _pressed
        ? Brand.signal
        : (disabled ? context.brand.paperDim : Brand.canvas);
    return GestureDetector(
      onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
      onTap: disabled ? null : widget.onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 52,
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: Brand.signal, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.busy) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              widget.label.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontSize: 12,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (widget.icon != null) ...[
              const SizedBox(width: 8),
              Icon(widget.icon, size: 14, color: fg),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ghost secondary action. Used next to the primary CTA.
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
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: context.brand.rule, width: 1),
        ),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 12,
                letterSpacing: 3,
                fontWeight: FontWeight.w500,
                color: context.brand.paperDim,
              ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data display
// ─────────────────────────────────────────────────────────────────────────────

/// Small key/value pair with a hairline underneath — the look of a printed
/// datasheet. Used on the Home / device status / detail screens.
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

  /// When set, the whole row becomes tappable and the value is rendered in
  /// [Brand.signal] to hint at the affordance.
  final VoidCallback? onTap;

  /// Optional trailing icon shown to the right of the value — pairs with
  /// [onTap] to make the affordance visible (e.g. phone receiver icon).
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final effectiveValueStyle = valueStyle ??
        text.bodyMedium?.copyWith(
          color: onTap != null ? Brand.signal : context.brand.paper,
          decoration: onTap != null ? TextDecoration.underline : null,
          decorationColor: Brand.signal,
          decorationThickness: 1,
        );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(value,
                  style: effectiveValueStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
            if (trailingIcon != null && onTap != null) ...[
              const SizedBox(width: 8),
              Icon(trailingIcon, size: 18, color: Brand.signal),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: context.brand.rule),
      ],
    );

    if (onTap == null) return body;
    return InkWell(onTap: onTap, child: body);
  }
}

/// Headline metric card used on the Dashboard.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.positive = true,
  });

  final String label;
  final String value;
  final String? delta;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border.all(color: context.brand.rule, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.labelMedium),
          const SizedBox(height: 18),
          Text(value, style: text.displayMedium?.copyWith(fontSize: 32)),
          if (delta != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  positive ? Icons.trending_up : Icons.trending_down,
                  size: 12,
                  color: positive ? Brand.signal : Brand.paperDim,
                ),
                const SizedBox(width: 6),
                Text(
                  delta!,
                  style: text.labelMedium?.copyWith(
                    color: positive ? Brand.signal : Brand.paperDim,
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

/// One row in an activity / recent / list stream. Each row has a small
/// orange dot on the left — the only colour moment — and a mono timestamp
/// on the right. Taps are swallowed unless [onTap] is provided.
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
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
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
                  Text(title,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
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

/// Thin horizontal divider that respects the design language.
class Hairline extends StatelessWidget {
  const Hairline({super.key});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: context.brand.rule);
}

/// Empty-state placeholder shown when a list has no results.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.label,
    required this.hint,
  });

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(label,
                style: text.headlineMedium?.copyWith(color: Brand.paperDim)),
            const SizedBox(height: 8),
            Text(hint,
                style: text.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
