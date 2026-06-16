// Reusable scaffold for the admin/console list pages (POS Version, Release
// Notes, License Key, Users, Email, Help, Credentials, Blog, BIR, Files,
// Activity Logs). Handles the station header, optional search box, the
// load / error / empty / list states, pull-to-refresh, and an optional
// "add" action — so each concrete page only supplies its fetch + row UI.

import 'package:flutter/material.dart';

import '../../models/admin_models.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';

typedef AdminFetch<T> = Future<Paged<T>> Function(String search);
typedef AdminItemBuilder<T> = Widget Function(
    BuildContext context, T item, VoidCallback refresh);
typedef AdminAdd = Future<void> Function(
    BuildContext context, VoidCallback refresh);

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

  @override
  State<AdminListPage<T>> createState() => _AdminListPageState<T>();
}

class _AdminListPageState<T> extends State<AdminListPage<T>> {
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.fetch(_search);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onAdd != null)
            SignalButton(
              label: widget.addLabel,
              icon: Icons.add,
              onPressed: () => widget.onAdd!(context, _load),
            ),
          const SizedBox(width: 8),
          StationAction(
              icon: Icons.refresh, tooltip: 'Refresh', onPressed: _load),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.searchable) ...[
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
              ),
              onSubmitted: (v) {
                _search = v.trim();
                _load();
              },
            ),
            const SizedBox(height: 16),
          ],
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('$_total RECORD${_total == 1 ? '' : 'S'}',
                  style: text.labelMedium),
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: Brand.signal),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('COULD NOT LOAD',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            SizedBox(
              width: 160,
              child: SignalButton(
                  label: 'Retry', icon: Icons.refresh, onPressed: _load),
            ),
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
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, i) =>
            widget.itemBuilder(context, _items[i], _load),
      ),
    );
  }
}

// ── Small shared helpers for the concrete pages ──────────────────────────

/// A confirm dialog returning true when the user accepts. Used by the
/// per-row delete actions.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        // Autofocused so a global Enter confirms; Esc cancels via the
        // app-wide back shortcut.
        FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel)),
      ],
    ),
  );
  return ok ?? false;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}
