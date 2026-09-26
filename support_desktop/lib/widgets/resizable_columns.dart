import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ColSpec {
  const ColSpec({
    this.width,
    this.flex = 1,
    this.minWidth = 40,
    this.maxWidth = 1600,
    this.resizable = true,
  });

  final double? width;
  final int flex;
  final double minWidth;
  final double maxWidth;
  final bool resizable;

  double get floor => width != null ? math.min(width!, minWidth) : minWidth;

  @override
  bool operator ==(Object other) =>
      other is ColSpec &&
      other.width == width &&
      other.flex == flex &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth &&
      other.resizable == resizable;

  @override
  int get hashCode => Object.hash(width, flex, minWidth, maxWidth, resizable);
}

abstract class ResizableColumnCell {
  ColSpec get colSpec;
  Widget buildColumnContent(BuildContext context);
}

class ColumnWidthController extends ChangeNotifier {
  ColumnWidthController(this.tableId) {
    final cached = _cache[tableId];
    if (cached != null) {
      _w.addAll(cached);
    } else {
      _load();
    }
  }

  final String tableId;
  final Map<String, double> _w = {};
  List<ColSpec> _specs = const [];
  double _extra = 0;
  Timer? _save;
  bool _disposed = false;

  static final Map<String, Map<String, double>> _cache = {};
  static Future<SharedPreferences>? _prefs;

  static Future<SharedPreferences> get _p =>
      _prefs ??= SharedPreferences.getInstance();

  String get _prefKey => 'tpColW::$tableId';

  Future<void> _load() async {
    try {
      final raw = (await _p).getString(_prefKey);
      final map = <String, double>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is num) map['$k'] = v.toDouble();
          });
        }
      }
      _cache[tableId] = map;
      if (_disposed || map.isEmpty) return;
      _w
        ..clear()
        ..addAll(map);
      notifyListeners();
    } catch (_) {}
  }

  void _persist() {
    _cache[tableId] = Map.of(_w);
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 350), () async {
      try {
        final p = await _p;
        if (_w.isEmpty) {
          await p.remove(_prefKey);
        } else {
          await p.setString(_prefKey, jsonEncode(_w));
        }
      } catch (_) {}
    });
  }

  bool get hasCustomWidths => _w.isNotEmpty;

  double? userWidth(Object key) => _w['$key'];

  double? effectiveWidth(Object key, ColSpec spec) => _w['$key'] ?? spec.width;

  bool isCustom(Object key) => _w.containsKey('$key');

  double clampFor(ColSpec spec, double w) =>
      w.clamp(spec.floor, math.max(spec.floor, spec.maxWidth)).toDouble();

  void setWidth(Object key, ColSpec spec, double w) {
    final v = clampFor(spec, w).roundToDouble();
    if (_w['$key'] == v) return;
    _w['$key'] = v;
    notifyListeners();
    _persist();
  }

  void reset(Object key) {
    if (_w.remove('$key') == null) return;
    notifyListeners();
    _persist();
  }

  void resetAll() {
    if (_w.isEmpty) return;
    _w.clear();
    notifyListeners();
    _persist();
  }

  void register(List<ColSpec> specs, {double extra = 0}) {
    if (_extra == extra && _listEq(_specs, specs)) return;
    _specs = List.unmodifiable(specs);
    _extra = extra;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  static bool _listEq(List<ColSpec> a, List<ColSpec> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  double get minContentWidth {
    if (_specs.isEmpty) return 0;
    var total = _extra;
    for (var i = 0; i < _specs.length; i++) {
      final s = _specs[i];
      final w = _w['$i'] ?? s.width;
      total += w ?? math.max(s.minWidth, 120.0);
    }
    return total;
  }

  Widget fit(Object key, ColSpec spec, Widget child) {
    if (spec.width != null) {
      return SizedBox(width: effectiveWidth(key, spec), child: child);
    }
    final w = _w['$key'];
    return Flexible(
      flex: w == null ? spec.flex : 0,
      fit: FlexFit.tight,
      child: SizedBox(width: w, child: child),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    if (_save?.isActive ?? false) {
      _save!.cancel();
      final snapshot = Map.of(_w);
      final key = _prefKey;
      _p.then(
        (p) => snapshot.isEmpty
            ? p.remove(key)
            : p.setString(key, jsonEncode(snapshot)),
      );
    }
    super.dispose();
  }
}

class _ColumnScopeData extends InheritedNotifier<ColumnWidthController> {
  const _ColumnScopeData({
    required ColumnWidthController controller,
    required super.child,
  }) : super(notifier: controller);
}

class ColumnResizeScope extends StatefulWidget {
  const ColumnResizeScope({
    super.key,
    required this.tableId,
    required this.child,
    this.scroll = true,
  });

  final String tableId;
  final Widget child;
  final bool scroll;

  static ColumnWidthController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ColumnScopeData>()?.notifier;

  @override
  State<ColumnResizeScope> createState() => _ColumnResizeScopeState();
}

class _ColumnResizeScopeState extends State<ColumnResizeScope> {
  late ColumnWidthController _c = ColumnWidthController(widget.tableId);
  final _h = ScrollController();

  @override
  void didUpdateWidget(covariant ColumnResizeScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableId != widget.tableId) {
      _c.dispose();
      _c = ColumnWidthController(widget.tableId);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body = widget.child;
    if (widget.scroll) {
      final child = widget.child;
      body = LayoutBuilder(
        builder: (context, box) {
          if (!box.hasBoundedWidth) return child;
          return ListenableBuilder(
            listenable: _c,
            builder: (context, _) {
              final need = _c.minContentWidth;
              final over = need > box.maxWidth + 0.5;
              return Scrollbar(
                controller: _h,
                thumbVisibility: over,
                notificationPredicate: (n) =>
                    n.depth == 0 && n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _h,
                  scrollDirection: Axis.horizontal,
                  physics: over ? null : const NeverScrollableScrollPhysics(),
                  child: _NeedWidthBox(
                    controller: _c,
                    viewport: box.maxWidth,
                    child: child,
                  ),
                ),
              );
            },
          );
        },
      );
    }
    return _ColumnScopeData(controller: _c, child: body);
  }
}

class _NeedWidthBox extends SingleChildRenderObjectWidget {
  const _NeedWidthBox({
    required this.controller,
    required this.viewport,
    super.child,
  });

  final ColumnWidthController controller;
  final double viewport;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNeedWidthBox(controller, viewport);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderNeedWidthBox renderObject,
  ) {
    renderObject
      ..controller = controller
      ..viewport = viewport
      ..markNeedsLayout();
  }
}

class _RenderNeedWidthBox extends RenderProxyBox {
  _RenderNeedWidthBox(this.controller, this.viewport);

  ColumnWidthController controller;
  double viewport;

  @override
  void performLayout() {
    final w = math.max(controller.minContentWidth, viewport);
    final c = BoxConstraints(
      minWidth: w,
      maxWidth: w,
      minHeight: constraints.minHeight,
      maxHeight: constraints.maxHeight,
    );
    if (child == null) {
      size = constraints.constrain(Size(w, constraints.minHeight));
      return;
    }
    child!.layout(c, parentUsesSize: true);
    size = constraints.constrain(child!.size);
  }
}

class _Parsed {
  const _Parsed(this.spec, this.child, {this.column = true});
  final ColSpec spec;
  final Widget? child;
  final bool column;
}

_Parsed _parseCell(BuildContext context, Widget cell, {bool header = false}) {
  if (cell is ResizableColumnCell) {
    final r = cell as ResizableColumnCell;
    return _Parsed(r.colSpec, r.buildColumnContent(context));
  }
  if (cell is Flexible) {
    return _Parsed(
      ColSpec(flex: cell.flex, resizable: !header || !_blank(cell.child)),
      cell.child,
    );
  }
  if (cell is SizedBox && cell.width != null && cell.width! >= 24) {
    return _Parsed(
      ColSpec(
        width: cell.width,
        resizable: !header || (cell.width! > 50 && !_blank(cell.child)),
      ),
      cell.child,
    );
  }
  return _Parsed(const ColSpec(), cell, column: false);
}

bool _blank(Widget? w) {
  if (w == null) return true;
  if (w is Text) return (w.data ?? '').trim().isEmpty;
  return false;
}

double _gapWidth(Widget w) => w is SizedBox ? (w.width ?? 0) : 0;

List<Widget> resizableRowCells(
  BuildContext context,
  List<Widget> cells, {
  bool header = false,
  double extra = 0,
  EdgeInsets headerPadding = EdgeInsets.zero,
}) {
  final c = ColumnResizeScope.maybeOf(context);
  if (c == null) return cells;
  final parsed = [
    for (final w in cells) _parseCell(context, w, header: header),
  ];
  if (header) {
    var gaps = extra;
    final specs = <ColSpec>[];
    for (var i = 0; i < parsed.length; i++) {
      if (parsed[i].column) {
        specs.add(parsed[i].spec);
      } else {
        gaps += _gapWidth(cells[i]);
      }
    }
    c.register(specs, extra: gaps);
  }
  final out = <Widget>[];
  var col = 0;
  for (var i = 0; i < parsed.length; i++) {
    final p = parsed[i];
    if (!p.column) {
      out.add(cells[i]);
      continue;
    }
    final idx = col++;
    final orig = cells[i];
    if (!header && orig is Flexible && orig.fit == FlexFit.loose) {
      out.add(orig);
      continue;
    }
    Widget child = p.child ?? const SizedBox.shrink();
    if (header) {
      child = ColumnHeaderCell(
        index: idx,
        spec: p.spec,
        padding: headerPadding,
        child: child,
      );
    }
    out.add(c.fit(idx, p.spec, child));
  }
  return out;
}

Widget resizableCell(
  BuildContext context,
  Object index,
  ColSpec spec,
  Widget child, {
  bool header = false,
  EdgeInsets headerPadding = EdgeInsets.zero,
}) {
  final c = ColumnResizeScope.maybeOf(context);
  if (c == null) {
    if (spec.width != null) return SizedBox(width: spec.width, child: child);
    return Expanded(flex: spec.flex, child: child);
  }
  if (header) {
    child = ColumnHeaderCell(
      index: index,
      spec: spec,
      padding: headerPadding,
      child: child,
    );
  }
  return c.fit(index, spec, child);
}

double resizableWidth(BuildContext context, Object index, ColSpec spec) {
  final c = ColumnResizeScope.maybeOf(context);
  return c?.effectiveWidth(index, spec) ?? spec.width ?? spec.minWidth;
}

void registerColumns(
  BuildContext context,
  List<ColSpec> specs, {
  double extra = 0,
}) {
  ColumnResizeScope.maybeOf(context)?.register(specs, extra: extra);
}

class ColumnHeaderCell extends StatefulWidget {
  const ColumnHeaderCell({
    super.key,
    required this.index,
    required this.spec,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Object index;
  final ColSpec spec;
  final Widget child;
  final EdgeInsets padding;

  @override
  State<ColumnHeaderCell> createState() => _ColumnHeaderCellState();
}

class _ColumnHeaderCellState extends State<ColumnHeaderCell> {
  bool _hover = false;
  bool _drag = false;
  double _startW = 0;
  double _startX = 0;

  ColumnWidthController? get _c => ColumnResizeScope.maybeOf(context);

  Future<void> _menu(TapUpDetails d) async {
    final c = _c;
    if (c == null) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final pos = RelativeRect.fromRect(
      Rect.fromLTWH(d.globalPosition.dx, d.globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    final v = await showMenu<String>(
      context: context,
      position: pos,
      items: [
        PopupMenuItem(
          value: 'one',
          enabled: c.isCustom(widget.index),
          child: const Text('Reset this column width'),
        ),
        PopupMenuItem(
          value: 'all',
          enabled: c.hasCustomWidths,
          child: const Text('Reset all column widths'),
        ),
      ],
    );
    if (v == 'one') c.reset(widget.index);
    if (v == 'all') c.resetAll();
  }

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: widget.padding, child: widget.child);
    final c = _c;
    if (c == null) return content;
    final active = _hover || _drag;
    final color = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: _menu,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          content,
          if (widget.spec.resizable)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: 9,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  onDoubleTap: () => c.reset(widget.index),
                  onHorizontalDragStart: (d) {
                    _startW = context.size?.width ?? 0;
                    _startX = d.globalPosition.dx;
                    setState(() => _drag = true);
                  },
                  onHorizontalDragUpdate: (d) => c.setWidth(
                    widget.index,
                    widget.spec,
                    _startW + d.globalPosition.dx - _startX,
                  ),
                  onHorizontalDragEnd: (_) => setState(() => _drag = false),
                  onHorizontalDragCancel: () => setState(() => _drag = false),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: active ? 3 : 0,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: _drag ? 0.9 : 0.55),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

TableColumnWidth resizableTableWidth(
  BuildContext context,
  Object index,
  ColSpec spec,
) {
  final c = ColumnResizeScope.maybeOf(context);
  final w = c?.effectiveWidth(index, spec) ?? spec.width;
  if (w != null) return FixedColumnWidth(w);
  return FlexColumnWidth(spec.flex.toDouble());
}
