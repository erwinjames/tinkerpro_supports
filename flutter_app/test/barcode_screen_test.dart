import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkerpro_support_flutter/api_client.dart';
import 'package:tinkerpro_support_flutter/models/barcode_models.dart';
import 'package:tinkerpro_support_flutter/screens/barcode_screen.dart';
import 'package:tinkerpro_support_flutter/services/barcode_service.dart';
import 'package:tinkerpro_support_flutter/theme.dart';

class _FakeBarcodeService extends BarcodeService {
  _FakeBarcodeService(super.api, {this.active});

  final BarcodeInvoice? active;
  final List<BarcodeRecord> stored = [
    const BarcodeRecord(
      id: 1,
      code: 'ABC-001',
      invoiceNumber: 'INV-1',
      customerName: 'Acme',
      batch: 1,
      createdAt: '2026-09-19 10:00:00',
      scannedBy: 'ej',
    ),
  ];
  final List<int> deleted = [];
  final List<String> scanned = [];
  int batch = 1;

  @override
  Future<BarcodeInvoice?> activeInvoice() async => active;

  @override
  Future<void> setActiveInvoice(String invoice, String customer) async {}

  @override
  Future<void> clearActiveInvoice() async {}

  @override
  Future<InvoiceSearchResult> searchInvoices(String term) async =>
      const InvoiceSearchResult(
        matches: [InvoiceMatch(invoiceNumber: 'INV-1', customerName: 'Acme')],
      );

  @override
  Future<BarcodeList> list(String invoice, {int? batch}) async => BarcodeList(
    ok: true,
    rows: stored.where((r) => batch == null || r.batch == batch).toList(),
    batch: this.batch,
    nextBatch: this.batch + 1,
    batches: [
      BarcodeBatch(
        batch: this.batch,
        count: stored.where((r) => r.batch == this.batch).length,
        lastScan: '',
      ),
    ],
  );

  @override
  Future<BarcodeScanResult> scan({
    required String code,
    required String invoice,
    required String customer,
  }) async {
    scanned.add(code);
    if (code == 'BAD') {
      return BarcodeScanResult(
        outcome: ScanOutcome.error,
        code: code,
        message: 'Failed to save barcode.',
      );
    }
    final existing = stored.where((r) => r.code == code);
    if (existing.isNotEmpty) {
      return BarcodeScanResult(
        outcome: ScanOutcome.exists,
        code: code,
        message: 'Barcode already exists.',
        id: existing.first.id,
        invoiceNumber: 'INV-1',
        customerName: 'Acme',
        batch: 1,
        firstScanned: '2026-09-19 10:00:00',
      );
    }
    stored.insert(
      0,
      BarcodeRecord(
        id: stored.length + 1,
        code: code,
        invoiceNumber: invoice,
        customerName: customer,
        batch: batch,
        createdAt: '2026-09-19 10:05:00',
        scannedBy: 'ej',
      ),
    );
    return BarcodeScanResult(
      outcome: ScanOutcome.saved,
      code: code,
      message: 'Barcode saved.',
      batch: batch,
    );
  }

  @override
  Future<BarcodeActionResult> delete(int id) async {
    deleted.add(id);
    stored.removeWhere((r) => r.id == id);
    return const BarcodeActionResult(ok: true);
  }

  @override
  Future<BarcodeActionResult> startBatch(String invoice, int batch) async {
    this.batch = batch;
    return BarcodeActionResult(ok: true, batch: batch);
  }
}

Future<_FakeBarcodeService> _service({BarcodeInvoice? active}) async {
  SharedPreferences.setMockInitialValues({});
  final api = await ApiClient.load();
  return _FakeBarcodeService(api, active: active);
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _host(BarcodeService service) => MaterialApp(
  theme: darkTheme(),
  home: BarcodeScreen(service: service),
);

const _active = BarcodeInvoice(
  invoiceNumber: 'INV-1',
  customerName: 'Acme',
  batch: 1,
);

void main() {
  testWidgets('restores the shared active invoice and lists its codes', (
    tester,
  ) async {
    _tall(tester);
    final service = await _service(active: _active);
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Scanner ready · INV-1'), findsOneWidget);
    expect(find.text('ABC-001'), findsOneWidget);
    expect(find.text('Change invoice'), findsOneWidget);
  });

  testWidgets('picking an invoice from search unlocks scanning', (
    tester,
  ) async {
    _tall(tester);
    final service = await _service();
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();
    expect(find.textContaining('No invoice selected'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'INV');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('INV-1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scanner ready · INV-1'), findsOneWidget);
  });

  testWidgets('typed scans show saved, duplicate and error outcomes', (
    tester,
  ) async {
    _tall(tester);
    final service = await _service(active: _active);
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    final field = find.widgetWithText(TextField, 'Type or scan a code…');
    await tester.enterText(field, 'NEW-777');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(service.scanned, ['NEW-777']);
    expect(find.text('Saved to INV-1 · Batch 1.'), findsOneWidget);

    await tester.enterText(field, 'ABC-001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Barcode Already Recorded'), findsOneWidget);
    await tester.tap(find.text('Continue scanning'));
    await tester.pumpAndSettle();

    await tester.enterText(field, 'BAD');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Failed to save barcode.'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate dialog closes by itself after four seconds', (
    tester,
  ) async {
    _tall(tester);
    final service = await _service(active: _active);
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Type or scan a code…'),
      'ABC-001',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Barcode Already Recorded'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Barcode Already Recorded'), findsNothing);
  });

  testWidgets('delete can be undone and only commits after the undo window', (
    tester,
  ) async {
    _tall(tester);
    final service = await _service(active: _active);
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('ABC-001'), findsNothing);
    expect(service.deleted, isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('ABC-001'), findsOneWidget);
    expect(service.deleted, isEmpty);

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(service.deleted, [1]);
  });

  testWidgets('new batch dialog validates and starts the batch', (
    tester,
  ) async {
    _tall(tester);
    final service = await _service(active: _active);
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New batch'));
    await tester.pumpAndSettle();
    expect(find.text('Start a new batch'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Batch number'), '1');
    await tester.pump();
    expect(find.text('Batch 1 is already the current batch.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Batch number'), '5');
    await tester.pump();
    await tester.tap(find.text('Start batch'));
    await tester.pumpAndSettle();
    expect(service.batch, 5);
    expect(find.text('Batch 5 started.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a row opens the detail with a drawn barcode', (
    tester,
  ) async {
    _tall(tester);
    final service = await _service(active: _active);
    await tester.pumpWidget(_host(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ABC-001'));
    await tester.pumpAndSettle();
    expect(find.text('Barcode ABC-001'), findsOneWidget);
    expect(find.text('Scanned by'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
