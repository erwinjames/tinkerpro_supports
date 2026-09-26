part of 'client_screen.dart';

const Map<String, IconData> _kDeliveryDocIcons = <String, IconData>{
  'invoice-pdf': Icons.request_quote_rounded,
  'delivery-note-pdf': Icons.local_shipping_rounded,
  'packing-slip-pdf': Icons.inventory_2_rounded,
  'waybill-pdf': Icons.receipt_long_rounded,
  'acknowledgement-receipt-pdf': Icons.draw_rounded,
  'return-refund-policy-pdf': Icons.undo_rounded,
};

const Color _pdfStage = Color(0xFF525659);
const double _previewDpi = 180;
const double _printDpi = 200;
const List<double> _zoomSteps = <double>[
  0.5,
  0.67,
  0.75,
  0.9,
  1,
  1.1,
  1.25,
  1.5,
  1.75,
  2,
  2.5,
  3,
];

class _DeliveryDocsViewer extends StatefulWidget {
  const _DeliveryDocsViewer({
    super.key,
    required this.service,
    required this.deliveryId,
    required this.deliveryNo,
  });

  final ClientService service;
  final String deliveryId;
  final String deliveryNo;

  @override
  State<_DeliveryDocsViewer> createState() => _DeliveryDocsViewerState();
}

class _DeliveryDocsViewerState extends State<_DeliveryDocsViewer> {
  final Map<String, Uint8List> _bytes = <String, Uint8List>{};
  final Map<String, Future<Uint8List>> _inflight =
      <String, Future<Uint8List>>{};
  final Map<String, List<ui.Image>> _pages = <String, List<ui.Image>>{};
  final Map<String, String> _errors = <String, String>{};
  final Set<String> _rendering = <String>{};
  final ScrollController _v = ScrollController();
  final ScrollController _h = ScrollController();
  Future<void> _gate = Future<void>.value();
  String _doc = 'invoice-pdf';
  double _zoom = 1;
  int _page = 1;
  bool _saving = false;
  bool _printingOne = false;
  bool _printingMany = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _v.addListener(_trackPage);
    _show(_doc);
    if (kDebugMode) {
      final d = Platform.environment['TP_DELIVERY_DOC'];
      if (d != null && kDeliveryDocuments.containsKey(d) && d != _doc) {
        WidgetsBinding.instance.addPostFrameCallback((_) => select(d));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _v.dispose();
    _h.dispose();
    for (final list in _pages.values) {
      for (final img in list) {
        img.dispose();
      }
    }
    _pages.clear();
    super.dispose();
  }

  String get _label => kDeliveryDocuments[_doc] ?? 'Document';

  String _fileName(String doc) {
    final label = kDeliveryDocuments[doc] ?? 'Document';
    final no = widget.deliveryNo.trim();
    return no.isEmpty ? label : '$label - $no';
  }

  Future<Uint8List> _bytesFor(String doc) {
    final cached = _bytes[doc];
    if (cached != null) return Future<Uint8List>.value(cached);
    final pending = _inflight[doc];
    if (pending != null) return pending;
    final run = _gate.then(
        (_) => widget.service.fetchDeliveryPdf(widget.deliveryId, doc));
    _gate = run.then<void>((_) {}, onError: (_) {});
    final future = run.then((b) {
      _bytes[doc] = b;
      return b;
    }).whenComplete(() {
      _inflight.remove(doc);
    });
    _inflight[doc] = future;
    return future;
  }

  Future<void> _show(String doc) async {
    if (_pages.containsKey(doc) || _rendering.contains(doc)) return;
    _rendering.add(doc);
    try {
      final bytes = await _bytesFor(doc);
      if (_disposed) return;
      final images = <ui.Image>[];
      await for (final r in Printing.raster(bytes, dpi: _previewDpi)) {
        final img = await r.toImage();
        images.add(img);
        if (_disposed) {
          _disposeLater(images);
          return;
        }
      }
      if (images.isEmpty) {
        throw DeliveryException('This document has no pages.');
      }
      _pages[doc] = images;
      _errors.remove(doc);
    } catch (e) {
      if (_disposed) return;
      _errors[doc] = _deliveryErrorText(e, 'Could not load this document.');
    } finally {
      _rendering.remove(doc);
    }
    if (mounted) setState(() {});
  }

  void _disposeLater(List<ui.Image> images) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final i in images) {
        i.dispose();
      }
    });
  }

  void select(String doc) {
    if (!kDeliveryDocuments.containsKey(doc)) return;
    if (doc == _doc) return;
    setState(() {
      _doc = doc;
      _page = 1;
      _zoom = 1;
    });
    if (_v.hasClients) _v.jumpTo(0);
    if (_h.hasClients) _h.jumpTo(0);
    _show(doc);
  }

  void reloadCurrent() {
    final doc = _doc;
    if (_inflight.containsKey(doc) || _rendering.contains(doc)) return;
    _bytes.remove(doc);
    final old = _pages.remove(doc);
    if (old != null) _disposeLater(old);
    setState(() {
      _errors.remove(doc);
      _page = 1;
    });
    _show(doc);
  }

  void _retry() {
    final doc = _doc;
    setState(() => _errors.remove(doc));
    _show(doc);
  }

  void _trackPage() {
    final images = _pages[_doc];
    if (images == null || !_v.hasClients) return;
    final width = _lastPageWidth;
    if (width <= 0) return;
    final probe = _v.offset + _v.position.viewportDimension / 3;
    var y = _stagePad;
    var page = images.length;
    for (var i = 0; i < images.length; i++) {
      final h = width * images[i].height / images[i].width;
      if (probe < y + h + _pageGap / 2) {
        page = i + 1;
        break;
      }
      y += h + _pageGap;
    }
    if (page != _page) setState(() => _page = page);
  }

  double _lastPageWidth = 0;
  static const double _stagePad = 14;
  static const double _pageGap = 12;

  void _zoomBy(int dir) {
    var idx = _zoomSteps.indexWhere((z) => z >= _zoom - 0.001);
    if (idx == -1) idx = _zoomSteps.length - 1;
    if (dir > 0) {
      if (_zoomSteps[idx] <= _zoom + 0.001) idx++;
    } else {
      idx--;
    }
    idx = idx.clamp(0, _zoomSteps.length - 1);
    setState(() => _zoom = _zoomSteps[idx]);
  }

  Future<void> _download() async {
    final bytes = _bytes[_doc];
    if (bytes == null || _saving) return;
    setState(() => _saving = true);
    try {
      final path =
          await widget.service.saveDeliveryPdf(bytes, _fileName(_doc));
      if (!mounted) return;
      _snack(
        context,
        'Saved to $path',
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => OpenFilex.open(path, type: 'application/pdf'),
        ),
      );
    } catch (_) {
      if (mounted) _snack(context, 'Could not save the PDF.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printCurrent() async {
    final bytes = _bytes[_doc];
    if (bytes == null || _printingOne || _printingMany) return;
    setState(() => _printingOne = true);
    try {
      await Printing.layoutPdf(
        name: _fileName(_doc),
        onLayout: (_) async => bytes,
      );
    } catch (_) {
      if (mounted) _snack(context, 'Could not open the print dialog.');
    } finally {
      if (mounted) setState(() => _printingOne = false);
    }
  }

  Future<void> printSelected() async {
    if (_printingMany || _printingOne) return;
    final docs = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _PrintDocsDialog(),
    );
    if (docs == null || !mounted) return;
    if (docs.isEmpty) {
      _snack(context, 'Select at least one document to print.');
      return;
    }
    setState(() => _printingMany = true);
    try {
      final valid = <Uint8List>[];
      final failed = <String>[];
      for (final d in docs) {
        try {
          valid.add(await _bytesFor(d));
        } catch (_) {
          failed.add(kDeliveryDocuments[d] ?? d);
        }
        if (_disposed) return;
      }
      if (valid.isEmpty) {
        if (mounted) _snack(context, 'No printable PDFs were returned.');
        return;
      }
      final job = valid.length == 1 ? valid.first : await _merge(valid);
      if (!mounted) return;
      if (failed.isNotEmpty) {
        _snack(context, 'Skipped (could not load): ${failed.join(', ')}');
      }
      final no = widget.deliveryNo.trim();
      await Printing.layoutPdf(
        name: docs.length == 1
            ? _fileName(docs.first)
            : (no.isEmpty ? 'Delivery documents' : 'Delivery documents - $no'),
        onLayout: (_) async => job,
      );
    } catch (_) {
      if (mounted) _snack(context, 'Could not prepare the printout.');
    } finally {
      if (mounted) setState(() => _printingMany = false);
    }
  }

  Future<Uint8List> _merge(List<Uint8List> docs) async {
    final out = pw.Document(compress: true);
    var count = 0;
    for (final bytes in docs) {
      try {
        await for (final r in Printing.raster(bytes, dpi: _printDpi)) {
          final format = PdfPageFormat(
            r.width * PdfPageFormat.inch / _printDpi,
            r.height * PdfPageFormat.inch / _printDpi,
          );
          final image =
              pw.RawImage(bytes: r.pixels, width: r.width, height: r.height);
          out.addPage(pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(image, fit: pw.BoxFit.fill),
            ),
          ));
          count++;
        }
      } catch (_) {}
    }
    if (count == 0) throw DeliveryException('Merged PDF has no pages.');
    return out.save();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(_radiusLg),
        border: Border.all(color: b.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in kDeliveryDocuments.entries)
                  _DocTab(
                    label: e.value,
                    icon: _kDeliveryDocIcons[e.key] ??
                        Icons.picture_as_pdf_rounded,
                    active: e.key == _doc,
                    loading: _inflight.containsKey(e.key),
                    onTap: () => select(e.key),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: b.rule),
          _toolbar(context),
          Expanded(child: _stage(context)),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final images = _pages[_doc];
    final ready = images != null && _bytes[_doc] != null;
    final pageInfo = images == null
        ? '—'
        : 'Page ${_page.clamp(1, images.length)} of ${images.length}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
          Text(pageInfo, style: text.bodySmall),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Zoom out',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: ready && _zoom > _zoomSteps.first + 0.001
                ? () => _zoomBy(-1)
                : null,
            icon: const Icon(Icons.zoom_out_rounded),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${(_zoom * 100).round()}%',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ),
          IconButton(
            tooltip: 'Zoom in',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: ready && _zoom < _zoomSteps.last - 0.001
                ? () => _zoomBy(1)
                : null,
            icon: const Icon(Icons.zoom_in_rounded),
          ),
          IconButton(
            tooltip: 'Fit width',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: ready && (_zoom - 1).abs() > 0.001
                ? () => setState(() => _zoom = 1)
                : null,
            icon: const Icon(Icons.fit_screen_rounded),
          ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
          _ToolButton(
            label: 'Download',
            icon: Icons.download_rounded,
            busy: _saving,
            onPressed: ready ? _download : null,
          ),
          _ToolButton(
            label: 'Print',
            icon: Icons.print_outlined,
            busy: _printingOne,
            onPressed: ready && !_printingMany ? _printCurrent : null,
          ),
          _ToolButton(
            label: _printingMany ? 'Preparing…' : 'Print selected',
            icon: Icons.print_rounded,
            busy: _printingMany,
            filled: true,
            onPressed: _printingMany || _printingOne ? null : printSelected,
          ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stage(BuildContext context) {
    final images = _pages[_doc];
    final error = _errors[_doc];
    Widget child;
    if (images != null) {
      child = LayoutBuilder(builder: (context, c) {
        final fit = math.max(120.0, c.maxWidth - _stagePad * 2);
        final width = fit * _zoom;
        _lastPageWidth = width;
        final contentWidth = math.max(c.maxWidth, width + _stagePad * 2);
        return Scrollbar(
          controller: _v,
          thumbVisibility: true,
          child: Scrollbar(
            controller: _h,
            thumbVisibility: true,
            notificationPredicate: (n) => n.depth == 1,
            child: SingleChildScrollView(
              controller: _v,
              child: SingleChildScrollView(
                controller: _h,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: contentWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: _stagePad),
                    child: Column(
                      children: [
                        for (var i = 0; i < images.length; i++) ...[
                          if (i > 0) const SizedBox(height: _pageGap),
                          Container(
                            width: width,
                            height: width * images[i].height / images[i].width,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x59000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: RawImage(
                              image: images[i],
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      });
    } else if (error != null) {
      child = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 34, color: Color(0xFFFFB765)),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Brand.signal),
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    } else {
      child = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 34,
              height: 34,
              child: TpLoader(strokeWidth: 3, color: Brand.signal),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading $_label…',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }
    return ColoredBox(color: _pdfStage, child: child);
  }
}

class _DocTab extends StatelessWidget {
  const _DocTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final fg = active ? Colors.white : b.paperDim;
    return Material(
      color: active ? Brand.signal : Colors.transparent,
      borderRadius: BorderRadius.circular(_radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_radius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading && !active)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: TpLoader(strokeWidth: 2, color: Brand.signal),
                )
              else
                Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final lead = busy
        ? SizedBox(
            width: 14,
            height: 14,
            child: TpLoader(
              strokeWidth: 2,
              color: filled ? Colors.white : Brand.signal,
            ),
          )
        : Icon(icon, size: 16);
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    if (filled) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Brand.signal,
          padding: pad,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: busy ? null : onPressed,
        icon: lead,
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: pad,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: busy ? null : onPressed,
      icon: lead,
      label: Text(label),
    );
  }
}
