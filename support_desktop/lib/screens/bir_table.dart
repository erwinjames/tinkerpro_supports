import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/resizable_columns.dart';
import '../widgets/tp_loader.dart';

class BirColumn {
  const BirColumn({
    required this.title,
    required this.width,
    required this.cell,
    this.sortKey,
    this.center = false,
  });

  final String title;
  final double width;
  final Widget Function(Map<String, dynamic> row, int index) cell;
  final String Function(Map<String, dynamic> row)? sortKey;
  final bool center;
}

class BirTable extends StatefulWidget {
  const BirTable({
    super.key,
    required this.columns,
    required this.frozen,
    required this.rows,
    required this.loading,
    required this.placeholder,
    this.onRowTap,
    this.rowHighlight,
    this.tableId = 'bir',
  });

  final String tableId;

  final List<BirColumn> columns;
  final List<BirColumn> frozen;
  final List<Map<String, dynamic>> rows;
  final bool loading;
  final String placeholder;
  final ValueChanged<Map<String, dynamic>>? onRowTap;
  final bool Function(Map<String, dynamic> row)? rowHighlight;

  @override
  State<BirTable> createState() => _BirTableState();
}

class _BirTableState extends State<BirTable> {
  static const _rowH = 43.0;
  static const _headH = 44.0;
  final _h = ScrollController();
  final _v = ScrollController();
  int? _hover;
  BirColumn? _sortCol;
  bool _asc = true;

  @override
  void dispose() {
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _sorted {
    final col = _sortCol;
    if (col == null || col.sortKey == null) return widget.rows;
    final list = [...widget.rows];
    list.sort((a, b) {
      final r = col.sortKey!(a).toLowerCase().compareTo(
        col.sortKey!(b).toLowerCase(),
      );
      return _asc ? r : -r;
    });
    return list;
  }

  ColSpec _spec(BirColumn c) => ColSpec(width: c.width);

  String _key(BirColumn c, bool frozen) => '${frozen ? 'f:' : ''}${c.title}';

  double _w(BuildContext ctx, BirColumn c, bool frozen) =>
      resizableWidth(ctx, _key(c, frozen), _spec(c));

  Widget _headCell(
    BuildContext ctx,
    BirColumn c, {
    bool frozenEdge = false,
    bool frozen = false,
  }) {
    final active = identical(_sortCol, c);
    return InkWell(
      onTap: c.sortKey == null
          ? null
          : () => setState(() {
              if (active) {
                _asc = !_asc;
              } else {
                _sortCol = c;
                _asc = true;
              }
            }),
      child: Container(
        width: _w(ctx, c, frozen),
        height: _headH,
        decoration: BoxDecoration(
          border: Border(
            right: const BorderSide(color: Color(0xFFDEE2E6)),
            left: frozenEdge
                ? const BorderSide(color: Color(0xFFDEE2E6))
                : BorderSide.none,
          ),
        ),
        child: ColumnHeaderCell(
          index: _key(c, frozen),
          spec: _spec(c),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  c.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                    color: Color(0xFF5B6573),
                  ),
                ),
              ),
              if (c.sortKey != null)
                Icon(
                  active && !_asc ? Icons.arrow_drop_down : Icons.arrow_drop_up,
                  size: 20,
                  color: active ? Brand.navy : const Color(0xFFB8BEC6),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(
    BuildContext ctx,
    List<BirColumn> cols,
    Map<String, dynamic> r,
    int i, {
    bool frozenEdge = false,
    bool frozen = false,
  }) {
    final hl = widget.rowHighlight?.call(r) ?? false;
    final bg = _hover == i
        ? const Color(0xFFF3F4F6)
        : (hl ? const Color(0xFFFFF7ED) : Colors.white);
    return MouseRegion(
      cursor: widget.onRowTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = i),
      onExit: (_) {
        if (_hover == i) setState(() => _hover = null);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(r),
        child: Container(
          height: _rowH,
          decoration: BoxDecoration(
            color: bg,
            border: const Border(bottom: BorderSide(color: Color(0xFFDEE2E6))),
          ),
          child: Row(
            children: [
              for (var k = 0; k < cols.length; k++)
                Container(
                  width: _w(ctx, cols[k], frozen),
                  height: _rowH,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  alignment: cols[k].center
                      ? Alignment.center
                      : Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      right: const BorderSide(color: Color(0xFFDEE2E6)),
                      left: frozenEdge && k == 0
                          ? const BorderSide(color: Color(0xFFDEE2E6))
                          : BorderSide.none,
                    ),
                  ),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: Color(0xFF212529),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: cols[k].cell(r, i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColumnResizeScope(
      tableId: widget.tableId,
      scroll: false,
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final rows = _sorted;
    final scrollW = widget.columns.fold<double>(
      0,
      (a, c) => a + _w(context, c, false),
    );
    final frozenW = widget.frozen.fold<double>(
      0,
      (a, c) => a + _w(context, c, true),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final availW = box.maxWidth - frozenW;
        final innerW = scrollW < availW ? availW : scrollW;
        final body = rows.isEmpty
            ? SizedBox(
                height: box.maxHeight - _headH - 14,
                child: Center(
                  child: widget.loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: TpLoader(
                            strokeWidth: 2,
                            color: Brand.signal,
                          ),
                        )
                      : Text(
                          widget.placeholder,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFCCCCCC),
                          ),
                        ),
                ),
              )
            : null;
        return Column(
          children: [
            Expanded(
              child: Scrollbar(
                controller: _h,
                thumbVisibility: true,
                notificationPredicate: (n) => n.depth == 0,
                child: SingleChildScrollView(
                  controller: _h,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: innerW + frozenW,
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                border: Border(
                                  top: BorderSide(color: Color(0xFFDEE2E6)),
                                  bottom: BorderSide(color: Color(0xFFDEE2E6)),
                                ),
                              ),
                              child: Row(
                                children: [
                                  for (final c in widget.columns)
                                    _headCell(context, c),
                                ],
                              ),
                            ),
                            Expanded(
                              child:
                                  body ??
                                  ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(
                                      context,
                                    ).copyWith(scrollbars: false),
                                    child: ListView.builder(
                                      controller: _v,
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      itemCount: rows.length,
                                      itemBuilder: (_, i) => SizedBox(
                                        width: innerW + frozenW,
                                        child: _row(
                                          context,
                                          [...widget.columns],
                                          rows[i],
                                          i,
                                        ),
                                      ),
                                    ),
                                  ),
                            ),
                          ],
                        ),
                        if (widget.frozen.isNotEmpty)
                          AnimatedBuilder(
                            animation: _h,
                            builder: (context, child) {
                              final off = _h.hasClients ? _h.offset : 0.0;
                              return Positioned(
                                left: box.maxWidth - frozenW + off,
                                top: 0,
                                bottom: 0,
                                width: frozenW,
                                child: child!,
                              );
                            },
                            child: Listener(
                              onPointerSignal: (e) {
                                if (e is PointerScrollEvent && _v.hasClients) {
                                  final p = _v.position;
                                  _v.jumpTo(
                                    (p.pixels + e.scrollDelta.dy).clamp(
                                      p.minScrollExtent,
                                      p.maxScrollExtent,
                                    ),
                                  );
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(-2, 0),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        border: Border(
                                          top: BorderSide(
                                            color: Color(0xFFDEE2E6),
                                          ),
                                          bottom: BorderSide(
                                            color: Color(0xFFDEE2E6),
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          for (
                                            var k = 0;
                                            k < widget.frozen.length;
                                            k++
                                          )
                                            _headCell(
                                              context,
                                              widget.frozen[k],
                                              frozenEdge: k == 0,
                                              frozen: true,
                                            ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: rows.isEmpty
                                          ? const SizedBox()
                                          : _FrozenList(
                                              controller: _v,
                                              count: rows.length,
                                              builder: (i) => _row(
                                                context,
                                                widget.frozen,
                                                rows[i],
                                                i,
                                                frozenEdge: true,
                                                frozen: true,
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FrozenList extends StatelessWidget {
  const _FrozenList({
    required this.controller,
    required this.count,
    required this.builder,
  });

  final ScrollController controller;
  final int count;
  final Widget Function(int) builder;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final off = controller.hasClients ? controller.offset : 0.0;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(0, -off),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (var i = 0; i < count; i++) builder(i)],
              ),
            ),
          ),
        );
      },
    );
  }
}
