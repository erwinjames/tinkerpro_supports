import 'package:flutter/material.dart';

import '../theme.dart';
import 'bir_widgets.dart';
import '../widgets/tp_loader.dart';

const birV1Orange = Color(0xFFFF7D00);
const birV1Danger = Color(0xFFDC3545);

Widget birV1StatusBadge(String status) {
  if (status == 'completed') {
    return const BirBadge(label: 'Completed', bg: Color(0xFF28A745));
  }
  if (status == 'for_ptu') {
    return const BirBadge(
      label: 'For PTU',
      bg: Color(0xFFFFC107),
      fg: Color(0xFF212529),
    );
  }
  return const BirBadge(label: 'Draft', bg: Color(0xFF6C757D));
}

class BirV1Pill extends StatelessWidget {
  const BirV1Pill({super.key, this.label = 'V1'});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF9A3412),
        ),
      ),
    );
  }
}

class BirV1Note extends StatelessWidget {
  const BirV1Note(this.text, {super.key, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: const Color(0xFF9A3412)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Color(0xFF9A3412)),
            ),
          ),
        ],
      ),
    );
  }
}

class BirV1Shell extends StatelessWidget {
  const BirV1Shell({
    super.key,
    required this.title,
    required this.child,
    this.width = 800,
    this.scrollable = true,
  });

  final String title;
  final Widget child;
  final double width;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              child: Row(
                children: [
                  const BirV1Pill(),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF212529),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: child,
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: child,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget birV1Label(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: Color(0xFF64748B),
    ),
  ),
);

InputDecoration birV1InputDecoration({String? hint, Widget? suffix}) =>
    InputDecoration(
      isDense: true,
      hintText: hint,
      counterText: '',
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Brand.inputBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: Brand.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: birV1Orange),
      ),
    );

class _SwalIcon extends StatelessWidget {
  const _SwalIcon(this.kind);
  final String kind;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (kind) {
      'success' => (Icons.check, const Color(0xFFA5DC86)),
      'error' => (Icons.close, const Color(0xFFF27474)),
      'warning' => (Icons.priority_high, const Color(0xFFF8BB86)),
      _ => (Icons.info_outline, const Color(0xFF3FC3EE)),
    };
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.6), width: 4),
      ),
      child: Icon(icon, color: color, size: 40),
    );
  }
}

Future<bool> _swal(
  BuildContext context, {
  required String icon,
  required String title,
  String text = '',
  String confirm = 'OK',
  Color confirmColor = birV1Orange,
  bool cancel = false,
  Widget? extra,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SwalIcon(icon),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF545454),
                ),
              ),
              if (text.isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15.5,
                    color: Color(0xFF545454),
                  ),
                ),
              ],
              ?extra,
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  BirSolidButton(
                    label: confirm,
                    color: confirmColor,
                    height: 40,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                  if (cancel) ...[
                    const SizedBox(width: 8),
                    BirSolidButton(
                      label: 'Cancel',
                      color: const Color(0xFF6E7881),
                      height: 40,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return r == true;
}

Future<void> birV1Toast(
  BuildContext context,
  String icon,
  String title, [
  String text = '',
]) async {
  if (!context.mounted) return;
  await _swal(context, icon: icon, title: title, text: text);
}

Future<bool> birV1Confirm(
  BuildContext context, {
  required String title,
  required String text,
  String confirm = 'Delete',
}) async {
  if (!context.mounted) return false;
  return _swal(
    context,
    icon: 'warning',
    title: title,
    text: text,
    confirm: confirm,
    confirmColor: birV1Danger,
    cancel: true,
  );
}

Future<String?> birV1EmailPrompt(BuildContext context, String initial) {
  final c = TextEditingController(text: initial);
  String? error;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        void submit() {
          final v = c.text.trim();
          if (v.isEmpty) {
            setS(() => error = 'Enter an email address.');
            return;
          }
          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
            setS(() => error = 'Invalid email address');
            return;
          }
          Navigator.of(ctx).pop(v);
        }

        return Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Send to email',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF545454),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: c,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: birV1InputDecoration(hint: 'Email address'),
                    onSubmitted: (_) => submit(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      color: const Color(0xFFF0F0F0),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error,
                            size: 18,
                            color: Color(0xFFF27474),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            error!,
                            style: const TextStyle(color: Color(0xFF666666)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BirSolidButton(
                        label: 'Send',
                        height: 40,
                        onPressed: submit,
                      ),
                      const SizedBox(width: 8),
                      BirSolidButton(
                        label: 'Cancel',
                        color: const Color(0xFF6E7881),
                        height: 40,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

void birV1ShowLoading(BuildContext context, String title, String text) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF545454),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15.5,
                    color: Color(0xFF545454),
                  ),
                ),
                const SizedBox(height: 18),
                const TpLoader(
                  strokeWidth: 3,
                  color: birV1Orange,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
