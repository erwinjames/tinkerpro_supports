import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../services/live_sync.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../../widgets/tp_loader.dart';

typedef AdminFetch<T> = Future<Paged<T>> Function(String search);
typedef AdminItemBuilder<T> =
    Widget Function(BuildContext context, T item, VoidCallback refresh);
typedef AdminAdd =
    Future<void> Function(BuildContext context, VoidCallback refresh);

class AdminListPage<T> extends StatefulWidget {
  const AdminListPage({
    super.key,
    required this.stationNumber,
    required this.stationLabel,
    required this.title,
    required this.fetch,
    required this.itemBuilder,
    this.onAdd,
    this.addLabel = 'New',
    this.searchable = true,
    this.searchHint = 'Search…',
    this.liveKeys = const [],
  });

  final String stationNumber;
  final String stationLabel;
  final String title;
  final AdminFetch<T> fetch;
  final AdminItemBuilder<T> itemBuilder;
  final AdminAdd? onAdd;
  final String addLabel;
  final bool searchable;
  final String searchHint;
  final List<String> liveKeys;

  @override
  State<AdminListPage<T>> createState() => _AdminListPageState<T>();
}

class _AdminListPageState<T> extends State<AdminListPage<T>>
    with LiveRefresh<AdminListPage<T>> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _loading = true;
  String? _error;
  List<T> _items = const [];
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  List<String> get liveKeys => widget.liveKeys;

  @override
  void onLiveChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (silent && _loading) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await widget.fetch(_search);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: widget.stationNumber,
      stationLabel: widget.stationLabel,
      title: widget.title,
      showBottomBrand: false,
      leading: !_loading && _error == null
          ? Text(
              '$_total record${_total == 1 ? '' : 's'}',
              style: text.bodyMedium?.copyWith(
                color: context.brand.paperDim,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.searchable) ...[
            SearchField(
              controller: _searchCtrl,
              hint: widget.searchHint,
              width: 300,
              onSubmitted: (v) {
                _search = v.trim();
                _load();
              },
            ),
            const SizedBox(width: 10),
          ],
          StationAction(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          if (widget.onAdd != null) ...[
            const SizedBox(width: 10),
            SignalButton(
              label: widget.addLabel,
              icon: Icons.add,
              onPressed: () => widget.onAdd!(context, _load),
            ),
          ],
        ],
      ),
      child: WebCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: _body(),
      ),
    );
  }

  Widget _body() {
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
            Text(
              'Could not load',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SignalButton(label: 'Retry', icon: Icons.refresh, onPressed: _load),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const EmptyState(
        label: 'Nothing here yet',
        hint: 'No records match the current view.',
      );
    }
    return RefreshIndicator(
      color: Brand.signal,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: context.brand.rule),
        itemBuilder: (context, i) =>
            widget.itemBuilder(context, _items[i], _load),
      ),
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final destructive = RegExp(
    r'delete|remove|revoke|disable|clear|reset',
    caseSensitive: false,
  ).hasMatch(confirmLabel);
  final ok = await showWebModal<bool>(
    context,
    title: title,
    icon: destructive ? Icons.warning_amber_rounded : Icons.help_outline,
    width: 460,
    builder: (_) =>
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      destructive
          ? DangerButton(
              label: confirmLabel,
              onPressed: () => Navigator.pop(ctx, true),
            )
          : SignalButton(
              label: confirmLabel,
              onPressed: () => Navigator.pop(ctx, true),
            ),
    ],
  );
  return ok ?? false;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
