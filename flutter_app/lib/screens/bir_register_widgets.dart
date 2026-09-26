import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bir_register_logic.dart';
import '../theme.dart';
import '../widgets/premium.dart';

void birToast(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: action,
      ),
    );
}

IconData birFileIcon(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
  if (n.endsWith('.doc') || n.endsWith('.docx')) {
    return Icons.description_rounded;
  }
  if (RegExp(r'\.(png|jpe?g|gif|webp|heic|heif|bmp|tiff?)$').hasMatch(n)) {
    return Icons.image_rounded;
  }
  return Icons.insert_drive_file_rounded;
}

bool birIsImage(String name) =>
    RegExp(r'\.(png|jpe?g|gif|webp|bmp)$').hasMatch(name.toLowerCase());

class BirStepper extends StatelessWidget {
  const BirStepper({super.key, required this.steps, required this.current});

  final List<String> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final upcoming = Colors.white.withValues(alpha: 0.42);
    final idleLine = Colors.white.withValues(alpha: 0.16);
    const node = 30.0;
    final count = steps.length;
    final index = count == 0 ? 0 : current.clamp(0, count - 1);
    final fraction = count < 2 ? 1.0 : index / (count - 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = constraints.maxWidth / (count == 0 ? 1 : count);
        final first = cell / 2;
        final span = math.max(0.0, constraints.maxWidth - cell);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: node,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: first,
                    top: node / 2 - 1.5,
                    width: span,
                    height: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: idleLine,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    left: first,
                    top: node / 2 - 1.5,
                    height: 3,
                    child: AnimatedContainer(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      width: span * fraction,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: Brand.orange,
                      ),
                    ),
                  ),
                  for (var i = 0; i < count; i++)
                    Positioned(
                      left: first + i * cell - node / 2,
                      top: 0,
                      width: node,
                      height: node,
                      child: _StepNode(
                        index: i,
                        done: i < index,
                        active: i == index,
                        duration: duration,
                        upcoming: upcoming,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: Semantics(
                      label:
                          'Step ${i + 1} of $count, ${steps[i]}, ${i < index ? 'completed' : (i == index ? 'current' : 'upcoming')}',
                      excludeSemantics: true,
                      child: AnimatedDefaultTextStyle(
                        duration: duration,
                        style: (text.labelMedium ?? const TextStyle()).copyWith(
                          color: i == index
                              ? Brand.orange
                              : (i < index ? Colors.white : upcoming),
                          fontWeight: i == index
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        child: Text(
                          steps[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.index,
    required this.done,
    required this.active,
    required this.duration,
    required this.upcoming,
  });

  final int index;
  final bool done;
  final bool active;
  final Duration duration;
  final Color upcoming;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: duration,
      curve: Curves.easeOutCubic,
      scale: active ? 1 : 0.86,
      child: AnimatedContainer(
        duration: duration,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? Brand.orange
              : (done ? Colors.white : Colors.white.withValues(alpha: 0.06)),
          border: Border.all(
            color: active
                ? Colors.white.withValues(alpha: 0.85)
                : (done ? Colors.white : upcoming),
            width: 1.5,
          ),
        ),
        child: done
            ? const Icon(Icons.check_rounded, size: 16, color: Brand.navy)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  color: active ? Colors.white : upcoming,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class BirSection extends StatelessWidget {
  const BirSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.trailing,
    this.iconColor,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final String? subtitle;
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final accent = iconColor ?? b.signal;
    return AppCard(
      padding: const EdgeInsets.all(16),
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  color: accent.withValues(alpha: 0.14),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class BirLabeled extends StatelessWidget {
  const BirLabeled({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.bottom = 14,
  });

  final String label;
  final Widget child;
  final bool required;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (required)
                    const TextSpan(
                      text: ' *',
                      semanticsLabel: ', required',
                      style: TextStyle(
                        color: Brand.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: b.paper,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class BirField extends StatelessWidget {
  const BirField({
    super.key,
    required this.label,
    required this.controller,
    this.required = false,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.onChanged,
    this.readOnly = false,
    this.prefixIcon,
    this.errorText,
    this.bottom = 14,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
    this.inputFormatters,
    this.onTap,
    this.suffix,
    this.highlight = false,
  });

  final String label;
  final TextEditingController controller;
  final bool required;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final IconData? prefixIcon;
  final String? errorText;
  final double bottom;
  final TextCapitalization textCapitalization;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final VoidCallback? onTap;
  final Widget? suffix;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return BirLabeled(
      label: label,
      required: required,
      bottom: bottom,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        maxLines: maxLines,
        minLines: 1,
        readOnly: readOnly,
        onTap: onTap,
        onChanged: onChanged,
        inputFormatters: inputFormatters,
        textCapitalization: textCapitalization,
        style: readOnly ? TextStyle(color: b.paperDim) : null,
        decoration: InputDecoration(
          hintText: hint ?? label,
          errorText: errorText,
          errorMaxLines: 3,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
          suffixIcon: suffix,
          enabledBorder: highlight
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
                  borderSide: const BorderSide(color: Brand.danger),
                )
              : null,
        ),
      ),
    );
  }
}

class BirDropdown<T> extends StatelessWidget {
  const BirDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.hint,
    this.icon,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final safe = items.any((i) => i.value == value) ? value : null;
    return DropdownButtonFormField<T>(
      key: ValueKey<Object?>('dd-$hint-$safe-${items.length}'),
      initialValue: safe,
      isExpanded: true,
      dropdownColor: b.surface,
      borderRadius: BorderRadius.circular(Brand.radius),
      icon: const Icon(Icons.expand_more_rounded),
      decoration: InputDecoration(
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
      ),
      hint: Text(
        hint,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: b.paperDim),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class BirUploadTile extends StatefulWidget {
  const BirUploadTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.hint,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? hint;
  final bool busy;

  @override
  State<BirUploadTile> createState() => _BirUploadTileState();
}

class _BirUploadTileState extends State<BirUploadTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );
  bool _pressed = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _entry.value = 1;
    } else {
      _entry.forward();
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final enabled = widget.onTap != null;
    final accent = enabled ? b.signal : b.paperDim;
    final accentText = enabled ? b.signalInk : b.paperDim;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final radius = BorderRadius.circular(Brand.radiusLg);
    final tile = Semantics(
      button: true,
      enabled: enabled,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: enabled ? b.tint(b.signal, 0.1) : b.surfaceHi,
            ),
            child: InkWell(
              onTap: widget.onTap,
              onTapDown: enabled ? (_) => _setPressed(true) : null,
              onTapUp: enabled ? (_) => _setPressed(false) : null,
              onTapCancel: enabled ? () => _setPressed(false) : null,
              borderRadius: radius,
              child: CustomPaint(
                painter: BirDashedBorderPainter(
                  color: enabled ? b.tint(b.signal, 0.6) : b.rule,
                  radius: Brand.radiusLg,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 22,
                    horizontal: 16,
                  ),
                  child: Column(
                    children: [
                      if (widget.busy)
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: b.signal,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: b.tint(accent, 0.16),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Icon(widget.icon, size: 24, color: accent),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        style: text.titleSmall?.copyWith(color: accentText),
                      ),
                      if (widget.hint != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.hint!,
                          textAlign: TextAlign.center,
                          style: text.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final pressable = AnimatedScale(
      scale: _pressed ? 0.975 : 1,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: tile,
    );
    if (reduce) return pressable;
    return AnimatedBuilder(
      animation: _entry,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_entry.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
          ),
        );
      },
      child: pressable,
    );
  }
}

class BirDashedBorderPainter extends CustomPainter {
  BirDashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(0.6);
    final path = Path()..addRRect(rrect);
    const dash = 7.0;
    const gap = 5.0;
    final segments = <Path>[];
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        segments.add(metric.extractPath(distance, end));
        distance += dash + gap;
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final segment in segments) {
      canvas.drawPath(segment, paint);
    }
  }

  @override
  bool shouldRepaint(BirDashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

class BirFileRow extends StatelessWidget {
  const BirFileRow({
    super.key,
    required this.name,
    this.caption,
    this.done = false,
    this.onRemove,
    this.onView,
    this.icon,
    this.iconColor,
  });

  final String name;
  final String? caption;
  final bool done;
  final VoidCallback? onRemove;
  final VoidCallback? onView;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final accent = iconColor ?? (done ? Brand.success : b.signal);
    return FadeSlideIn(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Brand.radius),
          color: b.tint(accent, 0.1),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            IconTile(
              icon: icon ?? birFileIcon(name),
              color: iconColor ?? (done ? Brand.success : b.signal),
              size: 34,
              iconSize: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: text.bodySmall?.copyWith(
                        color: done ? Brand.success : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onView != null)
              TextButton.icon(
                onPressed: onView,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.visibility_rounded, size: 16),
                label: const Text('View'),
              ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, size: 18, color: b.paperDim),
              ),
          ],
        ),
      ),
    );
  }
}

class BirNotice extends StatelessWidget {
  const BirNotice({
    super.key,
    required this.color,
    required this.icon,
    this.title,
    required this.message,
    this.bottom = 14,
  });

  final Color color;
  final IconData icon;
  final String? title;
  final String message;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: EdgeInsets.only(bottom: bottom),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        color: b.tint(color, 0.14),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: text.titleSmall?.copyWith(color: color)),
                  const SizedBox(height: 2),
                ],
                Text(message, style: text.bodySmall?.copyWith(color: b.paper)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BirBadge extends StatelessWidget {
  const BirBadge({
    super.key,
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: b.tint(color, 0.12),
          borderRadius: BorderRadius.circular(Brand.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BirCombo extends StatefulWidget {
  const BirCombo({
    super.key,
    required this.controller,
    required this.options,
    required this.hint,
    this.onChanged,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final List<String> options;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool readOnly;

  @override
  State<BirCombo> createState() => _BirComboState();
}

class _BirComboState extends State<BirCombo> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        if (widget.readOnly) return const Iterable<String>.empty();
        final q = value.text.toLowerCase();
        return widget.options.where(
          (o) => q.isEmpty || o.toLowerCase().contains(q),
        );
      },
      onSelected: (v) => widget.onChanged?.call(v),
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          readOnly: widget.readOnly,
          onChanged: widget.onChanged,
          style: widget.readOnly ? TextStyle(color: b.paperDim) : null,
          decoration: InputDecoration(
            hintText: widget.hint,
            suffixIcon: Icon(
              Icons.expand_more_rounded,
              size: 20,
              color: b.paperDim,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: b.surface,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
              side: BorderSide(color: b.rule),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 260),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    InkWell(
                      onTap: () => onSelected(o),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(o),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class BirSerialField extends StatefulWidget {
  const BirSerialField({
    super.key,
    required this.controller,
    required this.search,
    this.onChanged,
    this.onSelected,
    this.errorText,
  });

  final TextEditingController controller;
  final Future<List<LicenseSerialSuggestion>> Function(String) search;
  final ValueChanged<String>? onChanged;
  final ValueChanged<LicenseSerialSuggestion>? onSelected;
  final String? errorText;

  @override
  State<BirSerialField> createState() => _BirSerialFieldState();
}

class _BirSerialFieldState extends State<BirSerialField> {
  final _focus = FocusNode();
  Timer? _debounce;
  String _lastQuery = '';
  List<LicenseSerialSuggestion> _lastResults = const [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.dispose();
    super.dispose();
  }

  Future<Iterable<LicenseSerialSuggestion>> _options(TextEditingValue value) {
    final q = value.text.trim();
    _debounce?.cancel();
    if (q.length < 2) {
      _lastQuery = '';
      _lastResults = const [];
      if (_loading) setState(() => _loading = false);
      return Future.value(const <LicenseSerialSuggestion>[]);
    }
    if (q == _lastQuery) {
      return Future.value(_lastResults);
    }
    final completer = Completer<Iterable<LicenseSerialSuggestion>>();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (mounted) setState(() => _loading = true);
      final hits = await widget.search(q);
      _lastQuery = q;
      _lastResults = hits;
      if (mounted) setState(() => _loading = false);
      if (!completer.isCompleted) completer.complete(hits);
    });
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return BirLabeled(
      label: 'Serial Number',
      child: LayoutBuilder(
        builder: (context, constraints) {
          return RawAutocomplete<LicenseSerialSuggestion>(
            textEditingController: widget.controller,
            focusNode: _focus,
            optionsBuilder: _options,
            displayStringForOption: (hit) => hit.serial,
            onSelected: (hit) => widget.onSelected?.call(hit),
            fieldViewBuilder: (context, controller, focusNode, onSubmit) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: widget.onChanged,
                decoration: InputDecoration(
                  hintText: 'Search serial, business name, or license key',
                  errorText: widget.errorText,
                  errorMaxLines: 3,
                  prefixIcon: const Icon(Icons.qr_code_rounded, size: 20),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: b.surface,
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
                    side: BorderSide(color: b.rule),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 260,
                      maxWidth: constraints.maxWidth,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shrinkWrap: true,
                      children: [
                        for (final hit in options)
                          InkWell(
                            onTap: hit.selectable
                                ? () => onSelected(hit)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          hit.title,
                                          style: text.bodyMedium?.copyWith(
                                            fontWeight: hit.selectable
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            fontStyle: hit.selectable
                                                ? null
                                                : FontStyle.italic,
                                            color: hit.taken || !hit.selectable
                                                ? b.paperDim
                                                : null,
                                          ),
                                        ),
                                      ),
                                      if (hit.taken)
                                        const Icon(
                                          Icons.block_rounded,
                                          size: 16,
                                          color: Brand.danger,
                                        ),
                                    ],
                                  ),
                                  if (hit.detail.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        hit.detail,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.labelSmall?.copyWith(
                                          color: hit.taken
                                              ? Brand.danger
                                              : b.paperDim,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class BirSnRow {
  BirSnRow({
    this.type = '',
    this.serverType = '',
    String sn = '',
    String brand = '',
    String model = '',
  }) : sn = TextEditingController(text: sn),
       brand = TextEditingController(text: brand),
       model = TextEditingController(text: model);

  String type;
  String serverType;
  final TextEditingController sn;
  final TextEditingController brand;
  final TextEditingController model;
  String dupMessage = '';
  bool dupFromDb = false;

  bool get isDuplicate => dupMessage.isNotEmpty;

  Map<String, String> toEntry() => {
    'serial_number_type': type,
    'server_type': serverType,
    'serial_number': sn.text,
    'brand': brand.text,
    'model': model.text,
  };

  void dispose() {
    sn.dispose();
    brand.dispose();
    model.dispose();
  }
}

class BirBottomBar extends StatelessWidget {
  const BirBottomBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: b.surface,
        border: Border(top: BorderSide(color: b.signal.withValues(alpha: 0.3))),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(children: children),
        ),
      ),
    );
  }
}

Future<bool> birConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Discard',
  String cancel = 'Keep editing',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 12,
    this.duration = const Duration(milliseconds: 280),
    this.stagger = const Duration(milliseconds: 55),
    this.maxDelay = const Duration(milliseconds: 330),
  });

  final Widget child;
  final int index;
  final double offset;
  final Duration duration;
  final Duration stagger;
  final Duration maxDelay;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _delay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.value = 1;
      return;
    }
    var wait = widget.stagger * widget.index;
    if (wait > widget.maxDelay) wait = widget.maxDelay;
    if (wait == Duration.zero) {
      _c.forward();
    } else {
      _delay = Timer(wait, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class GlowStatusPill extends StatelessWidget {
  const GlowStatusPill({
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

  static Color inkFor(BuildContext context, Color c) {
    if (context.brand.isDark) return c;
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness * 0.6).clamp(0.0, 1.0)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final c = color ?? StatusPill.colorFor(label);
    final ink = inkFor(context, c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: c.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BirScanRing extends StatefulWidget {
  const BirScanRing({
    super.key,
    required this.progress,
    required this.complete,
    required this.child,
    this.size = 190,
  });

  final double progress;
  final bool complete;
  final Widget child;
  final double size;

  @override
  State<BirScanRing> createState() => _BirScanRingState();
}

class _BirScanRingState extends State<BirScanRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BirScanRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || widget.complete) {
      if (_sweep.isAnimating) _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = widget.complete ? Brand.success : b.signal;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: widget.progress.clamp(0.0, 1.0)),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        builder: (context, value, child) => AnimatedBuilder(
          animation: _sweep,
          builder: (context, inner) => CustomPaint(
            painter: _ScanRingPainter(
              progress: value,
              sweep: _sweep.value,
              accent: accent,
              track: b.tint(accent, 0.14),
              tick: b.tint(b.paperDim, 0.1),
              showSweep: !widget.complete && !reduce,
            ),
            child: inner,
          ),
          child: child,
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _ScanRingPainter extends CustomPainter {
  _ScanRingPainter({
    required this.progress,
    required this.sweep,
    required this.accent,
    required this.track,
    required this.tick,
    required this.showSweep,
  });

  final double progress;
  final double sweep;
  final Color accent;
  final Color track;
  final Color tick;
  final bool showSweep;

  @override
  void paint(Canvas canvas, Size size) {
    final center = (Offset.zero & size).center;
    const stroke = 9.0;
    final radius = math.min(size.width, size.height) / 2 - 16;
    if (radius <= 0) return;
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    const ticks = 48;
    final tickPaint = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < ticks; i++) {
      final angle = -math.pi / 2 + i * 2 * math.pi / ticks;
      final lit = i / ticks <= progress;
      tickPaint.color = lit ? accent.withValues(alpha: 0.5) : tick;
      final inner = radius + stroke / 2 + 3;
      final outer = inner + (lit ? 5 : 3);
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        tickPaint,
      );
    }
    if (showSweep) {
      const arc = math.pi / 3;
      canvas.drawArc(
        arcRect,
        -math.pi / 2 + sweep * 2 * math.pi,
        arc,
        false,
        Paint()
          ..color = accent.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    if (progress > 0) {
      final extent = 2 * math.pi * progress;
      canvas.drawArc(
        arcRect,
        -math.pi / 2,
        extent,
        false,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
      final headAngle = -math.pi / 2 + extent;
      final head =
          center +
          Offset(math.cos(headAngle) * radius, math.sin(headAngle) * radius);
      canvas.drawCircle(head, stroke / 2 - 1.5, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_ScanRingPainter old) =>
      old.progress != progress ||
      old.sweep != sweep ||
      old.accent != accent ||
      old.track != track ||
      old.tick != tick ||
      old.showSweep != showSweep;
}

class BirScanLine extends StatelessWidget {
  const BirScanLine({
    super.key,
    required this.label,
    required this.done,
    required this.active,
    this.index = 0,
  });

  final String label;
  final bool done;
  final bool active;
  final int index;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Widget leading = done
        ? const Icon(Icons.check_circle_rounded, size: 18, color: Brand.success)
        : active
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: b.signal),
          )
        : Icon(
            Icons.radio_button_unchecked_rounded,
            size: 18,
            color: b.paperDim,
          );
    return FadeSlideIn(
      index: index,
      offset: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(width: 18, height: 18, child: Center(child: leading)),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                child: Text(
                  label,
                  key: ValueKey<String>(label),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: active || done ? b.paper : b.paperDim,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
