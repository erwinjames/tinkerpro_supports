import 'package:flutter/material.dart';

import '../services/live_sync.dart';
import '../services/ops_data_service.dart';
import '../services/services.dart';
import '../theme.dart';
import 'ops_charts.dart';
import 'ops_ticket_detail.dart';
import 'ops_widgets.dart';
import '../widgets/tp_loader.dart';

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key, required this.service});
  final TicketService service;

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

const _ranges = <(String, String)>[
  ('0', 'All time'),
  ('7', 'Last 7 days'),
  ('30', 'Last 30 days'),
  ('90', 'Last 90 days'),
];

class _TicketListScreenState extends State<TicketListScreen>
    with LiveRefresh<TicketListScreen> {
  late final OpsDataService _svc = OpsDataService(widget.service.api);
  late final OpsTicketCtx _ctx = OpsTicketCtx(
    svc: _svc,
    userId: widget.service.api.userId ?? 0,
    agentName: widget.service.api.username ?? '',
  );
  final _search = TextEditingController();
  List<Json> _tickets = const [];
  Json _dash = const {};
  bool _loading = true;
  String _status = '';
  String _priority = '';
  String _quick = 'all';
  String _lbRange = '0';
  String _storeRange = '0';
  List<Json>? _lb;
  List<Json>? _stores;

  @override
  void initState() {
    super.initState();
    _load();
    _loadLeaderboard();
    _loadStores();
    _svc.ticketMeta().then((m) {
      final n = opsStr(m['agent_name']);
      if (n.isNotEmpty) _ctx.agentName = n;
    });
    _svc.agents().then((a) => _ctx.agents = a);
    _svc.helpTopics().then((h) => _ctx.helpTopics = h);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([_svc.tickets(), _svc.ticketDashboard()]);
    if (!mounted) return;
    setState(() {
      _tickets = results[0] as List<Json>;
      _dash = results[1] as Json;
      _loading = false;
    });
  }

  Future<void> _loadLeaderboard() async {
    final r = await _svc.resolveLeaderboard(_lbRange);
    if (mounted) setState(() => _lb = r);
  }

  Future<void> _loadStores() async {
    final r = await _svc.storeBreakdown(_storeRange);
    if (mounted) setState(() => _stores = r);
  }

  Future<Json?> _refetch(int id) async {
    await _load();
    _loadLeaderboard();
    _loadStores();
    final hit = _tickets.where((t) => opsInt(t['id']) == id);
    return hit.isEmpty ? null : hit.first;
  }

  Future<void>? _liveFuture;

  @override
  List<String> get liveKeys => const ['ticket'];

  @override
  void onLiveChange() => _liveReload();

  Future<void> _liveReload() {
    return _liveFuture ??= Future.wait([
      _load(),
      _loadLeaderboard(),
      _loadStores(),
    ]).whenComplete(() => _liveFuture = null);
  }

  Future<Json?> _liveLookup(int id) async {
    await _liveReload();
    if (_tickets.isEmpty) throw StateError('empty');
    final hit = _tickets.where((t) => opsInt(t['id']) == id);
    return hit.isEmpty ? null : hit.first;
  }

  bool _isMine(Json t) => opsStr(t['assigned_agent_id']) == '${_ctx.userId}';

  List<Json> get _filtered {
    final q = _search.text.toLowerCase().trim();
    return _tickets.where((t) {
      final okSearch = q.isEmpty ||
          opsStr(t['subject']).toLowerCase().contains(q) ||
          opsStr(t['customer_name']).toLowerCase().contains(q) ||
          opsStr(t['description']).toLowerCase().contains(q);
      final okStatus = _status.isEmpty || opsStr(t['status']) == _status;
      final okPri = _priority.isEmpty || opsStr(t['priority']) == _priority;
      var okQuick = true;
      if (_quick == 'unassigned') okQuick = !opsHasAgent(t);
      if (_quick == 'mine') okQuick = _isMine(t);
      return okSearch && okStatus && okPri && okQuick;
    }).toList();
  }

  void _open(Json t) {
    OpsTicketDetail.show(
      context,
      ctx: _ctx,
      ticket: t,
      refetch: _refetch,
      liveRefetch: _liveLookup,
    );
  }

  Future<void> _accept(Json t) async {
    if (await opsOpenAccept(context, _ctx, t)) _refetch(opsInt(t['id']));
  }

  final Set<int> _resolving = {};

  Future<void> _resolve(Json t) async {
    final id = opsInt(t['id']);
    setState(() => _resolving.add(id));
    final r = await _svc.resolveTicket(id);
    if (!mounted) return;
    setState(() => _resolving.remove(id));
    opsToast(context, r.ok ? 'Ticket resolved' : r.message, error: !r.ok);
    _refetch(id);
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final list = _filtered;
    final unassigned = _tickets.where((t) => !opsHasAgent(t)).length;
    final mine = _tickets.where(_isMine).length;
    return Container(
      color: b.canvas,
      child: RefreshIndicator(
        onRefresh: () async {
          await _load();
          _loadLeaderboard();
          _loadStores();
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header(context)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
              sliver: SliverList.list(children: [
                SizedBox(
                  height: 300,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: _ChartCard(
                        title: 'Top resolvers',
                        sub: 'Tickets marked resolved, by agent.',
                        range: _lbRange,
                        onRange: (v) {
                          setState(() => _lbRange = v);
                          _loadLeaderboard();
                        },
                        child: _lb == null
                            ? const SizedBox()
                            : _lb!.isEmpty
                                ? const OpsChartEmpty(
                                    icon: Icons.bar_chart,
                                    text: 'No resolved tickets yet for this range.')
                                : OpsBarChart(
                                    unit: 'resolved',
                                    bars: [
                                      for (final r in _lb!)
                                        OpsBar(
                                          opsStr(r['agent_name']),
                                          double.tryParse(opsStr(r['resolved'])) ?? 0,
                                          opsColorFor(opsStr(r['agent_name']),
                                              opsResolverPalette),
                                        ),
                                    ],
                                  ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _ChartCard(
                        title: 'Tickets by store',
                        sub: 'Ticket volume per store / tenant.',
                        range: _storeRange,
                        onRange: (v) {
                          setState(() => _storeRange = v);
                          _loadStores();
                        },
                        child: _stores == null
                            ? const SizedBox()
                            : _stores!.isEmpty
                                ? const OpsChartEmpty(
                                    icon: Icons.storefront_outlined,
                                    text: 'No tickets yet for this range.')
                                : OpsBarChart(
                                    unit: 'tickets',
                                    bars: [
                                      for (final r in _stores!)
                                        OpsBar(
                                          opsStr(r['store']),
                                          double.tryParse(opsStr(r['count'])) ?? 0,
                                          opsColorFor(
                                              opsStr(r['store']), opsStorePalette),
                                        ),
                                    ],
                                  ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: b.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: b.rule),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText:
                                'Search by subject, customer, or description…',
                            prefixIcon: Icon(Icons.search, size: 18),
                            prefixIconConstraints: BoxConstraints(minWidth: 38),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OpsSelect<String>(
                      value: _status,
                      height: 40,
                      items: const [
                        ('', 'All Status'),
                        ('new', 'New'),
                        ('progress', 'In Progress'),
                        ('resolved', 'Resolved'),
                      ],
                      onChanged: (v) => setState(() => _status = v),
                    ),
                    const SizedBox(width: 8),
                    OpsSelect<String>(
                      value: _priority,
                      height: 40,
                      items: const [
                        ('', 'All Priority'),
                        ('high', 'High'),
                        ('medium', 'Medium'),
                        ('low', 'Low'),
                      ],
                      onChanged: (v) => setState(() => _priority = v),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  OpsPill(
                    label: 'All',
                    count: '${_tickets.length}',
                    active: _quick == 'all',
                    onTap: () => setState(() => _quick = 'all'),
                  ),
                  OpsPill(
                    label: 'Unassigned',
                    count: '$unassigned',
                    active: _quick == 'unassigned',
                    onTap: () => setState(() => _quick = 'unassigned'),
                  ),
                  OpsPill(
                    label: 'Assigned to me',
                    count: '$mine',
                    active: _quick == 'mine',
                    onTap: () => setState(() => _quick = 'mine'),
                  ),
                ]),
                const SizedBox(height: 16),
              ]),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: TpLoader()),
                ),
              )
            else if (list.isEmpty)
              SliverToBoxAdapter(child: _empty(context))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final t = list[i];
                    return _TicketCard(
                      ticket: t,
                      svc: _svc,
                      mine: _isMine(t),
                      resolving: _resolving.contains(opsInt(t['id'])),
                      onOpen: () => _open(t),
                      onAccept: () => _accept(t),
                      onResolve: () => _resolve(t),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: b.rule),
        ),
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Brand.signal.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inbox_outlined, color: Brand.signal),
          ),
          const SizedBox(height: 12),
          Text('No tickets found',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: b.paper)),
          const SizedBox(height: 4),
          Text('Try adjusting your filters or search keywords.',
              style: TextStyle(fontSize: 13.5, color: b.paperDim)),
        ]),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final b = context.brand;
    String v(String k) => opsStr(_dash[k]).isEmpty ? '0' : opsStr(_dash[k]);
    return Container(
      decoration: BoxDecoration(
        color: b.canvas,
        border: Border(bottom: BorderSide(color: b.rule)),
      ),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 22),
          child: LayoutBuilder(builder: (context, box) {
            final intro = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TINKERPRO · SUPPORT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.8,
                    color: Brand.signal,
                  ),
                ),
                const SizedBox(height: 14),
                Text('Manage and track customer support requests',
                    style: TextStyle(fontSize: 14, color: b.paperDim)),
              ],
            );
            final tiles = [
              _StatTile(label: 'New', value: v('new_ticket'),
                  icon: Icons.inbox, color: opsBlue),
              _StatTile(label: 'In Progress', value: v('in_progress_ticket'),
                  icon: Icons.schedule, color: opsAmber),
              _StatTile(label: 'Resolved', value: v('resolved_ticket'),
                  icon: Icons.check_circle, color: opsGreen),
              _StatTile(label: 'Total', value: v('total_tickets'),
                  icon: Icons.layers, color: Brand.signal),
            ];
            if (box.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  intro,
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 10, children: tiles),
                ],
              );
            }
            return Row(children: [
              Expanded(child: intro),
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                tiles[i],
              ],
            ]);
          }),
        ),
        Positioned(
          left: 0,
          bottom: 0,
          child: Container(width: 64, height: 2, color: Brand.signal),
        ),
      ]),
    );
  }
}

class _StatTile extends StatefulWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  State<_StatTile> createState() => _StatTileState();
}

class _StatTileState extends State<_StatTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _hover ? Brand.signal : b.rule),
          boxShadow: _hover
              ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 4))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(widget.icon, size: 17, color: widget.color),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label.toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: b.paperDim)),
            const SizedBox(height: 2),
            Text(widget.value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: b.paper)),
          ]),
        ]),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.sub,
    required this.range,
    required this.onRange,
    required this.child,
  });

  final String title;
  final String sub;
  final String range;
  final ValueChanged<String> onRange;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: b.rule),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: b.paper)),
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 13, color: b.paperDim)),
            ]),
          ),
          OpsSelect<String>(value: range, items: _ranges, onChanged: onRange),
        ]),
        const SizedBox(height: 16),
        Expanded(child: child),
      ]),
    );
  }
}

class _TicketCard extends StatefulWidget {
  const _TicketCard({
    required this.ticket,
    required this.svc,
    required this.mine,
    required this.resolving,
    required this.onOpen,
    required this.onAccept,
    required this.onResolve,
  });

  final Json ticket;
  final OpsDataService svc;
  final bool mine;
  final bool resolving;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onResolve;

  @override
  State<_TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<_TicketCard> {
  bool _hover = false;

  Widget? _action() {
    final t = widget.ticket;
    if (!opsHasAgent(t)) {
      if (opsIsClosed(t)) return null;
      return OpsButton(
          label: 'Accept',
          icon: Icons.check,
          color: Brand.signal,
          onPressed: widget.onAccept);
    }
    if (widget.mine) {
      if (opsStr(t['status']) == 'resolved') return null;
      return OpsButton(
        label: widget.resolving ? 'Resolving…' : 'Resolve',
        icon: Icons.check_circle,
        color: opsGreen,
        busy: widget.resolving,
        onPressed: widget.onResolve,
      );
    }
    final who = opsStr(t['agent_name']);
    return Tooltip(
      message:
          '${opsClaimedVerb(t)} by ${who.isEmpty ? 'another agent' : who} — ask them to reassign it to you',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: OpsButton(
          label: '${opsClaimedVerb(t)}${who.isNotEmpty ? ' by $who' : ''}',
          icon: Icons.how_to_reg,
          color: Colors.grey,
          dashedMuted: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final t = widget.ticket;
    final pr = opsStr(t['priority']);
    final stripe = switch (pr) {
      'high' => opsRed,
      'medium' => opsAmber,
      'low' => opsGreen,
      _ => b.rule,
    };
    final atts = (t['attachments'] is List)
        ? (t['attachments'] as List).whereType<Map>().toList()
        : const <Map>[];
    final email = opsStr(t['customer_email']);
    final agent = opsStr(t['agent_name']);
    final action = _action();
    final muted = TextStyle(fontSize: 12, color: b.paperDim);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: b.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hover ? Brand.signal : b.rule),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 12,
                        offset: Offset(0, 4))
                  ]
                : null,
          ),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: stripe),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OpsAvatar(name: opsStr(t['customer_name'])),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  opsStr(t['subject']).isEmpty
                                      ? 'Untitled'
                                      : opsStr(t['subject']),
                                  style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600,
                                      color: b.paper,
                                      height: 1.35),
                                ),
                                ...opsTicketBadges(t),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              opsStr(t['description']).replaceAll(RegExp(r'\s+'), ' ').trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13.5, color: b.paperDim, height: 1.5),
                            ),
                            if (atts.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final a in atts.take(4))
                                  OpsAttachmentThumb(
                                    svc: widget.svc,
                                    path: opsStr(a['file_path']),
                                    name: opsStr(a['original_name']),
                                  ),
                                if (atts.length > 4)
                                  OpsAttachmentThumb(
                                    svc: widget.svc,
                                    path: opsStr(atts[4]['file_path']),
                                    name: opsStr(atts[4]['original_name']),
                                    moreCount: atts.length - 4,
                                  ),
                              ]),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 14,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      opsStr(t['customer_name']).isEmpty
                                          ? 'Unknown'
                                          : opsStr(t['customer_name']),
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: b.paper),
                                    ),
                                    if (email.isNotEmpty)
                                      Text(email,
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: b.paperDim)),
                                  ],
                                ),
                                if (agent.isNotEmpty)
                                  Tooltip(
                                    message: 'Assigned agent',
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.how_to_reg,
                                              size: 14, color: opsGreen),
                                          const SizedBox(width: 5),
                                          Text(agent,
                                              style: const TextStyle(
                                                  color: opsGreen,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12)),
                                        ]),
                                  ),
                                Tooltip(
                                  message: opsFullDate(opsStr(t['created_at'])),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.access_time,
                                        size: 13, color: b.paperDim),
                                    const SizedBox(width: 5),
                                    Text(opsTimeAgo(opsStr(t['created_at'])),
                                        style: muted),
                                  ]),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (action != null) ...[
                        const SizedBox(width: 16),
                        action,
                      ],
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
