import 'package:flutter/material.dart';

import '../models/admin_models.dart';
import '../services/live_sync.dart';
import '../theme.dart';
import 'premium.dart';
import 'tp_loader.dart';

class AdminColumn {
  const AdminColumn(
    this.label, {
    this.flex = 1,
    this.width,
    this.alignEnd = false,
    this.center = false,
    this.sortable = true,
    this.sortValue,
  });
  final String label;
  final int flex;
  final double? width;
  final bool alignEnd;
  final bool center;
  final bool sortable;
  final Comparable Function(dynamic item)? sortValue;
}

typedef AdminTableFetch<T> = Future<Paged<T>> Function(String search);
typedef AdminCellsBuilder<T> =
    List<Widget> Function(BuildContext context, T item, VoidCallback refresh);
typedef AdminRowTap<T> =
    void Function(BuildContext context, T item, VoidCallback refresh);
typedef AdminStatsBuilder<T> =
    List<StatItem> Function(List<T> items, int total);
typedef AdminSummaryBuilder<T> =
    Widget Function(
      BuildContext context,
      List<T> items,
      int total,
      Widget search,
    );

class AdminTableController {
  _AdminTablePageState? _state;
  Future<void> reload() async => _state?._load();
  Future<void> silentReload() async => _state?._silentLoad();
  void search(String query) => _state?._applySearch(query);
}

class AdminTableColors {
  static const header = Color(0xFFF8F9FA);
  static const headerText = Color(0xFF6C757D);
  static const border = Color(0xFFDEE2E6);
  static const cellRule = Color(0xFFE9ECEF);
  static const text = Color(0xFF212529);
  static const hover = Color(0xFFF1F7FE);
  static const holder = Color(0xFFF3F4F6);
  static const muted = Color(0xFF8A94A6);
}

class AdminTablePage<T> extends StatefulWidget {
  const AdminTablePage({
    super.key,
    required this.stationNumber,
    required this.stationLabel,
    required this.title,
    required this.fetch,
    required this.columns,
    required this.cells,
    this.onRowTap,
    this.onAdd,
    this.addLabel = 'New',
    this.addIcon = Icons.add,
    this.searchable = true,
    this.searchHint = 'Search…',
    this.stats,
    this.summary,
    this.searchInToolbar = true,
    this.header,
    this.tableTitle,
    this.emptyLabel = 'No records found',
    this.emptyHint = 'No records match the current view.',
    this.localFilter,
    this.rowFilter,
    this.filterKey,
    this.extraActions = const [],
    this.leadingActions = const [],
    this.pageSizes = const [15, 25, 50, 100],
    this.initialPageSize,
    this.rowMinHeight = 43,
    this.controller,
    this.onLoaded,
    this.showRefresh = false,
    this.body,
    this.embedded = false,
    this.liveKeys = const [],
    this.onLiveChange,
    this.livePaused,
    this.tableId,
  });

  final String stationNumber;
  final String stationLabel;
  final String title;
  final AdminTableFetch<T> fetch;
  final List<AdminColumn> columns;
  final AdminCellsBuilder<T> cells;
  final AdminRowTap<T>? onRowTap;
  final Future<void> Function(BuildContext context, VoidCallback refresh)?
  onAdd;
  final String addLabel;
  final IconData addIcon;
  final bool searchable;
  final String searchHint;
  final AdminStatsBuilder<T>? stats;
  final AdminSummaryBuilder<T>? summary;
  final bool searchInToolbar;
  final Widget? header;
  final Widget? tableTitle;
  final String emptyLabel;
  final String emptyHint;
  final bool Function(T item, String query)? localFilter;
  final bool Function(T item)? rowFilter;
  final Object? filterKey;
  final List<Widget> extraActions;
  final List<Widget> leadingActions;
  final List<int> pageSizes;
  final int? initialPageSize;
  final double rowMinHeight;
  final AdminTableController? controller;
  final void Function(List<T> items, int total)? onLoaded;
  final bool showRefresh;
  final Widget Function(
    BuildContext context,
    List<T> visible,
    VoidCallback refresh,
  )?
  body;
  final bool embedded;
  final List<String> liveKeys;
  final VoidCallback? onLiveChange;
  final bool Function()? livePaused;
  final String? tableId;

  @override
  State<AdminTablePage<T>> createState() => _AdminTablePageState<T>();
}

class _AdminTablePageState<T> extends State<AdminTablePage<T>>
    with LiveRefresh<AdminTablePage<T>> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _loading = true;
  String? _error;
  List<T> _items = const [];
  int _total = 0;
  late int _pageSize;
  int _page = 0;
  int? _sortCol;
  bool _sortAsc = true;
  int _seq = 0;

  @override
  List<String> get liveKeys => widget.liveKeys;

  @override
  void onLiveChange() {
    if (widget.livePaused?.call() ?? false) return;
    _silentLoad();
    widget.onLiveChange?.call();
  }

  @override
  void initState() {
    super.initState();
    _pageSize = widget.initialPageSize ?? widget.pageSizes.first;
    widget.controller?._state = this;
    _load();
  }

  @override
  void didUpdateWidget(covariant AdminTablePage<T> old) {
    super.didUpdateWidget(old);
    widget.controller?._state = this;
    if (old.filterKey != widget.filterKey) {
      _page = 0;
    }
  }

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await widget.fetch(
        widget.localFilter != null ? '' : _search,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
        _clampPage();
      });
      widget.onLoaded?.call(page.items, page.total);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _silentLoad() async {
    if (_loading) return;
    final seq = ++_seq;
    try {
      final page = await widget.fetch(
        widget.localFilter != null ? '' : _search,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _error = null;
        _clampPage();
      });
      widget.onLoaded?.call(page.items, page.total);
    } catch (_) {}
  }

  List<T> get _visible {
    final f = widget.localFilter;
    final rf = widget.rowFilter;
    final q = _search.trim().toLowerCase();
    var list = _items;
    if (rf != null) list = list.where(rf).toList();
    if (f != null && q.isNotEmpty) list = list.where((e) => f(e, q)).toList();
    final sc = _sortCol;
    if (sc != null && sc < widget.columns.length) {
      final sv = widget.columns[sc].sortValue;
      if (sv != null) {
        list = [...list];
        list.sort((a, b) {
          final r = sv(a).compareTo(sv(b));
          return _sortAsc ? r : -r;
        });
      }
    }
    return list;
  }

  int _pageCountFor(int n) => n == 0 ? 1 : ((n + _pageSize - 1) ~/ _pageSize);

  void _clampPage() {
    final pages = _pageCountFor(_visible.length);
    if (_page >= pages) _page = pages - 1;
    if (_page < 0) _page = 0;
  }

  void _applySearch(String v) {
    _search = v.trim();
    _page = 0;
    if (widget.localFilter != null) {
      setState(_clampPage);
    } else {
      _load();
    }
  }

  Widget _searchField({double? width}) => SearchField(
    controller: _searchCtrl,
    hint: widget.searchHint,
    width: width,
    onChanged: widget.localFilter != null ? _applySearch : null,
    onSubmitted: _applySearch,
  );

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final summary = widget.summary;
    final toolbarSearch = widget.searchable && widget.searchInToolbar;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null) ...[
          widget.header!,
          const SizedBox(height: 10),
        ],
        if (summary != null) ...[
          summary(context, _items, _total, _searchField()),
          const SizedBox(height: 10),
        ] else if (stats != null) ...[
          AdminStatBar(
            items: _loading || _error != null
                ? const []
                : stats(_items, _total),
            search: widget.searchable && !widget.searchInToolbar
                ? _searchField(width: 320)
                : null,
          ),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: context.brand.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.brand.rule),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.tableTitle != null) widget.tableTitle!,
                Expanded(child: _body()),
              ],
            ),
          ),
        ),
      ],
    );
    final content = LayoutBuilder(
      builder: (context, box) {
        if (!box.hasBoundedHeight || box.maxHeight >= 600) return column;
        return SingleChildScrollView(
          child: SizedBox(height: 600, child: column),
        );
      },
    );
    if (widget.embedded) return content;
    return StationScaffold(
      stationNumber: widget.stationNumber,
      stationLabel: widget.stationLabel,
      title: widget.title,
      showBottomBrand: false,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      leading: widget.leadingActions.isEmpty
          ? null
          : Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: widget.leadingActions,
            ),
      trailing: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (toolbarSearch) _searchField(width: 320),
          if (widget.showRefresh)
            StationAction(
              icon: Icons.refresh,
              tooltip: 'Refresh',
              onPressed: _load,
            ),
          if (widget.onAdd != null)
            SignalButton(
              label: widget.addLabel,
              icon: widget.addIcon,
              onPressed: () => widget.onAdd!(context, _load),
            ),
          ...widget.extraActions,
        ],
      ),
      child: content,
    );
  }

  ColSpec _spec(AdminColumn c) =>
      ColSpec(width: c.width, flex: c.flex, resizable: c.label.isNotEmpty);

  Widget _cell(
    BuildContext ctx,
    int index,
    AdminColumn c,
    Widget child, {
    required bool last,
  }) {
    Widget aligned = child;
    if (c.alignEnd) {
      aligned = Align(alignment: Alignment.centerRight, child: child);
    } else if (c.center) {
      aligned = Align(alignment: Alignment.center, child: child);
    }
    final boxed = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(
                right: BorderSide(color: AdminTableColors.cellRule),
              ),
            ),
      alignment: Alignment.centerLeft,
      child: aligned,
    );
    return resizableCell(ctx, index, _spec(c), boxed);
  }

  Widget _headerCell(BuildContext ctx, int i) {
    final c = widget.columns[i];
    final last = i == widget.columns.length - 1;
    final sortable = c.sortable && c.label.isNotEmpty;
    final active = _sortCol == i;
    final label = Row(
      children: [
        Expanded(
          child: Text(
            c.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: c.alignEnd
                ? TextAlign.right
                : (c.center ? TextAlign.center : TextAlign.left),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: AdminTableColors.headerText,
            ),
          ),
        ),
        if (sortable) ...[
          const SizedBox(width: 6),
          Icon(
            active && !_sortAsc ? Icons.arrow_drop_down : Icons.arrow_drop_up,
            size: 20,
            color: active ? AdminTableColors.text : const Color(0xFFBBBBBB),
          ),
        ],
      ],
    );
    final box = InkWell(
      mouseCursor: sortable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onTap: !sortable || c.sortValue == null
          ? null
          : () => setState(() {
              if (_sortCol == i) {
                _sortAsc = !_sortAsc;
              } else {
                _sortCol = i;
                _sortAsc = true;
              }
            }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        decoration: last
            ? null
            : const BoxDecoration(
                border: Border(
                  right: BorderSide(color: AdminTableColors.border),
                ),
              ),
        child: label,
      ),
    );
    return resizableCell(ctx, i, _spec(c), box, header: true);
  }

  Widget _body() {
    final text = Theme.of(context).textTheme;
    if (_loading) {
      return const Center(child: TpLoader());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconTile(
              icon: Icons.error_outline,
              size: 48,
              color: Brand.danger,
            ),
            const SizedBox(height: 12),
            Text('Could not load', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(_error!, textAlign: TextAlign.center, style: text.bodySmall),
            const SizedBox(height: 16),
            SignalButton(label: 'Retry', icon: Icons.refresh, onPressed: _load),
          ],
        ),
      );
    }
    final visible = _visible;
    final pages = _pageCountFor(visible.length);
    final page = _page.clamp(0, pages - 1);
    final start = page * _pageSize;
    final end = (start + _pageSize).clamp(0, visible.length);
    final slice = visible.sublist(start.clamp(0, visible.length), end);
    if (widget.body != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.body!(context, slice, _load)),
          _pager(visible.length, page, pages),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            decoration: const BoxDecoration(
              color: AdminTableColors.holder,
              border: Border(
                top: BorderSide(color: AdminTableColors.border),
                left: BorderSide(color: AdminTableColors.border),
                right: BorderSide(color: AdminTableColors.border),
              ),
            ),
            child: ColumnResizeScope(
              tableId: widget.tableId ?? 'admin:${widget.title}',
              child: Builder(
                builder: (hctx) {
                  registerColumns(hctx, [
                    for (final c in widget.columns) _spec(c),
                  ]);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 64,
                        decoration: const BoxDecoration(
                          color: AdminTableColors.header,
                          border: Border(
                            bottom: BorderSide(color: AdminTableColors.border),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < widget.columns.length; i++)
                              _headerCell(hctx, i),
                          ],
                        ),
                      ),
                      Expanded(
                        child: slice.isEmpty
                            ? EmptyState(
                                label: widget.emptyLabel,
                                hint: widget.emptyHint,
                              )
                            : ListView.builder(
                                itemCount: slice.length,
                                itemBuilder: (ctx, i) {
                                  final item = slice[i];
                                  final cells = widget.cells(ctx, item, _load);
                                  return _AdminRow(
                                    minHeight: widget.rowMinHeight,
                                    onTap: widget.onRowTap == null
                                        ? null
                                        : () => widget.onRowTap!(
                                            ctx,
                                            item,
                                            _load,
                                          ),
                                    children: [
                                      for (
                                        var j = 0;
                                        j < widget.columns.length;
                                        j++
                                      )
                                        _cell(
                                          ctx,
                                          j,
                                          widget.columns[j],
                                          j < cells.length
                                              ? DefaultTextStyle.merge(
                                                  style: const TextStyle(
                                                    fontSize: 15.5,
                                                    color:
                                                        AdminTableColors.text,
                                                  ),
                                                  child: cells[j],
                                                )
                                              : const SizedBox(),
                                          last: j == widget.columns.length - 1,
                                        ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        _pager(visible.length, page, pages),
      ],
    );
  }

  Widget _pager(int count, int page, int pages) {
    final window = <int>[];
    final lo = (page - 2).clamp(0, pages - 1);
    final hi = (lo + 4).clamp(0, pages - 1);
    for (var i = lo; i <= hi; i++) {
      window.add(i);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      decoration: const BoxDecoration(
        color: AdminTableColors.header,
        border: Border(top: BorderSide(color: AdminTableColors.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Page Size',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: AdminTableColors.text,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: context.brand.surface,
                  border: Border.all(color: AdminTableColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _pageSize,
                    isDense: true,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AdminTableColors.text,
                    ),
                    items: [
                      for (final s in widget.pageSizes)
                        DropdownMenuItem(value: s, child: Text('$s')),
                    ],
                    onChanged: (v) => setState(() {
                      _pageSize = v ?? _pageSize;
                      _page = 0;
                    }),
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            runSpacing: 6,
            children: [
              _PagerButton(
                label: 'First',
                onTap: page > 0 ? () => setState(() => _page = 0) : null,
              ),
              _PagerButton(
                label: 'Prev',
                onTap: page > 0 ? () => setState(() => _page = page - 1) : null,
              ),
              for (final i in window)
                _PagerButton(
                  label: '${i + 1}',
                  active: i == page,
                  onTap: () => setState(() => _page = i),
                ),
              _PagerButton(
                label: 'Next',
                onTap: page < pages - 1
                    ? () => setState(() => _page = page + 1)
                    : null,
              ),
              _PagerButton(
                label: 'Last',
                onTap: page < pages - 1
                    ? () => setState(() => _page = pages - 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminRow extends StatefulWidget {
  const _AdminRow({
    required this.children,
    required this.minHeight,
    this.onTap,
  });
  final List<Widget> children;
  final double minHeight;
  final VoidCallback? onTap;

  @override
  State<_AdminRow> createState() => _AdminRowState();
}

class _AdminRowState extends State<_AdminRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: BoxConstraints(minHeight: widget.minHeight),
          decoration: BoxDecoration(
            color: _hover ? AdminTableColors.hover : Colors.white,
            border: const Border(
              bottom: BorderSide(color: AdminTableColors.border),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
        ),
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  const _PagerButton({required this.label, this.onTap, this.active = false});
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Material(
        color: active ? Brand.signal : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: active ? Brand.signal : AdminTableColors.border,
          ),
        ),
        child: InkWell(
          onTap: active ? null : onTap,
          mouseCursor: enabled && !active
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            constraints: const BoxConstraints(minWidth: 34),
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: active
                      ? Colors.white
                      : (enabled
                            ? AdminTableColors.text
                            : AdminTableColors.muted),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminStatBar extends StatelessWidget {
  const AdminStatBar({
    super.key,
    required this.items,
    this.search,
    this.trailing,
  });
  final List<StatItem> items;
  final Widget? search;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      constraints: const BoxConstraints(minHeight: 62),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.brand.rule),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        children: [
          Wrap(
            spacing: 44,
            runSpacing: 10,
            children: [
              for (final s in items) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (s.icon != null) ...[
                          Icon(
                            s.icon,
                            size: 13,
                            color: s.color ?? Brand.signal,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          s.label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                            color: Brand.signal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.value,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AdminTableColors.text,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (trailing != null || search != null)
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [?trailing, ?search],
            ),
        ],
      ),
    );
  }
}

class AdminTicker extends StatelessWidget {
  const AdminTicker({super.key, required this.items, this.trailing = const []});
  final List<AdminTickerItem> items;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.brand.rule),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 8,
        children: [
          Wrap(
            spacing: 30,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final s in items)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(s.icon, size: 15, color: s.color),
                    const SizedBox(width: 8),
                    Text(
                      '${s.label.toUpperCase()}:',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: Color(0xFF6C757D),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      s.value,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AdminTableColors.text,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (trailing.isNotEmpty)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: trailing,
            ),
        ],
      ),
    );
  }
}

class AdminTickerItem {
  const AdminTickerItem(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class AdminChip extends StatelessWidget {
  const AdminChip({
    super.key,
    required this.label,
    this.count,
    this.active = false,
    this.onTap,
    this.icon,
  });
  final String label;
  final String? count;
  final bool active;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : const Color(0xFF495057);
    return Material(
      color: active ? Brand.navy : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: active ? Brand.navy : AdminTableColors.border),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: fg,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: 0.18)
                        : const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AdminBadge extends StatelessWidget {
  const AdminBadge(
    this.label, {
    super.key,
    required this.color,
    this.icon,
    this.solid = false,
  });
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: solid ? Colors.white : color),
            const SizedBox(width: 6),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: solid ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

class AdminMenuAction {
  const AdminMenuAction(
    this.label,
    this.icon,
    this.onTap, {
    this.danger = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
}

class AdminRowMenu extends StatelessWidget {
  const AdminRowMenu({super.key, required this.actions});
  final List<AdminMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PopupMenuButton<int>(
        tooltip: 'Actions',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        onSelected: (i) => actions[i].onTap(),
        itemBuilder: (_) => [
          for (var i = 0; i < actions.length; i++)
            PopupMenuItem<int>(
              value: i,
              height: 38,
              child: Row(
                children: [
                  Icon(
                    actions[i].icon,
                    size: 16,
                    color: actions[i].danger
                        ? Brand.danger
                        : AdminTableColors.headerText,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    actions[i].label,
                    style: TextStyle(
                      fontSize: 14,
                      color: actions[i].danger
                          ? Brand.danger
                          : AdminTableColors.text,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AdminTableColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: AdminTableColors.text,
          ),
        ),
      ),
    );
  }
}

class AdminTabBar extends StatelessWidget {
  const AdminTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
  });
  final List<AdminTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AdminTableColors.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              InkWell(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == index ? Brand.signal : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tabs[i].icon != null) ...[
                        Icon(
                          tabs[i].icon,
                          size: 16,
                          color: i == index
                              ? Brand.signal
                              : AdminTableColors.headerText,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        tabs[i].label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: i == index
                              ? Brand.signal
                              : AdminTableColors.headerText,
                        ),
                      ),
                      if (tabs[i].count != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: i == index
                                ? Brand.signal.withValues(alpha: 0.15)
                                : const Color(0xFFEEF0F3),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tabs[i].count!,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: i == index
                                  ? Brand.signal
                                  : AdminTableColors.text,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminTab {
  const AdminTab(this.label, {this.icon, this.count});
  final String label;
  final IconData? icon;
  final String? count;
}

class AdminRowAction extends StatelessWidget {
  const AdminRowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: OutlinedIconButton(
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
        color: color,
        size: 30,
      ),
    );
  }
}

class AdminRowActions extends StatelessWidget {
  const AdminRowActions({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: children,
    );
  }
}

class AdminCellText extends StatelessWidget {
  const AdminCellText(
    this.text, {
    super.key,
    this.bold = false,
    this.muted = false,
    this.mono = false,
    this.maxLines = 1,
    this.size,
  });
  final String text;
  final bool bold;
  final bool muted;
  final bool mono;
  final int maxLines;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.isEmpty ? '—' : text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: size ?? 15.5,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: muted || text.isEmpty
            ? AdminTableColors.muted
            : AdminTableColors.text,
        fontFamily: mono ? 'monospace' : null,
      ),
    );
  }
}

class AdminDateTimeCell extends StatelessWidget {
  const AdminDateTimeCell(
    this.raw, {
    super.key,
    this.prefix,
    this.showTime = true,
  });
  final String raw;
  final String? prefix;
  final bool showTime;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse(raw.trim());
    if (d == null) return AdminCellText(raw, muted: true);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (prefix != null) ...[
          Text(
            prefix!.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 0.6,
              color: AdminTableColors.muted,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            adminFormatDate(raw),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AdminTableColors.text,
            ),
          ),
        ),
        if (showTime) ...[
          const Text(
            '  ·  ',
            style: TextStyle(fontSize: 12, color: AdminTableColors.muted),
          ),
          Text(
            adminFormatTime(d),
            style: const TextStyle(
              fontSize: 12.5,
              color: AdminTableColors.muted,
            ),
          ),
        ],
      ],
    );
  }
}

String adminFormatTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${h.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String adminFormatDate(String raw, {bool withTime = false}) {
  final d = DateTime.tryParse(raw.trim());
  if (d == null) return raw;
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
  final date = '${months[d.month - 1]} ${d.day}, ${d.year}';
  if (!withTime) return date;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$date $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

String adminWeekday(String raw) {
  final d = DateTime.tryParse(raw.trim());
  if (d == null) return '';
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return days[d.weekday - 1];
}

String adminIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class AdminDateField extends StatelessWidget {
  const AdminDateField({
    super.key,
    required this.controller,
    this.hint = 'YYYY-MM-DD',
    this.lastYearOffset = 5,
  });

  final TextEditingController controller;
  final String hint;
  final int lastYearOffset;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      mouseCursor: SystemMouseCursors.click,
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: const Icon(Icons.calendar_today, size: 16),
      ),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(controller.text) ?? now,
          firstDate: DateTime(2015),
          lastDate: DateTime(now.year + lastYearOffset),
        );
        if (picked != null) controller.text = adminIsoDate(picked);
      },
    );
  }
}

class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle(this.label, {super.key, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Brand.signal),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Brand.signal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: context.brand.rule)),
        ],
      ),
    );
  }
}

void adminUndoDelete(
  BuildContext context, {
  required String message,
  required Future<void> Function() commit,
  VoidCallback? onUndo,
  Duration delay = const Duration(seconds: 5),
}) {
  var undone = false;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger
      .showSnackBar(
        SnackBar(
          content: Text(message),
          duration: delay,
          persist: false,
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () {
              undone = true;
              onUndo?.call();
            },
          ),
        ),
      )
      .closed
      .then((_) {
        if (!undone) commit();
      });
}
