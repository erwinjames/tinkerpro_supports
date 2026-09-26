import 'package:flutter/material.dart';

import '../models/user_admin_models.dart';
import '../theme.dart';
import 'premium.dart';

class PermissionToggleRow extends StatelessWidget {
  const PermissionToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.child = false,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final bool value;
  final bool child;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.only(left: child ? 18 : 0, top: 2, bottom: 2),
          child: Row(
            children: [
              if (child) ...[
                Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: b.paperDim,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: child
                          ? text.bodySmall?.copyWith(
                              color: b.paper,
                              fontWeight: FontWeight.w600,
                            )
                          : text.bodyMedium,
                    ),
                    if (hint != null && hint!.isNotEmpty)
                      Text(
                        hint!,
                        style: text.labelSmall?.copyWith(color: b.paperDim),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: enabled ? onChanged : null),
            ],
          ),
        ),
      ),
    );
  }
}

class PermissionGroupCard extends StatelessWidget {
  const PermissionGroupCard({
    super.key,
    required this.title,
    required this.defs,
    required this.open,
    required this.onToggleOpen,
    required this.valueOf,
    required this.effectiveOf,
    required this.onChanged,
  });

  final String title;
  final List<PermissionDef> defs;
  final bool open;
  final VoidCallback onToggleOpen;
  final bool Function(String key) valueOf;
  final bool Function(PermissionDef def) effectiveOf;
  final void Function(PermissionDef def, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final on = defs.where(effectiveOf).length;
    final accent = on > 0 ? Brand.success : b.paperDim;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: EdgeInsets.zero,
        radius: Brand.radiusLg,
        borderColor: on > 0 ? Brand.success.withValues(alpha: 0.35) : b.rule,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(Brand.radiusLg),
              onTap: onToggleOpen,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(child: Text(title, style: text.titleSmall)),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.9,
                            end: 1,
                          ).animate(anim),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: GlowBadge(
                          key: ValueKey('$on/${defs.length}'),
                          label: '$on of ${defs.length}',
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: b.paperDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: Duration(milliseconds: reduce ? 0 : 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !open
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Column(
                        children: [
                          for (var i = 0; i < defs.length; i++) ...[
                            if (i > 0 && defs[i].parent == null)
                              const Hairline(),
                            PermissionToggleRow(
                              label: defs[i].label,
                              hint: defs[i].hint,
                              child: defs[i].parent != null,
                              enabled:
                                  defs[i].parent == null ||
                                  valueOf(defs[i].parent!),
                              value: valueOf(defs[i].key),
                              onChanged: (v) => onChanged(defs[i], v),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class PermissionMeter extends StatelessWidget {
  const PermissionMeter({super.key, required this.value, required this.total});

  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final ratio = total == 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Semantics(
      label: '$value of $total permissions enabled',
      child: LayoutBuilder(
        builder: (context, c) => Container(
          height: 6,
          decoration: BoxDecoration(
            color: b.surfaceHi,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: reduce ? ratio : 0, end: ratio),
              duration: Duration(milliseconds: reduce ? 0 : 420),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => Container(
                width: c.maxWidth * t,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Brand.orange,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
