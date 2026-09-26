import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/barcode_models.dart';
import '../services/scan_sounds.dart';
import '../theme.dart';
import 'premium.dart';

class ContinuousScannerScreen extends StatefulWidget {
  const ContinuousScannerScreen({
    super.key,
    required this.invoice,
    required this.batchLabel,
    required this.onCode,
    this.describeDuplicate,
  });

  final String invoice;
  final String Function() batchLabel;
  final Future<BarcodeScanResult> Function(String code) onCode;
  final String Function(BarcodeScanResult result)? describeDuplicate;

  @override
  State<ContinuousScannerScreen> createState() =>
      _ContinuousScannerScreenState();
}

class _ContinuousScannerScreenState extends State<ContinuousScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf14,
      BarcodeFormat.dataMatrix,
      BarcodeFormat.qrCode,
    ],
  );

  static const Duration _repeatWindow = Duration(milliseconds: 2500);
  static const Duration _dupeHold = Duration(seconds: 4);

  final Map<String, DateTime> _recent = {};
  BarcodeScanResult? _last;
  BarcodeScanResult? _dupe;
  Timer? _dupeTimer;
  bool _busy = false;
  bool _torch = false;
  int _saved = 0;
  int _dupes = 0;

  @override
  void dispose() {
    _dupeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy || _dupe != null) return;
    final now = DateTime.now();
    _recent.removeWhere((_, at) => now.difference(at) > _repeatWindow);
    for (final barcode in capture.barcodes) {
      final code = (barcode.rawValue ?? '').trim();
      if (code.isEmpty || _recent.containsKey(code)) continue;
      _recent[code] = now;
      setState(() => _busy = true);
      final result = await widget.onCode(code);
      if (!mounted) return;
      _recent[code] = DateTime.now();
      ScanSounds.instance.play(result.outcome);
      setState(() {
        _busy = false;
        _last = result;
        if (result.outcome == ScanOutcome.saved) _saved++;
        if (result.outcome == ScanOutcome.exists) {
          _dupes++;
          _dupe = result;
        }
      });
      if (result.outcome == ScanOutcome.exists) {
        _dupeTimer?.cancel();
        _dupeTimer = Timer(_dupeHold, _closeDupe);
      }
      return;
    }
  }

  void _closeDupe() {
    _dupeTimer?.cancel();
    if (!mounted || _dupe == null) return;
    final code = _dupe!.code;
    setState(() => _dupe = null);
    _recent[code] = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PopScope<int>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_saved);
      },
      child: Scaffold(
        backgroundColor: Brand.navy,
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Align(
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 280,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _busy ? Colors.white : Brand.orange,
                    width: _busy ? 3 : 2,
                  ),
                  borderRadius: BorderRadius.circular(Brand.radiusLg),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        AppIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Done scanning',
                          onPressed: () => Navigator.of(context).pop(_saved),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.invoice,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                widget.batchLabel(),
                                style: text.labelMedium?.copyWith(
                                  color: Brand.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppIconButton(
                          icon: _torch
                              ? Icons.flashlight_on_rounded
                              : Icons.flashlight_off_rounded,
                          tooltip: _torch ? 'Turn off flash' : 'Turn on flash',
                          onPressed: () async {
                            await _controller.toggleTorch();
                            if (mounted) setState(() => _torch = !_torch);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _CountChip(
                          label: 'Saved',
                          value: _saved,
                          color: Brand.success,
                        ),
                        const SizedBox(width: 8),
                        _CountChip(
                          label: 'Duplicates',
                          value: _dupes,
                          color: Brand.warning,
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (_last != null)
                      _ResultBanner(result: _last!)
                    else
                      Text(
                        'Point the camera at a barcode. Each new code is '
                        'saved automatically.',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: Colors.white),
                      ),
                    const SizedBox(height: 12),
                    SignalButton(
                      label: 'Done',
                      icon: Icons.check_rounded,
                      onPressed: () => Navigator.of(context).pop(_saved),
                    ),
                  ],
                ),
              ),
            ),
            if (_dupe != null)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeDupe,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: _DuplicateCard(
                      result: _dupe!,
                      meta: widget.describeDuplicate?.call(_dupe!) ?? '',
                      onContinue: _closeDupe,
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

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        '$value $label',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final BarcodeScanResult result;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (color, icon, sub) = switch (result.outcome) {
      ScanOutcome.saved => (
        Brand.success,
        Icons.check_circle_rounded,
        'Saved${result.batch > 0 ? ' · Batch ${result.batch}' : ''}',
      ),
      ScanOutcome.exists => (
        Brand.warning,
        Icons.history_rounded,
        'Already exists',
      ),
      ScanOutcome.error => (Brand.danger, Icons.error_rounded, result.message),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({
    required this.result,
    required this.meta,
    required this.onContinue,
  });

  final BarcodeScanResult result;
  final String meta;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Material(
      color: b.surface,
      borderRadius: BorderRadius.circular(Brand.radiusLg),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_rounded, color: Brand.warning, size: 40),
            const SizedBox(height: 10),
            Text('Barcode Already Recorded', style: text.titleMedium),
            const SizedBox(height: 10),
            Text(
              result.code,
              textAlign: TextAlign.center,
              style: text.titleSmall?.copyWith(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Text(
              'This barcode already has a record in the database.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                meta,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: b.paperDim),
              ),
            ],
            const SizedBox(height: 16),
            SignalButton(
              label: 'Continue scanning',
              icon: Icons.qr_code_scanner_rounded,
              onPressed: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}
