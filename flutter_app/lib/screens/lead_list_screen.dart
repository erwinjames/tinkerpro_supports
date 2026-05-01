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
  });
  final LeadService service;
  final NotificationCenter notifications;

  @override
  State<LeadListScreen> createState() => _LeadListScreenState();
}

class _LeadListScreenState extends State<LeadListScreen> {
  List<LeadBrief> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    widget.notifications.addListener(_onNotificationsChanged);
  }

  @override
  void dispose() {
    widget.notifications.removeListener(_onNotificationsChanged);
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

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '06',
      stationLabel: 'LEADS · FORMS',
      title: 'Inbound.',
      showBottomBrand: false,
      trailing: StationAction(
        icon: Icons.refresh,
        tooltip: 'Refresh',
        onPressed: _load,
      ),
      belowRule: NotificationBell(
        count: widget.notifications.unseenCount,
        onPressed: () =>
            NotificationPanel.show(context, widget.notifications),
        tooltip: 'New leads & customers',
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
        onRefresh: _load,
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
                        label: 'No leads yet',
                        hint:
                            'Forms submitted on the public site will appear here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Hairline(),
                    itemBuilder: (_, i) {
                      final l = _rows[i];
                      return _LeadTile(
                        lead: l,
                        onTap: () {
                          showModalBottomSheet<void>(
                            context: context,
                            backgroundColor: Brand.surface,
                            isScrollControlled: true,
                            builder: (_) =>
                                _LeadDetailSheet(lead: l, service: widget.service),
                          );
                        },
                      );
                    },
                  ),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 12),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.signal,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lead.name.isEmpty ? 'No name' : lead.name,
                      style: text.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    [lead.businessType, lead.email, lead.phone]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(lead.createdAt, style: text.labelMedium),
          ],
        ),
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
  late final TextEditingController _note =
      TextEditingController(text: widget.lead.note);
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok =
        await widget.service.updateNote(widget.lead.id, _note.text.trim());
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok ? 'NOTE SAVED' : 'NOTE COULD NOT BE SAVED')),
    );
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Brand.surface,
          border: Border(top: BorderSide(color: Brand.signal, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('LEAD ${widget.lead.id.toString().padLeft(2, '0')}',
                style: text.labelLarge),
            const SizedBox(height: 8),
            const Hairline(),
            const SizedBox(height: 18),
            Text(widget.lead.name.isEmpty ? 'No name' : widget.lead.name,
                style: text.headlineMedium),
            const SizedBox(height: 12),
            if (widget.lead.email.isNotEmpty)
              StationDataRow(
                label: 'EMAIL',
                value: widget.lead.email,
                trailingIcon: Icons.mail_outline,
                onTap: () => _launch(
                  context,
                  Uri(scheme: 'mailto', path: widget.lead.email),
                  failure: 'No mail app available.',
                ),
              ),
            const SizedBox(height: 12),
            if (widget.lead.phone.isNotEmpty)
              StationDataRow(
                label: 'PHONE',
                value: widget.lead.phone,
                trailingIcon: Icons.phone_outlined,
                onTap: () => _launch(
                  context,
                  Uri(
                    scheme: 'tel',
                    path: widget.lead.phone.replaceAll(RegExp(r'[^\d+]'), ''),
                  ),
                  failure: 'No dialer available on this device.',
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'INTERNAL NOTE'),
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
                    busy: _saving,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Hand a URI to the OS. On desktop platforms (Linux) tel:/mailto: handlers
/// may not be installed — in that case show a snack bar instead of crashing.
Future<void> _launch(BuildContext context, Uri uri,
    {required String failure}) async {
  try {
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.toUpperCase())));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.toUpperCase())));
    }
  }
}
