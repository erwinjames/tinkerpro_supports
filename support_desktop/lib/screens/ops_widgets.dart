import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/tp_loader.dart';

const opsRed = Color(0xFFDC2626);
const opsAmber = Color(0xFFD97706);
const opsGreen = Color(0xFF16A34A);
const opsBlue = Color(0xFF2563EB);
const opsNavy = Color(0xFF0C233E);

String opsStr(dynamic v) => v == null ? '' : v.toString();
int opsInt(dynamic v) => v is int ? v : int.tryParse(opsStr(v)) ?? 0;

DateTime? opsParseDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String opsShortDate(DateTime d) =>
    '${_months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';

String opsFullDate(String raw) {
  final d = opsParseDate(raw);
  if (d == null) return raw.isEmpty ? '—' : raw;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${opsShortDate(d)}, ${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ap';
}

String opsTimeAgo(String raw) {
  final d = opsParseDate(raw);
  if (d == null) return raw;
  final diff = DateTime.now().difference(d).inSeconds.clamp(0, 1 << 31);
  if (diff < 60) return 'just now';
  if (diff < 3600) return '${diff ~/ 60}m ago';
  if (diff < 86400) return '${diff ~/ 3600}h ago';
  if (diff < 86400 * 7) return '${diff ~/ 86400}d ago';
  return opsShortDate(d);
}

class OpsBadge extends StatelessWidget {
  const OpsBadge({
    super.key,
    required this.label,
    required this.fg,
    required this.bg,
    this.dot = true,
  });

  final String label;
  final Color fg;
  final Color bg;
  final bool dot;

  factory OpsBadge.tone(String label, Color c) =>
      OpsBadge(label: label, fg: c, bg: c.withValues(alpha: 0.12));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
        ],
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: fg,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            height: 1.4,
          ),
        ),
      ]),
    );
  }
}

class OpsPill extends StatefulWidget {
  const OpsPill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
    this.dark = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? count;
  final bool dark;

  @override
  State<OpsPill> createState() => _OpsPillState();
}

class _OpsPillState extends State<OpsPill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final activeBg = widget.dark ? const Color(0xFF0F172A) : Brand.signal;
    final fg = widget.active
        ? Colors.white
        : (_hover && !widget.dark ? Brand.signal : b.paper);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: widget.active
                ? activeBg
                : (_hover && widget.dark ? b.surfaceHi : b.surface),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.active
                  ? activeBg
                  : (_hover && !widget.dark ? Brand.signal : b.rule),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              widget.label,
              style: TextStyle(
                color: fg,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: widget.active
                      ? Colors.white.withValues(alpha: 0.22)
                      : (widget.dark
                          ? b.surfaceHi
                          : Brand.signal.withValues(alpha: 0.10)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.count!,
                  style: TextStyle(
                    color: widget.active
                        ? Colors.white
                        : (widget.dark ? b.paperDim : Brand.signal),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class OpsSelect<T> extends StatelessWidget {
  const OpsSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 140,
    this.height = 40,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: b.rule),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down, size: 16, color: b.paperDim),
          style: TextStyle(color: b.paper, fontSize: 14, fontFamily: kFontFamily),
          borderRadius: BorderRadius.circular(8),
          items: [
            for (final (v, l) in items)
              DropdownMenuItem<T>(value: v, child: Text(l)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class OpsButton extends StatefulWidget {
  const OpsButton({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.onPressed,
    this.outlined = false,
    this.busy = false,
    this.dashedMuted = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool busy;
  final bool dashedMuted;

  @override
  State<OpsButton> createState() => _OpsButtonState();
}

class _OpsButtonState extends State<OpsButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final muted = widget.dashedMuted;
    final enabled = widget.onPressed != null && !widget.busy && !muted;
    final Color bg;
    final Color fg;
    final Color border;
    if (muted) {
      bg = const Color(0xFFF1F3F6);
      fg = const Color(0xFF6B7280);
      border = const Color(0xFFD6DAE1);
    } else if (widget.outlined) {
      bg = _hover && enabled
          ? widget.color.withValues(alpha: 0.10)
          : Colors.transparent;
      fg = widget.color;
      border = widget.color;
    } else {
      bg = _hover && enabled
          ? Color.lerp(widget.color, Colors.black, 0.1)!
          : widget.color;
      fg = Colors.white;
      border = bg;
    }
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: Opacity(
          opacity: widget.busy ? 0.7 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (widget.busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: TpLoader(strokeWidth: 2, color: fg),
                )
              else if (widget.icon != null)
                Icon(widget.icon, size: 14, color: fg),
              if (widget.busy || widget.icon != null) const SizedBox(width: 7),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class OpsField extends StatelessWidget {
  const OpsField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.hint,
  });

  final String label;
  final Widget child;
  final bool required;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: label),
            if (required)
              const TextSpan(text: ' *', style: TextStyle(color: opsRed)),
          ]),
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: b.paper)),
          const SizedBox(height: 6),
          child,
          if (hint != null && hint!.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(hint!, style: TextStyle(fontSize: 12, color: b.paperDim)),
          ],
        ],
      ),
    );
  }
}

void opsToast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? opsRed : null,
    duration: const Duration(seconds: 3),
  ));
}

Future<bool> opsConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Delete',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: opsRed),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r == true;
}

Future<bool> opsUndoWindow(BuildContext context, String message) async {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return true;
  var undone = false;
  m.hideCurrentSnackBar();
  final c = m.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 5),
    persist: false,
    action: SnackBarAction(label: 'Undo', onPressed: () => undone = true),
  ));
  await c.closed;
  if (undone) {
    m.showSnackBar(const SnackBar(
      content: Text('Delete undone'),
      duration: Duration(milliseconds: 1800),
    ));
  }
  return !undone;
}
