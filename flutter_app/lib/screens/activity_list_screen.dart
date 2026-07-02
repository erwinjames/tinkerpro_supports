import 'dart:async';

import 'package:flutter/material.dart';

import '../models/activity_models.dart';
import '../services/activity_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Activity Logs — read-only native list. Searchable feed of user actions
/// backed by the `getActivityLogs` action on api.php. Tapping a row opens a
/// detail dialog with the full details + IP address.
class ActivityListScreen extends StatefulWidget {
  const ActivityListScreen({super.key, required this.service});
  final ActivityService service;

  @override
  State<ActivityListScreen> createState() => _ActivityListScreenState();
}

class _ActivityListScreenState extends State<ActivityListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<ActivityLog> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({String? search}) async {
    setState(() => _loading = true);
    final rows = await widget.service.list(search: search);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _load(search: value);
    });
  }

  void _openDetail(ActivityLog log) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: Text(
          log.action.isEmpty ? 'Activity' : log.action,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StationDataRow(
              label: 'USER',
              value: log.username.isEmpty ? '—' : log.username,
            ),
            StationDataRow(
              label: 'WHEN',
              value: log.createdAt.isEmpty ? '—' : log.createdAt,
            ),
            StationDataRow(
              label: 'IP ADDRESS',
              value: log.ipAddress.isEmpty ? '—' : log.ipAddress,
            ),
            StationDataRow(
              label: 'DETAILS',
              value: log.details.isEmpty ? '—' : log.details,
            ),
          ],
        ),
        actions: [
          GhostButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'ACTIVITY LOGS',
      title: 'Activity.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.refresh,
        tooltip: 'Refresh',
        onPressed: () => _load(search: _searchController.text),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              labelText: 'SEARCH · ACTION · DETAILS · USER',
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Brand.paperDim),
                      onPressed: () {
                        _searchController.clear();
                        _load();
                      },
                    ),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RefreshIndicator(
              color: Brand.signal,
              backgroundColor: Brand.surface,
              onRefresh: () => _load(search: _searchController.text),
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Brand.signal,
                        ),
                      ),
                    )
                  : _rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 64),
                            EmptyState(
                              label: 'No activity',
                              hint:
                                  'Nothing matched your search. Pull down to refresh.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => const Hairline(),
                          itemBuilder: (_, i) {
                            final log = _rows[i];
                            return _ActivityRow(
                              log: log,
                              onTap: () => _openDetail(log),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.log, required this.onTap});
  final ActivityLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.action.isEmpty ? '—' : log.action,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    log.username.isEmpty ? '—' : log.username,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _shortWhen(log.createdAt),
              style: text.labelMedium?.copyWith(
                color: Brand.paperDim,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "x ago" / short timestamp for the row trailing slot. Falls back to
/// the raw string when it cannot be parsed.
String _shortWhen(String raw) {
  if (raw.isEmpty) return '—';
  final dt = DateTime.tryParse(raw);
  if (dt == null) return raw;
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
}
