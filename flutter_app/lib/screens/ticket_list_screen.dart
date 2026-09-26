import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key, required this.service, this.onBack});
  final TicketService service;
  final VoidCallback? onBack;

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends State<TicketListScreen> {
  List<TicketBrief> _rows = const [];
  bool _loading = true;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _status = 'all';

  static const _filters = <(String, String)>[
    ('all', 'All'),
    ('new', 'New'),
    ('assigned', 'Assigned'),
    ('in_progress', 'In progress'),
    ('resolved', 'Resolved'),
    ('closed', 'Closed'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.list();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  List<TicketBrief> get _visible {
    final q = _query.trim().toLowerCase();
    return _rows.where((t) {
      if (_status != 'all' && t.status != _status) return false;
      if (q.isEmpty) return true;
      return t.subject.toLowerCase().contains(q) ||
          t.customerName.toLowerCase().contains(q) ||
          t.customerEmail.toLowerCase().contains(q) ||
          t.id.toString().contains(q);
    }).toList();
  }

  static String _humanize(String s) {
    final v = s.replaceAll('_', ' ').trim();
    if (v.isEmpty) return v;
    return v[0].toUpperCase() + v.substring(1);
  }

  static Color _priorityColor(String p) {
    switch (p.toLowerCase()) {
      case 'high':
        return Brand.danger;
      case 'medium':
        return Brand.warning;
      default:
        return Brand.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final rows = _visible;
    final urgent = _rows
        .where((t) => t.priority.toLowerCase() == 'high')
        .length;
    final fresh = _rows.where((t) => t.status == 'new').length;
    return StationScaffold(
      stationNumber: '05',
      stationLabel: 'Tickets',
      title: 'Support queue',
      showBottomBrand: false,
      onBack: widget.onBack,
      backAlways: widget.onBack != null,
      trailing: StationAction(
        icon: Icons.refresh_rounded,
        tooltip: 'Refresh',
        onPressed: _load,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QueuePulse(
            loading: _loading,
            total: _rows.length,
            fresh: fresh,
            urgent: urgent,
          ),
          const SizedBox(height: 14),
          AppSearchField(
            controller: _search,
            hint: 'Search tickets',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          ChoicePills<(String, String)>(
            options: _filters,
            value: _filters.firstWhere(
              (f) => f.$1 == _status,
              orElse: () => _filters.first,
            ),
            labelOf: (f) => f.$2,
            countOf: _loading
                ? null
                : (f) => f.$1 == 'all'
                      ? _rows.length
                      : _rows.where((t) => t.status == f.$1).length,
            onChanged: (f) => setState(() => _status = f.$1),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: b.signal,
              backgroundColor: b.surface,
              onRefresh: _load,
              child: _loading
                  ? const SkeletonList()
                  : rows.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 48),
                        _rows.isEmpty
                            ? const EmptyState(
                                icon: Icons.confirmation_number_rounded,
                                label: 'Inbox zero',
                                hint:
                                    'No open tickets right now. Pull down to refresh.',
                              )
                            : const EmptyState(
                                icon: Icons.search_off_rounded,
                                label: 'No matching tickets',
                                hint: 'Try a different search or filter.',
                              ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _Rise(
                        index: i,
                        child: _TicketCard(
                          ticket: rows[i],
                          statusLabel: _humanize(rows[i].status),
                          priorityLabel: _humanize(rows[i].priority),
                          priorityColor: _priorityColor(rows[i].priority),
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

class _QueuePulse extends StatelessWidget {
  const _QueuePulse({
    required this.loading,
    required this.total,
    required this.fresh,
    required this.urgent,
  });

  final bool loading;
  final int total;
  final int fresh;
  final int urgent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GlassPanel(
      accent: urgent > 0 ? Brand.danger : b.signal,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live queue',
                  style: text.labelMedium?.copyWith(
                    color: b.signal,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 260),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SizeTransition(
                      sizeFactor: anim,
                      axis: Axis.horizontal,
                      alignment: const Alignment(-1, -1),
                      child: child,
                    ),
                  ),
                  child: Text(
                    loading ? '—' : '$total open',
                    key: ValueKey<String>(loading ? 'load' : '$total'),
                    style: text.headlineSmall?.copyWith(color: b.paper),
                  ),
                ),
              ],
            ),
          ),
          if (!loading) ...[
            GlowBadge(
              label: '$fresh new',
              color: Brand.info,
              icon: Icons.fiber_new_rounded,
            ),
            const SizedBox(width: 8),
            GlowBadge(
              label: '$urgent high',
              color: urgent > 0 ? Brand.danger : b.signal,
              icon: Icons.priority_high_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({
    required this.ticket,
    required this.statusLabel,
    required this.priorityLabel,
    required this.priorityColor,
  });

  final TicketBrief ticket;
  final String statusLabel;
  final String priorityLabel;
  final Color priorityColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final t = ticket;
    final urgent = t.priority == 'high' || t.status == 'new';
    final statusColor = StatusPill.colorFor(t.status);
    final accent = urgent ? priorityColor : statusColor;
    return AppCard(
      radius: Brand.radiusLg,
      borderColor: urgent ? accent.withValues(alpha: 0.45) : null,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(
            icon: Icons.confirmation_number_rounded,
            color: urgent ? b.signal : statusColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.subject,
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  t.customerName.isEmpty ? 'No customer' : t.customerName,
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (statusLabel.isNotEmpty)
                      GlowBadge(
                        label: statusLabel,
                        color: statusColor,
                        icon: Icons.circle,
                      ),
                    if (priorityLabel.isNotEmpty)
                      GlowBadge(
                        label: priorityLabel,
                        color: priorityColor,
                        icon: Icons.flag_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: b.tint(accent, 0.1),
                  borderRadius: BorderRadius.circular(Brand.radiusSm),
                  border: Border.all(color: accent.withValues(alpha: 0.35)),
                ),
                child: Text(
                  '#${t.id}',
                  style: text.labelLarge?.copyWith(
                    color: b.isDark ? b.paper : Brand.navy,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  t.createdAt,
                  style: text.labelMedium,
                  textAlign: TextAlign.end,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Rise extends StatefulWidget {
  const _Rise({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.07),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
      return;
    }
    final steps = widget.index < 0 ? 0 : (widget.index > 7 ? 7 : widget.index);
    if (steps == 0) {
      _c.forward();
      return;
    }
    Future<void>.delayed(Duration(milliseconds: 45 * steps), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}
