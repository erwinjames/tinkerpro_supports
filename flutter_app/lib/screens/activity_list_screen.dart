import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import '../models/activity_models.dart';
import '../services/activity_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'activity_common.dart';
import 'activity_conversations_tab.dart';
import 'activity_downloads_tab.dart';
import 'activity_logged_in_tab.dart';
import 'activity_portal_tab.dart';
import 'activity_tickets_tab.dart';

enum _Span { all, today, week, month, custom }

enum _Tab { userActivity, loggedIn, tickets, conversations, portal, downloads }

class ActivityListScreen extends StatefulWidget {
  const ActivityListScreen({super.key, required this.service});

  final ActivityService service;

  @override
  State<ActivityListScreen> createState() => _ActivityListScreenState();
}

class _ActivityListScreenState extends State<ActivityListScreen> {
  final ValueNotifier<int> _refresh = ValueNotifier<int>(0);
  final Map<_Tab, int> _counts = <_Tab, int>{};
  final Set<_Tab> _visited = <_Tab>{_Tab.userActivity};
  _Tab _tab = _Tab.userActivity;

  @override
  void dispose() {
    _refresh.dispose();
    super.dispose();
  }

  String _label(_Tab tab) {
    switch (tab) {
      case _Tab.userActivity:
        return 'User activity';
      case _Tab.loggedIn:
        return 'Logged in';
      case _Tab.tickets:
        return 'Tickets';
      case _Tab.conversations:
        return 'Conversations';
      case _Tab.portal:
        return 'Vendor & taxpayer';
      case _Tab.downloads:
        return 'Public downloads';
    }
  }

  void _count(_Tab tab, int? value) {
    if (!mounted) return;
    if (_counts[tab] == value) return;
    setState(() {
      if (value == null) {
        _counts.remove(tab);
      } else {
        _counts[tab] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _Tab.values;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Audit',
      title: 'Activity logs',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.refresh_rounded,
        tooltip: 'Refresh',
        onPressed: () => _refresh.value++,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoicePills<_Tab>(
            options: tabs,
            value: _tab,
            labelOf: _label,
            countOf: (t) => _counts[t],
            onChanged: (t) => setState(() {
              _tab = t;
              _visited.add(t);
            }),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: IndexedStack(
              index: tabs.indexOf(_tab),
              sizing: StackFit.expand,
              children: [
                _UserActivityTab(
                  service: widget.service,
                  active: _tab == _Tab.userActivity,
                  refresh: _refresh,
                  onCount: (c) => _count(_Tab.userActivity, c),
                ),
                if (_visited.contains(_Tab.loggedIn))
                  ActivityLoggedInTab(
                    service: widget.service,
                    active: _tab == _Tab.loggedIn,
                    refresh: _refresh,
                    onCount: (c) => _count(_Tab.loggedIn, c),
                  )
                else
                  const SizedBox.shrink(),
                if (_visited.contains(_Tab.tickets))
                  ActivityTicketsTab(
                    service: widget.service,
                    active: _tab == _Tab.tickets,
                    refresh: _refresh,
                    onCount: (c) => _count(_Tab.tickets, c),
                  )
                else
                  const SizedBox.shrink(),
                if (_visited.contains(_Tab.conversations))
                  ActivityConversationsTab(
                    service: widget.service,
                    active: _tab == _Tab.conversations,
                    refresh: _refresh,
                    onCount: (c) => _count(_Tab.conversations, c),
                  )
                else
                  const SizedBox.shrink(),
                if (_visited.contains(_Tab.portal))
                  ActivityPortalTab(
                    service: widget.service,
                    active: _tab == _Tab.portal,
                    refresh: _refresh,
                    onCount: (c) => _count(_Tab.portal, c),
                  )
                else
                  const SizedBox.shrink(),
                if (_visited.contains(_Tab.downloads))
                  ActivityDownloadsTab(
                    service: widget.service,
                    active: _tab == _Tab.downloads,
                    refresh: _refresh,
                    onCount: (c) => _count(_Tab.downloads, c),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserActivityTab extends StatefulWidget {
  const _UserActivityTab({
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
  State<_UserActivityTab> createState() => _UserActivityTabState();
}

class _UserActivityTabState extends State<_UserActivityTab> {
  static const int _pageSize = 40;
  static const int _topUpBudget = 6;

  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<ActivityLog> _rows = [];
  int _page = 1;
  int _total = 0;
  int _topUps = 0;
  bool _loading = true;
  bool _loadingMore = false;

  String _query = '';
  String _user = '';
  String _action = '';
  _Span _span = _Span.all;
  DateTimeRange? _custom;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.refresh.addListener(_onRefreshSignal);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.refresh.removeListener(_onRefreshSignal);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted || !widget.active) return;
    _load();
  }

  bool get _hasMore => _rows.length < _total;

  bool get _hasFilters =>
      _user.isNotEmpty || _action.isNotEmpty || _span != _Span.all;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 420) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _topUps = 0;
    });
    final page = await widget.service.fetch(
      search: _query,
      page: 1,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _rows
        ..clear()
        ..addAll(page.rows);
      _total = page.total < page.rows.length ? page.rows.length : page.total;
      _page = 1;
      _loading = false;
    });
    widget.onCount(_total);
    _topUp();
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final page = await widget.service.fetch(
      search: _query,
      page: next,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (page.rows.isEmpty) {
        _total = _rows.length;
        return;
      }
      _page = next;
      _rows.addAll(page.rows);
      if (page.total > _rows.length) _total = page.total;
    });
    _topUp();
  }

  void _topUp() {
    if (!_hasFilters || !_hasMore) return;
    if (_visible.length >= 15) return;
    if (_topUps >= _topUpBudget) return;
    _topUps++;
    _loadMore();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _query = value;
      _load();
    });
  }

  List<ActivityLog> get _visible {
    final from = _rangeStart;
    final to = _rangeEnd;
    return _rows
        .where((log) {
          if (_user.isNotEmpty && log.username != _user) return false;
          if (_action.isNotEmpty && log.action != _action) return false;
          if (from == null && to == null) return true;
          final when = log.when;
          if (when == null) return false;
          if (from != null && when.isBefore(from)) return false;
          if (to != null && when.isAfter(to)) return false;
          return true;
        })
        .toList(growable: false);
  }

  DateTime? get _rangeStart {
    final now = DateTime.now();
    switch (_span) {
      case _Span.all:
        return null;
      case _Span.today:
        return DateTime(now.year, now.month, now.day);
      case _Span.week:
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
      case _Span.month:
        return DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29));
      case _Span.custom:
        final r = _custom;
        if (r == null) return null;
        return DateTime(r.start.year, r.start.month, r.start.day);
    }
  }

  DateTime? get _rangeEnd {
    if (_span != _Span.custom) return null;
    final r = _custom;
    if (r == null) return null;
    return DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59);
  }

  String _spanLabel(_Span span) {
    switch (span) {
      case _Span.all:
        return 'All time';
      case _Span.today:
        return 'Today';
      case _Span.week:
        return '7 days';
      case _Span.month:
        return '30 days';
      case _Span.custom:
        final r = _custom;
        if (r == null) return 'Custom';
        return '${activityIsoDay(r.start)} → ${activityIsoDay(r.end)}';
    }
  }

  Future<void> _onSpan(_Span span) async {
    if (span != _Span.custom) {
      setState(() {
        _span = span;
        _topUps = 0;
      });
      _topUp();
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _custom,
      helpText: 'Filter by date',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _custom = picked;
      _span = _Span.custom;
      _topUps = 0;
    });
    _topUp();
  }

  void _resetFilters() {
    setState(() {
      _user = '';
      _action = '';
      _span = _Span.all;
      _custom = null;
      _topUps = 0;
    });
  }

  List<String> get _usernames {
    final set = <String>{};
    for (final r in _rows) {
      if (r.username.isNotEmpty) set.add(r.username);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _actions {
    final set = <String>{};
    for (final r in _rows) {
      if (r.action.isNotEmpty) set.add(r.action);
    }
    final list = set.toList()..sort();
    return list;
  }

  void _openDetail(ActivityLog log) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DetailSheet(log: log, service: widget.service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final rows = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Search action, details or user',
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        ChoicePills<_Span>(
          options: _Span.values,
          value: _span,
          labelOf: _spanLabel,
          onChanged: _onSpan,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ActivityFilterMenu(
                icon: Icons.person_outline_rounded,
                label: 'All users',
                value: _user,
                options: _usernames,
                onChanged: (v) {
                  setState(() {
                    _user = v;
                    _topUps = 0;
                  });
                  _topUp();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ActivityFilterMenu(
                icon: Icons.bolt_rounded,
                label: 'All actions',
                value: _action,
                options: _actions,
                onChanged: (v) {
                  setState(() {
                    _action = v;
                    _topUps = 0;
                  });
                  _topUp();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SectionHeader(
          title: 'Logs',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _loading ? '—' : '${rows.length} of $_total',
                style: text.labelMedium,
              ),
              if (_hasFilters) ...[
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: 'Reset filters',
                  child: InkWell(
                    onTap: _resetFilters,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.filter_alt_off_rounded,
                        size: 18,
                        color: b.signal,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: b.signal,
            backgroundColor: b.surface,
            onRefresh: _load,
            child: _loading
                ? const SkeletonList(count: 7)
                : rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 48),
                      EmptyState(
                        label: _rows.isEmpty
                            ? 'No activity'
                            : 'No matching activity',
                        hint: _rows.isEmpty
                            ? 'Nothing recorded yet. Pull down to refresh.'
                            : 'Try a different search, user, action or date range.',
                        icon: Icons.manage_search_rounded,
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: rows.length + 1,
                    itemBuilder: (_, i) {
                      if (i == rows.length) return _footer(context);
                      final log = rows[i];
                      return ActivityRise(
                        index: i,
                        child: _ActivityRow(
                          log: log,
                          isFirst: i == 0,
                          isLast: i == rows.length - 1,
                          onTap: () => _openDetail(log),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (_loadingMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(52, 8, 0, 16),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.brand.signal,
              ),
            ),
            const SizedBox(width: 10),
            Text('Loading older entries…', style: text.bodySmall),
          ],
        ),
      );
    }
    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(52, 8, 0, 16),
        child: GhostButton(label: 'Load more', onPressed: _loadMore),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(52, 10, 0, 20),
      child: Text('End of the trail · $_total entries', style: text.bodySmall),
    );
  }
}

class _ActivityKind {
  const _ActivityKind(this.icon, this.color);
  final IconData icon;
  final Color color;
}

_ActivityKind _kindFor(String action) {
  final a = action.toLowerCase();
  bool has(List<String> keys) => keys.any(a.contains);
  if (has(['logout', 'log out', 'sign out', 'signout'])) {
    return const _ActivityKind(Icons.logout_rounded, Color(0xFF64748B));
  }
  if (has(['login', 'log in', 'sign in', 'signin', 'auth'])) {
    return const _ActivityKind(Icons.login_rounded, Brand.info);
  }
  if (has(['password', 'reset', 'otp', 'token', 'permission', 'role'])) {
    return const _ActivityKind(Icons.key_rounded, Color(0xFF8B5CF6));
  }
  if (has(['delete', 'remove', 'deactivat', 'archive', 'purge'])) {
    return const _ActivityKind(Icons.delete_outline_rounded, Brand.danger);
  }
  if (has(['upload', 'import'])) {
    return const _ActivityKind(Icons.upload_rounded, Color(0xFF0EA5E9));
  }
  if (has(['download', 'export', 'print'])) {
    return const _ActivityKind(Icons.download_rounded, Color(0xFF14B8A6));
  }
  if (has(['create', 'add', 'new', 'register', 'insert'])) {
    return const _ActivityKind(Icons.add_circle_outline_rounded, Brand.success);
  }
  if (has(['update', 'edit', 'change', 'modif', 'save', 'set'])) {
    return const _ActivityKind(Icons.edit_rounded, Brand.warning);
  }
  if (has(['ticket'])) {
    return const _ActivityKind(
      Icons.confirmation_number_outlined,
      Brand.signal,
    );
  }
  if (has(['chat', 'message', 'reply', 'comment'])) {
    return const _ActivityKind(Icons.chat_bubble_outline_rounded, Brand.info);
  }
  if (has(['view', 'open', 'access'])) {
    return const _ActivityKind(Icons.visibility_outlined, Color(0xFF64748B));
  }
  return const _ActivityKind(Icons.history_rounded, Brand.signal);
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.log,
    required this.onTap,
    required this.isFirst,
    required this.isLast,
  });
  final ActivityLog log;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final kind = _kindFor(log.action);
    final user = log.username.isEmpty ? 'Unknown user' : log.username;
    final when = activityShortWhen(log.createdAt);
    final place = log.locationLabel;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                _Connector(color: kind.color, height: 14, hidden: isFirst),
                ActivityKindTile(
                  icon: kind.icon,
                  color: kind.color,
                  animate: true,
                ),
                Expanded(
                  child: _Connector(color: kind.color, hidden: isLast),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: AppCard(
                onTap: onTap,
                radius: Brand.radiusLg,
                borderColor: when == 'now'
                    ? kind.color.withValues(alpha: 0.45)
                    : null,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            log.action.isEmpty ? '—' : log.action,
                            style: text.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (when == 'now')
                          GlowBadge(label: 'now', color: kind.color)
                        else
                          Text(when, style: text.labelMedium),
                      ],
                    ),
                    if (log.details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        log.details,
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        AppAvatar(name: user, size: 20),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            user,
                            style: text.labelMedium?.copyWith(
                              color: b.paper,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (place.isNotEmpty || log.ipAddress.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            log.hasCoords
                                ? Icons.place_rounded
                                : Icons.public_rounded,
                            size: 13,
                            color: b.paperDim,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              place.isEmpty ? log.ipAddress : place,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSheet extends StatefulWidget {
  const _DetailSheet({required this.log, required this.service});

  final ActivityLog log;
  final ActivityService service;

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  ActivityTrace? _trace;
  TracePresence? _presence;
  Timer? _live;
  bool _loading = false;
  bool _denied = false;

  bool get _privileged => widget.service.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    if (!_privileged) return;
    _loading = true;
    _loadTrace();
    _live = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _loadTrace() async {
    final trace = await widget.service.trace(widget.log.id);
    if (!mounted) return;
    setState(() {
      _trace = trace;
      _presence = trace?.user ?? _presence;
      _loading = false;
      _denied = trace == null;
    });
  }

  Future<void> _poll() async {
    final userId = _trace?.user?.userId ?? widget.log.userId;
    final beat = await widget.service.heartbeat(userId);
    if (!mounted || beat == null) return;
    setState(() => _presence = beat.user ?? _presence);
    final trace = _trace;
    if (trace != null && beat.latestId > trace.latestId) _loadTrace();
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final trace = _trace;
    final point = trace?.selected;
    final lat = point?.lat ?? log.lat;
    final lon = point?.lon ?? log.lon;
    final source = point?.source ?? log.coordSource;

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                _header(context),
                const SizedBox(height: 18),
                if (trace != null) ...[
                  for (final section in trace.sections) ...[
                    SectionHeader(title: section.title),
                    AppCard(
                      radius: Brand.radiusLg,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          for (final f in section.fields) _field(context, f),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                ] else ...[
                  const SectionHeader(title: 'Entry'),
                  AppCard(
                    radius: Brand.radiusLg,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        StationDataRow(label: 'Log ID', value: '#${log.id}'),
                        StationDataRow(
                          label: 'User',
                          value: log.username.isEmpty
                              ? 'Unknown user'
                              : log.username,
                        ),
                        StationDataRow(
                          label: 'Action',
                          value: log.action.isEmpty ? '—' : log.action,
                        ),
                        StationDataRow(
                          label: 'Recorded',
                          value: activityLongWhen(log.createdAt),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SectionHeader(title: 'Network'),
                  AppCard(
                    radius: Brand.radiusLg,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        StationDataRow(
                          label: 'IP address',
                          value: log.ipAddress.isEmpty ? '—' : log.ipAddress,
                        ),
                        if (log.ipV4.isNotEmpty)
                          StationDataRow(label: 'Public IPv4', value: log.ipV4),
                        if (log.ipLan.isNotEmpty)
                          StationDataRow(
                            label: 'LAN address',
                            value: log.ipLan,
                          ),
                        StationDataRow(
                          label: 'ISP',
                          value: log.isp.isEmpty ? '—' : log.isp,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const SectionHeader(title: 'Position'),
                  AppCard(
                    radius: Brand.radiusLg,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        ActivityPillRow(
                          label: 'Source',
                          pill: StatusPill(
                            label: activitySourceLabel(source),
                            color: activitySourceColor(source),
                            dot: true,
                          ),
                        ),
                        StationDataRow(
                          label: 'IP location',
                          value: log.locationLabel.isEmpty
                              ? '—'
                              : log.locationLabel,
                        ),
                        if (log.locationCity.isNotEmpty)
                          StationDataRow(
                            label: 'City',
                            value: log.locationCity,
                          ),
                        if (log.locationZip.isNotEmpty)
                          StationDataRow(label: 'ZIP', value: log.locationZip),
                        StationDataRow(
                          label: 'Coordinates',
                          value: lat == null || lon == null
                              ? '—'
                              : activityCoords(lat, lon),
                        ),
                        if (log.gpsAccuracyM != null)
                          StationDataRow(
                            label: 'Accuracy',
                            value: activityMetres(log.gpsAccuracyM),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (lat != null && lon != null) ...[
                  SectionHeader(
                    title: 'Map',
                    trailing: StatusPill(
                      label: activitySourceLabel(source),
                      color: activitySourceColor(source),
                      dot: true,
                    ),
                  ),
                  ActivityMapPanel(
                    lat: lat,
                    lon: lon,
                    caption: point?.address.isNotEmpty == true
                        ? point!.address
                        : log.locationLabel,
                  ),
                  const SizedBox(height: 18),
                ],
                if (log.details.isNotEmpty) ...[
                  const SectionHeader(title: 'Details'),
                  GlassPanel(
                    accent: _kindFor(log.action).color,
                    child: SelectableText(
                      log.details,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (_privileged) _tracePane(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final log = widget.log;
    final kind = _kindFor(log.action);
    final presence = _presence;
    final who = presence?.displayName.isNotEmpty == true
        ? presence!.displayName
        : (log.username.isEmpty ? 'Unknown user' : log.username);
    return GlassPanel(
      accent: kind.color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                _privileged ? 'Activity trace' : 'Activity',
                style: text.labelMedium?.copyWith(
                  color: b.signal,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              if (_privileged)
                StatusPill(
                  label: presence == null
                      ? 'Static record'
                      : (presence.isOnline
                            ? 'Live · online now'
                            : 'Offline · last trace'),
                  color: presence?.isOnline == true
                      ? Brand.success
                      : b.paperDim,
                  dot: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ActivityKindTile(icon: kind.icon, color: kind.color, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log.action.isEmpty ? 'Activity' : log.action,
                      style: text.titleLarge?.copyWith(color: b.paper),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$who · ${activityLongWhen(log.createdAt)}',
                      style: text.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (presence != null && presence.lastSeen.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Last seen ${activityLongWhen(presence.lastSeen)}',
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(BuildContext context, TraceField f) {
    if (f.tag.isNotEmpty) {
      return ActivityPillRow(
        label: f.label,
        pill: StatusPill(
          label: activitySourceLabel(f.tag),
          color: activitySourceColor(f.tag),
          dot: true,
        ),
      );
    }
    return StationDataRow(
      label: f.label,
      value: f.value.isEmpty ? '—' : f.value,
      valueStyle: f.mono
          ? Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.brand.paper,
              fontWeight: FontWeight.w500,
              fontFamily: 'monospace',
            )
          : null,
    );
  }

  Widget _tracePane(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (_loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Trace'),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Skeleton(width: 170, height: 14),
                SizedBox(height: 12),
                Skeleton(width: 230, height: 11),
                SizedBox(height: 10),
                Skeleton(width: 190, height: 11),
              ],
            ),
          ),
        ],
      );
    }
    final trace = _trace;
    if (trace == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Trace'),
          AppCard(
            radius: Brand.radiusLg,
            child: Text(
              _denied
                  ? 'Super admin clearance required to view the activity trace.'
                  : 'Could not reach the trace service.',
              style: text.bodySmall,
            ),
          ),
        ],
      );
    }

    final stops = trace.track;
    final recent = stops.reversed.take(12).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Trace'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            GlowBadge(
              label: '${stops.length} located stops',
              color: Brand.info,
              icon: Icons.place_outlined,
            ),
            GlowBadge(
              label: '${trace.deviceFixes} device fixes',
              color: Brand.success,
              icon: Icons.my_location_rounded,
            ),
            GlowBadge(
              label: 'Path ${activityDistance(activityTrackDistance(stops))}',
              color: Brand.signal,
              icon: Icons.route_rounded,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (stops.isEmpty)
          AppCard(
            radius: Brand.radiusLg,
            child: Text(
              trace.emptyNote.isEmpty
                  ? 'No coordinates recorded for this entry.'
                  : trace.emptyNote,
              style: text.bodySmall,
            ),
          )
        else ...[
          AppCard(
            radius: Brand.radiusLg,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final p in recent)
                  ActivityTraceStop(
                    point: p,
                    selected: p.ids.any(trace.selectedIds.contains),
                    isLast: identical(p, recent.last),
                  ),
              ],
            ),
          ),
          if (stops.length > recent.length) ...[
            const SizedBox(height: 8),
            Text(
              'Showing the newest ${recent.length} of ${stops.length} stops.',
              style: text.bodySmall,
            ),
          ],
          if (trace.trackNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(trace.trackNote, style: text.bodySmall),
          ],
        ],
      ],
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.color, required this.hidden, this.height});

  final Color color;
  final bool hidden;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    if (hidden) {
      return SizedBox(width: 2, height: height);
    }
    return Container(
      width: 2,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: color.withValues(alpha: b.isDark ? 0.5 : 0.35),
      ),
    );
  }
}
