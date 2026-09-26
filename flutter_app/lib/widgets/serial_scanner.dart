import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';
import 'premium.dart';

bool get serialScanSupported => Platform.isAndroid || Platform.isIOS;

Future<String?> scanSerialCode(BuildContext context) async {
  if (!serialScanSupported) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Barcode scanning needs a camera — use the phone app.'),
        ),
      );
    return null;
  }
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (_) => const SerialScannerScreen(),
    ),
  );
}

class SerialScannerScreen extends StatefulWidget {
  const SerialScannerScreen({super.key});

  @override
  State<SerialScannerScreen> createState() => _SerialScannerScreenState();
}

class _SerialScannerScreenState extends State<SerialScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
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
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final value = (code.rawValue ?? '').trim();
      if (value.isEmpty) continue;
      _done = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Brand.navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 260,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Brand.orange, width: 2),
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
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
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
                  const Spacer(),
                  Text(
                    'Point the camera at the serial number barcode',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
