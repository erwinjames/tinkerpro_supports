import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/activity_models.dart';
import '../services/activity_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'activity_common.dart';

const Color _vendorColor = Color(0xFF1D4ED8);
const Color _taxpayerColor = Color(0xFFC2410C);

Color _actorColor(String actorType) {
  switch (actorType) {
    case 'owner':
      return const Color(0xFFC2410C);
    case 'employee':
      return const Color(0xFF166534);
    case 'vendor':
      return const Color(0xFF1D4ED8);
    default:
      return const Color(0xFF64748B);
  }
}

class ActivityPortalTab extends StatefulWidget {
  const ActivityPortalTab({
    super.key,
    required this.service,
    required this.active,
    required this.refresh,
    required this.onCount,
  });

  final ActivityService service;
  final bool active;
  final ValueListenable<int> refresh;
  final ActivityCountSink onCount;

  @override
  State<ActivityPortalTab> createState() => _ActivityPortalTabState();
}

class _ActivityPortalTabState extends State<ActivityPortalTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<PortalActivityLog> _rows = const <PortalActivityLog>[];
  String _query = '';
  String _source = '';
  String _actor = '';
  bool _loading = true;
  String? _error;

  static const List<String> _sources = ['taxpayer', 'vendor'];
  static const List<String> _actors = [
    'owner',
    'employee',
    'vendor',
    'anonymous',
  ];

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_onRefreshSignal);
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(covariant ActivityPortalTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refresh != oldWidget.refresh) {
      oldWidget.refresh.removeListener(_onRefreshSignal);
      widget.refresh.addListener(_onRefreshSignal);
    }
    if (widget.active && !oldWidget.active) _activate();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_onRefreshSignal);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _activate() {
    _load();
  }

  void _onRefreshSignal() {
    if (!mounted || !widget.active) return;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = _rows.isEmpty);
    try {
      final rows = await widget.service.portalActivity();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
      widget.onCount(rows.length);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = activityErrorText(e);
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = value.trim().toLowerCase());
    });
  }

  String _sourceLabel(String value) {
    if (value.isEmpty) return 'All portals';
    return value == 'vendor' ? 'Vendor' : 'Taxpayer';
  }

  String _actorLabel(String value) {
    switch (value) {
      case 'owner':
        return 'Owner';
      case 'employee':
        return 'Employee';
      case 'vendor':
        return 'Vendor';
      case 'anonymous':
        return 'Not signed in';
      default:
        return 'Anyone';
    }
  }

  List<PortalActivityLog> get _visible => _rows
      .where((r) {
        if (_source.isNotEmpty && r.source != _source) return false;
        if (_actor.isNotEmpty && r.actorType != _actor) return false;
        if (_query.isEmpty) return true;
        return r.haystack.contains(_query);
      })
      .toList(growable: false);

  void _open(PortalActivityLog row) {
    final geo = row.geo;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ActivityDetailSheet(
        service: widget.service,
        eyebrow: '${row.sourceLabel} portal',
        title: row.actionLabel,
        subtitle: '${row.actor} · ${activityLongWhen(row.createdAt)}',
        icon: row.isVendor ? Icons.storefront_rounded : Icons.apartment_rounded,
        color: row.failed
            ? Brand.danger
            : (row.isVendor ? _vendorColor : _taxpayerColor),
        pills: [
          StatusPill(
            label: row.sourceLabel,
            color: row.isVendor ? _vendorColor : _taxpayerColor,
          ),
          StatusPill(
            label: row.actorTypeLabel,
            color: _actorColor(row.actorType),
          ),
        ],
        note: row.details,
        noteLabel: 'Details',
        groups: [
          ActivityDetailGroup('Action', [
            ActivityDetailField('Action', row.actionLabel),
            ActivityDetailField('Code', row.actionCode, mono: true),
            ActivityDetailField('Recorded', activityLongWhen(row.createdAt)),
          ]),
          ActivityDetailGroup('Who', [
            ActivityDetailField('Actor', row.actor),
            ActivityDetailField('Signed in as', row.actorTypeLabel),
            ActivityDetailField('Business', row.business),
            ActivityDetailField('Reference', row.reference, mono: true),
          ]),
          ActivityDetailGroup('Network', [
            ActivityDetailField('IP address', row.ipAddress, mono: true),
            ActivityDetailField('ISP', geo.isp),
            ActivityDetailField('IP location', geo.label),
            if (geo.locationZip.isNotEmpty)
              ActivityDetailField('ZIP', geo.locationZip),
            ActivityDetailField('Device', row.device),
            ActivityDetailField('User agent', row.userAgent),
          ]),
        ],
        lat: geo.lat,
        lon: geo.lon,
        coordSource: geo.source,
        mapCaption: geo.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = _visible;
    final filtered = _source.isNotEmpty || _actor.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Search actor, business, TIN, action, IP',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ActivityFilterMenu(
                icon: Icons.account_balance_outlined,
                label: 'All portals',
                value: _source,
                options: _sources,
                labelOf: _sourceLabel,
                onChanged: (v) => setState(() => _source = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActivityFilterMenu(
                icon: Icons.badge_outlined,
                label: 'Signed in as',
                value: _actor,
                options: _actors,
                labelOf: _actorLabel,
                onChanged: (v) => setState(() => _actor = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionHeader(
          title: 'Vendor & taxpayer activity',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loading ? '—' : '${rows.length} of ${_rows.length}',
                style: text.labelMedium,
              ),
              if (filtered) ...[
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Reset filters',
                  child: InkWell(
                    onTap: () => setState(() {
                      _source = '';
                      _actor = '';
                    }),
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.filter_alt_off_rounded,
                        size: 18,
                        color: context.brand.signal,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ActivityFeedView<PortalActivityLog>(
            loading: _loading,
            error: _error,
            rows: rows,
            onRefresh: _load,
            resetToken: '$_query|$_source|$_actor',
            footerNoun: 'portal actions',
            emptyLabel: _rows.isEmpty ? 'No portal activity' : 'No match',
            emptyHint: _rows.isEmpty
                ? 'No vendor or taxpayer portal activity yet.'
                : 'Try a different search, portal or actor.',
            emptyIcon: Icons.badge_outlined,
            itemBuilder: (context, row, i) => ActivityRise(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PortalCard(row: row, onTap: () => _open(row)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PortalCard extends StatelessWidget {
  const _PortalCard({required this.row, required this.onTap});

  final PortalActivityLog row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final actionColor = row.failed
        ? Brand.danger
        : (row.isSignIn ? Brand.info : b.paper);
    final place = row.geo.label;
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ActivityKindTile(
                icon: row.isVendor
                    ? Icons.storefront_rounded
                    : Icons.apartment_rounded,
                color: row.isVendor ? _vendorColor : _taxpayerColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.actionLabel,
                      style: text.titleSmall?.copyWith(color: actionColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (row.actionCode.isNotEmpty &&
                        row.actionCode != row.action)
                      Text(
                        row.actionCode,
                        style: text.labelSmall?.copyWith(color: b.paperDim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(activityShortWhen(row.createdAt), style: text.labelMedium),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(
                label: row.sourceLabel,
                color: row.isVendor ? _vendorColor : _taxpayerColor,
              ),
              StatusPill(
                label: row.actorTypeLabel,
                color: _actorColor(row.actorType),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 13, color: b.paperDim),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  [
                    row.actor,
                    if (row.business.isNotEmpty) row.business,
                    if (row.reference.isNotEmpty) row.reference,
                  ].join(' · '),
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (row.details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              row.details,
              style: text.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (row.ipAddress.isNotEmpty || place.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  row.geo.hasCoords
                      ? Icons.place_rounded
                      : Icons.public_rounded,
                  size: 13,
                  color: b.paperDim,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    [
                      if (row.ipAddress.isNotEmpty) row.ipAddress,
                      if (place.isNotEmpty) place,
                      if (row.device.isNotEmpty) row.device,
                    ].join(' · '),
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
