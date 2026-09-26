import 'dart:async';

import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/barcode_service.dart';
import '../../services/live_sync.dart';
import '../../services/ringtone_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../../widgets/web_zbe_kit.dart';
import '../../widgets/tp_loader.dart';

const _ok = Color(0xFF16A34A);
const _warn = Color(0xFFD97706);
const _bad = Color(0xFFDC2626);

String _fmt(DateTime? d) {
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.month}/${d.day}/${d.year}, $h:${two(d.minute)}:${two(d.second)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

class _ScanFeedback {
  const _ScanFeedback(this.kind, this.code, this.sub);
  final String kind;
  final String code;
  final String sub;
}

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen>
    with LiveRefresh<BarcodeScreen> {
  late final BarcodeService _svc = BarcodeService(widget.api);

  final _invSearch = TextEditingController();
  final _invFocus = FocusNode();
  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();
  final _filterCtrl = TextEditingController();

  Timer? _searchTimer;
  int _searchSeq = 0;
  bool _searching = false;
  String? _searchMsg;
  List<BcInvoiceHit> _hits = const [];

  String? _invoice;
  String _customer = '';
  int _currentBatch = 1;
  int _nextBatch = 2;
  List<BcBatch> _batches = const [];
  String _viewBatch = 'current';

  bool _listLoading = false;
  String? _listError;
  List<BcBarcode> _rows = const [];
  final Set<int> _hidden = {};
  int? _flashId;

  bool _saving = false;
  int _saved = 0;
  int _dupes = 0;
  _ScanFeedback? _feedback;
  int _modalDepth = 0;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _invSearch.dispose();
    _invFocus.dispose();
    _scanCtrl.dispose();
    _scanFocus.dispose();
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final a = await _svc.activeInvoice();
      if (!mounted) return;
      if (a != null) {
        _select(a.invoice, a.customer, persist: false, batch: a.batch);
        return;
      }
    } catch (_) {}
    if (mounted) _invFocus.requestFocus();
  }

  bool get _viewingAll => _viewBatch == 'all';
  int get _viewedBatch =>
      _viewBatch == 'current' ? _currentBatch : (int.tryParse(_viewBatch) ?? _currentBatch);

  void _focusScan() {
    if (_invoice != null && _modalDepth == 0) _scanFocus.requestFocus();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _setBatch(int n, [int next = 0]) {
    _currentBatch = n < 1 ? 1 : n;
    _nextBatch = next > _currentBatch + 1 ? next : _currentBatch + 1;
  }

  void _onSearch(String value) {
    final term = value.trim();
    _searchTimer?.cancel();
    final seq = ++_searchSeq;
    if (term.length < 2) {
      setState(() {
        _hits = const [];
        _searchMsg = null;
        _searching = false;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchMsg = null;
    });
    _searchTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final hits = await _svc.searchInvoices(term);
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _searching = false;
          _hits = hits;
          _searchMsg = hits.isEmpty ? 'No matching invoices.' : null;
        });
      } catch (e) {
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _searching = false;
          _hits = const [];
          _searchMsg = e is BcException
              ? e.message
              : 'Could not reach the invoice service.';
        });
      }
    });
  }

  void _select(String inv, String cust, {bool persist = true, int batch = 1}) {
    if (persist) {
      _svc.setActiveInvoice(inv, cust).catchError((_) {});
    }
    setState(() {
      _invoice = inv;
      _customer = cust;
      _setBatch(batch);
      _viewBatch = 'current';
      _hits = const [];
      _searchMsg = null;
      _saved = 0;
      _dupes = 0;
      _feedback = null;
    });
    _loadList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusScan());
  }

  void _change() {
    _svc.clearActiveInvoice().catchError((_) {});
    setState(() {
      _invoice = null;
      _customer = '';
      _scanCtrl.clear();
      _rows = const [];
      _batches = const [];
      _viewBatch = 'current';
      _setBatch(1);
      _feedback = null;
      _invSearch.clear();
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _invFocus.requestFocus());
  }

  @override
  List<String> get liveKeys => const ['barcode'];

  @override
  void onLiveChange() {
    if (_invoice == null || _saving || _listLoading) return;
    _loadList(silent: true);
  }

  Future<void> _loadList({bool silent = false}) async {
    final inv = _invoice;
    if (inv == null) return;
    if (!silent) {
      setState(() {
        _listLoading = true;
        _listError = null;
      });
    }
    try {
      final res =
          await _svc.list(inv, batch: _viewingAll ? null : _viewedBatch);
      if (!mounted || _invoice != inv) return;
      setState(() {
        if (res.batch > 0) _setBatch(res.batch, res.nextBatch);
        _batches = res.batches;
        if (_viewBatch != 'current' &&
            _viewBatch != 'all' &&
            !_batches.any((b) => '${b.batch}' == _viewBatch)) {
          _viewBatch = 'current';
        }
        _rows = res.rows;
        _listLoading = false;
        _listError = null;
      });
    } catch (e) {
      if (!mounted || (silent && _invoice != inv)) return;
      if (silent && _rows.isNotEmpty) return;
      setState(() {
        _listLoading = false;
        _listError = 'Could not load the list.';
      });
    }
  }

  Future<void> _submitScan() async {
    final inv = _invoice;
    if (inv == null || _saving) return;
    final code = _scanCtrl.text.trim();
    if (code.isEmpty) {
      _focusScan();
      return;
    }
    _scanCtrl.clear();
    setState(() => _saving = true);
    try {
      final res = await _svc.scan(code, inv, _customer);
      if (!mounted) return;
      if (res.status == 'saved') {
        setState(() {
          _saved++;
          if (res.batch > 0) _setBatch(res.batch);
          if (_viewBatch != 'current' &&
              _viewBatch != 'all' &&
              _viewBatch != '$_currentBatch') {
            _viewBatch = 'current';
          }
          _feedback = _ScanFeedback('saved', res.code,
              'Saved to $inv · Batch $_currentBatch.');
        });
        RingtoneService.instance.ping();
        _toast('Barcode saved.');
        _loadList();
      } else if (res.status == 'exists') {
        var sub = 'Already exists';
        if (res.invoiceNumber.isNotEmpty) {
          sub += ' on ${res.invoiceNumber}${res.customerName.isNotEmpty ? ' (${res.customerName})' : ''}';
        }
        if (res.firstScanned != null) sub += ' — ${_fmt(res.firstScanned)}';
        setState(() {
          _dupes++;
          _feedback = _ScanFeedback('exists', res.code, '$sub.');
          _flashId = res.id;
        });
        await _openDupe(res);
      } else {
        final msg =
            res.message.isEmpty ? 'Something went wrong.' : res.message;
        setState(() => _feedback = _ScanFeedback('error', code, msg));
        _toast(res.message.isEmpty ? 'Failed to save barcode.' : res.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _feedback = _ScanFeedback(
          'error', code, 'Network error — is the server reachable?'));
      _toast('Network error.');
    } finally {
      if (mounted) setState(() => _saving = false);
      _focusScan();
    }
  }

  Future<T?> _modal<T>(WidgetBuilder builder) async {
    _modalDepth++;
    try {
      return await showDialog<T>(context: context, builder: builder);
    } finally {
      _modalDepth--;
      _focusScan();
    }
  }

  Future<void> _openDupe(BcScanResult res) async {
    var meta = '';
    if (res.invoiceNumber.isNotEmpty) {
      meta =
          'Recorded on ${res.invoiceNumber}${res.customerName.isNotEmpty ? ' · ${res.customerName}' : ''}';
    }
    if (res.batch > 0) meta += '${meta.isEmpty ? '' : ' · '}Batch ${res.batch}';
    if (res.firstScanned != null) {
      meta += '${meta.isEmpty ? '' : ' · '}${_fmt(res.firstScanned)}';
    }
    Timer? auto;
    await _modal<void>((ctx) {
      auto = Timer(const Duration(seconds: 4), () {
        if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
      });
      return WebModal(
        title: 'Barcode Already Recorded',
        icon: Icons.warning_amber,
        width: 480,
        actions: [
          SignalButton(
              label: 'Continue scanning', onPressed: () => Navigator.pop(ctx)),
        ],
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _warn.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _warn.withValues(alpha: 0.4)),
            ),
            child: SelectableText(res.code,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          const Text('This barcode already has a record in the database.',
              textAlign: TextAlign.center),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(meta,
                textAlign: TextAlign.center,
                style: TextStyle(color: ctx.brand.paperDim)),
          ],
        ]),
      );
    });
    auto?.cancel();
    if (mounted) setState(() => _flashId = null);
  }

  Future<void> _openDetail(BcBarcode b) async {
    final delete = await _modal<bool>((ctx) => WebModal(
          title: 'Barcode details',
          subtitle: b.code,
          icon: Icons.qr_code_2,
          width: 520,
          actions: [
            GhostButton(
              label: 'Delete',
              icon: Icons.delete_outline,
              onPressed: () => Navigator.pop(ctx, true),
            ),
            SignalButton(
                label: 'Close', onPressed: () => Navigator.pop(ctx, false)),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ctx.brand.rule),
                ),
                child: SelectableText(b.code,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 26,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: Brand.navy)),
              ),
              const SizedBox(height: 14),
              StationDataRow(
                  label: 'Invoice',
                  value: b.invoiceNumber.isEmpty ? '—' : b.invoiceNumber),
              StationDataRow(
                  label: 'Customer',
                  value: b.customerName.isEmpty ? '—' : b.customerName),
              StationDataRow(
                  label: 'Batch', value: b.batch > 0 ? 'Batch ${b.batch}' : '—'),
              StationDataRow(
                  label: 'Scanned by',
                  value: b.scannedBy.isEmpty ? '—' : b.scannedBy),
              StationDataRow(
                  label: 'Date',
                  value: b.createdAt == null ? '—' : _fmt(b.createdAt)),
            ],
          ),
        ));
    if (delete == true) await _delete(b, confirmFirst: true);
  }

  Future<bool> _confirm(String title, String message, String label,
      {bool danger = false}) async {
    _modalDepth++;
    try {
      return await zbeConfirm(context,
          title: title, message: message, confirm: label, danger: danger);
    } finally {
      _modalDepth--;
      _focusScan();
    }
  }

  Future<bool> _undoWindow(String message, VoidCallback onUndo) async {
    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final c = messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      persist: false,
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () {
          undone = true;
          onUndo();
        },
      ),
    ));
    await c.closed;
    return !undone;
  }

  Future<void> _delete(BcBarcode b, {bool confirmFirst = true}) async {
    if (confirmFirst &&
        !await _confirm('Delete barcode', 'Delete this barcode?', 'Delete',
            danger: true)) {
      _focusScan();
      return;
    }
    if (!mounted) return;
    setState(() => _hidden.add(b.id));
    final commit = await _undoWindow('Barcode deleted', () {
      if (mounted) setState(() => _hidden.remove(b.id));
      _focusScan();
    });
    if (!commit) return;
    try {
      await _svc.delete(b.id);
    } catch (e) {
      _toast('$e');
    }
    if (mounted) setState(() => _hidden.remove(b.id));
    await _loadList();
    _focusScan();
  }

  Future<void> _openNew() async {
    final inv = _invoice;
    if (inv == null) return;
    await _modal<void>((ctx) => _NewBatchDialog(
          invoice: inv,
          currentBatch: _currentBatch,
          nextBatch: _nextBatch,
          batches: _batches,
          onSubmit: (target) async {
            try {
              final res = await _svc.startBatch(inv, target);
              if (!mounted) return null;
              _afterBatchChange(res.batch);
              _toast(res.existingInNew > 0
                  ? 'Now scanning into batch ${res.batch} — it already holds ${res.existingInNew} code(s).'
                  : 'Batch ${res.batch} started.');
              return null;
            } catch (e) {
              final msg = e is BcException
                  ? e.message
                  : 'Network error — could not start the batch.';
              _toast(msg);
              return msg;
            }
          },
        ));
  }

  Future<void> _openReset() async {
    final inv = _invoice;
    if (inv == null) return;
    final target = await _modal<int>((ctx) => _ResetBatchDialog(
          invoice: inv,
          currentBatch: _currentBatch,
          batches: _batches,
        ));
    if (target == null || _invoice != inv) return;
    final n = _batches
        .firstWhere((b) => b.batch == target,
            orElse: () => BcBatch(batch: target, count: 0))
        .count;
    final sure = await _confirm(
      'Reset batch $target on $inv?',
      'This permanently deletes its $n barcode(s), then scanning continues into batch $target so you can re-scan it.\n\nThis cannot be undone.',
      'Reset batch',
      danger: true,
    );
    if (!sure || !mounted) return;
    final commit =
        await _undoWindow('Batch $target reset — $n code(s) deleted', _focusScan);
    if (!commit) return;
    try {
      final res = await _svc.clearBatch(inv, target);
      if (mounted) _afterBatchChange(res.batch);
    } catch (e) {
      _toast(e is BcException ? e.message : 'Network error — could not reset the batch.');
    }
  }

  void _afterBatchChange(int batch) {
    setState(() {
      _setBatch(batch);
      _viewBatch = 'current';
      _saved = 0;
      _dupes = 0;
      _feedback = null;
    });
    _loadList();
    _focusScan();
  }

  static const _navy = Color(0xFF0C233E);
  static const _faint = Color(0xFF8A94A6);
  static const _amber = Color(0xFFB45309);

  Color get _border =>
      zbeDark(context) ? context.brand.rule : const Color(0xFFE5E8EC);
  Color get _border2 =>
      zbeDark(context) ? context.brand.rule : const Color(0xFFEEF1F4);
  Color get _ink => zbeDark(context) ? context.brand.paper : _navy;
  Color get _muted =>
      zbeDark(context) ? context.brand.paperDim : const Color(0xFF5B6675);
  Color get _soft =>
      zbeDark(context) ? context.brand.surfaceHi : const Color(0xFFFBFCFD);

  @override
  Widget build(BuildContext context) {
    final selected = _invoice != null;
    return StationScaffold(
      stationNumber: 'BC',
      stationLabel: 'BARCODE',
      title: 'Barcode Scanner',
      showBottomBrand: false,
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 24),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < 1000 || box.maxHeight < 600) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerLeft, child: _statusPill()),
                  const SizedBox(height: 22),
                  _invoiceCard(),
                  const SizedBox(height: 16),
                  _scanCard(selected),
                  const SizedBox(height: 16),
                  SizedBox(height: 520, child: _listCard(selected)),
                ],
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: _statusPill()),
              const SizedBox(height: 22),
              _invoiceCard(),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 115, child: _scanCard(selected)),
                    const SizedBox(width: 16),
                    Expanded(flex: 85, child: _listCard(selected)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statusPill() {
    final ready = _invoice != null;
    final dark = zbeDark(context);
    final fg = ready ? _ok : _faint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: ready
            ? (dark ? _ok.withValues(alpha: 0.14) : const Color(0xFFECFDF3))
            : context.brand.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
            color: ready
                ? (dark ? _ok.withValues(alpha: 0.4) : const Color(0xFFBBF7D0))
                : _border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: ready ? _ok : const Color(0xFFC6CCD4),
            shape: BoxShape.circle,
            boxShadow: ready
                ? [
                    BoxShadow(
                        color: _ok.withValues(alpha: 0.15), spreadRadius: 4)
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(ready ? 'Scanner ready · $_invoice' : 'No invoice selected',
            style: TextStyle(
                fontSize: 12.8, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }

  Widget _card({
    required Widget child,
    String? step,
    String? title,
    List<Widget> headExtras = const [],
    Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: _border2)),
              ),
              child: Row(children: [
                if (step != null) ...[
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: zbeDark(context) ? Brand.signal : _navy,
                        borderRadius: BorderRadius.circular(7)),
                    child: Text(step,
                        style: const TextStyle(
                            fontSize: 12.8,
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _ink)),
                      ...headExtras,
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 10), trailing],
              ]),
            ),
          if (box.hasBoundedHeight) Flexible(child: child) else child,
        ],
      ),
      ),
    );
  }

  Widget _pair(String k, String v, {bool mono = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(k.toUpperCase(),
            style: const TextStyle(
                fontSize: 10.9,
                letterSpacing: 0.65,
                fontWeight: FontWeight.w600,
                color: _faint)),
        const SizedBox(height: 2),
        Text(v,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: mono ? 'monospace' : null,
                color: mono ? Brand.signal : _ink)),
      ],
    );
  }

  Widget _invoiceCard() {
    if (_invoice != null) {
      return _card(
        step: '1',
        title: 'Invoice',
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            _pair('Invoice', _invoice!, mono: true),
            const SizedBox(width: 22),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    _pair('Customer', _customer.isEmpty ? '—' : _customer),
              ),
            ),
            _BcTextBtn(
              label: 'Change invoice',
              icon: Icons.undo,
              big: true,
              onTap: _change,
            ),
          ]),
        ),
      );
    }
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: _border, width: 1.5),
    );
    return _card(
      step: '1',
      title: 'Invoice',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('SEARCH BY INVOICE NUMBER OR CUSTOMER',
                style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w600,
                    color: _faint)),
            const SizedBox(height: 8),
            TextField(
              controller: _invSearch,
              focusNode: _invFocus,
              onChanged: _onSearch,
              style: TextStyle(fontSize: 15.7, color: _ink),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: _soft,
                hintText: 'e.g. INV-00021 or customer name',
                hintStyle:
                    const TextStyle(fontSize: 15.7, color: Color(0xFFAAB2BD)),
                prefixIcon:
                    const Icon(Icons.search, size: 18, color: _faint),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                border: inputBorder,
                enabledBorder: inputBorder,
                focusedBorder: inputBorder.copyWith(
                    borderSide:
                        const BorderSide(color: Brand.signal, width: 1.5)),
              ),
            ),
            if (_searching || _searchMsg != null || _hits.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  color: context.brand.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                        color: _navy.withValues(alpha: 0.14),
                        blurRadius: 40,
                        offset: const Offset(0, 18)),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _searching || _searchMsg != null
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_searching ? 'Searching…' : _searchMsg!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 14, color: _faint)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _hits.length,
                        itemBuilder: (_, i) {
                          final h = _hits[i];
                          return ZbeRow(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            ruleColor: i == _hits.length - 1
                                ? Colors.transparent
                                : _border2,
                            hoverColor: zbeTint(context,
                                const Color(0xFFFFF7ED), Brand.signal, 0.08),
                            onTap: () {
                              if (h.invoice.isEmpty) {
                                _toast('That record has no invoice number.');
                                return;
                              }
                              _select(h.invoice, h.customer);
                            },
                            cells: [
                              Text(h.invoice.isEmpty ? '—' : h.invoice,
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 14.4,
                                      fontWeight: FontWeight.w600,
                                      color: Brand.signal)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                    h.customer.isEmpty
                                        ? 'Unknown customer'
                                        : h.customer,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 14, color: _muted)),
                              ),
                            ],
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scanCard(bool selected) {
    final dark = zbeDark(context);
    Color fbColor(String k) =>
        k == 'saved' ? _ok : (k == 'exists' ? _amber : _bad);
    Color fbBg(String k) => dark
        ? fbColor(k).withValues(alpha: 0.12)
        : (k == 'saved'
            ? const Color(0xFFECFDF3)
            : (k == 'exists'
                ? const Color(0xFFFFF8EB)
                : const Color(0xFFFEF2F2)));
    Color fbBorder(String k) => dark
        ? fbColor(k).withValues(alpha: 0.35)
        : (k == 'saved'
            ? const Color(0xFFBBF7D0)
            : (k == 'exists'
                ? const Color(0xFFFDE9C0)
                : const Color(0xFFFECACA)));
    IconData fbIcon(String k) => k == 'saved'
        ? Icons.check_circle
        : (k == 'exists' ? Icons.history : Icons.warning);

    Widget stat(String label, int n, Color? c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Column(children: [
              Text('$n',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 21.6,
                      height: 1,
                      fontWeight: FontWeight.w600,
                      color: c ?? _ink)),
              const SizedBox(height: 5),
              Text(label.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10.9,
                      letterSpacing: 0.55,
                      fontWeight: FontWeight.w600,
                      color: _faint)),
            ]),
          ),
        );

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(11),
      borderSide: BorderSide(color: _border, width: 1.5),
    );

    final reader = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected
                ? Brand.signal.withValues(alpha: 0.45)
                : _border,
            width: 1.5),
        gradient: dark
            ? null
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFBFCFD), Color(0xFFF7F9FB)]),
        color: dark ? context.brand.surfaceHi : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _border)),
            ),
            child: Row(children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selected ? _ok : const Color(0xFFCBD2DA),
                  shape: BoxShape.circle,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                              color: _ok.withValues(alpha: 0.18),
                              spreadRadius: 3)
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              const Text('SCANNER INPUT',
                  style: TextStyle(
                      fontSize: 10.9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600,
                      color: _faint)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _scanCtrl,
                      focusNode: _scanFocus,
                      enabled: selected,
                      autofocus: selected,
                      expands: true,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.center,
                      onSubmitted: (_) => _submitScan(),
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 21.6,
                          letterSpacing: 0.4,
                          color: _ink),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: selected
                            ? context.brand.surface
                            : (dark
                                ? context.brand.surfaceHi
                                : const Color(0xFFF1F3F5)),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(left: 16, right: 10),
                          child: Icon(Icons.barcode_reader,
                              size: 20, color: _faint),
                        ),
                        prefixIconConstraints:
                            const BoxConstraints(minWidth: 46),
                        hintText: selected
                            ? 'Waiting for scan…'
                            : 'Select an invoice first…',
                        hintStyle: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 21.6,
                            color: Color(0xFF9AA3B0)),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 18),
                        border: fieldBorder,
                        enabledBorder: fieldBorder,
                        disabledBorder: fieldBorder,
                        focusedBorder: fieldBorder.copyWith(
                            borderSide: const BorderSide(
                                color: Brand.signal, width: 1.5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _BcSaveButton(
                    busy: _saving,
                    onTap: selected ? _submitScan : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: selected ? 1 : 0.55,
      child: IgnorePointer(
        ignoring: !selected,
        child: _card(
          step: '2',
          title: 'Scan',
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                reader,
                if (_feedback != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: fbBg(_feedback!.kind),
                      borderRadius: BorderRadius.circular(10),
                      border: Border(
                        left: BorderSide(
                            color: fbColor(_feedback!.kind), width: 4),
                        top: BorderSide(color: fbBorder(_feedback!.kind)),
                        right: BorderSide(color: fbBorder(_feedback!.kind)),
                        bottom: BorderSide(color: fbBorder(_feedback!.kind)),
                      ),
                    ),
                    child: Row(children: [
                      Icon(fbIcon(_feedback!.kind),
                          size: 20, color: fbColor(_feedback!.kind)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_feedback!.code,
                                  style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                      color: fbColor(_feedback!.kind))),
                              const SizedBox(height: 2),
                              Text(_feedback!.sub,
                                  style: TextStyle(
                                      fontSize: 12.3,
                                      fontWeight: FontWeight.w500,
                                      color: fbColor(_feedback!.kind))),
                            ]),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  const SizedBox(width: 2),
                  const Icon(Icons.info, size: 13, color: _faint),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                        'Keep this field focused — most scanners type the code and press Enter automatically.',
                        style: const TextStyle(fontSize: 12.5, color: _faint)),
                  ),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  stat('Saved', _saved, _ok),
                  const SizedBox(width: 10),
                  stat('Duplicates', _dupes, _amber),
                  const SizedBox(width: 10),
                  stat('On invoice', _rows.length, null),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(IconData icon, String msg) => SizedBox(
        height: 240,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 29, color: const Color(0xFFCDD4DD)),
              const SizedBox(height: 10),
              Text(msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14.4, height: 1.55, color: _faint)),
            ]),
          ),
        ),
      );

  Widget _listCard(bool selected) {
    final q = _filterCtrl.text.trim().toLowerCase();
    final visible = _rows
        .where((b) => !_hidden.contains(b.id))
        .where((b) => q.isEmpty || b.code.toLowerCase().contains(q))
        .toList();
    final total = _batches.fold<int>(0, (n, b) => n + b.count);

    final scopeItems = <DropdownMenuItem<String>>[
      DropdownMenuItem(
          value: 'current', child: Text('Batch $_currentBatch (current)')),
      for (final b in _batches)
        if (b.batch != _currentBatch)
          DropdownMenuItem(
              value: '${b.batch}',
              child: Text('Batch ${b.batch} (${b.count})')),
      DropdownMenuItem(value: 'all', child: Text('All batches ($total)')),
    ];
    final scopeValue =
        scopeItems.any((i) => i.value == _viewBatch) ? _viewBatch : 'current';
    final offCurrent = scopeValue != 'current';

    Widget body;
    if (!selected) {
      body = _empty(
          Icons.inbox, 'Select an invoice to see its scanned barcodes.');
    } else if (_listLoading && _rows.isEmpty) {
      body = const SizedBox(height: 240, child: ZbeStateView(loading: true));
    } else if (_listError != null) {
      body = _empty(Icons.warning, 'Could not load the list.');
    } else if (_rows.isEmpty) {
      final msg = _viewingAll
          ? 'No barcodes scanned for this invoice yet.\nScan one to begin.'
          : (_viewedBatch == _currentBatch
              ? 'Batch $_currentBatch is empty.\nScan a barcode to begin.'
              : 'Batch $_viewedBatch has no barcodes.');
      body = _empty(Icons.view_week, msg);
    } else {
      body = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 240),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: visible.length,
          itemBuilder: (_, i) =>
              _row(visible[i], last: i == visible.length - 1),
        ),
      );
    }

    final dark = zbeDark(context);
    final filterBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: _border),
    );

    return _card(
      title: 'Scanned',
      headExtras: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: dark ? context.brand.surfaceHi : const Color(0xFFEEF1F4),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('${_rows.length}',
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _ink)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: Brand.signal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Brand.signal.withValues(alpha: 0.25)),
          ),
          child: Text('Batch $_currentBatch',
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Brand.signal)),
        ),
      ],
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _BcTextBtn(
          label: 'New batch',
          icon: Icons.add,
          accent: true,
          onTap: selected ? _openNew : null,
        ),
        const SizedBox(width: 10),
        _BcTextBtn(
          label: 'Reset',
          icon: Icons.undo,
          onTap: selected ? _openReset : null,
        ),
        const SizedBox(width: 10),
        _BcTextBtn(
          icon: Icons.sync,
          tooltip: 'Refresh',
          onTap: () {
            _loadList();
            _focusScan();
          },
        ),
      ]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _border2)),
            ),
            child: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _filterCtrl,
                    onChanged: (_) => setState(() {}),
                    expands: true,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.center,
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 13.6, color: _ink),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: _soft,
                      hintText: 'Filter scanned codes…',
                      hintStyle: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13.6,
                          color: _faint),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 12, right: 6),
                        child:
                            Icon(Icons.filter_alt, size: 15, color: _faint),
                      ),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 32),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      border: filterBorder,
                      enabledBorder: filterBorder,
                      focusedBorder: filterBorder.copyWith(
                          borderSide: const BorderSide(color: Brand.signal)),
                    ),
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                Container(
                  height: 36,
                  constraints: const BoxConstraints(maxWidth: 200),
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  decoration: BoxDecoration(
                    color: offCurrent
                        ? zbeTint(context, const Color(0xFFFFF7ED),
                            Brand.signal, 0.1)
                        : _soft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: offCurrent
                            ? Brand.signal.withValues(alpha: 0.35)
                            : _border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: scopeValue,
                      isDense: true,
                      borderRadius: BorderRadius.circular(8),
                      icon: Icon(Icons.keyboard_arrow_down,
                          size: 16,
                          color: offCurrent ? Brand.signal : _muted),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: offCurrent ? Brand.signal : _muted),
                      items: scopeItems,
                      onChanged: (v) {
                        setState(() => _viewBatch = v ?? 'current');
                        _loadList();
                        _focusScan();
                      },
                    ),
                  ),
                ),
              ],
            ]),
          ),
          if (_listLoading && _rows.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2, color: Brand.signal),
          Flexible(child: body),
        ],
      ),
    );
  }

  Widget _row(BcBarcode b, {bool last = false}) {
    final flash = _flashId == b.id;
    return ZbeRow(
      onTap: () => _openDetail(b),
      color: flash
          ? zbeTint(context, const Color(0xFFFFF2E0), Brand.signal, 0.15)
          : null,
      hoverColor: zbeDark(context)
          ? context.brand.surfaceHi
          : const Color(0xFFF7F9FB),
      ruleColor: last ? Colors.transparent : _border2,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      cells: [
        Container(
          width: 8,
          height: 8,
          decoration:
              const BoxDecoration(color: _ok, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(b.code,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14.7,
                      fontWeight: FontWeight.w600,
                      color: _ink)),
              const SizedBox(height: 2),
              Text(
                  '${b.scannedBy.isEmpty ? '—' : b.scannedBy} · ${_fmt(b.createdAt)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.8, color: _faint)),
            ],
          ),
        ),
        if (_viewingAll) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: zbeDark(context)
                  ? context.brand.surfaceHi
                  : const Color(0xFFEEF1F4),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('B${b.batch > 0 ? b.batch : 1}',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.9,
                    fontWeight: FontWeight.w600,
                    color: _muted)),
          ),
        ],
        const SizedBox(width: 12),
        _BcDeleteButton(onTap: () => _delete(b)),
      ],
    );
  }
}

class _BcTextBtn extends StatefulWidget {
  const _BcTextBtn({
    this.label,
    required this.icon,
    required this.onTap,
    this.accent = false,
    this.big = false,
    this.tooltip,
  });

  final String? label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool accent;
  final bool big;
  final String? tooltip;

  @override
  State<_BcTextBtn> createState() => _BcTextBtnState();
}

class _BcTextBtnState extends State<_BcTextBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const orange = Brand.signal;
    final dark = zbeDark(context);
    final enabled = widget.onTap != null;
    final border0 = dark ? context.brand.rule : const Color(0xFFE5E8EC);
    final muted = dark ? context.brand.paperDim : const Color(0xFF5B6675);
    final navy = dark ? context.brand.paper : const Color(0xFF0C233E);
    final hov = _hover && enabled;
    Color bg = context.brand.surface;
    Color fg = widget.big ? navy : muted;
    Color bd = border0;
    if (widget.accent) {
      bg = hov ? orange : zbeTint(context, const Color(0xFFFFF7ED), orange);
      fg = hov ? Colors.white : orange;
      bd = orange.withValues(alpha: hov ? 1 : 0.35);
    } else if (hov) {
      bg = widget.label == null
          ? (dark ? context.brand.surfaceHi : const Color(0xFFF3F5F7))
          : (widget.big
              ? context.brand.surface
              : zbeTint(context, const Color(0xFFFFF7ED), orange));
      fg = widget.label == null ? navy : orange;
      bd = orange;
    }
    final h = widget.big ? 38.0 : 32.0;
    Widget w = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            height: h,
            width: widget.label == null ? 32 : null,
            padding: widget.label == null
                ? null
                : EdgeInsets.symmetric(horizontal: widget.big ? 14 : 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.big ? 9 : 8),
              border: Border.all(color: bd, width: widget.big ? 1.5 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.icon, size: widget.big ? 14 : 14, color: fg),
              if (widget.label != null) ...[
                const SizedBox(width: 7),
                Text(widget.label!,
                    style: TextStyle(
                        fontSize: widget.big ? 13.1 : 12.8,
                        fontWeight: FontWeight.w600,
                        color: fg)),
              ],
            ]),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      w = Tooltip(message: widget.tooltip!, child: w);
    }
    return w;
  }
}

class _BcSaveButton extends StatefulWidget {
  const _BcSaveButton({required this.onTap, required this.busy});
  final VoidCallback? onTap;
  final bool busy;

  @override
  State<_BcSaveButton> createState() => _BcSaveButtonState();
}

class _BcSaveButtonState extends State<_BcSaveButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.busy;
    final bg = !enabled
        ? const Color(0xFFD9DDE2)
        : (_hover ? const Color(0xFFE67000) : Brand.signal);
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.busy ? Brand.signal : bg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: TpLoader(
                    strokeWidth: 2, color: Colors.white),
              )
            else
              const Icon(Icons.check, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            const Text('Save',
                style: TextStyle(
                    fontSize: 15.7,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}

class _BcDeleteButton extends StatefulWidget {
  const _BcDeleteButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_BcDeleteButton> createState() => _BcDeleteButtonState();
}

class _BcDeleteButtonState extends State<_BcDeleteButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Delete',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover
                  ? zbeTint(context, const Color(0xFFFEF2F2), _bad)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(Icons.delete,
                size: 15, color: _hover ? _bad : const Color(0xFFC0C6D0)),
          ),
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
    required this.onSubmit,
  });
  final String invoice;
  final int currentBatch;
  final int nextBatch;
  final List<BcBatch> batches;
  final Future<String?> Function(String target) onSubmit;

  @override
  State<_NewBatchDialog> createState() => _NewBatchDialogState();
}

class _NewBatchDialogState extends State<_NewBatchDialog> {
  late final _num = TextEditingController(text: '${widget.nextBatch}');
  int? _continue;
  bool _busy = false;
  String? _serverError;

  Future<void> _submit(bool valid) async {
    if (_busy || !valid) return;
    final target = _continue != null ? '$_continue' : _num.text.trim();
    setState(() {
      _busy = true;
      _serverError = null;
    });
    final err = await widget.onSubmit(target);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = false;
      _serverError = err;
    });
  }

  @override
  void dispose() {
    _num.dispose();
    super.dispose();
  }

  String _meta(BcBatch b) {
    if (b.count == 0) return 'Empty';
    return '${b.count} code(s)${b.lastScan != null ? ' · last scan ${_fmt(b.lastScan)}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final others =
        widget.batches.where((b) => b.batch != widget.currentBatch).toList();
    String? note;
    Color noteColor = _warn;
    var valid = true;
    if (_continue != null) {
      final b = widget.batches.firstWhere((x) => x.batch == _continue,
          orElse: () => BcBatch(batch: _continue!, count: 0));
      note =
          'Batch $_continue already has ${b.count} code(s). Scanning will add to it — nothing is deleted.';
    } else {
      final raw = _num.text.trim();
      final n = RegExp(r'^\d+$').hasMatch(raw) ? int.tryParse(raw) : null;
      if (n == null || n < 1) {
        valid = false;
        note = 'Enter a whole batch number of 1 or more.';
        noteColor = _bad;
      } else if (n == widget.currentBatch) {
        valid = false;
        note = 'Batch $n is already the current batch.';
        noteColor = _bad;
      } else {
        final clash = widget.batches.where((x) => x.batch == n).firstOrNull;
        if (clash != null) {
          note =
              'Batch $n already has ${clash.count} code(s). New scans will be added to it.';
        }
      }
    }
    if (_serverError != null) {
      note = _serverError;
      noteColor = _bad;
    }

    Widget choice({
      required bool selected,
      required String title,
      required String meta,
      required VoidCallback onTap,
    }) =>
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: selected ? Brand.signal.withValues(alpha: 0.05) : null,
              border: Border.all(
                  color: selected ? Brand.signal : context.brand.rule,
                  width: selected ? 1.5 : 1),
            ),
            child: Row(children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18, color: selected ? Brand.signal : null),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(meta,
                          style: TextStyle(
                              fontSize: 12, color: context.brand.paperDim)),
                    ]),
              ),
            ]),
          ),
        );

    return WebModal(
      title: 'Start a new batch',
      subtitle: widget.invoice,
      icon: Icons.add_box_outlined,
      width: 540,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        SignalButton(
          icon: _continue != null ? Icons.play_arrow : Icons.add,
          label:
              _continue != null ? 'Continue batch $_continue' : 'Start batch',
          onPressed: (_busy || !valid) ? null : () => _submit(valid),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              'Scanning on ${widget.invoice} moves from Batch ${widget.currentBatch} to the batch you pick. Every code already saved is kept — nothing is deleted.'),
          const SizedBox(height: 14),
          choice(
            selected: _continue == null,
            title: 'A fresh batch',
            meta: 'Starts empty — scanning begins from zero',
            onTap: () => setState(() {
              _continue = null;
              _serverError = null;
            }),
          ),
          if (_continue == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _num,
                autofocus: true,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _serverError = null),
                onSubmitted: (_) => _submit(valid),
                decoration: const InputDecoration(labelText: 'Batch number'),
              ),
            ),
          for (final b in others)
            choice(
              selected: _continue == b.batch,
              title: 'Continue Batch ${b.batch}',
              meta: '${_meta(b)} — new scans are added to it',
              onTap: () => setState(() {
                _continue = b.batch;
                _serverError = null;
              }),
            ),
          if (note != null)
            Text(note, style: TextStyle(color: noteColor, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ResetBatchDialog extends StatefulWidget {
  const _ResetBatchDialog({
    required this.invoice,
    required this.currentBatch,
    required this.batches,
  });
  final String invoice;
  final int currentBatch;
  final List<BcBatch> batches;

  @override
  State<_ResetBatchDialog> createState() => _ResetBatchDialogState();
}

class _ResetBatchDialogState extends State<_ResetBatchDialog> {
  int? _target;

  @override
  Widget build(BuildContext context) {
    final cur = widget.batches
        .where((b) => b.batch == widget.currentBatch)
        .firstOrNull;
    final sel = _target == null
        ? null
        : widget.batches.where((b) => b.batch == _target).firstOrNull;
    final n = sel?.count ?? 0;

    return WebModal(
      title: 'Reset batch',
      subtitle: widget.invoice,
      icon: Icons.restart_alt,
      width: 540,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        DangerButton(
          icon: Icons.delete_outline,
          label: _target == null ? 'Reset batch' : 'Reset Batch $_target',
          onPressed: (_target == null || n == 0)
              ? null
              : () => Navigator.pop(context, _target),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              'Now scanning into Batch ${widget.currentBatch} on ${widget.invoice} — ${cur?.count ?? 0} code(s) saved in it so far. Pick the batch to reset: its codes are deleted and scanning continues into it.'),
          const SizedBox(height: 14),
          if (widget.batches.isEmpty)
            Text('This invoice has no batches yet.',
                style: TextStyle(color: context.brand.paperDim)),
          for (final b in widget.batches)
            InkWell(
              onTap: () => setState(() => _target = b.batch),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: _target == b.batch ? _bad.withValues(alpha: 0.05) : null,
                  border: Border.all(
                      color: _target == b.batch ? _bad : context.brand.rule,
                      width: _target == b.batch ? 1.5 : 1),
                ),
                child: Row(children: [
                  Icon(
                      _target == b.batch
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: _target == b.batch ? _bad : null),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Batch ${b.batch}${b.batch == widget.currentBatch ? ' (current)' : ''}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                              b.count > 0
                                  ? 'Deletes its ${b.count} code(s), then scan into it again'
                                  : 'Already empty — nothing to reset',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: context.brand.paperDim)),
                        ]),
                  ),
                ]),
              ),
            ),
          if (_target != null)
            Text(
              n > 0
                  ? 'This permanently deletes the $n code(s) in batch $_target, then scanning continues into batch $_target so you can re-scan it. This cannot be undone.'
                  : 'Batch $_target is already empty — there is nothing to reset.',
              style: TextStyle(fontSize: 12.5, color: n > 0 ? _bad : _warn),
            ),
        ],
      ),
    );
  }
}
