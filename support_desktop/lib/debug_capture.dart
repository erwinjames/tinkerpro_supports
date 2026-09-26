import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

final GlobalKey debugCaptureKey = GlobalKey();

Widget debugCaptureWrap(Widget child) {
  if (!kDebugMode ||
      (Platform.environment['TP_SHOT_PATH'] == null &&
          Platform.environment['TP_SHOT_DIR'] == null)) {
    return child;
  }
  return RepaintBoundary(key: debugCaptureKey, child: child);
}

Future<void> debugShot(String name) async {
  if (!kDebugMode) return;
  final dir = Platform.environment['TP_SHOT_DIR'];
  if (dir == null || dir.isEmpty) return;
  final boundary =
      debugCaptureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) return;
  await File('$dir/$name.png').writeAsBytes(bytes.buffer.asUint8List());
}

void debugErrMark(String text) {
  if (!kDebugMode) return;
  final path = Platform.environment['TP_ERR_LOG'];
  if (path == null || path.isEmpty) return;
  File(path).writeAsStringSync('--- $text\n', mode: FileMode.append);
}

void installDebugErrorLog() {
  if (!kDebugMode) return;
  final path = Platform.environment['TP_ERR_LOG'];
  if (path == null || path.isEmpty) return;
  final file = File(path);
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    final full = details.toString();
    final lines = full.split('\n');
    final at = lines.indexWhere((l) => l.contains('relevant error-causing widget'));
    final where = at < 0
        ? lines.take(8).join(' / ')
        : lines.skip(at + 1).take(2).map((l) => l.trim()).join(' ');
    final head = details.exceptionAsString().split('\n').first;
    file.writeAsStringSync('EXCEPTION CAUGHT $head :: $where\n',
        mode: FileMode.append);
    prev?.call(details);
  };
}

void scheduleDebugCapture() {
  if (!kDebugMode) return;
  final path = Platform.environment['TP_SHOT_PATH'];
  if (path == null || path.isEmpty) return;
  final delay =
      int.tryParse(Platform.environment['TP_SHOT_DELAY'] ?? '') ?? 8;
  final drag = Platform.environment['TP_DRAG'];
  if (drag != null && drag.contains(';')) {
    final pts = [
      for (final p in drag.split(';'))
        Offset(double.parse(p.split(',')[0]), double.parse(p.split(',')[1]))
    ];
    Timer(Duration(seconds: (delay - 3).clamp(1, 1 << 20)), () async {
      final b = GestureBinding.instance;
      b.handlePointerEvent(PointerAddedEvent(position: pts.first, kind: PointerDeviceKind.mouse));
      b.handlePointerEvent(PointerDownEvent(position: pts.first, kind: PointerDeviceKind.mouse, buttons: kPrimaryButton));
      const steps = 20;
      var prev = pts.first;
      for (var i = 1; i <= steps; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        final t = i / steps;
        final p = Offset.lerp(pts.first, pts.last, t)!;
        b.handlePointerEvent(PointerMoveEvent(position: p, delta: p - prev, kind: PointerDeviceKind.mouse, buttons: kPrimaryButton));
        prev = p;
      }
      b.handlePointerEvent(PointerUpEvent(position: pts.last, kind: PointerDeviceKind.mouse));
      final click = Platform.environment['TP_CLICK_AFTER'];
      if (click != null && click.contains(',')) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        final c = Offset(double.parse(click.split(',')[0]), double.parse(click.split(',')[1]));
        b.handlePointerEvent(PointerHoverEvent(position: c, kind: PointerDeviceKind.mouse));
        b.handlePointerEvent(PointerDownEvent(position: c, kind: PointerDeviceKind.mouse, buttons: kPrimaryButton));
        await Future<void>.delayed(const Duration(milliseconds: 60));
        b.handlePointerEvent(PointerUpEvent(position: c, kind: PointerDeviceKind.mouse));
      }
    });
  }
  final hover = Platform.environment['TP_HOVER'];
  if (hover != null && hover.isNotEmpty) {
    final points = [
      for (final p in hover.split(';'))
        if (p.contains(','))
          Offset(double.parse(p.split(',')[0]), double.parse(p.split(',')[1]))
    ];
    final gap = int.tryParse(Platform.environment['TP_HOVER_GAP'] ?? '') ?? 1;
    final start = delay - points.length * gap - 1;
    for (var i = 0; i < points.length; i++) {
      Timer(Duration(milliseconds: ((start + i * gap) * 1000).clamp(500, 1 << 30)), () {
        final binding = GestureBinding.instance;
        if (i == 0) {
          binding.handlePointerEvent(
              PointerAddedEvent(position: points[i], kind: PointerDeviceKind.mouse));
        }
        binding.handlePointerEvent(
            PointerHoverEvent(position: points[i], kind: PointerDeviceKind.mouse));
      });
    }
  }
  Timer(Duration(seconds: delay), () async {
    try {
      final boundary = debugCaptureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          await File(path).writeAsBytes(bytes.buffer.asUint8List());
        }
      }
    } finally {
      exit(0);
    }
  });
}
