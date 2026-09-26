import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/activity_models.dart';
import '../services/activity_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'activity_common.dart';

class ActivityLoggedInTab extends StatefulWidget {
  const ActivityLoggedInTab({
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
  State<ActivityLoggedInTab> createState() => _ActivityLoggedInTabState();
}

class _ActivityLoggedInTabState extends State<ActivityLoggedInTab>
    with WidgetsBindingObserver {
  static const Duration _pollEvery = Duration(seconds: 30);

  final _searchController = TextEditingController();
  Timer? _debounce;
  Timer? _poll;

  List<OnlineUser> _rows = const <OnlineUser>[];
  String _query = '';
  bool _loading = true;
  bool _started = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.refresh.addListener(_onRefreshSignal);
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(covariant ActivityLoggedInTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refresh != oldWidget.refresh) {
      oldWidget.refresh.removeListener(_onRefreshSignal);
      widget.refresh.addListener(_onRefreshSignal);
    }
    if (widget.active && !oldWidget.active) {
      _activate();
    } else if (!widget.active && oldWidget.active) {
      _poll?.cancel();
      _poll = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.refresh.removeListener(_onRefreshSignal);
    _debounce?.cancel();
    _poll?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (widget.active) _activate();
      return;
    }
    _poll?.cancel();
    _poll = null;
  }

  void _activate() {
    _started = true;
    _load();
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) => _load(silent: true));
  }

  void _onRefreshSignal() {
    if (!mounted || !widget.active) return;
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = _rows.isEmpty);
    try {
      final rows = await widget.service.onlineUsers();
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
        if (!silent) _error = activityErrorText(e);
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

  List<OnlineUser> get _visible {
    if (_query.isEmpty) return _rows;
    return _rows
        .where((r) => r.haystack.contains(_query))
        .toList(growable: false);
  }

  void _open(OnlineUser row) {
    final geo = row.geo;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ActivityDetailSheet(
        service: widget.service,
        eyebrow: widget.service.isSuperAdmin ? 'Live trace' : 'Logged in',
        title: row.displayName,
        subtitle: row.username.isEmpty ? row.roleLabel : '@${row.username}',
        icon: Icons.person_pin_circle_rounded,
        color: Brand.success,
        pills: [
          const StatusPill(
            label: 'Online now',
            color: Brand.success,
            dot: true,
          ),
          StatusPill(label: row.roleLabel, color: Brand.info),
        ],
        groups: [
          ActivityDetailGroup('Session', [
            ActivityDetailField('User', row.displayName),
            ActivityDetailField(
              'Username',
              row.username.isEmpty ? '—' : '@${row.username}',
            ),
            ActivityDetailField('Role', row.roleLabel),
            ActivityDetailField(
              'Last activity',
              activityLongWhen(row.lastActivity),
            ),
            ActivityDetailField(
              'Last action',
              row.lastAction.isEmpty ? '—' : row.lastAction,
            ),
            ActivityDetailField('Last seen', activityLongWhen(row.lastSeen)),
          ]),
          ActivityDetailGroup('Network', [
            ActivityDetailField('IP address', row.ipAddress, mono: true),
            if (row.ipV4.isNotEmpty)
              ActivityDetailField('Public IPv4', row.ipV4, mono: true),
            if (row.ipLan.isNotEmpty)
              ActivityDetailField('LAN address', row.ipLan, mono: true),
            ActivityDetailField('ISP', geo.isp),
            ActivityDetailField('IP location', geo.label),
            if (geo.locationZip.isNotEmpty)
              ActivityDetailField('ZIP', geo.locationZip),
          ]),
        ],
        traceQuery: {'subject': 'user', 'user_id': '${row.id}'},
        heartbeatQuery: {
          'live': '1',
          'live_kind': 'user',
          'user_id': '${row.id}',
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
    if (!_started && !widget.active) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Search user, role, IP, location',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        SectionHeader(
          title: 'Currently logged in',
          trailing: Text(
            _loading ? '—' : '${rows.length} active',
            style: text.labelMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '${_rows.length} user(s) logged in & active in the last 30 min',
            style: text.bodySmall,
          ),
        ),
        Expanded(
          child: ActivityFeedView<OnlineUser>(
            loading: _loading,
            error: _error,
            rows: rows,
            onRefresh: _load,
            resetToken: _query,
            footerNoun: 'users',
            emptyLabel: _rows.isEmpty ? 'Nobody is here' : 'No matching user',
            emptyHint: _rows.isEmpty
                ? 'No one is logged in and active right now.'
                : 'Try a different name, role, IP or location.',
            emptyIcon: Icons.person_off_rounded,
            itemBuilder: (context, row, i) => ActivityRise(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OnlineUserCard(row: row, onTap: () => _open(row)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OnlineUserCard extends StatelessWidget {
  const _OnlineUserCard({required this.row, required this.onTap});

  final OnlineUser row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
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
              Stack(
                children: [
                  AppAvatar(name: row.displayName, size: 38),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: Brand.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: b.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.displayName,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (row.username.isNotEmpty)
                      Text(
                        '@${row.username}',
                        style: text.labelSmall?.copyWith(color: b.paperDim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: row.roleLabel, color: Brand.info),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 13, color: b.paperDim),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  activityShortWhen(row.lastActivity),
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (row.lastAction.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              row.lastAction,
              style: text.labelSmall?.copyWith(color: b.paperDim),
              maxLines: 1,
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
