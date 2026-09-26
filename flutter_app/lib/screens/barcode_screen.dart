import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../models/barcode_models.dart';
import '../services/barcode_service.dart';
import '../services/scan_sounds.dart';
import '../theme.dart';
import '../widgets/continuous_scanner.dart';
import '../widgets/premium.dart';
import '../widgets/serial_scanner.dart';

const String _viewCurrent = 'current';
const String _viewAll = 'all';

String barcodeDate(String raw) {
  final parsed = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
  if (parsed == null) return raw.trim();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
  final minute = parsed.minute.toString().padLeft(2, '0');
  final suffix = parsed.hour < 12 ? 'AM' : 'PM';
  return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}, '
      '$hour:$minute $suffix';
}

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key, required this.service});

  final BarcodeService service;

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _filter = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  BarcodeInvoice? _current;
  bool _booting = true;

  Timer? _searchTimer;
  int _searchSeq = 0;
  bool _searching = false;
  String? _searchError;
  List<InvoiceMatch> _matches = const [];

  bool _saving = false;
  BarcodeScanResult? _result;
  int _savedCount = 0;
  int _dupeCount = 0;

  bool _loadingList = false;
  bool _listFailed = false;
  List<BarcodeRecord> _rows = const [];
  List<BarcodeBatch> _batches = const [];
  int _currentBatch = 1;
  int _nextBatch = 2;
  Object _view = _viewCurrent;
  int? _flashId;
  final Set<int> _pendingDelete = <int>{};

  ScaffoldMessengerState? _messenger;

  bool get _viewingAll => _view == _viewAll;

  int get _viewedBatch => _view is int ? _view as int : _currentBatch;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _messenger?.hideCurrentSnackBar();
    _search.dispose();
    _code.dispose();
    _filter.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restore() async {
    final active = await widget.service.activeInvoice();
    if (!mounted) return;
    setState(() => _booting = false);
    if (active != null) {
      _select(
        active.invoiceNumber,
        active.customerName,
        persist: false,
        batch: active.batch,
      );
    }
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    final term = value.trim();
    if (term.length < 2) {
      setState(() {
        _matches = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      final seq = ++_searchSeq;
      final result = await widget.service.searchInvoices(term);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _searching = false;
        _searchError = result.error;
        _matches = result.matches;
      });
    });
  }

  void _pickMatch(InvoiceMatch match) {
    if (match.invoiceNumber.isEmpty) {
      _toast('That record has no invoice number.');
      return;
    }
    _select(match.invoiceNumber, match.customerName);
  }

  void _select(
    String invoice,
    String customer, {
    bool persist = true,
    int batch = 1,
  }) {
    setState(() {
      _current = BarcodeInvoice(invoiceNumber: invoice, customerName: customer);
      _currentBatch = batch < 1 ? 1 : batch;
      _nextBatch = _currentBatch + 1;
      _view = _viewCurrent;
      _savedCount = 0;
      _dupeCount = 0;
      _result = null;
      _matches = const [];
      _searchError = null;
      _search.clear();
    });
    if (persist) widget.service.setActiveInvoice(invoice, customer);
    _loadList();
    _codeFocus.requestFocus();
  }

  void _changeInvoice() {
    widget.service.clearActiveInvoice();
    setState(() {
      _current = null;
      _rows = const [];
      _batches = const [];
      _currentBatch = 1;
      _nextBatch = 2;
      _view = _viewCurrent;
      _result = null;
      _savedCount = 0;
      _dupeCount = 0;
      _code.clear();
      _filter.clear();
    });
  }

  Future<void> _loadList() async {
    final current = _current;
    if (current == null) return;
    setState(() {
      _loadingList = true;
      _listFailed = false;
    });
    final res = await widget.service.list(
      current.invoiceNumber,
      batch: _viewingAll ? null : _viewedBatch,
    );
    if (!mounted || _current?.invoiceNumber != current.invoiceNumber) return;
    setState(() {
      _loadingList = false;
      if (!res.ok) {
        _listFailed = true;
        return;
      }
      if (res.batch > 0) {
        _currentBatch = res.batch;
        _nextBatch = res.nextBatch > res.batch ? res.nextBatch : res.batch + 1;
      }
      _batches = res.batches;
      if (_view is int && !_batches.any((b) => b.batch == _view)) {
        _view = _viewCurrent;
      }
      _rows = res.rows;
    });
  }

  String _duplicateMeta(BarcodeScanResult r) {
    final parts = <String>[];
    if (r.invoiceNumber.isNotEmpty) {
      parts.add(
        'Recorded on ${r.invoiceNumber}'
        '${r.customerName.isNotEmpty ? ' · ${r.customerName}' : ''}',
      );
    }
    if (r.batch > 0) parts.add('Batch ${r.batch}');
    if (r.firstScanned.isNotEmpty) parts.add(barcodeDate(r.firstScanned));
    return parts.join(' · ');
  }

  Future<BarcodeScanResult> _submit(String raw, {bool reload = true}) async {
    final current = _current;
    final code = raw.trim();
    if (current == null || code.isEmpty) {
      return BarcodeScanResult(
        outcome: ScanOutcome.error,
        code: code,
        message: 'Select an invoice before scanning.',
      );
    }
    final res = await widget.service.scan(
      code: code,
      invoice: current.invoiceNumber,
      customer: current.customerName,
    );
    if (!mounted) return res;
    setState(() {
      _result = res;
      switch (res.outcome) {
        case ScanOutcome.saved:
          _savedCount++;
          if (res.batch > 0) {
            _currentBatch = res.batch;
            if (_nextBatch <= _currentBatch) _nextBatch = _currentBatch + 1;
          }
          if (_view is int && _view != _currentBatch) _view = _viewCurrent;
        case ScanOutcome.exists:
          _dupeCount++;
          _flashId = res.id;
        case ScanOutcome.error:
          break;
      }
    });
    if (res.outcome == ScanOutcome.saved && reload) _loadList();
    return res;
  }

  Future<void> _submitTyped() async {
    if (_saving || _current == null) return;
    final code = _code.text.trim();
    if (code.isEmpty) {
      _codeFocus.requestFocus();
      return;
    }
    _code.clear();
    setState(() => _saving = true);
    final res = await _submit(code);
    if (!mounted) return;
    setState(() => _saving = false);
    ScanSounds.instance.play(res.outcome);
    if (res.outcome == ScanOutcome.error) {
      _toast(res.message);
    } else if (res.outcome == ScanOutcome.exists) {
      await _showDuplicate(res);
    }
    if (mounted) _codeFocus.requestFocus();
  }

  Future<void> _showDuplicate(BarcodeScanResult res) async {
    final meta = _duplicateMeta(res);
    Timer? timer;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        timer = Timer(const Duration(seconds: 4), () {
          if (ctx.mounted) Navigator.of(ctx).pop();
        });
        final text = Theme.of(ctx).textTheme;
        return AlertDialog(
          icon: const Icon(
            Icons.history_rounded,
            color: Brand.warning,
            size: 36,
          ),
          title: const Text('Barcode Already Recorded'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                res.code,
                textAlign: TextAlign.center,
                style: text.titleSmall?.copyWith(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 8),
              const Text(
                'This barcode already has a record in the database.',
                textAlign: TextAlign.center,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(meta, textAlign: TextAlign.center, style: text.bodySmall),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Continue scanning'),
            ),
          ],
        );
      },
    );
    timer?.cancel();
  }

  Future<void> _openCamera() async {
    final current = _current;
    if (current == null) return;
    if (!serialScanSupported) {
      _toast(
        'Camera scanning needs the phone app. Type the code or use a USB '
        'scanner here.',
      );
      return;
    }
    await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        fullscreenDialog: true,
        builder: (_) => ContinuousScannerScreen(
          invoice: current.invoiceNumber,
          batchLabel: () => 'Batch $_currentBatch',
          onCode: (code) => _submit(code, reload: false),
          describeDuplicate: _duplicateMeta,
        ),
      ),
    );
    if (mounted) _loadList();
  }

  void _deleteWithUndo(BarcodeRecord row) {
    setState(() => _pendingDelete.add(row.id));
    var undone = false;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Barcode deleted'),
            duration: const Duration(seconds: 5),
            persist: false,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                undone = true;
                if (mounted) setState(() => _pendingDelete.remove(row.id));
              },
            ),
          ),
        )
        .closed
        .then((_) async {
          if (undone) return;
          final res = await widget.service.delete(row.id);
          if (!mounted) return;
          _pendingDelete.remove(row.id);
          if (!res.ok) _toast(res.message ?? 'Delete failed.');
          _loadList();
        });
  }

  Future<void> _confirmDelete(BarcodeRecord row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this barcode?'),
        content: Text(row.code),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) _deleteWithUndo(row);
  }

  Future<void> _openDetail(BarcodeRecord row) async {
    final delete = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BarcodeDetailSheet(row: row),
    );
    if (delete == true && mounted) _confirmDelete(row);
  }

  Future<void> _openNewBatch() async {
    final current = _current;
    if (current == null) return;
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _NewBatchDialog(
        invoice: current.invoiceNumber,
        currentBatch: _currentBatch,
        nextBatch: _nextBatch,
        batches: _batches,
      ),
    );
    if (target == null || !mounted) return;
    final res = await widget.service.startBatch(current.invoiceNumber, target);
    if (!mounted) return;
    if (!res.ok) {
      _toast(res.message ?? 'Could not start the batch.');
      return;
    }
    _afterBatchChange(res.batch);
    _toast(
      res.existingInNew > 0
          ? 'Now scanning into batch ${res.batch} — it already holds '
                '${res.existingInNew} code(s).'
          : 'Batch ${res.batch} started.',
    );
  }

  Future<void> _openReset() async {
    final current = _current;
    if (current == null) return;
    final target = await showDialog<int>(
      context: context,
      builder: (_) => _ResetBatchDialog(
        invoice: current.invoiceNumber,
        currentBatch: _currentBatch,
        batches: _batches,
      ),
    );
    if (target == null || !mounted) return;
    final count = _batches
        .where((b) => b.batch == target)
        .fold<int>(0, (n, b) => n + b.count);
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset batch $target on ${current.invoiceNumber}?'),
        content: Text(
          'This permanently deletes its $count barcode(s), then scanning '
          'continues into batch $target so you can re-scan it.\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Reset batch $target'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    var undone = false;
    final invoice = current.invoiceNumber;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text('Batch $target reset — $count code(s) deleted'),
            duration: const Duration(seconds: 5),
            persist: false,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => undone = true,
            ),
          ),
        )
        .closed
        .then((_) async {
          if (undone) return;
          final res = await widget.service.resetBatch(invoice, target);
          if (!mounted) return;
          if (!res.ok) {
            _toast(res.message ?? 'Could not reset the batch.');
            return;
          }
          if (_current?.invoiceNumber == invoice) _afterBatchChange(res.batch);
        });
  }

  void _afterBatchChange(int batch) {
    setState(() {
      _currentBatch = batch < 1 ? 1 : batch;
      _nextBatch = _currentBatch + 1;
      _view = _viewCurrent;
      _savedCount = 0;
      _dupeCount = 0;
      _result = null;
    });
    _loadList();
  }

  List<BarcodeRecord> get _visibleRows {
    final q = _filter.text.trim().toLowerCase();
    return _rows
        .where((r) => !_pendingDelete.contains(r.id))
        .where((r) => q.isEmpty || r.code.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;
    final header = <Widget>[
      _statusPill(context),
      const SizedBox(height: 12),
      _invoiceCard(context),
      const SizedBox(height: 12),
      _scanCard(context),
      const SizedBox(height: 12),
      _listHeader(context, rows.length),
      const SizedBox(height: 8),
    ];
    final Widget? placeholder = _current == null
        ? const _ListNote(
            icon: Icons.inbox_rounded,
            text: 'Select an invoice to see its scanned barcodes.',
          )
        : _loadingList && _rows.isEmpty
        ? const Column(
            children: [
              Skeleton(height: 56, radius: 12),
              SizedBox(height: 8),
              Skeleton(height: 56, radius: 12),
              SizedBox(height: 8),
              Skeleton(height: 56, radius: 12),
            ],
          )
        : _listFailed
        ? const _ListNote(
            icon: Icons.warning_amber_rounded,
            text: 'Could not load the list.',
          )
        : rows.isEmpty
        ? _ListNote(icon: Icons.qr_code_2_rounded, text: _emptyMessage())
        : null;

    return StationScaffold(
      stationNumber: '··',
      stationLabel: 'System',
      title: 'Barcode',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: RefreshIndicator(
        onRefresh: _loadList,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: header.length + (placeholder != null ? 1 : rows.length),
          itemBuilder: (context, index) {
            if (index < header.length) return header[index];
            if (placeholder != null) return placeholder;
            final row = rows[index - header.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BarcodeRow(
                row: row,
                showBatch: _viewingAll,
                flash: row.id == _flashId,
                onTap: () => _openDetail(row),
                onDelete: () => _confirmDelete(row),
              ),
            );
          },
        ),
      ),
    );
  }

  String _emptyMessage() {
    if (_viewingAll) {
      return 'No barcodes scanned for this invoice yet. Scan one to begin.';
    }
    if (_viewedBatch == _currentBatch) {
      return 'Batch $_currentBatch is empty. Scan a barcode to begin.';
    }
    return 'Batch $_viewedBatch has no barcodes.';
  }

  Widget _statusPill(BuildContext context) {
    final current = _current;
    final ready = current != null;
    return Align(
      alignment: Alignment.centerLeft,
      child: GlowBadge(
        label: _booting
            ? 'Loading…'
            : ready
            ? 'Scanner ready · ${current.invoiceNumber}'
            : 'No invoice selected',
        color: ready ? Brand.success : context.brand.paperDim,
        icon: Icons.circle,
        maxLabelWidth: 260,
      ),
    );
  }

  Widget _step(
    BuildContext context,
    String n,
    String title, {
    Widget? trailing,
  }) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: b.signal, shape: BoxShape.circle),
            child: Text(
              n,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: text.titleMedium)),
          ?trailing,
        ],
      ),
    );
  }

  Widget _invoiceCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final current = _current;
    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _step(context, '1', 'Invoice'),
          if (current != null) ...[
            _pair(context, 'Invoice', current.invoiceNumber, mono: true),
            const SizedBox(height: 6),
            _pair(
              context,
              'Customer',
              current.customerName.isEmpty ? '—' : current.customerName,
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Change invoice',
              icon: Icons.undo_rounded,
              onPressed: _changeInvoice,
            ),
          ] else ...[
            Text(
              'Search by invoice number or customer',
              style: text.labelMedium,
            ),
            const SizedBox(height: 6),
            AppSearchField(
              controller: _search,
              hint: 'e.g. INV-00021 or customer name',
              onChanged: _onSearchChanged,
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (_searchError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _searchError!,
                  style: text.bodySmall?.copyWith(color: Brand.danger),
                ),
              )
            else if (_search.text.trim().length >= 2 && _matches.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'No matching invoices.',
                  style: text.bodySmall?.copyWith(color: b.paperDim),
                ),
              ),
            for (final match in _matches)
              InkWell(
                onTap: () => _pickMatch(match),
                borderRadius: BorderRadius.circular(Brand.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        color: b.signal,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              match.invoiceNumber.isEmpty
                                  ? '—'
                                  : match.invoiceNumber,
                              style: text.titleSmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              match.customerName.isEmpty
                                  ? 'Unknown customer'
                                  : match.customerName,
                              style: text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: b.paperDim),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _pair(
    BuildContext context,
    String label,
    String value, {
    bool mono = false,
  }) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 86, child: Text(label, style: text.labelMedium)),
        Expanded(
          child: Text(
            value,
            style: text.titleSmall?.copyWith(
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _scanCard(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final ready = _current != null;
    return Opacity(
      opacity: ready ? 1 : 0.55,
      child: AppCard(
        radius: Brand.radiusLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _step(context, '2', 'Scan'),
            SignalButton(
              label: 'Scan with camera',
              icon: Icons.qr_code_scanner_rounded,
              onPressed: ready ? _openCamera : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    focusNode: _codeFocus,
                    enabled: ready,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.qr_code_2_rounded),
                      hintText: ready
                          ? 'Type or scan a code…'
                          : 'Select an invoice first…',
                    ),
                    onSubmitted: (_) => _submitTyped(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: ready && !_saving ? _submitTyped : null,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Save'),
                ),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              _ResultPanel(
                result: _result!,
                invoice: _current?.invoiceNumber ?? '',
                batch: _currentBatch,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatChip(
                    value: _savedCount,
                    label: 'Saved',
                    color: Brand.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatChip(
                    value: _dupeCount,
                    label: 'Duplicates',
                    color: Brand.warning,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatChip(
                    value: _rows.length,
                    label: 'On invoice',
                    color: b.paperDim,
                  ),
                ),
              ],
            ),
            if (!serialScanSupported) ...[
              const SizedBox(height: 10),
              Text(
                'On this computer, type codes or use a USB barcode scanner in '
                'the box above — it saves when the scanner sends Enter.',
                style: text.bodySmall?.copyWith(color: b.paperDim),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _listHeader(BuildContext context, int shown) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final ready = _current != null;
    final total = _batches.fold<int>(0, (n, x) => n + x.count);
    final options = <DropdownMenuItem<Object>>[
      DropdownMenuItem(
        value: _viewCurrent,
        child: Text('Batch $_currentBatch (current)'),
      ),
      for (final batch in _batches)
        if (batch.batch != _currentBatch)
          DropdownMenuItem(
            value: batch.batch,
            child: Text('Batch ${batch.batch} (${batch.count})'),
          ),
      DropdownMenuItem(value: _viewAll, child: Text('All batches ($total)')),
    ];
    return AppCard(
      radius: Brand.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _step(
            context,
            '3',
            'Scanned',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ready)
                  GlowBadge(label: 'Batch $_currentBatch', color: b.signal),
                const SizedBox(width: 6),
                Text('$shown', style: text.titleSmall),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: ready ? _openNewBatch : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New batch'),
              ),
              OutlinedButton.icon(
                onPressed: ready ? _openReset : null,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Reset'),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: ready ? _loadList : null,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (ready) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<Object>(
              initialValue: _view,
              key: ValueKey('scope-$_view-$_currentBatch-${_batches.length}'),
              isExpanded: true,
              items: options,
              decoration: const InputDecoration(labelText: 'Showing'),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _view = value);
                _loadList();
              },
            ),
            const SizedBox(height: 10),
            AppSearchField(
              controller: _filter,
              hint: 'Filter scanned codes…',
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    );
  }
}

class _ListNote extends StatelessWidget {
  const _ListNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          Icon(icon, size: 36, color: b.paperDim),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: b.paperDim),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: b.surfaceHi,
        borderRadius: BorderRadius.circular(Brand.radiusSm),
        border: Border.all(color: b.rule),
      ),
      child: Column(
        children: [
          Text('$value', style: text.titleLarge?.copyWith(color: color)),
          Text(label, style: text.labelSmall),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.result,
    required this.invoice,
    required this.batch,
  });

  final BarcodeScanResult result;
  final String invoice;
  final int batch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final String sub;
    final Color color;
    final IconData icon;
    switch (result.outcome) {
      case ScanOutcome.saved:
        color = Brand.success;
        icon = Icons.check_circle_rounded;
        sub = 'Saved to $invoice · Batch $batch.';
      case ScanOutcome.exists:
        color = Brand.warning;
        icon = Icons.history_rounded;
        final on = result.invoiceNumber.isEmpty
            ? ''
            : ' on ${result.invoiceNumber}'
                  '${result.customerName.isEmpty ? '' : ' (${result.customerName})'}';
        final when = result.firstScanned.isEmpty
            ? ''
            : ' — ${barcodeDate(result.firstScanned)}';
        sub = 'Already exists$on$when.';
      case ScanOutcome.error:
        color = Brand.danger;
        icon = Icons.warning_amber_rounded;
        sub = result.message;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Brand.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.code,
                  style: text.titleSmall?.copyWith(fontFamily: 'monospace'),
                ),
                Text(sub, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeRow extends StatelessWidget {
  const _BarcodeRow({
    required this.row,
    required this.showBatch,
    required this.flash,
    required this.onTap,
    required this.onDelete,
  });

  final BarcodeRecord row;
  final bool showBatch;
  final bool flash;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusSm,
      borderColor: flash ? Brand.warning : null,
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Brand.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontFamily: 'monospace'),
                ),
                Text(
                  '${row.scannedBy.isEmpty ? '—' : row.scannedBy} · '
                  '${barcodeDate(row.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium,
                ),
              ],
            ),
          ),
          if (showBatch)
            GlowBadge(
              label: 'B${row.batch < 1 ? 1 : row.batch}',
              color: b.signal,
            ),
          IconButton(
            tooltip: 'Delete',
            onPressed: onDelete,
            icon: Icon(Icons.delete_outline_rounded, color: b.paperDim),
          ),
        ],
      ),
    );
  }
}

class _BarcodeDetailSheet extends StatelessWidget {
  const _BarcodeDetailSheet({required this.row});

  final BarcodeRecord row;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    Widget field(String k, String v, {bool mono = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(k, style: text.labelMedium)),
          Expanded(
            child: Text(
              v.isEmpty ? '—' : v,
              style: text.bodyMedium?.copyWith(
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Barcode ${row.code}', style: text.titleMedium),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Brand.radiusSm),
                border: Border.all(color: b.rule),
              ),
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: row.code,
                height: 96,
                color: Brand.navy,
                style: const TextStyle(
                  color: Brand.navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                errorBuilder: (_, _) => Center(
                  child: Text(
                    row.code,
                    style: const TextStyle(
                      color: Brand.navy,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            field('Invoice', row.invoiceNumber, mono: true),
            field('Customer', row.customerName),
            field(
              'Batch',
              row.batch > 0 ? 'Batch ${row.batch}' : '',
              mono: true,
            ),
            field('Scanned by', row.scannedBy),
            field('Date', barcodeDate(row.createdAt)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Brand.danger,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewBatchDialog extends StatefulWidget {
  const _NewBatchDialog({
    required this.invoice,
    required this.currentBatch,
    required this.nextBatch,
    required this.batches,
  });

  final String invoice;
  final int currentBatch;
  final int nextBatch;
  final List<BarcodeBatch> batches;

  @override
  State<_NewBatchDialog> createState() => _NewBatchDialogState();
}

class _NewBatchDialogState extends State<_NewBatchDialog> {
  late final TextEditingController _number = TextEditingController(
    text: '${widget.nextBatch}',
  );
  int? _continue;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  ({String? error, String? warn, int? target}) _check() {
    final chosen = _continue;
    if (chosen != null) {
      final count = widget.batches
          .where((b) => b.batch == chosen)
          .fold<int>(0, (n, b) => n + b.count);
      return (
        error: null,
        warn:
            'Batch $chosen already has $count code(s). Scanning will add to '
            'it — nothing is deleted.',
        target: chosen,
      );
    }
    final raw = _number.text.trim();
    final n = int.tryParse(raw);
    if (raw.isEmpty || !RegExp(r'^\d+$').hasMatch(raw) || n == null || n < 1) {
      return (
        error: 'Enter a whole batch number of 1 or more.',
        warn: null,
        target: null,
      );
    }
    if (n == widget.currentBatch) {
      return (
        error: 'Batch $n is already the current batch.',
        warn: null,
        target: null,
      );
    }
    final clash = widget.batches.where((b) => b.batch == n);
    return (
      error: null,
      warn: clash.isEmpty
          ? null
          : 'Batch $n already has ${clash.first.count} code(s). New scans '
                'will be added to it.',
      target: n,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final check = _check();
    final others = widget.batches
        .where((b) => b.batch != widget.currentBatch)
        .toList();
    return AlertDialog(
      title: const Text('Start a new batch'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Scanning on ${widget.invoice} moves from Batch '
              '${widget.currentBatch} to the batch you pick. Every code '
              'already saved is kept — nothing is deleted.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 12),
            RadioGroup<int?>(
              groupValue: _continue,
              onChanged: (v) => setState(() => _continue = v),
              child: Column(
                children: [
                  RadioListTile<int?>(
                    value: null,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('A fresh batch'),
                    subtitle: const Text(
                      'Starts empty — scanning begins from zero',
                    ),
                  ),
                  if (_continue == null)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: TextField(
                        controller: _number,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Batch number',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  for (final b in others)
                    RadioListTile<int?>(
                      value: b.batch,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Continue Batch ${b.batch}'),
                      subtitle: Text(
                        '${_batchMeta(b)} — new scans are added to it',
                      ),
                    ),
                ],
              ),
            ),
            if (check.error != null)
              Text(
                check.error!,
                style: text.bodySmall?.copyWith(color: Brand.danger),
              )
            else if (check.warn != null)
              Text(
                check.warn!,
                style: text.bodySmall?.copyWith(color: Brand.warning),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: check.target == null
              ? null
              : () => Navigator.of(context).pop(check.target),
          icon: Icon(
            _continue == null ? Icons.add_rounded : Icons.play_arrow_rounded,
          ),
          label: Text(
            _continue == null ? 'Start batch' : 'Continue batch $_continue',
          ),
        ),
      ],
    );
  }
}

String _batchMeta(BarcodeBatch b) {
  if (b.count == 0) return 'Empty';
  return '${b.count} code(s)'
      '${b.lastScan.isEmpty ? '' : ' · last scan ${barcodeDate(b.lastScan)}'}';
}

class _ResetBatchDialog extends StatefulWidget {
  const _ResetBatchDialog({
    required this.invoice,
    required this.currentBatch,
    required this.batches,
  });

  final String invoice;
  final int currentBatch;
  final List<BarcodeBatch> batches;

  @override
  State<_ResetBatchDialog> createState() => _ResetBatchDialogState();
}

class _ResetBatchDialogState extends State<_ResetBatchDialog> {
  int? _target;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final kept = widget.batches
        .where((b) => b.batch == widget.currentBatch)
        .fold<int>(0, (n, b) => n + b.count);
    final count = widget.batches
        .where((b) => b.batch == _target)
        .fold<int>(0, (n, b) => n + b.count);
    return AlertDialog(
      title: const Text('Reset batch'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Now scanning into Batch ${widget.currentBatch} on '
              '${widget.invoice} — $kept code(s) saved in it so far. Pick '
              'the batch to reset: its codes are deleted and scanning '
              'continues into it.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 12),
            if (widget.batches.isEmpty)
              Text('This invoice has no batches yet.', style: text.bodySmall)
            else
              RadioGroup<int>(
                groupValue: _target,
                onChanged: (v) => setState(() => _target = v),
                child: Column(
                  children: [
                    for (final b in widget.batches)
                      RadioListTile<int>(
                        value: b.batch,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Batch ${b.batch}'
                          '${b.batch == widget.currentBatch ? ' (current)' : ''}',
                        ),
                        subtitle: Text(
                          b.count > 0
                              ? 'Deletes its ${b.count} code(s), then scan '
                                    'into it again'
                              : 'Already empty — nothing to reset',
                        ),
                      ),
                  ],
                ),
              ),
            if (_target != null) ...[
              const SizedBox(height: 8),
              Text(
                count > 0
                    ? 'This permanently deletes the $count code(s) in batch '
                          '$_target, then scanning continues into batch '
                          '$_target so you can re-scan it. This cannot be '
                          'undone.'
                    : 'Batch $_target is already empty — there is nothing '
                          'to reset.',
                style: text.bodySmall?.copyWith(
                  color: count > 0 ? Brand.danger : Brand.warning,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Brand.danger),
          onPressed: _target == null || count == 0
              ? null
              : () => Navigator.of(context).pop(_target),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(_target == null ? 'Reset batch' : 'Reset Batch $_target'),
        ),
      ],
    );
  }
}
