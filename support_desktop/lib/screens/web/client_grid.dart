part of 'client_screen.dart';

const Color _gHeadBg = Color(0xFFF7F7F5);
const Color _gHeadLine = Color(0xFFE8E8E4);
const Color _gRowLine = Color(0xFFF0F0F0);
const Color _gTitle = Color(0xFF888888);

class _GCol {
  const _GCol({this.width, this.flex = 1, this.align = Alignment.centerLeft});

  final double? width;
  final int flex;
  final Alignment align;
}

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _gLine(BuildContext context) =>
    _isDark(context) ? context.brand.rule : _gHeadLine;

ColSpec _gSpec(_GCol c, {bool resizable = true}) =>
    ColSpec(width: c.width, flex: c.flex, resizable: resizable);

Widget _gCell(BuildContext context, int index, _GCol c, Widget child,
    {bool last = false, EdgeInsets? pad, bool header = false}) {
  final inner = Container(
    alignment: c.align,
    padding: pad ?? const EdgeInsets.symmetric(horizontal: 16),
    decoration: last
        ? null
        : BoxDecoration(
            border: Border(right: BorderSide(color: _gLine(context))),
          ),
    child: child,
  );
  return resizableCell(context, index, _gSpec(c), inner, header: header);
}

class _GridHeader extends StatelessWidget {
  const _GridHeader({required this.cols, required this.labels});

  final List<_GCol> cols;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    registerColumns(context, [for (final c in cols) _gSpec(c)]);
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: _isDark(context) ? context.brand.surfaceHi : _gHeadBg,
        border: Border(bottom: BorderSide(color: _gLine(context), width: 1.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cols.length; i++)
            _gCell(
              context,
              i,
              cols[i],
              Text(
                labels[i].toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: _isDark(context) ? context.brand.paperDim : _gTitle,
                ),
              ),
              last: i == cols.length - 1,
              header: true,
            ),
        ],
      ),
    );
  }
}

class _GridRow extends StatefulWidget {
  const _GridRow({
    required this.cols,
    required this.cells,
    this.onTap,
    this.height = 43,
  });

  final List<_GCol> cols;
  final List<Widget> cells;
  final VoidCallback? onTap;
  final double height;

  @override
  State<_GridRow> createState() => _GridRowState();
}

class _GridRowState extends State<_GridRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: widget.height),
          decoration: BoxDecoration(
            color: _isDark(context)
                ? (_hover ? context.brand.surfaceHi : context.brand.surface)
                : (_hover ? const Color(0xFFFCFCFB) : Colors.white),
            border: Border(
                bottom: BorderSide(
                    color: _isDark(context) ? context.brand.rule : _gRowLine)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.cols.length; i++)
                  _gCell(
                    context,
                    i,
                    widget.cols[i],
                    widget.cells[i],
                    last: i == widget.cols.length - 1,
                    pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
