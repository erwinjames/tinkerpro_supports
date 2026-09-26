import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class FileTypeStyle {
  const FileTypeStyle(this.icon, this.color, this.label);
  final IconData icon;
  final Color color;
  final String label;

  static FileTypeStyle of(String filename) {
    final dot = filename.lastIndexOf('.');
    final ext = dot < 0 ? '' : filename.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'pdf':
        return const FileTypeStyle(
          Icons.picture_as_pdf_rounded,
          Color(0xFFE5484D),
          'PDF',
        );
      case 'doc':
      case 'docx':
      case 'rtf':
      case 'odt':
        return const FileTypeStyle(
          Icons.description_rounded,
          Color(0xFF3B82F6),
          'DOC',
        );
      case 'xls':
      case 'xlsx':
      case 'csv':
      case 'ods':
        return const FileTypeStyle(
          Icons.table_chart_rounded,
          Color(0xFF16A34A),
          'XLS',
        );
      case 'ppt':
      case 'pptx':
      case 'odp':
        return const FileTypeStyle(
          Icons.slideshow_rounded,
          Color(0xFFF97316),
          'PPT',
        );
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'svg':
      case 'heic':
        return const FileTypeStyle(
          Icons.image_rounded,
          Color(0xFF8B5CF6),
          'IMG',
        );
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
        return const FileTypeStyle(
          Icons.movie_rounded,
          Color(0xFFEC4899),
          'VID',
        );
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'm4a':
        return const FileTypeStyle(
          Icons.audiotrack_rounded,
          Color(0xFF0EA5E9),
          'AUD',
        );
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return const FileTypeStyle(
          Icons.folder_zip_rounded,
          Color(0xFFF59E0B),
          'ZIP',
        );
      case 'apk':
      case 'exe':
      case 'msi':
      case 'dmg':
      case 'deb':
      case 'appimage':
        return const FileTypeStyle(
          Icons.install_desktop_rounded,
          Color(0xFF14B8A6),
          'APP',
        );
      case 'txt':
      case 'md':
      case 'log':
      case 'json':
      case 'xml':
        return const FileTypeStyle(
          Icons.article_rounded,
          Color(0xFF64748B),
          'TXT',
        );
      default:
        return FileTypeStyle(
          Icons.insert_drive_file_rounded,
          const Color(0xFF64748B),
          ext.isEmpty ? 'FILE' : ext.toUpperCase(),
        );
    }
  }
}

Color chipInk(BuildContext context, Color color) {
  final b = context.brand;
  if (b.isDark) {
    return color.computeLuminance() < 0.22
        ? Color.lerp(color, Colors.white, 0.6)!
        : color;
  }
  return color.computeLuminance() > 0.3
      ? Color.lerp(color, Brand.navy, 0.45)!
      : color;
}

class FileTypeTile extends StatelessWidget {
  const FileTypeTile({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 21,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: iconSize, color: chipInk(context, color)),
    );
  }
}

class FileChip extends StatelessWidget {
  const FileChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final ink = chipInk(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class Stagger extends StatelessWidget {
  const Stagger({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || index > 7) return child;
    final delay = index * 45;
    final total = 280 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, inner) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

class UploadRing extends StatefulWidget {
  const UploadRing({
    super.key,
    required this.progress,
    required this.busy,
    required this.color,
    required this.icon,
  });

  final double progress;
  final bool busy;
  final Color color;
  final IconData icon;

  @override
  State<UploadRing> createState() => _UploadRingState();
}

class _UploadRingState extends State<UploadRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant UploadRing old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.busy && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      label: widget.busy
          ? 'Uploading ${(widget.progress * 100).round()} percent'
          : 'Upload ${(widget.progress * 100).round()} percent ready',
      excludeSemantics: true,
      child: SizedBox(
        width: 72,
        height: 72,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: widget.progress.clamp(0, 1)),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => AnimatedBuilder(
            animation: _spin,
            builder: (context, _) => CustomPaint(
              painter: _RingPainter(
                progress: value,
                sweepStart: reduce || !widget.busy
                    ? 0
                    : _spin.value * math.pi * 2,
                color: widget.color,
                track: b.isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Brand.navy.withValues(alpha: 0.12),
              ),
              child: Center(
                child: FileTypeTile(
                  icon: widget.icon,
                  color: widget.color,
                  size: 46,
                  iconSize: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.sweepStart,
    required this.color,
    required this.track,
  });

  final double progress;
  final double sweepStart;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.shortestSide / 2 - 3;
    final ring = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(center, radius, base);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      ring,
      -math.pi / 2 + sweepStart,
      math.pi * 2 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.sweepStart != sweepStart ||
      old.color != color ||
      old.track != track;
}

class ProgressTrack extends StatelessWidget {
  const ProgressTrack({super.key, required this.value, this.color});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0, 1)),
        duration: reduce ? Duration.zero : const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 8,
          backgroundColor: b.surfaceHi,
          valueColor: AlwaysStoppedAnimation<Color>(color ?? b.signal),
        ),
      ),
    );
  }
}

void fileToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool danger = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: Brand.danger,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  String hint = '',
  String emptyError = 'Please enter a folder name',
  int maxLength = 255,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: maxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: hint, errorText: error),
            onSubmitted: (_) {
              if (controller.text.trim().isEmpty) {
                setInner(() => error = emptyError);
                return;
              }
              Navigator.of(ctx).pop(controller.text.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  setInner(() => error = emptyError);
                  return;
                }
                Navigator.of(ctx).pop(controller.text.trim());
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
  return result;
}
