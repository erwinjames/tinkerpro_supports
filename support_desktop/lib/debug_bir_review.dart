import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'debug_capture.dart';
import 'screens/bir_register_review_dialog.dart';
import 'theme.dart';
import 'widgets/toast_host.dart';

Widget debugBirReviewApp(ApiClient api) {
  final dark = Platform.environment['TP_BIR_DARK'] == '1';
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: lightTheme(),
    darkTheme: darkTheme(),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => debugCaptureWrap(toastHost(child!)),
    home: _DebugBirReviewHost(api: api),
  );
}

class _DebugBirReviewHost extends StatefulWidget {
  const _DebugBirReviewHost({required this.api});
  final ApiClient api;

  @override
  State<_DebugBirReviewHost> createState() => _DebugBirReviewHostState();
}

class _DebugBirReviewHostState extends State<_DebugBirReviewHost> {
  @override
  void initState() {
    super.initState();
    if (!kDebugMode) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final m = Platform.environment['TP_BIR_MODE'] ?? 'add';
      final mode = switch (m) {
        'complete' => BirReviewMode.complete,
        'continue' => BirReviewMode.continueUpload,
        _ => BirReviewMode.add,
      };
      BirRegisterReviewDialog.show(
        context,
        api: widget.api,
        data: _sample(mode),
        mode: mode,
        customerId: mode == BirReviewMode.add ? null : 0,
        invoiceNumber: 'INV-DEBUG',
      );
      _scheduleClicks();
    });
  }

  void _scheduleClicks() {
    final raw = Platform.environment['TP_BIR_CLICKS'] ?? '';
    for (final part in raw.split(';')) {
      final bits = part.split(':');
      if (bits.length != 2 || !bits[1].contains(',')) continue;
      final ms = int.tryParse(bits[0]) ?? 0;
      final xy = bits[1].split(',');
      final p = Offset(double.parse(xy[0]), double.parse(xy[1]));
      Timer(Duration(milliseconds: ms), () async {
        final b = GestureBinding.instance;
        if (xy.length > 2) {
          b.handlePointerEvent(
            PointerScrollEvent(
              position: p,
              kind: PointerDeviceKind.mouse,
              scrollDelta: Offset(0, double.parse(xy[2])),
            ),
          );
          return;
        }
        b.handlePointerEvent(
          PointerHoverEvent(position: p, kind: PointerDeviceKind.mouse),
        );
        b.handlePointerEvent(
          PointerDownEvent(
            position: p,
            kind: PointerDeviceKind.mouse,
            buttons: kPrimaryButton,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        b.handlePointerEvent(
          PointerUpEvent(position: p, kind: PointerDeviceKind.mouse),
        );
      });
    }
  }

  Map<String, dynamic> _sample(BirReviewMode mode) {
    final empty = Platform.environment['TP_BIR_EMPTY'] == '1';
    return {
      'fields': {
        'raw_extracted_text':
            'REPUBLIC OF THE PHILIPPINES\nDEPARTMENT OF FINANCE\nBUREAU OF INTERNAL REVENUE\nCERTIFICATE OF REGISTRATION\nTIN 123-456-789-00000\nRDO 043\nREGISTERED NAME SAMPLE TRADING\nLINE OF BUSINESS 47190 RETAIL SALE',
        'companyname': empty ? '' : 'SAMPLE TRADING',
        'tin': '123-456-789-00000',
        'branch_code': '00000',
        'rdo': '',
        'tin_issuance_date': 'November 25, 2021',
        'line_of_business':
            '47190 - Other retail sale in non-specialized stores',
        'address': '123 Sample Street, Barangay Uno, Pasig City, Metro Manila',
        'lastname': 'DELA CRUZ',
        'firstname': 'JUAN',
        'middlename': 'SANTOS',
        'birthdate': '',
        'phone_number': '',
        'email_address': '',
        'acc_number': 'FP012026-043-0000001-00000',
        'registration_type': 'NON-VAT',
        'softwarename': 'TinkerPro POS',
        'software_version': '3.2',
        'authorized_person': 'JUAN SANTOS DELA CRUZ',
        'is_vat': '0',
      },
      'visible_fields': const [
        'raw_text',
        'companyname',
        'tin',
        'branch_code',
        'address',
        'rdo',
        'line_of_business',
        'registration_type',
        'birthdate',
        'authorized_person',
        'acc_number',
        'software_name',
        'software_version',
        'serial_number_type',
        'server_type',
        'serial_number',
        'brand',
        'model',
      ],
      'catalog': {
        'TinkerPro POS': [
          {'version': '3.2', 'acc_number': 'FP012026-043-0000001-00000'},
          {'version': '3.1', 'acc_number': 'FP012025-043-0000001-00000'},
        ],
        'TinkerPro Cafe': [
          {'version': '1.0', 'acc_number': 'FP012026-043-0000002-00000'},
        ],
      },
      'serial_rows': [
        {
          'serial_number_type': 'Server',
          'server_type': 'Consolidator',
          'serial_number': 'TP-SRV-0001',
          'brand': 'TinkerPro',
          'model': 'Mini PC',
        },
        {
          'serial_number_type': 'Terminal',
          'serial_number': '',
          'brand': '',
          'model': '',
        },
      ],
      'lob_candidates': [
        {
          'code': '47190',
          'description': 'Other retail sale in non-specialized stores',
          'label': '47190 - Other retail sale in non-specialized stores',
        },
        {
          'code': '56101',
          'description': 'Restaurants',
          'label': '56101 - Restaurants',
        },
      ],
      'stored_files': [
        {'original': 'BIR-Form-2303.pdf', 'stored': 'debug-2303.pdf'},
        {
          'original': 'drivers-license-front.jpg',
          'stored': 'debug-id.jpg',
          'is_valid_id': true,
        },
      ],
      if (mode == BirReviewMode.complete)
        'summary': {
          'name': 'SAMPLE TRADING',
          'tin': '123-456-789-00000',
          'branch': '00000',
        },
    };
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(backgroundColor: context.brand.canvas);
}
