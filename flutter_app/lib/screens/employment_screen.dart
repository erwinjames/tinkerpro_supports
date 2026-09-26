import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, FilteringTextInputFormatter;
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../models/employment_models.dart';
import '../services/employment_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'employment_edit_screen.dart';
import 'employment_record_screen.dart';

class EmploymentEntryButton extends StatefulWidget {
  const EmploymentEntryButton({super.key, required this.api});

  final ApiClient api;

  @override
  State<EmploymentEntryButton> createState() => _EmploymentEntryButtonState();
}

class _EmploymentEntryButtonState extends State<EmploymentEntryButton> {
  late final EmploymentService _service = EmploymentService(widget.api);
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final count = await _service.pendingCount();
    if (mounted) setState(() => _pending = count);
  }

  Future<void> _open() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmploymentScreen(api: widget.api),
      ),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        StationAction(
          icon: Icons.assignment_ind_rounded,
          tooltip: _pending > 0
              ? 'Employment info · $_pending awaiting review'
              : 'Employment info',
          onPressed: _open,
        ),
        if (_pending > 0)
          Positioned(
            top: -4,
            right: -4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Brand.danger,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Brand.navy, width: 2),
                ),
                child: Text(
                  _pending > 99 ? '99+' : '$_pending',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _Tab { records, links }

class EmploymentScreen extends StatefulWidget {
  const EmploymentScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<EmploymentScreen> createState() => _EmploymentScreenState();
}

class _EmploymentScreenState extends State<EmploymentScreen>
    with WidgetsBindingObserver {
  late final EmploymentService _service = EmploymentService(widget.api);
  static const _pageSize = 25;

  _Tab _tab = _Tab.records;
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  Timer? _searchTimer;
  String _search = '';
  String _status = '';

  List<EmploymentRecordBrief> _records = const [];
  EmploymentSummary _summary = const EmploymentSummary();
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _requestSeq = 0;

  List<EmploymentLink>? _links;
  bool _linksLoading = false;
  String? _linksError;

  final Set<int> _hiddenRecords = {};
  final Set<int> _hiddenLinks = {};
  int? _opening;

  Timer? _pulseTimer;
  String? _pulseKey;
  int _pulseLatest = 0;
  bool _pulseBusy = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _loadRecords();
    _pulseTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _pulseCheck(),
    );
    _pulseCheck();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseTimer?.cancel();
    _searchTimer?.cancel();
    _searchController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _pulseCheck();
  }

  void _onScroll() {
    if (_tab != _Tab.records || _loading || _loadingMore) return;
    if (_records.length >= _total) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  Future<void> _loadRecords() async {
    final seq = ++_requestSeq;
    _pulseKey = null;
    setState(() {
      _loading = _records.isEmpty;
      _error = null;
    });
    try {
      final page = await _service.records(
        search: _search,
        status: _status,
        page: 1,
        limit: _pageSize,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _records = page.records;
        _total = page.total;
        _summary = page.summary;
        _page = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    final seq = _requestSeq;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.records(
        search: _search,
        status: _status,
        page: _page + 1,
        limit: _pageSize,
      );
      if (!mounted || seq != _requestSeq) return;
      final seen = _records.map((r) => r.id).toSet();
      setState(() {
        _records = [
          ..._records,
          ...page.records.where((r) => !seen.contains(r.id)),
        ];
        _total = page.total;
        _summary = page.summary;
        _page += 1;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _loadLinks() async {
    setState(() {
      _linksLoading = _links == null;
      _linksError = null;
    });
    try {
      final links = await _service.links();
      if (!mounted) return;
      setState(() {
        _links = links;
        _linksLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _linksLoading = false;
        _linksError = e.toString();
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadRecords(),
      if (_links != null || _tab == _Tab.links) _loadLinks(),
    ]);
  }

  Future<void> _pulseCheck() async {
    if (!_foreground || _pulseBusy || !mounted) return;
    _pulseBusy = true;
    try {
      final p = await _service.pulse();
      if (p == null || !mounted) return;
      if (_pulseKey == null) {
        _pulseKey = p.key;
        _pulseLatest = p.latestId;
        return;
      }
      if (p.key == _pulseKey) return;
      final fresh = p.latestId > _pulseLatest;
      _pulseKey = p.key;
      _pulseLatest = p.latestId;
      await _loadRecords();
      _pulseKey = p.key;
      if (_tab == _Tab.links) _loadLinks();
      if (fresh && mounted) {
        employmentToast(
          context,
          'A new employment information sheet just came in.',
        );
      }
    } finally {
      _pulseBusy = false;
    }
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      _search = value;
      _loadRecords();
    });
  }

  void _setStatusFilter(String value) {
    if (value == _status) return;
    setState(() {
      _status = value;
      _records = const [];
      _loading = true;
    });
    _loadRecords();
  }

  void _setTab(_Tab tab) {
    setState(() => _tab = tab);
    if (tab == _Tab.links) _loadLinks();
  }

  Future<EmploymentRecord?> _fetchRecord(int id) async {
    setState(() => _opening = id);
    try {
      return await _service.record(id);
    } catch (e) {
      if (mounted) employmentToast(context, e.toString());
      return null;
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<EmploymentRecord?> _ensureStaffLinked(EmploymentRecord record) async {
    if (record.isStaffLinked) return record;
    final res = await showStaffLinkSheet(
      context,
      service: _service,
      recordId: record.id,
      fullName: record.fullName,
    );
    if (res == null || !mounted) return null;
    employmentToast(context, res.message ?? 'Saved.');
    _loadRecords();
    return record.copyWith({
      'staff_user_id': res.data['staff_user_id'],
      'staff_name': res.data['staff_name'],
      'staff_link_skipped': res.data['staff_link_skipped'],
    });
  }

  Future<void> _openRecord(int id) async {
    if (_opening != null) return;
    final fetched = await _fetchRecord(id);
    if (fetched == null || !mounted) return;
    final record = await _ensureStaffLinked(fetched);
    if (record == null || !mounted) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) =>
            EmploymentRecordScreen(service: _service, record: record),
      ),
    );
    if (!mounted) return;
    if (result == kEmploymentDeleteRequest) {
      _deleteRecordWithUndo(id);
    } else if (result == kEmploymentChanged) {
      _loadRecords();
    }
  }

  Future<void> _editRecord(int id) async {
    if (_opening != null) return;
    final record = await _fetchRecord(id);
    if (record == null || !mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EmploymentEditScreen(service: _service, record: record),
      ),
    );
    if (saved == true && mounted) _loadRecords();
  }

  Future<void> _printRecord(EmploymentRecordBrief brief) async {
    if (!brief.isStaffLinked) {
      final res = await showStaffLinkSheet(
        context,
        service: _service,
        recordId: brief.id,
        fullName: brief.fullName,
      );
      if (res == null || !mounted) return;
      employmentToast(context, res.message ?? 'Saved.');
      _loadRecords();
    }
    if (!mounted) return;
    await printEmploymentSheet(context, _service, brief.id);
  }

  Future<void> _markReviewed(EmploymentRecordBrief brief) async {
    final next = brief.status == 'reviewed' ? 'submitted' : 'reviewed';
    final res = await _service.setStatus(brief.id, next);
    if (!mounted) return;
    employmentToast(
      context,
      res.ok
          ? (res.message ?? 'Marked as $next.')
          : (res.message ?? 'Could not update the status'),
    );
    if (res.ok) _loadRecords();
  }

  Future<void> _confirmDeleteRecord(EmploymentRecordBrief brief) async {
    final ok = await employmentConfirm(
      context,
      title: 'Delete this sheet?',
      message:
          'The employee record and its dependents are permanently removed.',
      confirmLabel: 'Delete',
    );
    if (ok && mounted) _deleteRecordWithUndo(brief.id);
  }

  void _deleteRecordWithUndo(int id) {
    setState(() => _hiddenRecords.add(id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Record deleted'),
            duration: const Duration(seconds: 5),
            persist: false,
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        )
        .closed
        .then((reason) async {
          if (reason == SnackBarClosedReason.action) {
            if (mounted) setState(() => _hiddenRecords.remove(id));
            return;
          }
          final res = await _service.deleteRecord(id);
          if (!res.ok) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(res.message ?? 'Could not delete the record'),
              ),
            );
          }
          if (!mounted) return;
          setState(() => _hiddenRecords.remove(id));
          _loadRecords();
        });
  }

  void _copy(String url) {
    Clipboard.setData(ClipboardData(text: url));
    employmentToast(context, 'Link copied');
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) employmentToast(context, 'Could not open the form');
  }

  Future<void> _revokeLink(EmploymentLink link) async {
    final ok = await employmentConfirm(
      context,
      title: 'Revoke this link?',
      message: 'Anyone holding it will no longer be able to open the form.',
      confirmLabel: 'Revoke',
      icon: Icons.block_rounded,
    );
    if (!ok || !mounted) return;
    final res = await _service.revokeLink(link.id);
    if (!mounted) return;
    employmentToast(
      context,
      res.message ?? (res.ok ? 'Link revoked.' : 'Could not revoke the link'),
    );
    if (res.ok) {
      _loadLinks();
      _loadRecords();
    }
  }

  Future<void> _deleteLink(EmploymentLink link) async {
    final ok = await employmentConfirm(
      context,
      title: 'Delete this link?',
      message: 'Submissions already made through it are kept.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    setState(() => _hiddenLinks.add(link.id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Link deleted'),
            duration: const Duration(seconds: 5),
            persist: false,
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        )
        .closed
        .then((reason) async {
          if (reason == SnackBarClosedReason.action) {
            if (mounted) setState(() => _hiddenLinks.remove(link.id));
            return;
          }
          final res = await _service.deleteLink(link.id);
          if (!res.ok) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(res.message ?? 'Could not delete the link'),
              ),
            );
          }
          if (!mounted) return;
          setState(() => _hiddenLinks.remove(link.id));
          _loadLinks();
          _loadRecords();
        });
  }

  Future<void> _emailLink(EmploymentLink link) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Email this link',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                link.label.isEmpty ? 'Untitled link' : link.label,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _EmailLinkPanel(
                service: _service,
                linkId: link.id,
                initialEmail: link.sentTo,
                initialHint: link.isReusable
                    ? 'Send it to whoever should pass it around.'
                    : '',
                onSent: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
    if (sent == true && mounted) _loadLinks();
  }

  Future<void> _createLink() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _CreateLinkScreen(service: _service),
      ),
    );
    if (created == true && mounted) {
      _loadRecords();
      _loadLinks();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.api.canManageEmployment) {
      return StationScaffold(
        stationLabel: 'Admin only',
        title: 'Employment Info',
        showBottomBrand: false,
        onBack: () => Navigator.of(context).pop(),
        child: const EmptyState(
          label: 'Access restricted',
          hint: 'Only administrators can manage employment information.',
          icon: Icons.lock_rounded,
        ),
      );
    }
    final links = _links;
    return StationScaffold(
      stationLabel: 'Admin only',
      title: 'Employment Info',
      subtitle: 'Share a fill-up link and review information sheets',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StationAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onPressed: _refreshAll,
          ),
          const SizedBox(width: 8),
          StationAction(
            icon: Icons.add_link_rounded,
            tooltip: 'Create share link',
            onPressed: _createLink,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoicePills<_Tab>(
            options: _Tab.values,
            value: _tab,
            onChanged: _setTab,
            labelOf: (t) => t == _Tab.records ? 'Submissions' : 'Share links',
            countOf: (t) => t == _Tab.records
                ? (_loading && _records.isEmpty ? null : _summary.total)
                : links?.length,
          ),
          const SizedBox(height: 12),
          if (_tab == _Tab.records) ...[
            AppSearchField(
              controller: _searchController,
              hint: 'Search name, email, job title, ID…',
              onChanged: _onSearch,
            ),
            const SizedBox(height: 12),
            ChoicePills<String>(
              options: const ['', 'submitted', 'reviewed', 'archived'],
              value: _status,
              onChanged: _setStatusFilter,
              labelOf: (s) =>
                  s.isEmpty ? 'All statuses' : employmentStatusLabel(s),
              countOf: _loading && _records.isEmpty
                  ? null
                  : (s) {
                      switch (s) {
                        case 'submitted':
                          return _summary.submitted;
                        case 'reviewed':
                          return _summary.reviewed;
                        case 'archived':
                          return _summary.archived;
                        default:
                          return _summary.total;
                      }
                    },
            ),
            const SizedBox(height: 14),
          ],
          Expanded(
            child: _tab == _Tab.records ? _buildRecords() : _buildLinks(),
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    final s = _summary;
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _StatTile(
            label: 'Total sheets',
            value: s.total,
            icon: Icons.description_rounded,
          ),
          _StatTile(
            label: 'Awaiting review',
            value: s.submitted,
            icon: Icons.pending_actions_rounded,
            accent: Brand.warning,
            alert: s.submitted > 0,
          ),
          _StatTile(
            label: 'Reviewed',
            value: s.reviewed,
            icon: Icons.verified_rounded,
            accent: Brand.success,
          ),
          _StatTile(
            label: 'Submitted today',
            value: s.today,
            icon: Icons.today_rounded,
            accent: Brand.info,
          ),
          _StatTile(
            label: 'Active links',
            value: s.activeLinks,
            icon: Icons.link_rounded,
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _scrollMessage(Widget child) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [const SizedBox(height: 48), child],
  );

  Widget _buildRecords() {
    final visible = _records
        .where((r) => !_hiddenRecords.contains(r.id))
        .toList();
    Widget body;
    if (_loading && _records.isEmpty) {
      body = const SkeletonList(count: 6);
    } else if (_error != null && _records.isEmpty) {
      body = _scrollMessage(
        EmptyState(
          label: 'Could not load the sheets',
          hint: _error!,
          icon: Icons.cloud_off_rounded,
          action: FilledButton.icon(
            onPressed: _loadRecords,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ),
      );
    } else {
      body = ListView.separated(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: visible.length + 2,
        separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 14 : 10),
        itemBuilder: (_, i) {
          if (i == 0) return _stats();
          if (i == visible.length + 1) {
            if (visible.isEmpty) {
              final filtered = _search.isNotEmpty || _status.isNotEmpty;
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: EmptyState(
                  label: filtered
                      ? 'No matching sheets'
                      : 'No employment information sheets yet',
                  hint: filtered
                      ? 'Try a different search or status.'
                      : 'Create a share link and send it to an employee.',
                  icon: Icons.assignment_ind_outlined,
                  action: filtered
                      ? null
                      : FilledButton.icon(
                          onPressed: _createLink,
                          icon: const Icon(Icons.add_link_rounded, size: 18),
                          label: const Text('Create share link'),
                        ),
                ),
              );
            }
            if (_loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }
          final r = visible[i - 1];
          return _EntryFade(
            index: i - 1,
            child: _RecordCard(
              record: r,
              opening: _opening == r.id,
              onTap: () => _openRecord(r.id),
              onAction: (action) {
                switch (action) {
                  case 'status':
                    _markReviewed(r);
                  case 'view':
                    _openRecord(r.id);
                  case 'edit':
                    _editRecord(r.id);
                  case 'print':
                    _printRecord(r);
                  case 'delete':
                    _confirmDeleteRecord(r);
                }
              },
            ),
          );
        },
      );
    }
    return RefreshIndicator(onRefresh: _loadRecords, child: body);
  }

  Widget _buildLinks() {
    final links = _links;
    Widget body;
    if (_linksLoading && links == null) {
      body = const SkeletonList(count: 5);
    } else if (_linksError != null && links == null) {
      body = _scrollMessage(
        EmptyState(
          label: 'Could not load the share links',
          hint: _linksError!,
          icon: Icons.cloud_off_rounded,
          action: FilledButton.icon(
            onPressed: _loadLinks,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ),
      );
    } else {
      final visible = (links ?? const <EmploymentLink>[])
          .where((l) => !_hiddenLinks.contains(l.id))
          .toList();
      if (visible.isEmpty) {
        body = _scrollMessage(
          EmptyState(
            label: 'No share links yet.',
            hint: 'Create a link and send it to an employee.',
            icon: Icons.link_off_rounded,
            action: FilledButton.icon(
              onPressed: _createLink,
              icon: const Icon(Icons.add_link_rounded, size: 18),
              label: const Text('Create share link'),
            ),
          ),
        );
      } else {
        body = ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: visible.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final l = visible[i];
            return _EntryFade(
              index: i,
              child: _LinkCard(
                link: l,
                onCopy: () => _copy(l.url),
                onAction: (action) {
                  switch (action) {
                    case 'open':
                      _openUrl(l.url);
                    case 'copy':
                      _copy(l.url);
                    case 'email':
                      _emailLink(l);
                    case 'revoke':
                      _revokeLink(l);
                    case 'delete':
                      _deleteLink(l);
                  }
                },
              ),
            );
          },
        );
      }
    }
    return RefreshIndicator(onRefresh: _loadLinks, child: body);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.alert = false,
    this.last = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color? accent;
  final bool alert;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final tone = accent ?? b.signal;
    return Padding(
      padding: EdgeInsets.only(right: last ? 0 : 10),
      child: SizedBox(
        width: 136,
        child: GlassPanel(
          accent: tone,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: tone.withValues(alpha: alert ? 0.5 : 0.3),
                      ),
                    ),
                    child: Icon(
                      icon,
                      size: 13,
                      color: b.isDark
                          ? tone
                          : Color.lerp(tone, const Color(0xFF0B1B2E), 0.25),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CountUp(
                      value: value,
                      style: text.headlineSmall?.copyWith(
                        color: alert
                            ? (b.isDark
                                  ? Brand.warning
                                  : Color.lerp(
                                      Brand.warning,
                                      const Color(0xFF0B1B2E),
                                      0.35,
                                    ))
                            : b.paper,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(color: b.paperDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.opening,
    required this.onTap,
    required this.onAction,
  });

  final EmploymentRecordBrief record;
  final bool opening;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final r = record;
    final name = r.fullName.trim().isEmpty ? 'Unnamed' : r.fullName;
    final String staffLine;
    if (r.staffName.trim().isNotEmpty) {
      final role = r.staffRole.replaceAll('_', ' ').trim();
      staffLine = role.isEmpty ? r.staffName : '${r.staffName} · $role';
    } else if (r.staffLinkSkipped) {
      staffLine = 'Not a staff account';
    } else {
      staffLine = 'Not linked to a staff account';
    }
    final job = [
      r.jobTitle.trim().isEmpty ? '—' : r.jobTitle.trim(),
      if (r.workLocation.trim().isNotEmpty) r.workLocation.trim(),
    ].join(' · ');
    final deps = r.dependentCount;
    final tone = employmentStatusColor(context, r.status);
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: r.status == 'submitted'
          ? tone.withValues(alpha: 0.4)
          : b.rule,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppAvatar(name: name, size: 42),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      r.staffName.trim().isNotEmpty
                          ? Icons.badge_rounded
                          : Icons.person_off_outlined,
                      size: 13,
                      color: b.paperDim,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        staffLine,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  job,
                  style: text.bodySmall?.copyWith(color: b.paper),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    EmploymentStatusPill(status: r.status),
                    Text(
                      deps == 0
                          ? 'No dependents'
                          : '$deps ${deps == 1 ? 'dependent' : 'dependents'}',
                      style: text.labelMedium,
                    ),
                    if (r.maritalStatus.isNotEmpty)
                      Text(r.maritalStatus, style: text.labelMedium),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Submitted ${employmentDateTime(r.createdAt)}',
                  style: text.labelSmall,
                ),
              ],
            ),
          ),
          if (opening)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Actions',
              icon: Icon(Icons.more_vert_rounded, color: b.paperDim),
              onSelected: onAction,
              itemBuilder: (_) => [
                if (r.status != 'reviewed')
                  const PopupMenuItem(
                    value: 'status',
                    child: _MenuRow(
                      Icons.check_circle_rounded,
                      'Mark as reviewed',
                    ),
                  ),
                const PopupMenuItem(
                  value: 'view',
                  child: _MenuRow(Icons.visibility_rounded, 'View'),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: _MenuRow(Icons.edit_rounded, 'Edit'),
                ),
                const PopupMenuItem(
                  value: 'print',
                  child: _MenuRow(Icons.picture_as_pdf_rounded, 'Print PDF'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: _MenuRow(
                    Icons.delete_outline_rounded,
                    'Delete',
                    danger: true,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label, {this.danger = false});

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final c = danger ? Brand.danger : b.paper;
    return Row(
      children: [
        Icon(icon, size: 19, color: c),
        const SizedBox(width: 12),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c),
        ),
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({
    required this.link,
    required this.onCopy,
    required this.onAction,
  });

  final EmploymentLink link;
  final VoidCallback onCopy;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final l = link;
    final meta = [
      if (l.sentTo.isNotEmpty) 'emailed to ${l.sentTo}',
      if (l.note.isNotEmpty) l.note,
    ].join(' · ');
    final Color statusColor = l.isActive
        ? Brand.success
        : (l.isUsed ? const Color(0xFF64748B) : Brand.danger);
    final type = l.isReusable
        ? 'Shared · ${l.useCount == 0 ? 'no sheets yet' : '${l.useCount} ${l.useCount == 1 ? 'sheet filed' : 'sheets filed'}'}'
        : 'Single use';
    return AppCard(
      radius: Brand.radiusLg,
      borderColor: l.isActive ? statusColor.withValues(alpha: 0.35) : b.rule,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: l.isReusable ? Icons.groups_rounded : Icons.link_rounded,
            color: l.isActive ? b.signal : b.paperDim,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.label.isEmpty ? 'Untitled link' : l.label,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (!l.isConsumed) ...[
                  const SizedBox(height: 8),
                  Material(
                    color: b.surfaceHi,
                    borderRadius: BorderRadius.circular(Brand.radiusSm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Brand.radiusSm),
                      onTap: onCopy,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.copy_rounded,
                                size: 17,
                                color: b.signalInk,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _GlowPill(
                      label: l.statusLabel,
                      color: statusColor,
                      dot: true,
                    ),
                    Text(type, style: text.labelMedium),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Expires ${employmentDateTime(l.expiresAt)}'
                  '${l.lastUsedAt.isNotEmpty ? ' · last used ${employmentDateTime(l.lastUsedAt)}' : ''}',
                  style: text.labelSmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Actions',
            icon: Icon(Icons.more_vert_rounded, color: b.paperDim),
            onSelected: onAction,
            itemBuilder: (_) => [
              if (!l.isConsumed) ...[
                const PopupMenuItem(
                  value: 'open',
                  child: _MenuRow(Icons.open_in_new_rounded, 'Open form'),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: _MenuRow(Icons.copy_rounded, 'Copy link'),
                ),
              ],
              if (l.isActive) ...[
                const PopupMenuItem(
                  value: 'email',
                  child: _MenuRow(Icons.send_rounded, 'Email link'),
                ),
                const PopupMenuItem(
                  value: 'revoke',
                  child: _MenuRow(Icons.block_rounded, 'Revoke'),
                ),
              ],
              const PopupMenuItem(
                value: 'delete',
                child: _MenuRow(
                  Icons.delete_outline_rounded,
                  'Delete',
                  danger: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmailLinkPanel extends StatefulWidget {
  const _EmailLinkPanel({
    super.key,
    required this.service,
    required this.linkId,
    this.initialEmail = '',
    this.initialHint = '',
    this.onSent,
  });

  final EmploymentService service;
  final int linkId;
  final String initialEmail;
  final String initialHint;
  final VoidCallback? onSent;

  @override
  State<_EmailLinkPanel> createState() => _EmailLinkPanelState();
}

class _EmailLinkPanelState extends State<_EmailLinkPanel> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );
  final _subject = TextEditingController(text: kEmploymentMailSubject);
  final _message = TextEditingController(text: kEmploymentMailMessage);
  bool _compose = false;
  bool _sending = false;
  bool _sent = false;
  late String _hint = widget.initialHint;
  bool? _hintOk;

  @override
  void dispose() {
    _email.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() {
        _hint = 'Enter an email address first.';
        _hintOk = false;
      });
      return;
    }
    setState(() {
      _sending = true;
      _hintOk = null;
    });
    final res = await widget.service.emailLink(
      id: widget.linkId,
      email: email,
      subject: _subject.text,
      message: _message.text,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = res.ok;
      _hint =
          res.message ??
          (res.ok ? 'Link sent to $email' : 'Could not send the email.');
      _hintOk = res.ok;
    });
    if (res.ok) {
      employmentToast(context, _hint);
      widget.onSent?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final hintColor = _hintOk == null
        ? b.paperDim
        : (_hintOk! ? Brand.success : Brand.danger);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          onChanged: (_) {
            if (_sent || _hintOk != null) {
              setState(() {
                _sent = false;
                _hintOk = null;
              });
            }
          },
          decoration: const InputDecoration(
            labelText: 'Email it to',
            hintText: 'name@example.com',
            prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
          ),
        ),
        if (_hint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(_hint, style: text.bodySmall?.copyWith(color: hintColor)),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: () => setState(() => _compose = !_compose),
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: Text(_compose ? 'Hide message' : 'Compose message'),
          ),
        ),
        if (_compose) ...[
          const SizedBox(height: 4),
          TextField(
            controller: _subject,
            maxLength: 190,
            decoration: const InputDecoration(
              labelText: 'Subject',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLength: 2000,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Message',
              alignLabelWithHint: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'The link, expiry date and your name are added automatically '
            'below your message.',
            style: text.bodySmall,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: () {
                setState(() {
                  _subject.text = kEmploymentMailSubject;
                  _message.text = kEmploymentMailMessage;
                });
                employmentToast(
                  context,
                  'Subject and message reset to the default',
                );
              },
              child: const Text('Reset to default'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SignalButton(
          label: _sending ? 'Sending…' : (_sent ? 'Sent' : 'Send'),
          icon: _sent ? Icons.check_rounded : Icons.send_rounded,
          busy: _sending,
          onPressed: _sending ? null : _send,
        ),
      ],
    );
  }
}

class _CreateLinkScreen extends StatefulWidget {
  const _CreateLinkScreen({required this.service});

  final EmploymentService service;

  @override
  State<_CreateLinkScreen> createState() => _CreateLinkScreenState();
}

class _CreateLinkScreenState extends State<_CreateLinkScreen> {
  static const _presets = ['7', '15', '30', '60', 'custom'];
  static const _other = -1;

  bool _shared = false;
  List<EmploymentStaff>? _staff;
  int? _picked;
  final _label = TextEditingController();
  final _note = TextEditingController();
  final _days = TextEditingController(text: '30');
  String _preset = '30';
  bool _saving = false;
  bool _created = false;

  EmploymentResult? _result;
  EmploymentStaff? _resultStaff;
  bool _resultShared = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _label.dispose();
    _note.dispose();
    _days.dispose();
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    final res = await widget.service.staff();
    if (!mounted) return;
    setState(() => _staff = res.users);
    if (res.users.isEmpty) {
      employmentToast(
        context,
        res.message ??
            'No staff accounts available — use "Someone else" to type the '
                'name',
      );
    }
  }

  EmploymentStaff? get _pickedStaff {
    final id = _picked;
    if (id == null || id == _other) return null;
    for (final s in _staff ?? const <EmploymentStaff>[]) {
      if (s.id == id) return s;
    }
    return null;
  }

  int get _selectedDays {
    if (_preset == 'custom') {
      final n = int.tryParse(_days.text.trim()) ?? 30;
      return n.clamp(1, 365);
    }
    return int.tryParse(_preset) ?? 30;
  }

  String get _userHint {
    if (_picked == _other) {
      return 'Type the name this link is for — it will not be tied to a staff '
          'account.';
    }
    final s = _pickedStaff;
    if (s == null) {
      return 'Pick a staff account, or choose "Someone else" to type a name.';
    }
    if (s.openLinks > 0) {
      return 'This person already has an unused link — the new one will work '
          'as well.';
    }
    if (s.sheetCount > 0) {
      return 'This person already submitted ${s.sheetCount} '
          '${s.sheetCount == 1 ? 'sheet' : 'sheets'}.';
    }
    return "The link will be labelled with this person's name.";
  }

  bool get _userHintWarn {
    final s = _pickedStaff;
    return s != null && (s.openLinks > 0 || s.sheetCount > 0);
  }

  Future<void> _pickStaff() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StaffPickerSheet(staff: _staff, selected: _picked),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      if (picked != _other) _label.clear();
    });
  }

  Future<void> _generate() async {
    if (!_shared) {
      if (_picked == null) {
        employmentToast(context, 'Pick who this link is for');
        return;
      }
      if (_picked == _other && _label.text.trim().isEmpty) {
        employmentToast(context, 'Type the name this link is for');
        return;
      }
    }
    setState(() => _saving = true);
    final useLabel = _shared || _picked == _other;
    final res = await widget.service.createLink(
      reusable: _shared,
      userId: useLabel ? 0 : (_picked ?? 0),
      label: useLabel ? _label.text : '',
      note: _note.text,
      days: _selectedDays,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.ok) {
      employmentToast(context, res.message ?? 'Could not create the link');
      return;
    }
    final label = (res.data['label'] ?? '').toString();
    setState(() {
      _created = true;
      _result = res;
      _resultShared = _shared;
      _resultStaff = _shared ? null : _pickedStaff;
      _copied = false;
    });
    employmentToast(
      context,
      _shared
          ? 'Shared link created — anyone with it can file a sheet'
          : 'Share link created for ${label.isEmpty ? 'the employee' : label}',
    );
    _loadStaff();
  }

  void _another() {
    setState(() {
      _result = null;
      _resultStaff = null;
      _shared = false;
      _picked = null;
      _label.clear();
      _note.clear();
      _days.text = '30';
      _preset = '30';
      _copied = false;
    });
  }

  void _copyNew(String url) {
    Clipboard.setData(ClipboardData(text: url));
    employmentToast(context, 'Link copied');
    _copiedTimer?.cancel();
    setState(() => _copied = true);
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_created);
      },
      child: StationScaffold(
        stationLabel: 'Employment Info',
        title: result == null ? 'Create a fill-up link' : 'Link ready',
        subtitle: result != null
            ? ''
            : (_shared
                  ? 'One link for a whole batch — every person who opens it '
                        'files their own sheet.'
                  : 'Send it to one person. It closes the moment they submit.'),
        compact: true,
        showBottomBrand: false,
        onBack: () => Navigator.of(context).pop(_created),
        child: result == null ? _buildForm() : _buildDone(result),
      ),
    );
  }

  Widget _buildForm() {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final staff = _pickedStaff;
    final showLabel = _shared || _picked == _other;
    final closes = DateTime.now().add(Duration(days: _selectedDays));
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SectionHeader(title: 'Who can use this link?'),
        ChoicePills<bool>(
          options: const [false, true],
          value: _shared,
          onChanged: (v) => setState(() {
            _shared = v;
            _label.clear();
          }),
          labelOf: (v) => v ? 'Many people' : 'One person',
        ),
        const SizedBox(height: 8),
        Text(
          _shared
              ? 'The link stays open until it expires or you revoke it — as '
                    'many people as you like can fill it in.'
              : 'One link, one sheet — it closes the moment they submit.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_shared) ...[
                Text('Who is this for?', style: text.labelLarge),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
                  onTap: _staff == null ? null : _pickStaff,
                  child: InputDecorator(
                    isEmpty: _picked == null,
                    decoration: InputDecoration(
                      hintText: _staff == null
                          ? 'Loading staff…'
                          : 'Select a staff account…',
                      prefixIcon: const Icon(Icons.person_rounded, size: 20),
                      suffixIcon: Icon(
                        Icons.expand_more_rounded,
                        color: b.paperDim,
                      ),
                    ),
                    child: _picked == null
                        ? null
                        : Text(
                            _picked == _other
                                ? 'Someone else — type a name'
                                : (staff?.name ?? ''),
                            style: text.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _userHint,
                  style: text.bodySmall?.copyWith(
                    color: _userHintWarn ? b.signalInk : null,
                  ),
                ),
                if (showLabel) const SizedBox(height: 16),
              ],
              if (showLabel) ...[
                TextField(
                  controller: _label,
                  maxLength: 191,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: _shared
                        ? 'Name this link (optional)'
                        : 'Name on the link',
                    hintText: _shared
                        ? 'e.g. New hires — Batch 1'
                        : 'e.g. Juan Dela Cruz — new hire',
                    counterText: '',
                  ),
                ),
                if (_shared) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Only for your own list of links — everyone fills in '
                    'their own name on the form.',
                    style: text.bodySmall,
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Link expires after'),
        ChoicePills<String>(
          options: _presets,
          value: _preset,
          onChanged: (v) => setState(() => _preset = v),
          labelOf: (v) => v == 'custom' ? 'Custom' : '$v days',
        ),
        if (_preset == 'custom') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Number of days',
              helperText: '1 to 365',
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'If nobody fills it in, the link stops working on '
          '${employmentLongDate(closes)}.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _note,
          maxLength: 255,
          decoration: const InputDecoration(
            labelText: 'Internal note (optional)',
            hintText: 'Only visible to admins',
            counterText: '',
          ),
        ),
        const SizedBox(height: 24),
        SignalButton(
          label: _saving ? 'Generating…' : 'Generate link',
          icon: Icons.link_rounded,
          busy: _saving,
          onPressed: _saving ? null : _generate,
        ),
        const SizedBox(height: 10),
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(_created),
        ),
      ],
    );
  }

  Widget _buildDone(EmploymentResult result) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final url = (result.data['url'] ?? '').toString();
    final id = (result.data['id'] is num)
        ? (result.data['id'] as num).toInt()
        : int.tryParse('${result.data['id']}') ?? 0;
    final label = (result.data['label'] ?? '').toString();
    final expires = parseEmploymentDate(
      (result.data['expires_at'] ?? '').toString(),
    );
    final staff = _resultStaff;
    final emailHint = _resultShared
        ? 'Send it to whoever should pass it around.'
        : (staff != null && staff.email.isNotEmpty
              ? 'Taken from their staff account — change it if needed.'
              : 'No email on file, type where it should go.');
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        GlassPanel(
          accent: Brand.success,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Brand.success.withValues(alpha: 0.18),
                  border: Border.all(
                    color: Brand.success.withValues(alpha: 0.5),
                  ),
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 28,
                  color: b.isDark
                      ? Brand.success
                      : Color.lerp(
                          Brand.success,
                          const Color(0xFF0B1B2E),
                          0.25,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Link ready for '
                '${_resultShared ? 'everyone you share it with' : (label.isEmpty ? 'this employee' : label)}',
                style: text.titleMedium?.copyWith(color: b.paper),
                textAlign: TextAlign.center,
              ),
              if (expires != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${_resultShared ? 'Unlimited submissions' : 'Single use'}'
                  ' · expires ${employmentLongDate(expires)}',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader(title: 'Share this link'),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  url,
                  style: text.bodySmall?.copyWith(color: b.paper),
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _copyNew(url),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: _copied ? Brand.success : null,
                ),
                icon: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  size: 18,
                ),
                label: Text(_copied ? 'Copied' : 'Copy'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionHeader(
          title: 'or send it for them',
          trailing: Text('Email', style: text.labelMedium),
        ),
        AppCard(
          child: _EmailLinkPanel(
            key: ValueKey('email-$id'),
            service: widget.service,
            linkId: id,
            initialEmail: _resultShared ? '' : (staff?.email ?? ''),
            initialHint: emailHint,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                label: 'Preview form',
                icon: Icons.open_in_new_rounded,
                onPressed: () async {
                  final uri = Uri.tryParse(url);
                  if (uri == null) return;
                  final ok = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok && mounted) {
                    employmentToast(context, 'Could not open the form');
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GhostButton(
                label: 'Create another',
                icon: Icons.add_rounded,
                onPressed: _another,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SignalButton(
          label: 'Done',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

class _StaffPickerSheet extends StatefulWidget {
  const _StaffPickerSheet({required this.staff, required this.selected});

  final List<EmploymentStaff>? staff;
  final int? selected;

  @override
  State<_StaffPickerSheet> createState() => _StaffPickerSheetState();
}

class _StaffPickerSheetState extends State<_StaffPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final q = _query.trim().toLowerCase();
    final list = (widget.staff ?? const <EmploymentStaff>[]).where((u) {
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          u.username.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();

    Widget row({
      required int value,
      required String title,
      String subtitle = '',
      bool warn = false,
      Widget? leading,
    }) {
      final selected = widget.selected == value;
      return Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  ?leading,
                  if (leading != null) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: text.bodySmall?.copyWith(
                              color: warn ? b.signalInk : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_rounded, color: b.signal, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Who is this for?', style: text.titleLarge),
              const SizedBox(height: 12),
              AppSearchField(
                controller: _search,
                hint: 'Search staff by name…',
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: ListView.separated(
                    itemCount: list.length + 1,
                    separatorBuilder: (_, _) => const Hairline(),
                    itemBuilder: (_, i) {
                      if (i == list.length) {
                        return row(
                          value: -1,
                          title: 'Someone else — type a name',
                          leading: IconTile(
                            icon: Icons.edit_rounded,
                            color: b.paperDim,
                            size: 36,
                            iconSize: 18,
                          ),
                        );
                      }
                      final u = list[i];
                      final suffix = [
                        if (u.role.isNotEmpty) u.role,
                        if (u.sheetCount > 0)
                          '${u.sheetCount} ${u.sheetCount == 1 ? 'sheet' : 'sheets'}',
                        if (u.openLinks > 0) 'link active',
                      ].join(' · ');
                      return row(
                        value: u.id,
                        title: u.name,
                        subtitle: suffix,
                        warn: u.openLinks > 0 || u.sheetCount > 0,
                        leading: AppAvatar(name: u.name, size: 36),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowPill extends StatelessWidget {
  const _GlowPill({required this.label, required this.color, this.dot = false});

  final String label;
  final Color color;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final ink = b.isDark
        ? color
        : Color.lerp(color, const Color(0xFF0B1B2E), 0.3)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

class _EntryFade extends StatelessWidget {
  const _EntryFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return child;
    final delay = (index.clamp(0, 7)) * 55;
    final total = 300 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
