import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../widgets/tp_loader.dart';

const Color birNavy = Color(0xFF0C233E);
const Color birOrange = Color(0xFFFF7D00);

void birToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Brand.danger : null,
        duration: Duration(milliseconds: error ? 4500 : 2000),
      ),
    );
}

class BirNavyModal extends StatelessWidget {
  const BirNavyModal({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.kicker,
    this.footer,
    this.width = 520,
    this.onClose,
    this.closeEnabled = true,
    this.headerTrailing,
    this.subtitleWidget,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? subtitle;
  final String? kicker;
  final Widget? footer;
  final double width;
  final VoidCallback? onClose;
  final bool closeEnabled;
  final Widget? headerTrailing;
  final Widget? subtitleWidget;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final close = onClose ?? () => Navigator.of(context).maybePop();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (closeEnabled) close();
        },
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(32),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width.clamp(320.0, screen.width - 64).toDouble(),
            minWidth: width.clamp(320.0, screen.width - 64).toDouble(),
            maxHeight: screen.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: birNavy,
                padding: const EdgeInsets.fromLTRB(28, 22, 16, 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (kicker != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: birOrange.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                kicker!.toUpperCase(),
                                style: const TextStyle(
                                  color: birOrange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.9,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: birOrange,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  icon,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              subtitle!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.62),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (subtitleWidget != null) ...[
                            const SizedBox(height: 8),
                            subtitleWidget!,
                          ],
                        ],
                      ),
                    ),
                    if (headerTrailing != null) ...[
                      const SizedBox(width: 12),
                      headerTrailing!,
                    ],
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: closeEnabled ? close : null,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                      ),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.white.withValues(
                          alpha: closeEnabled ? 1 : 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(child: child),
              ?footer,
            ],
          ),
        ),
      ),
    );
  }
}

class BirPdfDropZone extends StatelessWidget {
  const BirPdfDropZone({super.key, required this.onTap, this.multiple = false});

  final VoidCallback? onTap;
  final bool multiple;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: CustomPaint(
        painter: _DashPainter(),
        child: Container(
          constraints: const BoxConstraints(minHeight: 220),
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: birOrange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  color: birOrange,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                multiple ? 'Choose your PDF files' : 'Choose your PDF',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: birNavy,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Click to browse from your device',
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Select PDF File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: birOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: birOrange.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.picture_as_pdf,
                      size: 13,
                      color: Color(0xFFC26200),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'PDF files only',
                      style: TextStyle(
                        color: Color(0xFFC26200),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BirFileChip extends StatelessWidget {
  const BirFileChip({super.key, required this.name, this.onRemove});

  final String name;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5E5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: birOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.picture_as_pdf, color: birOrange, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: birNavy,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove file',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16, color: birNavy),
          ),
        ],
      ),
    );
  }
}

class BirPrimaryButton extends StatelessWidget {
  const BirPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward,
    this.busy = false,
    this.busyLabel = 'Processing...',
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;
  final bool busy;
  final String busyLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: birOrange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(
            0xFF4D79C5,
          ).withValues(alpha: 0.7),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: TpLoader(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(busy ? busyLabel : label),
          ],
        ),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD4D4D4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      );
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
