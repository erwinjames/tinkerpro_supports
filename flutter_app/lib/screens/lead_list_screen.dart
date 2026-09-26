import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/notification_center.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'notification_panel.dart';

class LeadListScreen extends StatefulWidget {
  const LeadListScreen({
    super.key,
    required this.service,
    required this.notifications,
    this.onBack,
  });
  final LeadService service;
  final NotificationCenter notifications;
  final VoidCallback? onBack;

  @override
  State<LeadListScreen> createState() => _LeadListScreenState();
}

class _LeadListScreenState extends State<LeadListScreen> {
  List<LeadBrief> _rows = const [];
  bool _loading = true;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
    widget.notifications.addListener(_onNotificationsChanged);
  }

  @override
  void dispose() {
    widget.notifications.removeListener(_onNotificationsChanged);
    _search.dispose();
    super.dispose();
  }

  void _onNotificationsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.list();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
    widget.notifications.refresh();
  }

  List<LeadBrief> get _visible {
    final q = _query.trim().toLowerCase();
    return _rows.where((l) {
      if (_filter == 'noted' && l.note.trim().isEmpty) return false;
      if (_filter == 'unnoted' && l.note.trim().isNotEmpty) return false;
      if (q.isEmpty) return true;
      return [
        l.name,
        l.email,
        l.phone,
        l.location,
        l.businessType,
        l.selectedPackage,
      ].any((f) => f.toLowerCase().contains(q));
    }).toList();
  }

  void _open(LeadBrief l) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LeadDetailSheet(lead: l, service: widget.service),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final rows = _visible;
    const filters = <(String, String)>[
      ('all', 'All'),
      ('unnoted', 'Needs note'),
      ('noted', 'With note'),
    ];
    return StationScaffold(
      stationNumber: '06',
      stationLabel: 'Leads',
      title: 'Inbound',
      showBottomBrand: false,
      onBack: widget.onBack,
      backAlways: widget.onBack != null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NotificationBell(
            count: widget.notifications.unseenCount,
            onPressed: () =>
                NotificationPanel.show(context, widget.notifications),
            tooltip: 'Notifications',
          ),
          const SizedBox(width: 8),
          StationAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _search,
            hint: 'Search leads',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          ChoicePills<(String, String)>(
            options: filters,
            value: filters.firstWhere(
              (f) => f.$1 == _filter,
              orElse: () => filters.first,
            ),
            labelOf: (f) => f.$2,
            countOf: _loading
                ? null
                : (f) => switch (f.$1) {
                    'noted' =>
                      _rows.where((l) => l.note.trim().isNotEmpty).length,
                    'unnoted' =>
                      _rows.where((l) => l.note.trim().isEmpty).length,
                    _ => _rows.length,
                  },
            onChanged: (f) => setState(() => _filter = f.$1),
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
                                icon: Icons.move_to_inbox_rounded,
                                label: 'No leads yet',
                                hint:
                                    'Forms submitted on the public site will appear here.',
                              )
                            : const EmptyState(
                                icon: Icons.search_off_rounded,
                                label: 'No matching leads',
                                hint: 'Try a different search or filter.',
                              ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final l = rows[i];
                        return _Rise(
                          index: i,
                          child: _LeadTile(lead: l, onTap: () => _open(l)),
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

class _LeadTile extends StatelessWidget {
  const _LeadTile({required this.lead, required this.onTap});
  final LeadBrief lead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final name = lead.name.isEmpty ? 'No name' : lead.name;
    final fresh = lead.note.trim().isEmpty;
    final contact = [
      lead.email,
      lead.phone,
    ].where((e) => e.isNotEmpty).join(' · ');
    return AppCard(
      onTap: onTap,
      radius: Brand.radiusLg,
      borderColor: fresh ? b.signal.withValues(alpha: 0.42) : null,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: name),
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
                if (contact.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    contact,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (lead.businessType.isNotEmpty ||
                    lead.selectedPackage.isNotEmpty ||
                    fresh) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (fresh)
                        const GlowBadge(
                          label: 'Needs note',
                          icon: Icons.bolt_rounded,
                        ),
                      if (lead.businessType.isNotEmpty)
                        GlowBadge(
                          label: lead.businessType,
                          color: Brand.info,
                          icon: Icons.storefront_rounded,
                        ),
                      if (lead.selectedPackage.isNotEmpty)
                        GlowBadge(
                          label: lead.selectedPackage,
                          color: Brand.signal,
                          icon: Icons.inventory_2_rounded,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 96),
            child: Text(
              lead.createdAt,
              style: text.labelMedium,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeadDetailSheet extends StatefulWidget {
  const _LeadDetailSheet({required this.lead, required this.service});
  final LeadBrief lead;
  final LeadService service;

  @override
  State<_LeadDetailSheet> createState() => _LeadDetailSheetState();
}

class _LeadDetailSheetState extends State<_LeadDetailSheet> {
  late final TextEditingController _note = TextEditingController(
    text: widget.lead.note,
  );
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await widget.service.updateNote(
      widget.lead.id,
      _note.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Note saved' : 'Note could not be saved')),
    );
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final lead = widget.lead;
    final name = lead.name.isEmpty ? 'No name' : lead.name;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassPanel(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Lead',
                      style: text.labelMedium?.copyWith(
                        color: context.brand.signal,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        AppAvatar(name: name, size: 52),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: text.titleLarge?.copyWith(
                                  color: context.brand.paper,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Lead #${lead.id.toString().padLeft(2, '0')}'
                                '${lead.createdAt.isEmpty ? '' : ' · ${lead.createdAt}'}',
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (lead.businessType.isNotEmpty ||
                        lead.selectedPackage.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (lead.businessType.isNotEmpty)
                            GlowBadge(
                              label: lead.businessType,
                              color: Brand.info,
                              icon: Icons.storefront_rounded,
                            ),
                          if (lead.selectedPackage.isNotEmpty)
                            GlowBadge(
                              label: lead.selectedPackage,
                              color: Brand.signal,
                              icon: Icons.inventory_2_rounded,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (lead.email.isNotEmpty ||
                  lead.phone.isNotEmpty ||
                  lead.location.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeader(title: 'Contact'),
                AppCard(
                  radius: Brand.radiusLg,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (lead.email.isNotEmpty)
                        StationDataRow(
                          label: 'Email',
                          value: lead.email,
                          trailingIcon: Icons.mail_outline_rounded,
                          onTap: () => _launch(
                            context,
                            Uri(scheme: 'mailto', path: lead.email),
                            failure: 'No mail app available.',
                          ),
                        ),
                      if (lead.phone.isNotEmpty)
                        StationDataRow(
                          label: 'Phone',
                          value: lead.phone,
                          trailingIcon: Icons.phone_rounded,
                          onTap: () => _launch(
                            context,
                            Uri(
                              scheme: 'tel',
                              path: lead.phone.replaceAll(
                                RegExp(r'[^\d+]'),
                                '',
                              ),
                            ),
                            failure: 'No dialer available on this device.',
                          ),
                        ),
                      if (lead.location.isNotEmpty)
                        StationDataRow(label: 'Location', value: lead.location),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const SectionHeader(title: 'Internal note'),
              TextField(
                controller: _note,
                maxLines: 4,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Add context for the team',
                  alignLabelWithHint: true,
                ),
                style: text.bodyMedium,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GhostButton(
                      label: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SignalButton(
                      label: 'Save note',
                      icon: Icons.check_rounded,
                      busy: _saving,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _launch(
  BuildContext context,
  Uri uri, {
  required String failure,
}) async {
  try {
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
    }
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
