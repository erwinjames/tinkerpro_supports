import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show Printing;
import 'package:shared_preferences/shared_preferences.dart';

import '../../api_client.dart';
import '../../services/client_service.dart';
import '../../services/live_sync.dart';
import '../../services/services.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../admin/admin_list.dart';
import '../customer_form_screen.dart';
import '../../widgets/tp_loader.dart';
import '../../widgets/brand_asset.dart';

part 'client_detail_view.dart';
part 'client_grid.dart';
part 'delivery_docs_viewer.dart';

const Color _danger = Color(0xFFC62828);
const Color _warning = Color(0xFFE65100);
const Color _success = Color(0xFF2E7D32);
const Color _info = Color(0xFF1565C0);
const double _radius = 6;
const double _radiusLg = 10;

Color _deliveryStatusColor(BuildContext context, String status) {
  switch (status) {
    case 'Delivered':
      return _success;
    case 'Ready for Delivery':
      return _info;
    case 'Out for Delivery':
      return _warning;
    case 'Cancelled':
      return _danger;
    default:
      return context.brand.paperDim;
  }
}

IconData _deliveryStatusIcon(String status) {
  switch (status) {
    case 'Delivered':
      return Icons.task_alt_rounded;
    case 'Ready for Delivery':
      return Icons.inventory_2_rounded;
    case 'Out for Delivery':
      return Icons.local_shipping_rounded;
    case 'Cancelled':
      return Icons.block_rounded;
    default:
      return Icons.local_shipping_rounded;
  }
}

String _deliveryErrorText(Object error, String fallback) {
  if (error is DeliveryException) {
    return error.message.trim().isEmpty ? fallback : error.message;
  }
  if (error is HttpException) {
    return error.message.trim().isEmpty ? fallback : error.message;
  }
  return fallback;
}

String _deliveryDateLine(String raw) {
  final value = raw.trim();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) return value;
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const days = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  final dd = day.toString().padLeft(2, '0');
  return '${months[month - 1]} $dd, $year · ${days[date.weekday - 1]}';
}

String _deliveryStatusPhrase(String status) {
  switch (status) {
    case 'Delivered':
      return 'has been delivered';
    case 'Out for Delivery':
      return 'is now out for delivery';
    case 'Cancelled':
      return 'has been cancelled';
    case 'Ready for Delivery':
      return 'is ready for delivery';
    default:
      return 'has been updated to $status';
  }
}

String _deliverySmsPhrase(String status, String eta) {
  switch (status) {
    case 'Out for Delivery':
      return 'is out for delivery${eta.trim().isEmpty ? '' : ' (ETA ${eta.trim()})'}';
    case 'Delivered':
      return 'has been delivered';
    case 'Cancelled':
      return 'has been cancelled';
    case 'Ready for Delivery':
      return 'is ready for delivery';
    default:
      return 'status is now $status';
  }
}

String _or(String value) => value.trim().isEmpty ? '—' : value.trim();

void _snack(BuildContext context, String message, {SnackBarAction? action}) {
  if (message.trim().isEmpty) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: action,
      persist: false,
      duration: const Duration(seconds: 4),
    ));
}

Future<void> _openPdf(BuildContext context, Future<String> download,
    {String preparing = 'Preparing PDF…'}) async {
  _snack(context, preparing);
  try {
    final path = await download;
    final result = await OpenFilex.open(path, type: 'application/pdf');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (result.type != ResultType.done) {
      _snack(context, 'No app available to open the PDF ($path)');
    }
  } catch (e) {
    if (!context.mounted) return;
    _snack(context, _deliveryErrorText(e, 'Could not fetch the requested PDF.'));
  }
}

Future<T?> _showHostedModal<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool dismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => ScaffoldMessenger(
      child: Builder(
        builder: (inner) => Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: <Widget>[
              if (dismissible)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(inner).maybePop(),
                  ),
                ),
              Positioned.fill(child: Builder(builder: builder)),
            ],
          ),
        ),
      ),
    ),
  );
}

class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen>
    with SingleTickerProviderStateMixin {
  late final ClientService _service = ClientService(widget.api);
  final GlobalKey<_ClientsPaneState> _clientsKey =
      GlobalKey<_ClientsPaneState>();
  final GlobalKey<_DeliveryPaneState> _deliveryKey =
      GlobalKey<_DeliveryPaneState>();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final TextEditingController _clientSearch = TextEditingController();
  int _tab = 0;
  int _readyCount = 0;
  bool _toolbarQueued = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (_tabs.index != _tab) setState(() => _tab = _tabs.index);
    });
    if (kDebugMode && Platform.environment['TP_CLIENT_TAB'] == 'delivery') {
      _tabs.index = 1;
      _tab = 1;
    }
    _primeReadyCount();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _clientSearch.dispose();
    super.dispose();
  }

  Future<void> _primeReadyCount() async {
    try {
      final res = await _service.deliveries();
      if (!mounted) return;
      setState(() => _readyCount = res.readyCount);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '18',
      stationLabel: 'CLIENT',
      title: 'Client & Data Sheet',
      showBottomBrand: false,
      trailing: _tab != 0
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SearchField(
                  controller: _clientSearch,
                  hint: 'Search Client Records…',
                  width: 350,
                  onChanged: (v) => _clientsKey.currentState?.onSearch(v),
                  onSubmitted: (_) => _clientsKey.currentState?.submitSearch(),
                ),
                const SizedBox(width: 10),
                SignalButton(
                  label: 'New Entry',
                  icon: Icons.add,
                  onPressed: () => _clientsKey.currentState?.create(),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: context.brand.rule, width: 1.5)),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final tools = _tab == 1 && _deliveryKey.currentState != null
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _deliveryKey.currentState!.toolbar(),
                      )
                    : null;
                if (tools != null && box.maxWidth < 900) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _tabBar(),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: tools,
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: _tabBar(),
                      ),
                    ),
                    ?tools,
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                _ClientsPane(
                  key: _clientsKey,
                  service: _service,
                  searchCtrl: _clientSearch,
                ),
                _DeliveryPane(
                  key: _deliveryKey,
                  service: _service,
                  onReadyCount: (n) {
                    if (mounted && n != _readyCount) {
                      setState(() => _readyCount = n);
                    }
                  },
                  onChanged: () {
                    if (_toolbarQueued) return;
                    _toolbarQueued = true;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _toolbarQueued = false;
                      if (mounted && _tab == 1) setState(() {});
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    Widget tab(IconData icon, String label, {int badge = 0}) => Tab(
          height: 46,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17),
              const SizedBox(width: 8),
              Text(label.toUpperCase()),
              if (badge > 0) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Ready for Delivery',
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(
                      color: Brand.signal,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
    return TabBar(
      controller: _tabs,
      isScrollable: true,
      dividerColor: Colors.transparent,
      tabAlignment: TabAlignment.start,
      labelPadding: const EdgeInsets.symmetric(horizontal: 22),
      tabs: [
        tab(Icons.people_alt_rounded, 'Clients'),
        tab(Icons.local_shipping_rounded, 'Delivery', badge: _readyCount),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: b.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.brand.paperDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? b.surfaceHi : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: dark ? b.paperDim : const Color(0xFF666666),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {this.align = TextAlign.left});

  final String label;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      textAlign: align,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            letterSpacing: 0.6,
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: b.surfaceHi,
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: Brand.signal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: b.rule),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...children,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: b.rule.withValues(alpha: 0.6))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: Text(label,
                style: text.bodyMedium?.copyWith(
                    color: b.paperDim, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: SelectableText(
              _or(value),
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pages,
    required this.pageSize,
    required this.sizes,
    required this.onPage,
    required this.onPageSize,
    this.summary = '',
    this.enabled = true,
  });

  final int page;
  final int pages;
  final int pageSize;
  final List<int> sizes;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onPageSize;
  final String summary;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final start = (page - 2).clamp(1, pages);
    final end = (start + 4).clamp(1, pages);
    Widget btn(String label, int target, {bool active = false}) {
      final can = enabled && !active && target >= 1 && target <= pages &&
          target != page;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: active ? Brand.signal : b.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: active ? Brand.signal : b.rule),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: can ? () => onPage(target) : null,
            child: Container(
              constraints: const BoxConstraints(minWidth: 34),
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text(
                label,
                style: text.bodyMedium?.copyWith(
                  color: active
                      ? Colors.white
                      : (can ? b.paper : b.paperDim.withValues(alpha: 0.7)),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        color: b.surface,
        border: Border(top: BorderSide(color: b.rule)),
      ),
      child: Row(
        children: [
          Text('Page Size',
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: b.rule),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: pageSize,
                isDense: true,
                borderRadius: BorderRadius.circular(6),
                items: [
                  for (final s in sizes)
                    DropdownMenuItem<int>(value: s, child: Text('$s')),
                ],
                onChanged: enabled
                    ? (v) {
                        if (v != null) onPageSize(v);
                      }
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              summary,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ),
          btn('First', 1),
          btn('Prev', page - 1),
          for (var p = start; p <= end; p++)
            btn('$p', p, active: p == page),
          btn('Next', page + 1),
          btn('Last', pages),
        ],
      ),
    );
  }
}

Widget _loadingBox() => const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: SizedBox(
          width: 22,
          height: 22,
          child: TpLoader(strokeWidth: 2, color: Brand.signal),
        ),
      ),
    );

const List<_GCol> _clientCols = <_GCol>[
  _GCol(width: 70, align: Alignment.center),
  _GCol(width: 350),
  _GCol(flex: 1),
  _GCol(width: 180),
  _GCol(width: 200, align: Alignment.centerRight),
];

class _BranchPill extends StatelessWidget {
  const _BranchPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFD6AB)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFB45309),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ClientsPane extends StatefulWidget {
  const _ClientsPane({
    super.key,
    required this.service,
    required this.searchCtrl,
  });

  final ClientService service;
  final TextEditingController searchCtrl;

  @override
  State<_ClientsPane> createState() => _ClientsPaneState();
}

class _ClientsPaneState extends State<_ClientsPane>
    with LiveRefresh<_ClientsPane> {
  static const List<int> _pageSizes = <int>[10, 15, 25, 50, 100];

  int _limit = 15;
  Timer? _debounce;
  List<ClientBrief> _rows = const [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  String? _error;
  final Set<int> _busyImport = <int>{};
  final Set<int> _pendingDelete = <int>{};
  int _seq = 0;

  TextEditingController get _searchCtrl => widget.searchCtrl;

  @override
  List<String> get liveKeys => const ['client'];

  @override
  void onLiveChange() => reload(silent: true);

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> reload({bool silent = false}) async {
    final seq = ++_seq;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final res = await widget.service.list(
        search: _searchCtrl.text.trim(),
        page: _page,
        limit: _limit,
      );
      if (!mounted || seq != _seq) return;
      if (silent && res.rows.isEmpty && res.total > 0 && _page > 1) {
        _page = (res.total / _limit).ceil().clamp(1, 1 << 30);
        return reload(silent: true);
      }
      setState(() {
        _rows = res.rows;
        _total = res.total;
        _loading = false;
        _error = null;
      });
      if (kDebugMode &&
          !_debugOpened &&
          _rows.isNotEmpty &&
          (Platform.environment['TP_CLIENT_OPEN'] ?? '').isNotEmpty) {
        _debugOpened = true;
        final first = _rows.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openDetail(first);
        });
      }
    } catch (e) {
      if (!mounted || seq != _seq) return;
      if (silent) {
        if (_loading) setState(() => _loading = false);
        return;
      }
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _page = 1;
      reload();
    });
  }

  void submitSearch() {
    _debounce?.cancel();
    _page = 1;
    reload();
  }

  Future<bool?> _openForm({ClientDetail? existing}) {
    return _showHostedModal<bool>(
      context,
      (_) => _ClientFormPage(service: widget.service, existing: existing),
      dismissible: false,
    );
  }

  Future<void> create() async {
    final saved = await _openForm();
    if (saved == true) {
      if (mounted) _snack(context, 'Client Added Successfully');
      _page = 1;
      await reload();
    }
  }

  Future<void> _delete(ClientBrief c) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this client?',
      message: 'The client record will be permanently purged from the registry.',
      confirmLabel: 'Delete client',
    );
    if (!ok || !mounted) return;
    setState(() => _pendingDelete.add(c.id));
    var undone = false;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final bar = messenger.showSnackBar(SnackBar(
      content: const Text('Client purged'),
      duration: const Duration(seconds: 5),
      persist: false,
      action: SnackBarAction(label: 'Undo', onPressed: () => undone = true),
    ));
    await bar.closed;
    if (undone) {
      if (mounted) {
        setState(() => _pendingDelete.remove(c.id));
        _snack(context, 'Delete undone');
      }
      return;
    }
    final deleted = await widget.service.delete(c.id);
    if (!mounted) return;
    setState(() => _pendingDelete.remove(c.id));
    if (!deleted) _snack(context, 'Failed to purge client record.');
    await reload();
  }

  Future<void> _import(ClientBrief c) async {
    if (_busyImport.contains(c.id)) return;
    setState(() => _busyImport.add(c.id));
    final res = await widget.service.importToBir(c.id);
    if (!mounted) return;
    if (!res.ok || res.customerId <= 0) {
      setState(() => _busyImport.remove(c.id));
      _snack(context, res.message ?? 'Could not import client.');
      return;
    }
    setState(() {
      _rows = [
        for (final r in _rows) r.id == c.id ? r.copyWith(birImported: true) : r
      ];
    });
    final customers = CustomerService(widget.service.api);
    final full = await customers.detailFull(res.customerId);
    if (!mounted) return;
    setState(() => _busyImport.remove(c.id));
    if (full == null) {
      _snack(context, 'Failed to load customer details.');
      return;
    }
    await CustomerFormScreen.show(context, service: customers, existing: full);
    if (mounted) await reload(silent: true);
  }

  void _print(int id) {
    _openPdf(context, widget.service.downloadClientPdf(id),
        preparing: 'Preparing client data sheet…');
  }

  bool _debugOpened = false;

  Future<void> _openDetail(ClientBrief c) async {
    final changed = await _showHostedModal<bool>(
      context,
      (_) => _ClientDetailModal(service: widget.service, brief: c),
    );
    if (changed == true && mounted) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final pages = (_total / _limit).ceil().clamp(1, 1 << 30);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColumnResizeScope(
              tableId: 'client:clients',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _GridHeader(
                    cols: _clientCols,
                    labels: ['ID', 'Identity / Client Name', 'Invoice Reference', 'Branch', 'Actions'],
                  ),
                  Expanded(child: _tableBody()),
                ],
              ),
            ),
          ),
          _Pager(
            page: _page,
            pages: pages,
            pageSize: _limit,
            sizes: _pageSizes,
            enabled: !_loading,
            summary: '',
            onPage: (p) {
              _page = p;
              reload();
            },
            onPageSize: (s) {
              _limit = s;
              _page = 1;
              reload();
            },
          ),
        ],
      ),
    );
  }

  Widget _tableBody() {
    final text = Theme.of(context).textTheme;
    if (_loading && _rows.isEmpty) return _loadingBox();
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load clients', style: text.titleSmall),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: text.bodySmall),
            const SizedBox(height: 12),
            GhostButton(label: 'Retry', icon: Icons.refresh, onPressed: reload),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return const EmptyState(
        label: 'No clients found',
        hint: 'No client records match the current search.',
      );
    }
    final visible =
        _rows.where((r) => !_pendingDelete.contains(r.id)).toList();
    return Stack(
      children: [
        ListView.builder(
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final c = visible[i];
            return _GridRow(
              cols: _clientCols,
              onTap: () => _openDetail(c),
              cells: [
                Text(
                  '${(_page - 1) * _limit + i + 1}',
                  style: TextStyle(fontSize: 15, color: context.brand.paper),
                ),
                Text(
                  c.name.isEmpty ? 'Untitled client' : c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.brand.paper,
                  ),
                ),
                _Badge(c.invoiceNumber.isEmpty ? 'N/A' : c.invoiceNumber),
                c.branch.trim().isEmpty
                    ? const Text('—', style: TextStyle(color: Color(0xFF9CA3AF)))
                    : _BranchPill(c.branch),
                _rowMenu(c),
              ],
            );
          },
        ),
        if (_loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2, color: Brand.signal),
          ),
      ],
    );
  }

  Widget _rowMenu(ClientBrief c) {
    final b = context.brand;
    if (_busyImport.contains(c.id)) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 16,
          height: 16,
          child: TpLoader(strokeWidth: 2),
        ),
      );
    }
    Widget item(IconData icon, String label, Color color, {bool enabled = true}) =>
        Row(
          children: [
            Icon(icon, size: 15, color: enabled ? color : b.paperDim),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: !enabled
                    ? b.paperDim
                    : (color == _danger ? _danger : b.paper),
              ),
            ),
          ],
        );
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      position: PopupMenuPosition.under,
      color: b.surface,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (v) {
        switch (v) {
          case 'print':
            _print(c.id);
          case 'import':
            _import(c);
          case 'delete':
            _delete(c);
        }
      },
      itemBuilder: (_) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'print',
          height: 36,
          child: item(Icons.print_rounded, 'Print', Brand.signal),
        ),
        PopupMenuItem<String>(
          value: 'import',
          height: 36,
          enabled: !c.birImported,
          child: item(
            c.birImported ? Icons.check_rounded : Icons.description_rounded,
            c.birImported
                ? 'Already imported to BIR Registration'
                : 'Import to BIR Registration',
            Brand.signal,
            enabled: !c.birImported,
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          height: 36,
          child: item(Icons.delete_rounded, 'Delete', _danger),
        ),
      ],
      child: Container(
        width: 34,
        height: 30,
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: b.rule),
        ),
        child: Icon(Icons.arrow_drop_down_rounded, size: 20, color: b.paperDim),
      ),
    );
  }
}

class _DeliveryPane extends StatefulWidget {
  const _DeliveryPane({
    super.key,
    required this.service,
    required this.onReadyCount,
    this.onChanged,
  });

  final ClientService service;
  final ValueChanged<int> onReadyCount;
  final VoidCallback? onChanged;

  @override
  State<_DeliveryPane> createState() => _DeliveryPaneState();
}

class _DeliveryPaneState extends State<_DeliveryPane> {
  static const String _statusStoreKey = 'tp.delivery.statusFilter';
  static const Duration _autoEvery = Duration(seconds: 60);

  final _searchCtrl = TextEditingController();
  List<DeliveryBrief> _rows = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String _term = '';
  String _branch = '';
  int _page = 1;
  int _pageSize = 15;
  Set<String> _statuses = <String>{'Ready for Delivery', 'Out for Delivery'};
  Timer? _autoTimer;
  bool _visible = false;
  bool _autoBusy = false;
  DateTime _loadedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _restoreStatuses();
    reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = Visibility.of(context);
    if (visible == _visible) return;
    _visible = visible;
    _autoTimer?.cancel();
    _autoTimer = null;
    if (!visible) return;
    _autoTimer = Timer.periodic(_autoEvery, (_) => _autoRefresh());
    if (DateTime.now().difference(_loadedAt) >= _autoEvery) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoRefresh());
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoRefresh() async {
    if (!mounted || !_visible || _autoBusy || _refreshing || _loading) return;
    _autoBusy = true;
    try {
      final res = await widget.service.deliveries();
      if (!mounted) return;
      _loadedAt = DateTime.now();
      setState(() {
        _rows = res.rows;
        _error = null;
        if (_branch.isNotEmpty && !_branches.contains(_branch)) _branch = '';
      });
      widget.onReadyCount(res.readyCount);
    } catch (_) {
    } finally {
      _autoBusy = false;
    }
  }

  Future<void> _restoreStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_statusStoreKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is List && mounted) {
        setState(() => _statuses = decoded.map((e) => e.toString()).toSet());
      }
    } catch (_) {}
  }

  Future<void> _saveStatuses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statusStoreKey, jsonEncode(_statuses.toList()));
    } catch (_) {}
  }

  Future<void> reload({bool force = false}) async {
    setState(() {
      if (_rows.isEmpty) _loading = true;
      _refreshing = true;
      _error = null;
    });
    try {
      final res = await widget.service.deliveries(force: force);
      if (!mounted) return;
      _loadedAt = DateTime.now();
      setState(() {
        _rows = res.rows;
        _loading = false;
        _refreshing = false;
        if (_branch.isNotEmpty && !_branches.contains(_branch)) _branch = '';
      });
      widget.onReadyCount(res.readyCount);
      if (res.stale && res.message.isNotEmpty) _snack(context, res.message);
      _debugAutoOpen();
    } catch (e) {
      if (!mounted) return;
      final message = _deliveryErrorText(
          e, force ? 'Failed to refresh deliveries.' : 'Failed to load deliveries.');
      setState(() {
        _loading = false;
        _refreshing = false;
        if (_rows.isEmpty) _error = message;
      });
      if (_rows.isNotEmpty) _snack(context, message);
    }
  }

  List<String> get _branches => _rows
      .map((r) => r.branch.trim())
      .where((b) => b.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  List<DeliveryBrief> get _filtered {
    final statusActive = _statuses.isNotEmpty &&
        _statuses.length < kDeliveryStatuses.length;
    return _rows.where((r) {
      if (!r.matches(_term)) return false;
      if (statusActive && !_statuses.contains(r.status)) return false;
      if (_branch.isNotEmpty && r.branch != _branch) return false;
      return true;
    }).toList();
  }

  String get _statusLabel {
    if (_statuses.isEmpty || _statuses.length == kDeliveryStatuses.length) {
      return 'All Statuses';
    }
    if (_statuses.length == 1) return _statuses.first;
    return '${_statuses.length} selected';
  }

  void _onStatusChanged(String id, String status) {
    setState(() {
      _rows = [for (final r in _rows) r.id == id ? r.withStatus(status) : r];
    });
    widget.onReadyCount(
        _rows.where((r) => r.status == 'Ready for Delivery').length);
    reload(force: true);
  }

  bool _debugOpened = false;

  void _debugAutoOpen() {
    if (!kDebugMode || _debugOpened || _rows.isEmpty) return;
    final want = Platform.environment['TP_DELIVERY_OPEN'];
    if (want == null || want.isEmpty) return;
    _debugOpened = true;
    final row = _rows.firstWhere(
      (r) => r.id == want || r.deliveryNo == want,
      orElse: () => _rows.first,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openDetail(row);
    });
  }

  Future<void> _openDetail(DeliveryBrief r) async {
    await _showHostedModal<void>(
      context,
      (_) => _DeliveryDetailPane(
        service: widget.service,
        brief: r,
        onStatusChanged: (s) => _onStatusChanged(r.id, s),
      ),
    );
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    widget.onChanged?.call();
  }

  static const List<_GCol> _cols = <_GCol>[
    _GCol(width: 60, align: Alignment.center),
    _GCol(flex: 30),
    _GCol(flex: 12),
    _GCol(flex: 16),
    _GCol(flex: 15),
    _GCol(flex: 10, align: Alignment.center),
    _GCol(flex: 21),
    _GCol(flex: 20),
    _GCol(flex: 20),
    _GCol(flex: 19),
  ];

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final pages = (rows.length / _pageSize).ceil().clamp(1, 1 << 30);
    final page = _page.clamp(1, pages);
    final start = (page - 1) * _pageSize;
    final slice = rows.skip(start).take(_pageSize).toList();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColumnResizeScope(
              tableId: 'client:deliveries',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _GridHeader(
                    cols: _cols,
                    labels: [
                      'No.',
                      'Client Name',
                      'Date',
                      'Delivery No.',
                      'Invoice No.',
                      'Items',
                      'Delivery Date',
                      'Branch',
                      'Internal Note',
                      'Status',
                    ],
                  ),
                  Expanded(child: _table(slice, start)),
                ],
              ),
            ),
          ),
          _Pager(
            page: page,
            pages: pages,
            pageSize: _pageSize,
            sizes: const <int>[10, 15, 25, 50, 100],
            enabled: !_loading,
            summary: '',
            onPage: (p) => setState(() => _page = p),
            onPageSize: (s) => setState(() {
              _pageSize = s;
              _page = 1;
            }),
          ),
        ],
      ),
    );
  }

  Widget toolbar() {
    final b = context.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _refreshing
            ? Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 16,
                  height: 16,
                  child: TpLoader(
                      strokeWidth: 2, color: Brand.signal),
                ),
              )
            : Tooltip(
                message: 'Refresh',
                child: Material(
                  color: b.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: b.rule),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => reload(force: true),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(Icons.sync_rounded,
                          size: 18, color: b.paperDim),
                    ),
                  ),
                ),
              ),
        const SizedBox(width: 10),
        SearchField(
          controller: _searchCtrl,
          hint: 'Search by delivery, invoice, or customer',
          width: 280,
          onChanged: (v) => setState(() {
            _term = v.trim().toLowerCase();
            _page = 1;
          }),
        ),
        const SizedBox(width: 10),
        MenuAnchor(
          alignmentOffset: const Offset(0, 4),
          menuChildren: [
            for (final s in kDeliveryStatuses)
              CheckboxMenuButton(
                value: _statuses.contains(s),
                closeOnActivate: false,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _statuses = {..._statuses, s};
                    } else {
                      _statuses = {..._statuses}..remove(s);
                    }
                    _page = 1;
                  });
                  _saveStatuses();
                },
                child: Text(s, style: const TextStyle(fontSize: 13.5)),
              ),
          ],
          builder: (context, controller, _) => Material(
            color: b.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                  color: controller.isOpen ? Brand.signal : b.rule),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: Container(
                height: 38,
                constraints: const BoxConstraints(minWidth: 150),
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_statusLabel,
                        style: TextStyle(fontSize: 13, color: b.paper)),
                    const SizedBox(width: 24),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: b.paperDim),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _table(List<DeliveryBrief> rows, int offset) {
    final text = Theme.of(context).textTheme;
    if (_loading) return _loadingBox();
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load deliveries', style: text.titleSmall),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: text.bodySmall),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: () => reload(force: true),
            ),
          ],
        ),
      );
    }
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'No deliveries found',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: context.brand.paperDim.withValues(alpha: 0.55),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) => _deliveryRow(rows[i], offset + i),
    );
  }

  Widget _deliveryRow(DeliveryBrief r, int i) {
    final b = context.brand;
    final muted = TextStyle(fontSize: 14, color: b.paperDim);
    final body = TextStyle(fontSize: 14, color: b.paper);
    Widget line(String v, TextStyle style) => Text(
          _or(v),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: v.trim().isEmpty ? muted : style,
        );
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})')
        .firstMatch(r.deliveryDate.trim());
    Widget dateCell;
    if (m == null) {
      dateCell = line(r.deliveryDate, muted);
    } else {
      final full = _deliveryDateLine(r.deliveryDate).split(' · ');
      dateCell = Text.rich(
        TextSpan(children: [
          TextSpan(text: full.first, style: body),
          if (full.length > 1) TextSpan(text: '  ${full.last}', style: muted),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return _GridRow(
      cols: _cols,
      height: 46,
      onTap: () => _openDetail(r),
      cells: [
        Text('${i + 1}', style: body),
        line(
            r.clientName,
            TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: b.paper)),
        line(r.date, muted),
        line(
            r.deliveryNo,
            TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: b.paper)),
        r.invoiceNo.isEmpty
            ? Text('—', style: muted)
            : Row(
                children: [
                  Flexible(
                    child: Text(
                      r.invoiceNo,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Brand.signal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _CopyButton(value: r.invoiceNo),
                ],
              ),
        Text(_or(r.items), style: body),
        dateCell,
        r.branch.isEmpty
            ? Text('—', style: muted)
            : Row(
                children: [
                  const Icon(Icons.store_rounded,
                      size: 14, color: Color(0xFF2A9D8F)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      r.branch,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF2A9D8F)),
                    ),
                  ),
                ],
              ),
        r.internalNote.isEmpty
            ? Text('—', style: muted)
            : Tooltip(
                message: r.internalNote,
                child: Row(
                  children: [
                    const Icon(Icons.sticky_note_2_rounded,
                        size: 14, color: Color(0xFFE6A817)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        r.internalNote,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                  ],
                ),
              ),
        r.status.trim().isEmpty
            ? Text('—', style: muted)
            : Text(
                r.status,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _deliveryStatusColor(context, r.status),
                ),
              ),
      ],
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.value});

  final String value;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Copy invoice number',
      visualDensity: VisualDensity.compact,
      iconSize: 14,
      style: IconButton.styleFrom(minimumSize: const Size(26, 26)),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.value));
        if (!mounted) return;
        setState(() => _copied = true);
        Timer(const Duration(milliseconds: 1200), () {
          if (mounted) setState(() => _copied = false);
        });
      },
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        color: _copied ? _success : context.brand.paperDim,
      ),
    );
  }
}

class _DeliveryDetailPane extends StatefulWidget {
  const _DeliveryDetailPane({
    required this.service,
    required this.brief,
    required this.onStatusChanged,
  });

  final ClientService service;
  final DeliveryBrief brief;
  final ValueChanged<String> onStatusChanged;

  @override
  State<_DeliveryDetailPane> createState() => _DeliveryDetailPaneState();
}

class _DeliveryDetailPaneState extends State<_DeliveryDetailPane> {
  final GlobalKey<_DeliveryDocsViewerState> _viewer =
      GlobalKey<_DeliveryDocsViewerState>();
  DeliveryDetail? _detail;
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await widget.service.delivery(widget.brief.id);
      if (!mounted) return;
      setState(() {
        _detail = res.detail;
        _loading = false;
      });
      if (res.stale && res.message.isNotEmpty) _snack(context, res.message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _deliveryErrorText(e, 'Failed to load delivery.');
      });
    }
  }

  void _reload() {
    _viewer.currentState?.reloadCurrent();
    _load();
  }

  Future<void> _pickStatus(String status) async {
    final detail = _detail;
    if (detail == null || _busy) return;
    final choice = await showDialog<({bool notify, bool sms})>(
      context: context,
      builder: (_) => _StatusConfirmDialog(detail: detail, status: status),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    final res = await widget.service.updateDeliveryStatus(
      id: widget.brief.id,
      status: status,
      notify: choice.notify,
      sms: choice.sms,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _snack(context,
          res.message.trim().isEmpty ? 'Failed to update status.' : res.message);
      return;
    }
    final channels = <String>[];
    final lines = <String>[];
    if (choice.notify && res.emailSent) {
      channels.add('email');
    } else if (choice.notify && !res.emailSent) {
      lines.add(
          'Email not sent: ${res.emailMessage.isEmpty ? 'failed' : res.emailMessage}');
    }
    if (choice.sms && res.smsSent) {
      channels.add('SMS');
    } else if (choice.sms && !res.smsSent) {
      lines.add(
          'SMS not sent: ${res.smsMessage.isEmpty ? 'failed' : res.smsMessage}');
    }
    lines.add(
        'Status updated to $status${channels.isEmpty ? '' : ' · notified via ${channels.join(' + ')}'}');
    _snack(context, lines.join('\n'));
    setState(() => _detail = detail.copyWithStatus(status));
    widget.onStatusChanged(status);
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final status = detail?.status ?? widget.brief.status;
    final title = widget.brief.deliveryNo.isNotEmpty
        ? widget.brief.deliveryNo
        : (detail?.deliveryNo.isNotEmpty == true
            ? detail!.deliveryNo
            : 'Delivery');
    final nav = Navigator.of(context);
    return WebModal(
      title: title,
      subtitle: widget.brief.clientName.trim().isEmpty
          ? null
          : widget.brief.clientName,
      icon: _deliveryStatusIcon(status),
      width: 1360,
      height: 900,
      scrollable: false,
      actions: [
        GhostButton(
          label: 'Reload',
          icon: Icons.refresh,
          onPressed: _loading ? null : _reload,
        ),
        if (detail != null)
          GhostButton(
            label: 'Print…',
            icon: Icons.print_rounded,
            onPressed: () => _viewer.currentState?.printSelected(),
          ),
        if (detail != null)
          MenuAnchor(
            menuChildren: [
              for (final s in kDeliverySettableStatuses)
                MenuItemButton(
                  leadingIcon: Icon(
                    _deliveryStatusIcon(s),
                    size: 16,
                    color: _deliveryStatusColor(context, s),
                  ),
                  trailingIcon: s == status
                      ? const Icon(Icons.check_rounded, size: 16)
                      : null,
                  onPressed: () => _pickStatus(s),
                  child: Text(s),
                ),
            ],
            builder: (context, controller, _) => SignalButton(
              label: 'Update Status',
              icon: Icons.published_with_changes_rounded,
              busy: _busy,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        GhostButton(label: 'Close', onPressed: () => nav.maybePop()),
      ],
      child: _body(detail, status),
    );
  }

  Widget _body(DeliveryDetail? detail, String status) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    if (_loading && detail == null) return _loadingBox();
    if (detail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Delivery unavailable', style: text.titleSmall),
              const SizedBox(height: 8),
              Text(
                _error.isEmpty ? 'This delivery could not be loaded.' : _error,
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
              const SizedBox(height: 12),
              GhostButton(
                label: 'Try again',
                icon: Icons.refresh,
                onPressed: _load,
              ),
            ],
          ),
        ),
      );
    }
    final color = _deliveryStatusColor(context, status);
    final details = _SectionCard(
      title: 'Delivery Details',
      icon: Icons.local_shipping_rounded,
      children: [
        _KeyValue('Company', detail.companyLabel),
        _KeyValue('Date', detail.date),
        _KeyValue('Delivery Date', _deliveryDateLine(detail.deliveryDate)),
        _KeyValue('Invoice', detail.invoiceNo),
        _KeyValue('Branch', detail.branch),
        _KeyValue('Recipient', detail.recipientName),
        _KeyValue('Recipient Phone', detail.recipientPhone),
        _KeyValue('Address', detail.recipientAddress),
        _KeyValue('Customer Email', detail.customerEmail),
        if (detail.deliveredAt.isNotEmpty)
          _KeyValue('Delivered At', detail.deliveredAt),
        _KeyValue('Internal Note', detail.internalNote),
        if (detail.notes.isNotEmpty) _KeyValue('Notes', detail.notes),
      ],
    );
    final items = detail.items.isEmpty
        ? null
        : _SectionCard(
            title: 'Items (${detail.items.length})',
            icon: Icons.inventory_2_rounded,
            children: [
ColumnResizeScope(tableId: 'client:delivery-items', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Builder(builder: (context) => Row(
                children: resizableRowCells(context, [
                  Expanded(flex: 5, child: _HeaderCell('Description')),
                  Expanded(
                      flex: 2,
                      child: _HeaderCell('Qty', align: TextAlign.right)),
                  Expanded(
                      flex: 2,
                      child: _HeaderCell('Delivered', align: TextAlign.right)),
                  Expanded(
                      flex: 2,
                      child: _HeaderCell('Amount', align: TextAlign.right)),
                ], header: true),
              )),
              for (final item in detail.items) ...[
                Divider(height: 12, color: b.rule),
                Builder(builder: (context) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: resizableRowCells(context, [
                    Expanded(
                        flex: 5,
                        child: Text(_or(item.description),
                            style: text.bodyMedium)),
                    Expanded(
                        flex: 2,
                        child: Text(_or(item.quantity),
                            textAlign: TextAlign.right, style: text.bodySmall)),
                    Expanded(
                        flex: 2,
                        child: Text(_or(item.deliveredQuantity),
                            textAlign: TextAlign.right, style: text.bodySmall)),
                    Expanded(
                        flex: 2,
                        child: Text(_or(item.amount),
                            textAlign: TextAlign.right, style: text.bodySmall)),
                  ]),
                )),
              ],
])),
              if (detail.total.isNotEmpty) ...[
                Divider(height: 16, color: b.rule),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total ${detail.currency} ${detail.total}'.trim(),
                    style: text.titleSmall,
                  ),
                ),
              ],
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _Pill(
              label: _or(status),
              color: color,
              icon: _deliveryStatusIcon(status),
            ),
            if (widget.brief.invoiceNo.isNotEmpty)
              _Pill(
                label: 'Ref ${widget.brief.invoiceNo}',
                icon: Icons.receipt_rounded,
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: TpLoader(strokeWidth: 2, color: Brand.signal),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final viewer = _DeliveryDocsViewer(
                key: _viewer,
                service: widget.service,
                deliveryId: widget.brief.id,
                deliveryNo: widget.brief.deliveryNo.isNotEmpty
                    ? widget.brief.deliveryNo
                    : detail.deliveryNo,
              );
              if (box.maxWidth < 900) {
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: math.max(box.maxHeight - 24, 420),
                        child: viewer,
                      ),
                      const SizedBox(height: 16),
                      details,
                      ?items,
                    ],
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 7, child: viewer),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [details, ?items],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatusConfirmDialog extends StatefulWidget {
  const _StatusConfirmDialog({required this.detail, required this.status});

  final DeliveryDetail detail;
  final String status;

  @override
  State<_StatusConfirmDialog> createState() => _StatusConfirmDialogState();
}

class _StatusConfirmDialogState extends State<_StatusConfirmDialog> {
  late bool _notify = widget.detail.customerEmail.isNotEmpty;
  late bool _sms = widget.detail.hasSms;

  String get _smsBody {
    final d = widget.detail;
    final ref = d.invoiceNo.isNotEmpty
        ? 'Invoice #${d.invoiceNo}'
        : (d.deliveryNo.isNotEmpty ? 'Delivery #${d.deliveryNo}' : 'your order');
    return 'Hi ${d.recipientLabel}, your order ($ref) '
        '${_deliverySmsPhrase(widget.status, d.deliveryDate)}. Thank you!';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final hasEmail = d.customerEmail.isNotEmpty;
    final hasSms = d.hasSms;
    return WebModal(
      title: 'Set status to ${widget.status}',
      subtitle: '${d.deliveryNo.isEmpty ? '' : '${d.deliveryNo} · '}'
          '${hasEmail ? 'Notify ${d.recipientLabel}?' : 'No email on file'}',
      icon: _deliveryStatusIcon(widget.status),
      width: 600,
      actions: [
        GhostButton(
          label: 'Update without notifying',
          onPressed: () =>
              Navigator.of(context).pop((notify: false, sms: false)),
        ),
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        SignalButton(
          label: 'Update & Notify',
          icon: Icons.send_rounded,
          onPressed: (_notify && hasEmail) || (_sms && hasSms)
              ? () => Navigator.of(context).pop((
                    notify: _notify && hasEmail,
                    sms: _sms && hasSms,
                  ))
              : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.mail_outline_rounded),
            title: const Text('Email'),
            subtitle:
                Text(hasEmail ? d.customerEmail : 'No email address on file'),
            value: _notify && hasEmail,
            onChanged: hasEmail ? (v) => setState(() => _notify = v) : null,
          ),
          if (hasEmail && _notify)
            _PreviewBox(lines: [
              'to ${d.customerEmail}',
              'Delivery Note #${d.deliveryNo} from ${d.companyLabel} — ${widget.status}',
              'Dear ${d.recipientLabel},\n\nYour order (delivery note #${d.deliveryNo}) '
                  '${_deliveryStatusPhrase(widget.status)}. Thank you for your business.',
              d.deliveryNo.isEmpty ? 'PDF attached' : '${d.deliveryNo}.pdf attached',
            ]),
          if (hasSms) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.sms_outlined),
              title: const Text('SMS'),
              subtitle: Text(d.smsPhone),
              value: _sms,
              onChanged: (v) => setState(() => _sms = v),
            ),
            if (_sms)
              _PreviewBox(lines: [
                'to ${d.smsPhone}',
                _smsBody,
                '${_smsBody.length} characters',
              ]),
          ],
        ],
      ),
    );
  }
}

class _PrintDocsDialog extends StatefulWidget {
  const _PrintDocsDialog();

  @override
  State<_PrintDocsDialog> createState() => _PrintDocsDialogState();
}

class _PrintDocsDialogState extends State<_PrintDocsDialog> {
  final Set<String> _selected = kDeliveryDocuments.keys.toSet();

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Select documents to print',
      icon: Icons.print_rounded,
      width: 420,
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        SignalButton(
          label: 'Print Selected',
          icon: Icons.print_rounded,
          onPressed: () => Navigator.of(context).pop(<String>[
            for (final k in kDeliveryDocuments.keys)
              if (_selected.contains(k)) k,
          ]),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in kDeliveryDocuments.entries)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: _selected.contains(e.key),
              title: Text(e.value),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(e.key);
                } else {
                  _selected.remove(e.key);
                }
              }),
            ),
        ],
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: b.surfaceHi,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: b.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Text(
              lines[i],
              style: i == 0 || i == lines.length - 1
                  ? text.bodySmall?.copyWith(color: b.paperDim)
                  : text.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

const String _snDefault = 'N/A';
const String _specNa = 'Not Applicable';
const String _specOther = 'Others';
const String _otherOption = 'Other';

const List<String> _systemUnitOptions = <String>[
  'Generic CPU',
  'Branded CPU',
  'ALL IN ONE SYSTEM',
];

const Map<String, String> _systemUnitLabels = <String, String>{
  'Generic CPU': 'Generic CPU',
  'Branded CPU': 'Branded CPU',
  'ALL IN ONE SYSTEM': 'All-in-One System',
};

const List<String> _ramOptions = <String>[
  '2GB',
  '4GB',
  '6GB',
  '8GB',
  '16GB',
  '32GB',
];

const List<String> _monitorSizeOptions = <String>[
  '14 Inches',
  '15.6 Inches',
  '17 Inches',
  '19 Inches',
  '20 Inches',
];

const Map<String, String> _monitorSizeLabels = <String, String>{
  '14 Inches': '14"',
  '15.6 Inches': '15.6"',
  '17 Inches': '17"',
  '19 Inches': '19"',
  '20 Inches': '20"',
};

const List<String> _monitorBrandOptions = <String>[
  'N-Vision',
  'Supervision',
  'LG',
  'HP',
  'Acer',
  'AOC',
  'ASUS',
  'GreatWall',
  'Gamdas',
  'Orion',
  'TinkerPro',
];

const List<String> _monitorTypeOptions = <String>[
  'Touch Screen',
  'Non Touch',
  'Projection Type',
];

const List<String> _storageTypeOptions = <String>[
  'Solid State Drive',
  'Hard Disk Drive',
  'MMC',
];

const Map<String, String> _storageTypeLabels = <String, String>{
  'Solid State Drive': 'SSD (Solid State Drive)',
  'Hard Disk Drive': 'HDD (Hard Disk Drive)',
  'MMC': 'MMC',
};

const List<String> _storageSizeOptions = <String>[
  '16GB',
  '32GB',
  '60GB',
  '120GB',
  '128GB',
  '130GB',
  '256GB',
  '500GB',
  '1TB',
];

const Map<String, List<String>> _specOptions = <String, List<String>>{
  'monitor': <String>[
    '14 Inches',
    '15.6 Inches',
    '17 Inches',
    '19 Inches',
    '20 Inches',
  ],
  'ram': <String>['2GB', '4GB', '6GB', '8GB', '16GB', '32GB'],
  'storage': <String>[
    '16GB',
    '32GB',
    '60GB',
    '120GB',
    '128GB',
    '256GB',
    '500GB',
    '1TB',
  ],
  'storagetype': <String>['HDD', 'SSD', 'M.2', 'eMMC', 'NVMe'],
  'cashdrawer': <String>['3 Bills', '4 Bills', '5 Bills', '6 Bills', '8 Bills'],
  'printer': <String>['58mm', '80mm'],
  'processor': <String>[
    '1.8 GHz',
    '2.0 GHz',
    '2.4 GHz',
    '2.6 GHz',
    '3.0 GHz',
    '3.2 GHz',
    '3.6 GHz',
  ],
  'barcode': <String>['1D', '2D'],
};

const Map<String, List<String>> _specBrands = <String, List<String>>{
  'monitor': <String>[
    'N-Vision',
    'Supervision',
    'Dell',
    'LG',
    'HP',
    'Acer',
    'AOC',
    'ASUS',
    'Samsung',
    'GreatWall',
    'Gamdas',
    'Orion',
    'TinkerPro',
  ],
  'processor': <String>['AMD', 'Intel'],
};

const List<String> _monthNames = <String>[
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

class _SerialFieldSpec {
  const _SerialFieldSpec(this.label, this.icon, this.formKey, this.column);

  final String label;
  final IconData icon;
  final String formKey;
  final String column;
}

const List<_SerialFieldSpec> _serialFields = <_SerialFieldSpec>[
  _SerialFieldSpec('Motherboard', Icons.memory_rounded,
      'clientMotherboardSerialNumber', 'motherboard_serialnum'),
  _SerialFieldSpec('Keyboard', Icons.keyboard_rounded,
      'clientKeyboardSerialNumber', 'keyboard_serialnum'),
  _SerialFieldSpec(
      'Mouse', Icons.mouse_rounded, 'clientMouseSerialNumber', 'mouse_serialnum'),
  _SerialFieldSpec('Barcode Scanner', Icons.qr_code_scanner_rounded,
      'clientbarcodescannerSerialNumber', 'barcodeScanner_serialnum'),
  _SerialFieldSpec('Thermal Printer', Icons.print_rounded,
      'clientthermalprinterSerialNumber', 'thermalPrinter_serialnum'),
  _SerialFieldSpec('Cash Drawer', Icons.point_of_sale_rounded,
      'clientCashDrawerSerialNumber', 'cashDrawer_serialnum'),
  _SerialFieldSpec('Barcode Printer', Icons.local_printshop_rounded,
      'clientBarcodePrinterSerialNumber', 'barcodePrinter_serialnum'),
  _SerialFieldSpec('Customer Display (Pole / Monitor)',
      Icons.desktop_windows_rounded, 'clientcusdisplaySerialNumber',
      'cusdisplay_serialnum'),
];

class _ClientFormPage extends StatefulWidget {
  const _ClientFormPage({required this.service, this.existing});

  final ClientService service;
  final ClientDetail? existing;

  bool get isEdit => existing != null;

  @override
  State<_ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends State<_ClientFormPage> {
  final _name = TextEditingController();
  final _invoice = TextEditingController();
  final _branch = TextEditingController();
  final _datePrepared = TextEditingController();
  final _dateApproved = TextEditingController();
  final _storageConfig = TextEditingController();
  final _systemSerial = TextEditingController();
  final _mac = TextEditingController();
  final _min = TextEditingController();
  final _ptu = TextEditingController();
  final _tin = TextEditingController();
  final _registeredAddress = TextEditingController();

  final Map<String, TextEditingController> _serials =
      <String, TextEditingController>{
    for (final f in _serialFields) f.formKey: TextEditingController(),
  };

  final List<_UnitGroup> _units = <_UnitGroup>[];
  final List<_RamGroup> _rams = <_RamGroup>[];
  final List<_StorageRow> _storage = <_StorageRow>[];
  final List<_MonitorGroup> _monitors = <_MonitorGroup>[];
  final List<_SpecRow> _specRows = <_SpecRow>[];

  final Set<String> _invalid = <String>{};
  List<ClientSpecReplacement> _replacements = <ClientSpecReplacement>[];

  Timer? _nameDebounce;
  List<ClientCustomerMatch> _nameMatches = const <ClientCustomerMatch>[];
  bool _nameSearching = false;
  final Map<String, List<ClientCustomerMatch>> _nameCache =
      <String, List<ClientCustomerMatch>>{};

  bool _invoiceMode = false;
  bool _customerLocked = false;
  bool _specLocked = true;
  bool _saving = false;
  DateTime? _lastSubmitAt;
  bool _reloading = false;
  int? _clientId;

  static const List<({String title, String subtitle, IconData icon})> _steps =
      <({String title, String subtitle, IconData icon})>[
    (
      title: 'Customer Information',
      subtitle: 'Basic details about the client',
      icon: Icons.person_rounded,
    ),
    (
      title: 'System Specifications',
      subtitle: 'Hardware and system setup',
      icon: Icons.desktop_windows_rounded,
    ),
    (
      title: 'Serial Numbers & Brand Names',
      subtitle: 'Device details and brands',
      icon: Icons.qr_code_2_rounded,
    ),
    (
      title: 'BIR Compliant System',
      subtitle: 'BIR registration details',
      icon: Icons.receipt_long_rounded,
    ),
  ];

  final ScrollController _scroll = ScrollController();
  final List<GlobalKey> _sectionKeys =
      List<GlobalKey>.generate(4, (_) => GlobalKey());
  int _step = 0;
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _units.add(_UnitGroup());
    _rams.add(_RamGroup());
    _monitors.add(_MonitorGroup());
    final e = widget.existing;
    if (e == null) {
      _setStorageConfigValue('');
      _applySerialDefaults();
    } else {
      _clientId = e.id;
      _loadFrom(e);
    }
  }

  void _loadFrom(ClientDetail e) {
    _invalid.clear();
    _invoiceMode = false;
    _customerLocked = false;
    _specLocked = true;
    _name.text = e.name;
    _invoice.text = e.invoiceNumber;
    _branch.text = e.branch;
    _datePrepared.text = e.datePrepared;
    _dateApproved.text = e.dateApproved;
    _mac.text = e.macAddress;
    _min.text = e.min;
    _ptu.text = e.ptu;
    _tin.text = e.tin;
    _registeredAddress.text = e.registeredAddress;
    _systemSerial.text = e.systemSerial;
    _replacements = e.specReplacements;

    final serialValues = <String, String>{
      'clientMotherboardSerialNumber': e.motherboardSerial,
      'clientKeyboardSerialNumber': e.keyboardSerial,
      'clientMouseSerialNumber': e.mouseSerial,
      'clientbarcodescannerSerialNumber': e.barcodeScannerSerial,
      'clientthermalprinterSerialNumber': e.thermalPrinterSerial,
      'clientCashDrawerSerialNumber': e.cashDrawerSerial,
      'clientBarcodePrinterSerialNumber': e.barcodePrinterSerial,
      'clientcusdisplaySerialNumber': e.cusDisplaySerial,
    };
    serialValues.forEach((k, v) => _serials[k]!.text = v);

    _populateUnitGroups(e.systemUnit, e.systemUnitSerial);
    _populateRamGroups(e.ramConfig);
    _setStorageConfigValue(e.storageConfig);
    _setStorageSerialValue(e.storageSerial);
    _populateMonitorGroups(
        e.monitorSize, e.monitorBrand, e.monitorType, e.monitorSerial);

    if (e.invoiceItems.isNotEmpty) {
      _buildStoredSpecRows(e.invoiceItems);
      _invoiceMode = true;
      _customerLocked = true;
      _specLocked = true;
    }
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _scroll.dispose();
    for (final c in <TextEditingController>[
      _name,
      _invoice,
      _branch,
      _datePrepared,
      _dateApproved,
      _storageConfig,
      _systemSerial,
      _mac,
      _min,
      _ptu,
      _tin,
      _registeredAddress,
      ..._serials.values,
    ]) {
      c.dispose();
    }
    for (final g in _units) {
      g.dispose();
    }
    for (final g in _rams) {
      g.dispose();
    }
    for (final g in _storage) {
      g.dispose();
    }
    for (final g in _monitors) {
      g.dispose();
    }
    for (final r in _specRows) {
      r.dispose();
    }
    super.dispose();
  }

  void _applySerialDefaults() {
    for (final c in _serials.values) {
      if (c.text.trim().isEmpty) c.text = _snDefault;
    }
  }

  void _populateUnitGroups(String brands, String serials) {
    for (final g in _units) {
      g.dispose();
    }
    _units.clear();
    final names = _splitCsv(brands);
    final sns = _splitCsvKeepEmpty(serials);
    final count =
        <int>[names.length, sns.length, 1].reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < count; i++) {
      final g = _UnitGroup();
      g.setValue(i < names.length ? names[i] : '');
      g.serial.text = i < sns.length ? sns[i] : '';
      _units.add(g);
    }
  }

  void _populateRamGroups(String value) {
    for (final g in _rams) {
      g.dispose();
    }
    _rams.clear();
    final list = _splitCsv(value);
    if (list.isEmpty) {
      _rams.add(_RamGroup());
      return;
    }
    for (final v in list) {
      _rams.add(_RamGroup()..choice.init(v));
    }
  }

  void _populateMonitorGroups(
      String sizes, String brands, String types, String serials) {
    for (final g in _monitors) {
      g.dispose();
    }
    _monitors.clear();
    final s = _splitCsv(sizes);
    final b = _splitCsv(brands);
    final t = _splitCsv(types);
    final sn = _splitCsvKeepEmpty(serials);
    final count = <int>[s.length, b.length, t.length, sn.length, 1]
        .reduce((a, b) => a > b ? a : b);
    for (var i = 0; i < count; i++) {
      final g = _MonitorGroup();
      g.size.init(i < s.length ? s[i] : '');
      g.brand.init(i < b.length ? b[i] : '');
      g.type.init(i < t.length ? t[i] : '');
      g.serial.text = i < sn.length ? sn[i] : '';
      _monitors.add(g);
    }
  }

  void _setStorageConfigValue(String value) {
    for (final r in _storage) {
      r.dispose();
    }
    _storage.clear();
    final parts = _splitCsv(value);
    _StorageRow? current;
    for (final p in parts) {
      if (_storageTypeOptions.contains(p)) {
        current = _StorageRow()..setType(p);
        _storage.add(current);
      } else if (current != null && current.sizeValue.isEmpty) {
        current.setSize(p);
      } else {
        current = _StorageRow()..setSize(p);
        _storage.add(current);
      }
    }
    if (_storage.isEmpty) _storage.add(_StorageRow());
    _rebuildStorageConfig();
  }

  void _setStorageSerialValue(String value) {
    final vals = _splitCsvKeepEmpty(value);
    for (var i = 0; i < _storage.length; i++) {
      _storage[i].serial.text = i < vals.length ? vals[i] : '';
    }
  }

  void _rebuildStorageConfig() {
    final out = <String>[];
    for (final r in _storage) {
      final t = r.typeValue;
      final s = r.sizeValue;
      if (t.isNotEmpty) out.add(t);
      if (s.isNotEmpty) out.add(s);
    }
    _storageConfig.text = out.join(', ');
  }

  void _buildStoredSpecRows(List<ClientInvoiceItem> items) {
    for (final r in _specRows) {
      r.dispose();
    }
    _specRows.clear();
    final byGroup = <String, Map<String, _SpecRow>>{};
    for (var i = 0; i < items.length; i++) {
      final row = items[i];
      final groupName =
          row.itemName.trim().isEmpty ? 'Item' : row.itemName.trim();
      final component = row.component.trim();
      final meta = _normalizeSpec(component);
      var optionVal = row.optionValue.trim();
      var sizeVal = '';
      if (meta.optionsKey == 'storagetype') {
        final m = RegExp(r'(\d+(?:\.\d+)?)\s*(GB|TB)', caseSensitive: false)
            .firstMatch(optionVal);
        if (m != null) {
          sizeVal = '${m.group(1)}${m.group(2)!.toUpperCase()}';
          optionVal = optionVal.replaceFirst(m.group(0)!, '').trim();
        }
      }
      final serial = row.serialNumber.trim();
      final entry = _SpecEntry(
        optionsKey: meta.optionsKey,
        freeSpec: false,
        option: optionVal,
        size: sizeVal,
        brand: row.brandName.trim(),
        serial: (serial.isEmpty || serial == _snDefault) ? '' : serial,
        target: meta.target,
        raw: component,
        serverIndex: i,
      );
      final key = component.toLowerCase();
      final group = byGroup.putIfAbsent(groupName, () => <String, _SpecRow>{});
      final existing = group[key];
      if (existing != null) {
        existing.entries.add(entry);
      } else {
        final specRow = _SpecRow(
          itemName: groupName,
          component: component,
          icon: meta.icon,
          optionsKey: meta.optionsKey,
          freeSpec: false,
        )..entries.add(entry);
        group[key] = specRow;
        _specRows.add(specRow);
      }
    }
    _initSystemSerialToggle();
  }

  void _initSystemSerialToggle() {
    final storageEntries = <_SpecEntry>[];
    for (final row in _specRows) {
      if (row.optionsKey != 'storagetype') continue;
      storageEntries.addAll(row.entries);
    }
    if (storageEntries.isEmpty) return;
    if (!storageEntries.any((e) => e.sysSerial)) {
      storageEntries.first.sysSerial = true;
    }
  }

  bool get _systemSerialEnabled {
    if (!_invoiceMode) return true;
    final toggles = <_SpecEntry>[];
    for (final row in _specRows) {
      if (row.optionsKey != 'storagetype') continue;
      toggles.addAll(row.entries);
    }
    if (toggles.isEmpty) return true;
    return toggles.any((e) => e.sysSerial);
  }

  Future<void> _openInvoiceSearch() async {
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _InvoicePickDialog(service: widget.service),
    );
    if (picked == null || !mounted) return;
    await _selectInvoice(picked);
  }

  Future<void> _selectInvoice(Map<String, dynamic> invoice) async {
    final invNo = _invoiceNumberOf(invoice);
    final invBranch = _invoiceBranchOf(invoice);
    final invLabel = invBranch.isEmpty ? invNo : '$invNo ($invBranch)';

    final check = await widget.service.checkInvoice(invNo, branch: invBranch);
    if (!mounted) return;
    if (check.exists) {
      final takenBy = check.clientName.trim().isEmpty
          ? ''
          : ' (${check.clientName.trim()})';
      if (!check.branchMatched) {
        final proceed = await confirmDialog(
          context,
          title: 'Invoice already recorded',
          message:
              'Invoice $invNo is already recorded$takenBy without a branch. '
              'Continue with branch $invBranch?',
          confirmLabel: 'Continue anyway',
        );
        if (!proceed || !mounted) return;
      } else {
        await _alert(
          title: 'Invoice already recorded',
          message: 'Invoice $invLabel already has a client record$takenBy.',
        );
        return;
      }
    }

    final prefill = await widget.service.invoicePrefill(invoice);
    if (!mounted) return;
    if (prefill == null) {
      _snack(context, 'Could not reach the invoice service.');
      return;
    }
    _fillFromInvoice(prefill);
    _snack(context, 'Form auto-filled from invoice $invLabel');
    if (prefill.rows.isNotEmpty) {
      unawaited(widget.service.parseInvoiceSpecs(prefill.components));
    }
  }

  void _fillFromInvoice(ClientInvoicePrefill p) {
    setState(() {
      _name.text = p.field('clientName');
      _invoice.text = p.field('clientInvoiceNumber');
      _branch.text = p.field('clientBranch');
      _datePrepared.text = p.field('clientDatePrepared');
      _populateUnitGroups(
        p.field('clientSystemsUnit'),
        p.field('clientSystemUnitSerialNumber'),
      );
      _populateRamGroups(p.field('clientRamConfig'));
      _setStorageConfigValue(p.field('clientstorageConfig'));
      _setStorageSerialValue(p.field('clientStorageSerialNumber'));
      _populateMonitorGroups(
        p.field('clientmonitorsizeConfig'),
        p.field('clientmonitorbrandConfig'),
        p.field('clientmonitortypeConfig'),
        p.field('clientMonitorSerialNumber'),
      );
      for (final f in _serialFields) {
        _serials[f.formKey]!.text = p.field(f.formKey);
      }
      _systemSerial.text = p.field('clientSystemSerialNumber');
      _mac.text = p.field('clientMacAddress');
      _min.text = p.field('clientMIN');
      _ptu.text = p.field('clientPTU');
      _dateApproved.text = p.field('clientDateApproved');
      _tin.text = p.field('clientTIN');
      _registeredAddress.text = p.field('clientRegisteredAddress');

      for (final r in _specRows) {
        r.dispose();
      }
      _specRows.clear();
      for (final r in p.rows) {
        final row = _SpecRow(
          itemName: r.itemName,
          component: r.component,
          icon: _faIcon(r.icon),
          optionsKey: r.optionsKey,
          freeSpec: r.freeSpec,
        );
        for (final e in r.entries) {
          row.entries.add(_SpecEntry(
            optionsKey: r.optionsKey,
            freeSpec: r.freeSpec,
            option: e.option,
            size: e.size,
            brand: e.brand,
            serial: e.serial,
            target: e.target,
            raw: e.raw,
          ));
        }
        _specRows.add(row);
      }
      _initSystemSerialToggle();
      _invoiceMode = true;
      _customerLocked = true;
      _specLocked = true;
      _nameMatches = const <ClientCustomerMatch>[];
      _invalid.clear();
      if (_step == 2) _step = 1;
    });
  }

  void _clearInvoiceMode() {
    setState(() {
      for (final r in _specRows) {
        r.dispose();
      }
      _specRows.clear();
      _invoiceMode = false;
      _customerLocked = false;
      _specLocked = true;
    });
  }

  void _onNameChanged(String value) {
    if (_invalid.contains('clientName')) {
      setState(() => _invalid.remove('clientName'));
    }
    final term = value.trim();
    _nameDebounce?.cancel();
    if (term.isEmpty) {
      setState(() => _nameMatches = const <ClientCustomerMatch>[]);
      return;
    }
    final cached = _nameCache[term];
    if (cached != null) {
      setState(() => _nameMatches = cached);
      return;
    }
    _nameDebounce = Timer(const Duration(milliseconds: 250), () async {
      setState(() => _nameSearching = true);
      final list = await widget.service.searchCustomers(term);
      if (!mounted) return;
      _nameCache[term] = list;
      setState(() {
        _nameSearching = false;
        if (_name.text.trim() == term) _nameMatches = list;
      });
    });
  }

  void _pickCustomer(ClientCustomerMatch m) {
    setState(() {
      _nameMatches = const <ClientCustomerMatch>[];
      _name.text = m.ownerName;
      _registeredAddress.text = m.address;
      _systemSerial.text = m.serialNumber;
      _min.text = m.min;
      _tin.text = m.tin;
      _ptu.text = m.ptu;
    });
    final label = m.ownerName.isNotEmpty
        ? m.ownerName
        : (m.companyName.isNotEmpty ? m.companyName : 'customer');
    _snack(context, 'Auto-filled from "$label"');
  }

  Map<String, dynamic> _formState() {
    String specKind(_SpecRow row) {
      if (row.optionsKey == 'storagetype') return 'storage';
      return row.freeSpec ? 'free' : 'select';
    }

    return <String, dynamic>{
      if (_clientId != null) 'client_id': _clientId,
      'invoice_mode': _invoiceMode,
      'fields': <String, String>{
        'clientName': _name.text,
        'clientInvoiceNumber': _invoice.text,
        'clientBranch': _branch.text,
        'clientDatePrepared': _datePrepared.text,
        for (final f in _serialFields) f.formKey: _serials[f.formKey]!.text,
        'clientSystemSerialNumber': _systemSerial.text,
        'clientMacAddress': _mac.text,
        'clientMIN': _min.text,
        'clientPTU': _ptu.text,
        'clientDateApproved': _dateApproved.text,
        'clientTIN': _tin.text,
        'clientRegisteredAddress': _registeredAddress.text,
      },
      'units': <Map<String, String>>[
        for (final g in _units) {'value': g.value, 'serial': g.serial.text},
      ],
      'rams': <String>[for (final g in _rams) g.choice.value],
      'storage': <Map<String, String>>[
        for (final r in _storage)
          {'type': r.typeValue, 'size': r.sizeValue, 'serial': r.serial.text},
      ],
      'monitors': <Map<String, String>>[
        for (final g in _monitors)
          {
            'size': g.size.value,
            'brand': g.brand.value,
            'type': g.type.value,
            'serial': g.serial.text,
          },
      ],
      'spec_rows': <Map<String, dynamic>>[
        if (_invoiceMode)
          for (final row in _specRows)
            {
              'item_name': row.itemName,
              'component': row.component.text,
              'kind': specKind(row),
              'entries': <Map<String, String>>[
                for (final e in row.entries)
                  {
                    'option': row.freeSpec ? e.freeValue.text : e.option.value,
                    'size': e.size.value,
                    'brand': e.brand.text,
                    'serial': e.serial.text,
                    'target': e.target,
                  },
              ],
            },
      ],
    };
  }

  bool _validate() {
    final missing = <String>{};
    if (!(_invoiceMode && _customerLocked)) {
      if (_name.text.trim().isEmpty) missing.add('clientName');
      if (_invoice.text.trim().isEmpty) missing.add('clientInvoiceNumber');
      if (_datePrepared.text.trim().isEmpty) missing.add('clientDatePrepared');
    }
    if (!_invoiceMode) {
      if (_units.isEmpty || _units.first.value.isEmpty) {
        missing.add('clientSystemsUnit');
      }
      if (_rams.isEmpty || _rams.first.choice.value.isEmpty) {
        missing.add('clientRamConfig');
      }
      if (_monitors.isEmpty || _monitors.first.size.value.isEmpty) {
        missing.add('clientmonitorsizeConfig');
      }
      if (_monitors.isEmpty || _monitors.first.brand.value.isEmpty) {
        missing.add('clientmonitorbrandConfig');
      }
    }
    setState(() {
      _invalid
        ..clear()
        ..addAll(missing);
      if (missing.contains('clientName') ||
          missing.contains('clientInvoiceNumber') ||
          missing.contains('clientDatePrepared')) {
        _customerLocked = false;
      }
    });
    return missing.isEmpty;
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final last = _lastSubmitAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      _snack(context, 'Please wait a moment before submitting again.');
      return;
    }
    if (!_validate()) {
      _snack(context, 'Please fill in the required fields.');
      const customerKeys = <String>{
        'clientName',
        'clientInvoiceNumber',
        'clientDatePrepared',
      };
      _goTo(_invalid.any(customerKeys.contains) ? 0 : 1);
      return;
    }
    _lastSubmitAt = now;
    setState(() => _saving = true);
    final result = await widget.service.save(_formState());
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.ok) {
      Navigator.of(context).pop(true);
    } else {
      _snack(
        context,
        result.transport
            ? 'An error occurred: ${result.message}'
            : widget.isEdit
                ? 'Client Not Updated: ${result.message}'
                : 'Client Not Added: ${result.message}',
      );
    }
  }

  Future<void> _reload() async {
    final id = _clientId;
    if (id == null || _reloading) return;
    setState(() => _reloading = true);
    final fresh = await widget.service.detail(id);
    if (!mounted) return;
    setState(() {
      _reloading = false;
      if (fresh != null) _loadFrom(fresh);
    });
  }

  Future<void> _recordReplacement(_ReplacementTarget target) async {
    final id = _clientId;
    if (id == null) return;
    final result = await showDialog<({String component, String serial})>(
      context: context,
      builder: (_) => _ReplacementDialog(componentName: target.componentName),
    );
    if (result == null || !mounted) return;
    if (result.component.trim().isEmpty && result.serial.trim().isEmpty) {
      _snack(context, 'Enter the replacement component or serial number.');
      return;
    }
    final res = await widget.service.addSpecReplacement(
      clientId: id,
      src: target.src,
      index: target.index,
      serialField: target.serialField,
      oldComponent: target.componentName,
      newComponent: result.component.trim(),
      newSerial: result.serial.trim(),
    );
    if (!mounted) return;
    _snack(context, res.message);
    if (res.ok) await _reload();
  }

  String _fieldDisplayName(_SerialFieldSpec f) {
    final list = _historyFor('${f.column}:0');
    if (list.isEmpty) return f.label;
    final latest = list.last.newComponent.trim();
    return latest.isEmpty ? f.label : latest;
  }

  List<ClientSpecReplacement> _historyFor(String rowKey) {
    if (rowKey.isEmpty) return const <ClientSpecReplacement>[];
    return _replacements.where((r) => r.rowKey == rowKey).toList();
  }

  Future<void> _alert({required String title, required String message}) {
    return showWebModal<void>(
      context,
      title: title,
      icon: Icons.error_outline_rounded,
      width: 460,
      builder: (_) => Text(message),
      actions: (ctx) => <Widget>[
        SignalButton(
          label: 'Close',
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    );
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(controller.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() => controller.text = picked.toIso8601String().split('T').first);
  }

  List<int> get _visibleSteps =>
      _invoiceMode ? const <int>[0, 1, 3] : const <int>[0, 1, 2, 3];

  int get _stepPos {
    final i = _visibleSteps.indexOf(_step);
    return i < 0 ? 0 : i;
  }

  void _onScroll() {
    if (_jumping || !_scroll.hasClients) return;
    final pos = _scroll.position;
    final visible = _visibleSteps;
    var step = visible.first;
    if (pos.maxScrollExtent > 0 && pos.pixels >= pos.maxScrollExtent - 4) {
      step = visible.last;
    } else {
      for (final i in visible) {
        final top = _sectionTop(i);
        if (top != null && top <= pos.pixels + 80) step = i;
      }
    }
    if (step != _step) setState(() => _step = step);
  }

  double? _sectionTop(int i) {
    final ro = _sectionKeys[i].currentContext?.findRenderObject();
    if (ro == null || !ro.attached) return null;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(ro, 0).offset;
  }

  Future<void> _goTo(int i) async {
    final visible = _visibleSteps;
    final target = visible.contains(i)
        ? i
        : visible.firstWhere((v) => v >= i, orElse: () => visible.last);
    setState(() => _step = target);
    final ctx = _sectionKeys[target].currentContext;
    if (ctx == null) return;
    _jumping = true;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    _jumping = false;
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 48).clamp(320.0, 1400.0).toDouble();
    final height = (screen.height - 48).clamp(320.0, 1000.0).toDouble();
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _formHeader(),
                Divider(height: 1, color: b.rule),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (width >= 900) _stepRail(),
                      Expanded(
                        child: Scrollbar(
                          controller: _scroll,
                          child: SingleChildScrollView(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                KeyedSubtree(
                                  key: _sectionKeys[0],
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      if (!widget.isEdit)
                                        _invoiceSearchSection(),
                                      _customerSection(),
                                    ],
                                  ),
                                ),
                                KeyedSubtree(
                                  key: _sectionKeys[1],
                                  child: _systemSection(),
                                ),
                                if (!_invoiceMode)
                                  KeyedSubtree(
                                    key: _sectionKeys[2],
                                    child: _serialSection(),
                                  ),
                                KeyedSubtree(
                                  key: _sectionKeys[3],
                                  child: _birSection(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: b.rule),
                _bottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _formHeader() {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Container(
      color: b.surface,
      padding: const EdgeInsets.fromLTRB(24, 14, 12, 14),
      child: Row(
        children: <Widget>[
          Image(image: brandAsset('assets/brand/logo-wordmark.png'), height: 34, fit: BoxFit.contain),
          const SizedBox(width: 18),
          Container(width: 1, height: 32, color: b.rule),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.isEdit
                      ? 'Update Client and Data Sheet'
                      : 'Client and Data Sheet Form',
                  style: text.titleLarge,
                ),
                if (widget.isEdit && widget.existing!.name.trim().isNotEmpty)
                  Text(
                    widget.existing!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
              ],
            ),
          ),
          if (_reloading) ...<Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: TpLoader(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Brand.signal),
          ),
        ],
      ),
    );
  }

  Widget _stepRail() {
    final b = context.brand;
    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: b.surfaceHi,
        border: Border(right: BorderSide(color: b.rule)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          for (final i in _visibleSteps) _stepTile(i),
        ],
      ),
    );
  }

  Widget _stepTile(int i) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final s = _steps[i];
    final pos = _visibleSteps.indexOf(i);
    final active = i == _step;
    final done = pos < _stepPos;
    final filled = active || done;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active ? b.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: active ? b.rule : Colors.transparent),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _goTo(i),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? Brand.signal : b.surface,
                    border: Border.all(
                      color: filled ? Brand.signal : b.rule,
                      width: 1.5,
                    ),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white)
                      : Text(
                          '${pos + 1}',
                          style: text.labelLarge?.copyWith(
                            color: active ? Colors.white : b.paperDim,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              s.icon,
                              size: 16,
                              color: active ? Brand.signal : b.paper,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.title,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: active ? Brand.signal : b.paper,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.subtitle,
                        style: text.bodySmall?.copyWith(color: b.paperDim),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final visible = _visibleSteps;
    final pos = _stepPos;
    final last = pos >= visible.length - 1;
    return Container(
      color: b.surface,
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Row(
        children: <Widget>[
          Text(
            'Page ${pos + 1} of ${visible.length}',
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 240,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (pos + 1) / visible.length,
                minHeight: 6,
                color: Brand.signal,
                backgroundColor: b.rule,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Fields marked * are required · Ctrl+S to save',
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
          ),
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          if (pos > 0) ...<Widget>[
            const SizedBox(width: 10),
            GhostButton(
              label: 'Back',
              onPressed: () => _goTo(visible[pos - 1]),
            ),
          ],
          if (!last && widget.isEdit) ...<Widget>[
            const SizedBox(width: 10),
            GhostButton(
              label: 'Save changes',
              icon: Icons.check_rounded,
              onPressed: _saving ? null : _save,
            ),
          ],
          const SizedBox(width: 10),
          last
              ? SignalButton(
                  label: widget.isEdit ? 'Save changes' : 'Save',
                  busy: _saving,
                  icon: Icons.check_rounded,
                  onPressed: _saving ? null : _save,
                )
              : SignalButton(
                  label: 'Next',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () => _goTo(visible[pos + 1]),
                ),
        ],
      ),
    );
  }

  Widget _formSection(int index, {required Widget child, Widget? action}) {
    final s = _steps[index];
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Brand.signal,
                ),
                child: Text(
                  '${_visibleSteps.indexOf(index) + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(s.icon, color: Brand.signal, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title,
                  style: text.titleLarge?.copyWith(
                    color: Brand.signal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _formCard({
    required List<Widget> children,
    EdgeInsets padding = const EdgeInsets.fromLTRB(24, 6, 24, 6),
  }) {
    final b = context.brand;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(_radiusLg),
        border: Border.all(color: b.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _lrRow(
    String label,
    Widget input, {
    IconData? icon,
    bool required = false,
    bool last = false,
    double maxInput = 520,
  }) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: b.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 250,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 16, color: Brand.signal),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: text.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (required)
                    const Text(
                      ' *',
                      style: TextStyle(
                          color: _danger, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxInput),
                child: input,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _invoiceSearchSection() {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.search_rounded, size: 16, color: Brand.signal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Search invoice number to auto-fill',
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (_invoiceMode)
                _sectionAction('Clear', Icons.close_rounded, _clearInvoiceMode),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            readOnly: true,
            mouseCursor: SystemMouseCursors.click,
            onTap: _openInvoiceSearch,
            decoration: InputDecoration(
              hintText: _invoiceMode && _invoice.text.trim().isNotEmpty
                  ? 'Invoice ${_invoice.text.trim()} · search another invoice…'
                  : 'Type an invoice number, e.g. INV-00123…',
              prefixIcon: const Icon(Icons.search, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerSection() {
    return _formSection(
      0,
      action: _invoiceMode
          ? _sectionAction(
              _customerLocked ? 'Edit' : 'Done',
              _customerLocked ? Icons.edit_rounded : Icons.check_rounded,
              () => setState(() => _customerLocked = !_customerLocked),
            )
          : null,
      child: _formCard(
        padding: _customerLocked
            ? const EdgeInsets.fromLTRB(24, 14, 24, 14)
            : const EdgeInsets.fromLTRB(24, 6, 24, 6),
        children: _customerLocked
            ? <Widget>[
                _KeyValue('Customer Name', _name.text),
                _KeyValue('Agreement / Invoice Number', _invoice.text),
                _KeyValue('Branch', _branch.text),
                _KeyValue('Date Prepared', _datePrepared.text),
              ]
            : <Widget>[
                _lrRow('Customer Name', _nameField(),
                    icon: Icons.person_rounded, required: true),
                _lrRow(
                  'Agreement / Invoice Number',
                  _field(_invoice,
                      fieldKey: 'clientInvoiceNumber', hint: 'Invoice number'),
                  icon: Icons.sell_rounded,
                  required: true,
                ),
                _lrRow('Branch', _field(_branch, hint: 'Branch'),
                    icon: Icons.account_tree_rounded),
                _lrRow(
                  'Date Prepared',
                  _dateField(_datePrepared, fieldKey: 'clientDatePrepared'),
                  icon: Icons.calendar_month_rounded,
                  required: true,
                  last: true,
                ),
              ],
      ),
    );
  }

  Widget _nameField() {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final invalid = _invalid.contains('clientName');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          onChanged: _onNameChanged,
          decoration: InputDecoration(
            hintText: widget.isEdit
                ? 'Enter customer name'
                : 'Enter customer name (type to search BIR registrations)',
            enabledBorder: invalid ? _invalidBorder() : null,
            suffixIcon: _nameSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: TpLoader(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        if (_nameMatches.isNotEmpty && _name.text.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: b.surface,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: b.rule),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final m in _nameMatches)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_search_rounded, size: 18),
                    title: Text(
                      m.ownerName.isEmpty ? '(no owner name)' : m.ownerName,
                      style: text.bodyMedium,
                    ),
                    subtitle: m.companyName.isEmpty
                        ? null
                        : Text(m.companyName, style: text.bodySmall),
                    onTap: () => _pickCustomer(m),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(
                        () => _nameMatches = const <ClientCustomerMatch>[]),
                    child: const Text('Dismiss'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _systemSection() {
    return _formSection(
      1,
      action: _invoiceMode
          ? _sectionAction(
              _specLocked ? 'Edit' : 'Done',
              _specLocked ? Icons.edit_rounded : Icons.check_rounded,
              () => setState(() => _specLocked = !_specLocked),
            )
          : null,
      child: _invoiceMode
          ? _formCard(
              padding: const EdgeInsets.all(16),
              children: _invoiceSpecChildren(),
            )
          : _specTable(),
    );
  }

  Widget _specTable() {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final rows = <({
      String label,
      IconData icon,
      bool required,
      List<Widget> children
    })>[
      (
        label: 'Systems Unit Brand',
        icon: Icons.dns_rounded,
        required: true,
        children: <Widget>[
          for (var i = 0; i < _units.length; i++) _unitGroupCard(i),
          _addMoreButton(
              'Add More', () => setState(() => _units.add(_UnitGroup()))),
        ],
      ),
      (
        label: 'RAM Configuration',
        icon: Icons.memory_rounded,
        required: true,
        children: <Widget>[
          for (var i = 0; i < _rams.length; i++) _ramGroupCard(i),
          _addMoreButton(
              'Add More', () => setState(() => _rams.add(_RamGroup()))),
        ],
      ),
      (
        label: 'HDD / SSD Type and Size',
        icon: Icons.storage_rounded,
        required: false,
        children: <Widget>[
          for (var i = 0; i < _storage.length; i++) _storageRowCard(i),
          _addMoreButton(
            'Add More',
            () => setState(() {
              _storage.add(_StorageRow());
              _rebuildStorageConfig();
            }),
          ),
        ],
      ),
      (
        label: 'Monitor',
        icon: Icons.tv_rounded,
        required: true,
        children: <Widget>[
          for (var i = 0; i < _monitors.length; i++) _monitorGroupCard(i),
          _addMoreButton('Add Monitor',
              () => setState(() => _monitors.add(_MonitorGroup()))),
        ],
      ),
    ];
    const headStyle = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
      fontSize: 14,
    );
    return Container(
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(_radiusLg),
        border: Border.all(color: b.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: ColumnResizeScope(tableId: 'client:specs', child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            color: Brand.signal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Builder(builder: (context) => Row(
              children: resizableRowCells(context, <Widget>[
                SizedBox(
                    width: 260, child: Text('Specification', style: headStyle)),
                Expanded(child: Text('Serial Number', style: headStyle)),
              ], header: true, extra: 32),
            )),
          ),
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              decoration: BoxDecoration(
                color: i.isOdd ? Brand.signalGlow(0.05) : b.surface,
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: b.rule)),
              ),
              child: Builder(builder: (context) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: resizableRowCells(context, <Widget>[
                  SizedBox(
                    width: 260,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14, right: 12),
                      child: Row(
                        children: <Widget>[
                          Icon(rows[i].icon, size: 16, color: Brand.signal),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              rows[i].label,
                              style: text.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (rows[i].required)
                            const Text(
                              ' *',
                              style: TextStyle(
                                  color: _danger,
                                  fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: rows[i].children,
                    ),
                  ),
                ]),
              )),
            ),
        ],
      ),),
    );
  }

  Widget _unitGroupCard(int index) {
    final g = _units[index];
    final branded =
        RegExp(r'^branded cpu', caseSensitive: false).hasMatch(g.selected ?? '');
    return _rowShell(
      onRemove:
          index == 0 ? null : () => setState(() => _units.removeAt(index).dispose()),
      replacement: _replacementFor(_ReplacementTarget(
        src: 'field',
        index: index,
        serialField: 'system_unit_serialnum',
        componentName: g.value.isEmpty ? 'System Unit' : g.value,
      )),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _dropdown(
                value: g.selected,
                hint: 'Select an option',
                invalid: index == 0 && _invalid.contains('clientSystemsUnit'),
                options: _systemUnitOptions,
                labelOf: (v) => _systemUnitLabels[v] ?? v,
                onChanged: (v) => setState(() {
                  g.selected = v;
                  _invalid.remove('clientSystemsUnit');
                  if (!RegExp(r'^branded cpu', caseSensitive: false)
                      .hasMatch(v ?? '')) {
                    g.brand.clear();
                  }
                }),
              ),
            ),
            if (branded) ...<Widget>[
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: g.brand,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Brand name (e.g. HP, Dell)',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        _serialInput(g.serial),
        for (final r in _historyFor('system_unit_serialnum:$index'))
          _historyRow(r, 'System Unit'),
      ],
    );
  }

  Widget _ramGroupCard(int index) {
    final g = _rams[index];
    return _rowShell(
      onRemove:
          index == 0 ? null : () => setState(() => _rams.removeAt(index).dispose()),
      children: <Widget>[
        _choiceControl(
          g.choice,
          hint: 'Select an option',
          otherHint: 'Specify other RAM size',
          invalid: index == 0 && _invalid.contains('clientRamConfig'),
          invalidKey: 'clientRamConfig',
        ),
      ],
    );
  }

  Widget _storageRowCard(int index) {
    final r = _storage[index];
    return _rowShell(
      onRemove: index == 0 && _storage.length == 1
          ? null
          : () => setState(() {
                _storage.removeAt(index).dispose();
                if (_storage.isEmpty) _storage.add(_StorageRow());
                _rebuildStorageConfig();
              }),
      replacement: _replacementFor(_ReplacementTarget(
        src: 'field',
        index: index,
        serialField: 'storage_serialnum',
        componentName: <String>[r.typeValue, r.sizeValue]
            .where((v) => v.isNotEmpty)
            .join(' '),
      )),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _dropdown(
                value: r.type,
                hint: 'Select type',
                options: _storageTypeOptions,
                labelOf: (v) => _storageTypeLabels[v] ?? v,
                onChanged: (v) => setState(() {
                  r.type = v;
                  _rebuildStorageConfig();
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown(
                value: r.size,
                hint: 'Size',
                options: <String>[..._storageSizeOptions, _otherOption],
                onChanged: (v) => setState(() {
                  r.size = v;
                  if (v != _otherOption) r.sizeOther.clear();
                  _rebuildStorageConfig();
                }),
              ),
            ),
          ],
        ),
        if (r.size == _otherOption) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            controller: r.sizeOther,
            onChanged: (_) => setState(_rebuildStorageConfig),
            decoration:
                const InputDecoration(hintText: 'Custom size', isDense: true),
          ),
        ],
        const SizedBox(height: 8),
        _serialInput(r.serial),
        for (final h in _historyFor('storage_serialnum:$index'))
          _historyRow(h, 'Storage'),
      ],
    );
  }

  Widget _monitorGroupCard(int index) {
    final g = _monitors[index];
    final label = <String>[g.size.value, g.brand.value]
        .where((v) => v.isNotEmpty)
        .join(' ')
        .trim();
    return _rowShell(
      onRemove: index == 0
          ? null
          : () => setState(() => _monitors.removeAt(index).dispose()),
      replacement: _replacementFor(_ReplacementTarget(
        src: 'field',
        index: index,
        serialField: 'monitor_serialnum',
        componentName: label.isEmpty ? 'Monitor' : label,
      )),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _subLabel('Size'),
                  _choiceControl(
                    g.size,
                    hint: 'Select a size',
                    otherHint: 'Specify other size',
                    labelOf: (v) => _monitorSizeLabels[v] ?? v,
                    invalid: index == 0 &&
                        _invalid.contains('clientmonitorsizeConfig'),
                    invalidKey: 'clientmonitorsizeConfig',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _subLabel('Brand'),
                  _choiceControl(
                    g.brand,
                    hint: 'Select a brand',
                    otherHint: 'Specify other brand',
                    invalid: index == 0 &&
                        _invalid.contains('clientmonitorbrandConfig'),
                    invalidKey: 'clientmonitorbrandConfig',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _subLabel('Type'),
                  _choiceControl(
                    g.type,
                    hint: 'Select a type',
                    otherHint: 'Specify other type',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _subLabel('Serial Number'),
        _serialInput(g.serial),
        for (final h in _historyFor('monitor_serialnum:$index'))
          _historyRow(h, 'Monitor'),
      ],
    );
  }

  List<Widget> _invoiceSpecChildren() {
    if (_specRows.isEmpty) {
      return <Widget>[
        Text('This invoice has no line items.',
            style: Theme.of(context).textTheme.bodySmall),
      ];
    }
    final out = <Widget>[];
    String lastGroup = '';
    final groupCount = _specRows.map((r) => r.itemName).toSet().length;
    for (var i = 0; i < _specRows.length; i++) {
      final row = _specRows[i];
      if (groupCount > 1 && row.itemName != lastGroup) {
        lastGroup = row.itemName;
        out.add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : 8, bottom: 8),
          child: Text(
            row.itemName,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Brand.signal),
          ),
        ));
      }
      out.add(_specRowCard(i));
    }
    if (!_specLocked) {
      out.add(_addMoreButton('Add component', () {
        setState(() {
          final row = _SpecRow(
            itemName: _specRows.isEmpty ? 'Item' : _specRows.last.itemName,
            component: '',
            icon: Icons.category_rounded,
            optionsKey: '',
            freeSpec: true,
          )..entries.add(_SpecEntry(optionsKey: '', freeSpec: true));
          _specRows.add(row);
        });
      }));
    }
    return out;
  }

  Widget _specRowCard(int index) {
    final row = _specRows[index];
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final isStorage = row.optionsKey == 'storagetype';
    final rowKeys = row.entries
        .map((e) => e.serverIndex == null ? '' : 'item:${e.serverIndex}')
        .toList();
    final hasHistory = rowKeys.any((k) => _historyFor(k).isNotEmpty);
    final displayName = row.component.text.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: b.canvas,
        borderRadius: BorderRadius.circular(_radiusLg),
        border: Border.all(color: b.signal.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(row.icon, size: 18, color: Brand.signal),
              const SizedBox(width: 8),
              Expanded(
                child: _specLocked
                    ? Text(displayName.isEmpty ? '—' : displayName,
                        style: text.titleSmall)
                    : TextField(
                        controller: row.component,
                        decoration: const InputDecoration(
                          hintText: 'Component name',
                          isDense: true,
                        ),
                      ),
              ),
              if (hasHistory) ...<Widget>[
                const SizedBox(width: 8),
                const _Pill(
                  label: 'Replacement',
                  icon: Icons.swap_horiz_rounded,
                  color: _warning,
                ),
              ],
            ],
          ),
          for (var i = 0; i < row.entries.length; i++) ...<Widget>[
            const SizedBox(height: 10),
            _specEntry(row, i, isStorage),
            for (final r in _historyFor(rowKeys[i]))
              _historyRow(r, row.component.text.trim()),
          ],
          if (!_specLocked) ...<Widget>[
            const SizedBox(height: 8),
            _addMoreButton('Add specification', () {
              setState(() {
                row.entries.add(_SpecEntry(
                  optionsKey: row.optionsKey,
                  freeSpec: row.freeSpec,
                ));
                _initSystemSerialToggle();
              });
            }),
          ],
        ],
      ),
    );
  }

  Widget _specEntry(_SpecRow row, int i, bool isStorage) {
    final e = row.entries[i];
    final removable = !_specLocked;
    final spec = row.freeSpec
        ? TextField(
            controller: e.freeValue,
            enabled: !_specLocked,
            decoration:
                const InputDecoration(hintText: 'Specification', isDense: true),
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _specSelect(e.option, enabled: !_specLocked)),
              if (isStorage) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(child: _specSelect(e.size, enabled: !_specLocked)),
              ],
            ],
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: isStorage ? 5 : 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_subLabel('Specification'), spec],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _subLabel('Brand Name'),
                  TextField(
                    controller: e.brand,
                    enabled: !_specLocked,
                    decoration: const InputDecoration(
                        hintText: 'Brand name', isDense: true),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _subLabel('Serial Number'),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: e.serial,
                          decoration: const InputDecoration(
                            hintText: 'Serial number',
                            isDense: true,
                          ),
                        ),
                      ),
                      ?_replacementFor(_ReplacementTarget(
                        src: 'item',
                        index: e.serverIndex ?? -1,
                        serialField: '',
                        componentName: row.component.text.trim(),
                      )),
                      if (removable)
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.close_rounded,
                              size: 18, color: _danger),
                          onPressed: () => setState(() {
                            if (row.entries.length <= 1) {
                              _specRows.remove(row);
                              row.dispose();
                              return;
                            }
                            row.entries.removeAt(i).dispose();
                            _initSystemSerialToggle();
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (isStorage) ...<Widget>[
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Switch(
                value: e.sysSerial,
                onChanged: (v) => setState(() {
                  for (final r in _specRows) {
                    if (r.optionsKey != 'storagetype') continue;
                    for (final other in r.entries) {
                      other.sysSerial = false;
                    }
                  }
                  e.sysSerial = v;
                }),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Use this drive as the System Serial Number',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _historyRow(ClientSpecReplacement r, String fallbackName) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final name =
        r.oldComponent.trim().isEmpty ? fallbackName : r.oldComponent.trim();
    final when = _formatReplacedAt(r.replacedAt);
    final who = r.replacedByName.trim();
    final tag = <String>[
      when.isEmpty ? 'Replaced' : 'Replaced $when',
      if (who.isNotEmpty) 'by $who',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('└─', style: text.bodySmall?.copyWith(color: b.paperDim)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(name, style: text.bodyMedium),
                Text(tag, style: text.labelSmall?.copyWith(color: b.paperDim)),
                Text(
                  r.oldSerial.trim().isEmpty
                      ? 'SN: N/A'
                      : 'SN: ${r.oldSerial.trim()}',
                  style: text.bodySmall?.copyWith(color: b.paperDim),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _replacementFor(_ReplacementTarget target) {
    if (_clientId == null) return null;
    if (target.src == 'item' && target.index < 0) return null;
    return IconButton(
      tooltip: 'Record a replacement',
      icon: const Icon(Icons.swap_horiz_rounded, size: 18, color: Brand.signal),
      onPressed: () => _recordReplacement(target),
    );
  }

  Widget _serialSection() {
    return _formSection(
      2,
      child: _formCard(
        children: <Widget>[
          for (var i = 0; i < _serialFields.length; i++)
            _lrRow(
              _fieldDisplayName(_serialFields[i]),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                          child:
                              _serialInput(_serials[_serialFields[i].formKey]!)),
                      ?_replacementFor(_ReplacementTarget(
                        src: 'field',
                        index: 0,
                        serialField: _serialFields[i].column,
                        componentName: _fieldDisplayName(_serialFields[i]),
                      )),
                    ],
                  ),
                  for (final r in _historyFor('${_serialFields[i].column}:0'))
                    _historyRow(r, _serialFields[i].label),
                ],
              ),
              icon: _serialFields[i].icon,
              last: i == _serialFields.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _birSection() {
    return _formSection(
      3,
      child: _formCard(
        children: <Widget>[
          _lrRow(
            'System Serial Number',
            _serialInput(
              _systemSerial,
              hint: 'System Serial Number',
              enabled: _systemSerialEnabled,
            ),
            icon: Icons.confirmation_number_rounded,
          ),
          _lrRow('MAC Address (Physical Address)',
              _field(_mac, hint: 'MAC Address'),
              icon: Icons.lan_rounded),
          _lrRow('Machine Identification Number (MIN)',
              _field(_min, hint: 'MIN'),
              icon: Icons.fingerprint_rounded),
          _lrRow('PTU', _field(_ptu, hint: 'PTU'),
              icon: Icons.verified_rounded),
          _lrRow('Date Approved', _dateField(_dateApproved),
              icon: Icons.event_available_rounded),
          _lrRow('TIN', _field(_tin, hint: 'TIN'), icon: Icons.badge_rounded),
          _lrRow(
            'Registered Address (As per 2303)',
            _field(_registeredAddress, hint: 'Registered Address'),
            icon: Icons.location_on_rounded,
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _sectionAction(String label, IconData icon, VoidCallback? onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  Widget _subLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: context.brand.paperDim),
        ),
      );

  Widget _field(
    TextEditingController controller, {
    int maxLines = 1,
    String? hint,
    String? fieldKey,
  }) {
    final invalid = fieldKey != null && _invalid.contains(fieldKey);
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: fieldKey == null || !invalid
          ? null
          : (_) => setState(() => _invalid.remove(fieldKey)),
      decoration: InputDecoration(
        hintText: hint,
        enabledBorder: invalid ? _invalidBorder() : null,
      ),
    );
  }

  OutlineInputBorder _invalidBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: const BorderSide(color: _danger),
      );

  Widget _dateField(
    TextEditingController controller, {
    String? fieldKey,
  }) {
    final invalid = fieldKey != null && _invalid.contains(fieldKey);
    return TextField(
      controller: controller,
      readOnly: true,
      mouseCursor: SystemMouseCursors.click,
      onTap: () async {
        await _pickDate(controller);
        if (fieldKey != null && mounted) {
          setState(() => _invalid.remove(fieldKey));
        }
      },
      decoration: InputDecoration(
        hintText: 'YYYY-MM-DD',
        enabledBorder: invalid ? _invalidBorder() : null,
        prefixIcon: Icon(Icons.calendar_today_rounded,
            size: 18, color: context.brand.paperDim),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear date',
                icon: Icon(Icons.close_rounded,
                    size: 18, color: context.brand.paperDim),
                onPressed: () => setState(() => controller.clear()),
              ),
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required String hint,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String Function(String)? labelOf,
    bool enabled = true,
    bool invalid = false,
  }) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return InputDecorator(
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        enabledBorder: invalid ? _invalidBorder() : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(value) ? value : null,
          isExpanded: true,
          isDense: true,
          dropdownColor: b.surface,
          borderRadius: BorderRadius.circular(_radius),
          icon: Icon(Icons.expand_more_rounded, color: b.paperDim),
          hint: Text(hint, style: text.bodyMedium?.copyWith(color: b.paperDim)),
          items: <DropdownMenuItem<String>>[
            for (final o in options)
              DropdownMenuItem<String>(
                value: o,
                child: Text(labelOf == null ? o : labelOf(o),
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  Widget _choiceControl(
    _Choice choice, {
    required String hint,
    required String otherHint,
    String Function(String)? labelOf,
    bool invalid = false,
    String? invalidKey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _dropdown(
          value: choice.selected,
          hint: hint,
          invalid: invalid,
          options: <String>[...choice.options, _otherOption],
          labelOf: labelOf,
          onChanged: (v) => setState(() {
            choice.selected = v;
            if (invalidKey != null) _invalid.remove(invalidKey);
            if (v != _otherOption) choice.other.clear();
          }),
        ),
        if (choice.selected == _otherOption) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            controller: choice.other,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: otherHint, isDense: true),
          ),
        ],
      ],
    );
  }

  Widget _specSelect(_SpecSelect select, {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _dropdown(
          value: select.selected,
          hint: 'Select…',
          enabled: enabled,
          options: select.options,
          onChanged: (v) => setState(() {
            select.selected = v;
            if (v != _specOther) select.other.clear();
          }),
        ),
        if (select.selected == _specOther) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            controller: select.other,
            enabled: enabled,
            decoration:
                const InputDecoration(hintText: 'Enter value', isDense: true),
          ),
        ],
      ],
    );
  }

  Widget _serialInput(
    TextEditingController controller, {
    String hint = 'Serial number',
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(hintText: hint, isDense: true),
    );
  }

  Widget _rowShell({
    required List<Widget> children,
    VoidCallback? onRemove,
    Widget? replacement,
  }) {
    final b = context.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: b.canvas,
        borderRadius: BorderRadius.circular(_radiusLg),
        border: Border.all(color: b.rule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          if (onRemove != null || replacement != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ?replacement,
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: _danger),
                    onPressed: onRemove,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _addMoreButton(String label, VoidCallback onTap) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text(label),
        ),
      );
}

IconData _faIcon(String name) {
  switch (name) {
    case 'fa-print':
      return Icons.print_rounded;
    case 'fa-barcode':
      return Icons.qr_code_scanner_rounded;
    case 'fa-cash-register':
      return Icons.point_of_sale_rounded;
    case 'fa-desktop':
      return Icons.desktop_windows_rounded;
    case 'fa-microchip':
      return Icons.memory_rounded;
    case 'fa-keyboard':
      return Icons.keyboard_rounded;
    case 'fa-mouse':
      return Icons.mouse_rounded;
    case 'fa-tv':
      return Icons.tv_rounded;
    case 'fa-hdd':
      return Icons.storage_rounded;
    case 'fa-server':
      return Icons.dns_rounded;
    default:
      return Icons.category_rounded;
  }
}

String _formatReplacedAt(String raw) {
  final normalized = raw.trim().replaceFirst(' ', 'T');
  if (normalized.isEmpty) return '';
  final parsed = DateTime.tryParse(normalized);
  if (parsed == null) return '';
  return '${_monthNames[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}

List<String> _splitCsv(String value) =>
    value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

List<String> _splitCsvKeepEmpty(String value) {
  if (value.trim().isEmpty) return const <String>[];
  return value.split(',').map((s) => s.trim()).toList();
}

String _pickField(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && v.toString().trim().isNotEmpty) {
      return v.toString().trim();
    }
  }
  return '';
}

String _invoiceNumberOf(Map<String, dynamic> item) => _pickField(item, <String>[
      'invoice_number',
      'invoiceNumber',
      'invoice_no',
      'invoiceNo',
      'number',
      'invoice',
    ]);

String _invoiceBranchOf(Map<String, dynamic> item) {
  for (final k in <String>['branch_name', 'branch_code', 'branchName', 'branch']) {
    final v = item[k];
    if (v == null) continue;
    if (v is Map) {
      final nested = _pickField(
          Map<String, dynamic>.from(v), <String>['name', 'branch_name', 'code']);
      if (nested.isNotEmpty) return nested;
      continue;
    }
    if (v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  return '';
}

String _invoiceNameOf(Map<String, dynamic> item) {
  final customer = item['customer'] is Map
      ? Map<String, dynamic>.from(item['customer'])
      : item;
  final name = _pickField(customer, <String>[
    'display_name',
    'name',
    'company_name',
    'customerName',
    'email',
  ]);
  if (name.isNotEmpty) return name;
  return _pickField(item, <String>['name', 'customer_name']);
}

String _detectBrand(String text, String brandsKey) {
  for (final b in _specBrands[brandsKey] ?? const <String>[]) {
    if (RegExp('\\b${b.replaceAll('-', '[-\\s]?')}', caseSensitive: false)
        .hasMatch(text)) {
      return b;
    }
  }
  return '';
}

class _SpecMeta {
  _SpecMeta({
    required this.name,
    required this.icon,
    required this.target,
    required this.optionsKey,
    required this.defaultOption,
    required this.defaultSize,
    required this.defaultBrand,
  });

  final String name;
  final IconData icon;
  final String target;
  final String optionsKey;
  final String defaultOption;
  final String defaultSize;
  final String defaultBrand;
}

({String formKey, IconData icon})? _componentSerialField(String label) {
  bool m(String p) => RegExp(p, caseSensitive: false).hasMatch(label);
  if (m(r'thermal\s*printer')) {
    return (
      formKey: 'clientthermalprinterSerialNumber',
      icon: Icons.print_rounded
    );
  }
  if (m(r'barcode\s*printer')) {
    return (
      formKey: 'clientBarcodePrinterSerialNumber',
      icon: Icons.local_printshop_rounded
    );
  }
  if (m(r'barcode\s*scanner|\bscanner\b')) {
    return (
      formKey: 'clientbarcodescannerSerialNumber',
      icon: Icons.qr_code_scanner_rounded
    );
  }
  if (m(r'cash\s*drawer')) {
    return (
      formKey: 'clientCashDrawerSerialNumber',
      icon: Icons.point_of_sale_rounded
    );
  }
  if (m(r'customer\s*display|pole')) {
    return (
      formKey: 'clientcusdisplaySerialNumber',
      icon: Icons.desktop_windows_rounded
    );
  }
  if (m(r'motherboard|mainboard')) {
    return (formKey: 'clientMotherboardSerialNumber', icon: Icons.memory_rounded);
  }
  if (m(r'keyboard')) {
    return (formKey: 'clientKeyboardSerialNumber', icon: Icons.keyboard_rounded);
  }
  if (m(r'mouse')) {
    return (formKey: 'clientMouseSerialNumber', icon: Icons.mouse_rounded);
  }
  if (m(r'monitor|display|screen')) {
    return (formKey: 'clientMonitorSerialNumber', icon: Icons.tv_rounded);
  }
  if (m(r'\bssd\b|solid\s*state|\bhdd\b|hard\s*disk|\be?mmc\b|storage')) {
    return (formKey: 'clientStorageSerialNumber', icon: Icons.storage_rounded);
  }
  if (m(r'all\s*-?\s*in\s*-?\s*one|branded\s*cpu|generic\s*cpu|\bcpu\b|system\s*unit')) {
    return (formKey: 'clientSystemUnitSerialNumber', icon: Icons.dns_rounded);
  }
  return null;
}

_SpecMeta _normalizeSpec(String label) {
  final c = label;
  final field = _componentSerialField(c);
  String name = c;
  IconData icon = field?.icon ?? Icons.category_rounded;
  final target = field?.formKey ?? '';
  String optionsKey = '';
  String defaultOption = '';
  String defaultSize = '';
  String defaultBrand = '';
  bool m(String p) => RegExp(p, caseSensitive: false).hasMatch(c);
  RegExpMatch? match(String p) => RegExp(p, caseSensitive: false).firstMatch(c);

  if (m(r'monitor|display|screen')) {
    name = 'Monitor';
    optionsKey = 'monitor';
    final s = match(r'(\d+(?:\.\d+)?)\s*(?:in\b|inch|inches|")');
    if (s != null) defaultOption = '${s.group(1)} Inches';
    defaultBrand = _detectBrand(c, 'monitor');
  } else if (m(r'\bram\b|memory')) {
    name = 'RAM';
    optionsKey = 'ram';
    final s = match(r'(\d+)\s*GB');
    if (s != null) defaultOption = '${s.group(1)}GB';
  } else if (m(
      r'\bssd\b|solid\s*state|\bhdd\b|hard\s*disk|\bnvme\b|\bm\.?2\b|\be?mmc\b|storage')) {
    name = 'Storage';
    icon = Icons.storage_rounded;
    optionsKey = 'storagetype';
    if (m(r'\bnvme\b')) {
      defaultOption = 'NVMe';
    } else if (m(r'\bm\.?2\b')) {
      defaultOption = 'M.2';
    } else if (m(r'\bssd\b|solid\s*state')) {
      defaultOption = 'SSD';
    } else if (m(r'\be?mmc\b')) {
      defaultOption = 'eMMC';
    } else if (m(r'\bhdd\b|hard\s*disk')) {
      defaultOption = 'HDD';
    }
    final s = match(r'(\d+(?:\.\d+)?)\s*(GB|TB)');
    if (s != null) defaultSize = '${s.group(1)}${s.group(2)!.toUpperCase()}';
  } else if (m(r'receipt\s*printer')) {
    name = 'Receipt Printer';
    icon = Icons.print_rounded;
    optionsKey = 'printer';
    final s = match(r'(\d+)\s*mm');
    if (s != null) defaultOption = '${s.group(1)}mm';
  } else if (m(r'thermal\s*printer')) {
    name = 'Thermal Printer';
    optionsKey = 'printer';
    final s = match(r'(\d+)\s*mm');
    if (s != null) defaultOption = '${s.group(1)}mm';
  } else if (m(r'processor|\bcpu\b|system\s*unit|all\s*-?\s*in\s*-?\s*one')) {
    name = 'Processor';
    icon = Icons.memory_rounded;
    optionsKey = 'processor';
    final s = match(r'(\d+(?:\.\d+)?)\s*(MHz|GHz)');
    if (s != null) {
      final unit = RegExp(r'ghz', caseSensitive: false).hasMatch(s.group(2)!)
          ? 'GHz'
          : 'MHz';
      defaultOption = '${s.group(1)} $unit';
    }
    defaultBrand = _detectBrand(c, 'processor');
  } else if (m(r'cash\s*drawer')) {
    name = 'Cash Drawer';
    optionsKey = 'cashdrawer';
    final s = match(r'(\d+(?:\s*/\s*\d+)?)\s*bills?');
    if (s != null) {
      defaultOption = '${s.group(1)!.replaceAll(RegExp(r'\s+'), '')} Bills';
    }
  } else if (m(r'barcode\s*scanner|\bscanner\b')) {
    name = 'Barcode Scanner';
    optionsKey = 'barcode';
    final s = match(r'\b(1d(?:\s*[/&]\s*2d)?|2d)\b');
    if (s != null) {
      defaultOption = s.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    }
  } else if (m(r'barcode\s*printer')) {
    name = 'Barcode Printer';
  } else if (m(r'motherboard|mainboard')) {
    name = 'Motherboard';
  } else if (m(r'keyboard')) {
    name = 'Keyboard';
  } else if (m(r'mouse\s*pad|mousepad')) {
    name = 'Mouse Pad';
  } else if (m(r'mouse')) {
    name = 'Mouse';
  } else if (m(r'customer\s*display|pole')) {
    name = 'Customer Display';
  }
  if (optionsKey.isEmpty && defaultOption.isEmpty) defaultOption = _specNa;
  return _SpecMeta(
    name: name,
    icon: icon,
    target: target,
    optionsKey: optionsKey,
    defaultOption: defaultOption,
    defaultSize: defaultSize,
    defaultBrand: defaultBrand,
  );
}

class _ReplacementTarget {
  const _ReplacementTarget({
    required this.src,
    required this.index,
    required this.serialField,
    required this.componentName,
  });

  final String src;
  final int index;
  final String serialField;
  final String componentName;
}

class _Choice {
  _Choice(this.options);

  final List<String> options;
  String? selected;
  final TextEditingController other = TextEditingController();

  void init(String value) {
    if (value.isEmpty) {
      selected = null;
      other.clear();
    } else if (options.contains(value)) {
      selected = value;
      other.clear();
    } else {
      selected = _otherOption;
      other.text = value;
    }
  }

  String get value =>
      selected == _otherOption ? other.text.trim() : (selected ?? '');

  void dispose() => other.dispose();
}

class _SpecSelect {
  _SpecSelect(this.optionsKey, String initial) {
    set(initial);
  }

  final String optionsKey;
  String? selected;
  String custom = '';
  final TextEditingController other = TextEditingController();

  List<String> get options => <String>[
        if (custom.isNotEmpty) custom,
        ...(_specOptions[optionsKey] ?? const <String>[]),
        _specNa,
        _specOther,
      ];

  void set(String value) {
    final v = value.trim();
    if (v.isEmpty) {
      selected = null;
      custom = '';
      other.clear();
      return;
    }
    if (v == _specOther) {
      selected = _specOther;
      return;
    }
    final list = _specOptions[optionsKey] ?? const <String>[];
    if (list.contains(v) || v == _specNa) {
      selected = v;
      custom = '';
      return;
    }
    custom = v;
    selected = v;
  }

  String get value =>
      selected == _specOther ? other.text.trim() : (selected ?? '');

  void dispose() => other.dispose();
}

class _UnitGroup {
  String? selected;
  final TextEditingController brand = TextEditingController();
  final TextEditingController serial = TextEditingController();

  void setValue(String value) {
    final v = value.trim();
    if (RegExp(r'^branded cpu', caseSensitive: false).hasMatch(v)) {
      selected = 'Branded CPU';
      brand.text =
          v.replaceFirst(RegExp(r'^branded cpu\s*-?\s*', caseSensitive: false), '');
      return;
    }
    selected = v.isEmpty ? null : v;
    brand.clear();
  }

  String get value {
    final v = selected ?? '';
    if (RegExp(r'^branded cpu', caseSensitive: false).hasMatch(v)) {
      final b = brand.text.trim();
      return b.isEmpty ? 'Branded CPU' : 'Branded CPU - $b';
    }
    return v;
  }

  void dispose() {
    brand.dispose();
    serial.dispose();
  }
}

class _RamGroup {
  final _Choice choice = _Choice(_ramOptions);

  void dispose() => choice.dispose();
}

class _StorageRow {
  String? type;
  String? size;
  final TextEditingController sizeOther = TextEditingController();
  final TextEditingController serial = TextEditingController();

  void setType(String value) => type = value.isEmpty ? null : value;

  void setSize(String value) {
    final v = value.trim();
    if (v.isEmpty) {
      size = null;
      sizeOther.clear();
      return;
    }
    if (_storageSizeOptions.contains(v)) {
      size = v;
      sizeOther.clear();
      return;
    }
    size = _otherOption;
    sizeOther.text = v;
  }

  String get typeValue => type ?? '';

  String get sizeValue =>
      size == _otherOption ? sizeOther.text.trim() : (size ?? '');

  void dispose() {
    sizeOther.dispose();
    serial.dispose();
  }
}

class _MonitorGroup {
  final _Choice size = _Choice(_monitorSizeOptions);
  final _Choice brand = _Choice(_monitorBrandOptions);
  final _Choice type = _Choice(_monitorTypeOptions);
  final TextEditingController serial = TextEditingController();

  void dispose() {
    size.dispose();
    brand.dispose();
    type.dispose();
    serial.dispose();
  }
}

class _SpecEntry {
  _SpecEntry({
    required this.optionsKey,
    required this.freeSpec,
    String option = '',
    String size = '',
    String brand = '',
    String serial = '',
    this.target = '',
    this.raw = '',
    this.serverIndex,
  })  : option = _SpecSelect(optionsKey, freeSpec ? '' : option),
        size = _SpecSelect('storage', size),
        freeValue = TextEditingController(text: freeSpec ? option : ''),
        brand = TextEditingController(text: brand),
        serial = TextEditingController(text: serial);

  final String optionsKey;
  final bool freeSpec;
  final _SpecSelect option;
  final _SpecSelect size;
  final TextEditingController freeValue;
  final TextEditingController brand;
  final TextEditingController serial;
  final String target;
  final String raw;
  final int? serverIndex;
  bool sysSerial = false;

  void dispose() {
    option.dispose();
    size.dispose();
    freeValue.dispose();
    brand.dispose();
    serial.dispose();
  }
}

class _SpecRow {
  _SpecRow({
    required this.itemName,
    required String component,
    required this.icon,
    required this.optionsKey,
    required this.freeSpec,
  }) : component = TextEditingController(text: component);

  final String itemName;
  final TextEditingController component;
  final IconData icon;
  final String optionsKey;
  final bool freeSpec;
  final List<_SpecEntry> entries = <_SpecEntry>[];

  String get raw => entries.isEmpty || entries.first.raw.isEmpty
      ? component.text.trim()
      : entries.first.raw;

  void dispose() {
    component.dispose();
    for (final e in entries) {
      e.dispose();
    }
  }
}

class _ReplacementDialog extends StatefulWidget {
  const _ReplacementDialog({required this.componentName});

  final String componentName;

  @override
  State<_ReplacementDialog> createState() => _ReplacementDialogState();
}

class _ReplacementDialogState extends State<_ReplacementDialog> {
  late final TextEditingController _component =
      TextEditingController(text: widget.componentName);
  final TextEditingController _serial = TextEditingController();

  @override
  void dispose() {
    _component.dispose();
    _serial.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context)
      .pop((component: _component.text, serial: _serial.text));

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title:
          'Replacement for ${widget.componentName.isEmpty ? 'component' : widget.componentName}',
      subtitle: 'The current entry is kept as history under this component.',
      icon: Icons.swap_horiz_rounded,
      width: 560,
      actions: <Widget>[
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        SignalButton(
          label: 'Save replacement',
          icon: Icons.check_rounded,
          onPressed: _submit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FormRow(
            label: 'Component',
            labelWidth: 140,
            child: TextField(
              controller: _component,
              decoration: const InputDecoration(hintText: 'New component'),
            ),
          ),
          FormRow(
            label: 'Serial Number',
            labelWidth: 140,
            child: TextField(
              controller: _serial,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration:
                  const InputDecoration(hintText: 'New serial number'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoicePickDialog extends StatefulWidget {
  const _InvoicePickDialog({required this.service});

  final ClientService service;

  @override
  State<_InvoicePickDialog> createState() => _InvoicePickDialogState();
}

class _InvoicePickDialogState extends State<_InvoicePickDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  String _message = '';
  List<Map<String, dynamic>> _results = const <Map<String, dynamic>>[];
  final Map<String, List<Map<String, dynamic>>> _cache =
      <String, List<Map<String, dynamic>>>{};

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final term = value.trim();
    _debounce?.cancel();
    if (term.isEmpty) {
      setState(() {
        _results = const <Map<String, dynamic>>[];
        _message = '';
      });
      return;
    }
    final cached = _cache[term];
    if (cached != null) {
      setState(() {
        _results = cached;
        _message = cached.isEmpty ? 'No matching invoice found.' : '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(term));
  }

  Future<void> _search(String term) async {
    if (term.isEmpty) return;
    setState(() {
      _searching = true;
      _message = '';
    });
    final res = await widget.service.searchInvoice(term);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = res.rows;
      if (res.error.isNotEmpty) {
        _message = res.error;
      } else {
        _cache[term] = res.rows;
        _message = res.rows.isEmpty ? 'No matching invoice found.' : '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return WebModal(
      title: 'Find invoice',
      subtitle: 'Search invoice number to auto-fill',
      icon: Icons.receipt_long_rounded,
      width: 600,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: (v) => _search(v.trim()),
            decoration: const InputDecoration(
              hintText: 'Type an invoice number, e.g. INV-00123…',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
          if (_searching) ...<Widget>[
            const SizedBox(height: 16),
            const Center(child: TpLoader()),
          ],
          if (_message.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(_message, style: text.bodySmall, textAlign: TextAlign.center),
          ],
          if (_results.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: b.rule),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: <Widget>[
                  for (var i = 0; i < _results.length; i++) ...<Widget>[
                    if (i > 0) Divider(height: 1, color: b.rule),
                    _resultTile(_results[i]),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultTile(Map<String, dynamic> item) {
    final no = _invoiceNumberOf(item);
    final branch = _invoiceBranchOf(item);
    final name = _invoiceNameOf(item);
    return ListTile(
      leading: const Icon(Icons.description_rounded),
      title: Row(
        children: [
          Flexible(
            child: Text(no.isEmpty ? '—' : no, overflow: TextOverflow.ellipsis),
          ),
          if (branch.isNotEmpty) ...[
            const SizedBox(width: 8),
            _Pill(label: branch, icon: Icons.account_tree_rounded),
          ],
        ],
      ),
      subtitle: name.isEmpty
          ? null
          : Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).pop(item),
    );
  }
}
