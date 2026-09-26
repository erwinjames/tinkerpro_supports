import 'package:flutter/material.dart';

import '../theme.dart';
import 'bir_widgets.dart';
import '../widgets/tp_loader.dart';

enum BirToastKind { success, info, warning, error }

void birToast(
  BuildContext context,
  String message, {
  BirToastKind kind = BirToastKind.info,
  Duration duration = const Duration(milliseconds: 2500),
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final color = switch (kind) {
    BirToastKind.success => const Color(0xFF16A34A),
    BirToastKind.info => const Color(0xFF0EA5E9),
    BirToastKind.warning => const Color(0xFFF59E0B),
    BirToastKind.error => const Color(0xFFDC2626),
  };
  final icon = switch (kind) {
    BirToastKind.success => Icons.check_circle,
    BirToastKind.info => Icons.info,
    BirToastKind.warning => Icons.warning_amber_rounded,
    BirToastKind.error => Icons.error,
  };
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: duration,
        persist: false,
        behavior: SnackBarBehavior.floating,
        width: 420,
        action: action,
        content: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

class BirLoading {
  BirLoading._(this._nav);
  final NavigatorState _nav;
  bool _closed = false;

  static BirLoading show(
    BuildContext context, {
    required String title,
    required String text,
  }) {
    final nav = Navigator.of(context, rootNavigator: true);
    final h = BirLoading._(nav);
    showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: SizedBox(
            width: 420,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 30, 28, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF545454),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF545454),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: TpLoader(
                      strokeWidth: 3,
                      color: Brand.signal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return h;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_nav.mounted) _nav.pop();
  }
}

enum BirAlertIcon { success, error, warning }

Future<bool> birAlert(
  BuildContext context, {
  required BirAlertIcon icon,
  required String title,
  required String text,
  String confirmLabel = 'OK',
  String? cancelLabel,
  Color confirmColor = Brand.signal,
}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final color = switch (icon) {
    BirAlertIcon.success => const Color(0xFFA5DC86),
    BirAlertIcon.error => const Color(0xFFF27474),
    BirAlertIcon.warning => const Color(0xFFF8BB86),
  };
  final glyph = switch (icon) {
    BirAlertIcon.success => Icons.check,
    BirAlertIcon.error => Icons.close,
    BirAlertIcon.warning => Icons.priority_high,
  };
  final r = await showDialog<bool>(
    context: nav.context,
    useRootNavigator: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: SizedBox(
        width: 460,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 4),
                ),
                child: Icon(glyph, color: color, size: 44),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF545454),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF545454)),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (cancelLabel != null) ...[
                    BirSolidButton(
                      label: cancelLabel,
                      color: const Color(0xFF6C757D),
                      height: 42,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                    const SizedBox(width: 10),
                  ],
                  BirSolidButton(
                    label: confirmLabel,
                    color: confirmColor,
                    height: 42,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
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
