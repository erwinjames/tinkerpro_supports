import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/activity_models.dart';
import '../services/activity_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'activity_common.dart';

const Color _permanentColor = Color(0xFF10B981);
const Color _expiringColor = Color(0xFFF59E0B);

IconData _deviceIcon(String device) {
  final d = device.toLowerCase();
  if (d.contains('iphone') ||
      d.contains('android phone') ||
      d.contains('mobile')) {
    return Icons.smartphone_rounded;
  }
  if (d.contains('ipad') || d.contains('tablet')) {
    return Icons.tablet_rounded;
  }
  if (d.contains('curl') || d.contains('wget')) {
    return Icons.terminal_rounded;
  }
  return Icons.desktop_windows_rounded;
}

class ActivityDownloadsTab extends StatefulWidget {
  const ActivityDownloadsTab({
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
  State<ActivityDownloadsTab> createState() => _ActivityDownloadsTabState();
}

enum _Token { all, permanent, expiring }

class _ActivityDownloadsTabState extends State<ActivityDownloadsTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<PublicDownloadLog> _rows = const <PublicDownloadLog>[];
  String _query = '';
  _Token _token = _Token.all;
  bool _loading = true;
  bool _started = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_onRefreshSignal);
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(covariant ActivityDownloadsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refresh != oldWidget.refresh) {
      oldWidget.refresh.removeListener(_onRefreshSignal);
      widget.refresh.addListener(_onRefreshSignal);
    }
    if (widget.active && !_started) _activate();
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_onRefreshSignal);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _activate() {
    _started = true;
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
      final rows = await widget.service.publicDownloads();
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

  String _tokenLabel(_Token t) {
    switch (t) {
      case _Token.all:
        return 'All';
      case _Token.permanent:
        return 'Permanent';
      case _Token.expiring:
        return 'Expiring';
    }
  }

  List<PublicDownloadLog> get _visible => _rows
      .where((r) {
        if (_token == _Token.permanent && !r.permanent) return false;
        if (_token == _Token.expiring && r.permanent) return false;
        if (_query.isEmpty) return true;
        return r.haystack.contains(_query);
      })
      .toList(growable: false);

  void _open(PublicDownloadLog row) {
    final geo = row.geo;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ActivityDetailSheet(
        service: widget.service,
        eyebrow: widget.service.isSuperAdmin
            ? 'Share link trace'
            : 'Share link opened',
        title: '${row.collectionName} — share link opened',
        subtitle: activityLongWhen(row.accessedAt),
        icon: Icons.cloud_download_rounded,
        color: row.permanent ? _permanentColor : _expiringColor,
        pills: [
          StatusPill(
            label: row.tokenType.isEmpty ? 'token' : row.tokenType,
            color: row.permanent ? _permanentColor : _expiringColor,
          ),
        ],
        note: row.userAgent,
        noteLabel: 'User agent',
        groups: [
          ActivityDetailGroup('Access', [
            ActivityDetailField('Access ID', '#${row.id}'),
            ActivityDetailField('Collection', row.collectionName),
            ActivityDetailField('Collection ID', row.collectionId, mono: true),
            ActivityDetailField('Token type', row.tokenType),
            ActivityDetailField('Accessed', activityLongWhen(row.accessedAt)),
          ]),
          ActivityDetailGroup('Device', [
            ActivityDetailField('Device', row.device),
          ]),
          ActivityDetailGroup('Network', [
            ActivityDetailField('IP address', row.ipAddress, mono: true),
            ActivityDetailField('ISP', geo.isp),
            ActivityDetailField('IP location', geo.label),
            if (geo.locationZip.isNotEmpty)
              ActivityDetailField('ZIP', geo.locationZip),
          ]),
        ],
        traceQuery: {'subject': 'download', 'access_id': '${row.id}'},
        heartbeatQuery: {
          'live': '1',
          'live_kind': 'download',
          'collection_id': row.collectionId,
        },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Search collection, IP, agent',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        ChoicePills<_Token>(
          options: _Token.values,
          value: _token,
          labelOf: _tokenLabel,
          onChanged: (v) => setState(() => _token = v),
        ),
        const SizedBox(height: 12),
        SectionHeader(
          title: 'Public download access',
          trailing: Text(
            _loading ? '—' : '${rows.length} of ${_rows.length}',
            style: text.labelMedium,
          ),
        ),
        Expanded(
          child: ActivityFeedView<PublicDownloadLog>(
            loading: _loading,
            error: _error,
            rows: rows,
            onRefresh: _load,
            resetToken: '$_query|$_token',
            footerNoun: 'download access records',
            emptyLabel: _rows.isEmpty ? 'No downloads' : 'No match',
            emptyHint: _rows.isEmpty
                ? 'No public download activity yet.'
                : 'Try a different collection, IP or agent.',
            emptyIcon: Icons.cloud_download_rounded,
            itemBuilder: (context, row, i) => ActivityRise(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DownloadCard(row: row, onTap: () => _open(row)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.row, required this.onTap});

  final PublicDownloadLog row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final color = row.permanent ? _permanentColor : _expiringColor;
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
                icon: Icons.cloud_download_rounded,
                color: color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.collectionName,
                      style: text.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (row.collectionId.isNotEmpty)
                      Text(
                        row.shortCollectionId,
                        style: text.labelSmall?.copyWith(
                          color: b.paperDim,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(activityShortWhen(row.accessedAt), style: text.labelMedium),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusPill(
                label: row.tokenType.isEmpty ? 'token' : row.tokenType,
                color: color,
              ),
              GlowBadge(
                label: row.device.isEmpty ? 'Unknown device' : row.device,
                color: Brand.info,
                icon: _deviceIcon(row.device),
              ),
            ],
          ),
          if (row.ipAddress.isNotEmpty || place.isNotEmpty) ...[
            const SizedBox(height: 8),
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
