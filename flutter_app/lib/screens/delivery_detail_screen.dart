import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/delivery_models.dart';
import '../services/client_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'delivery_pane.dart';

String deliveryStatusPhrase(String status) {
  switch (status) {
    case 'Delivered':
      return 'has been delivered';
    case 'Out for Delivery':
      return 'is now out for delivery';
    case 'Cancelled':
      return 'has been cancelled';
    case 'Ready for Delivery':
      return 'is ready for delivery';
    default:
      return 'has been updated to $status';
  }
}

String deliverySmsPhrase(String status, String eta) {
  switch (status) {
    case 'Out for Delivery':
      return 'is out for delivery${eta.trim().isEmpty ? '' : ' (ETA ${eta.trim()})'}';
    case 'Delivered':
      return 'has been delivered';
    case 'Cancelled':
      return 'has been cancelled';
    case 'Ready for Delivery':
      return 'is ready for delivery';
    default:
      return 'status is now $status';
  }
}

class DeliveryDetailScreen extends StatefulWidget {
  const DeliveryDetailScreen({
    super.key,
    required this.service,
    required this.brief,
  });

  final ClientService service;
  final DeliveryBrief brief;

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  DeliveryDetail? _detail;
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String _error = '';
  String _pendingDoc = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await widget.service.delivery(widget.brief.id);
      if (!mounted) return;
      setState(() {
        _detail = res.detail;
        _loading = false;
      });
      if (res.stale && res.message.isNotEmpty) {
        deliveryToast(context, res.message);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = deliveryErrorText(e, 'Failed to load delivery.');
      });
    }
  }

  Future<void> _openDoc(String doc) async {
    if (_pendingDoc.isNotEmpty) return;
    setState(() => _pendingDoc = doc);
    deliveryToast(context, 'Preparing ${kDeliveryDocuments[doc] ?? 'PDF'}…');
    try {
      final path = await widget.service.downloadDeliveryPdf(
        widget.brief.id,
        doc,
      );
      final result = await OpenFilex.open(path, type: 'application/pdf');
      if (!mounted) return;
      setState(() => _pendingDoc = '');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (result.type != ResultType.done) {
        deliveryToast(context, 'No app available to open the PDF');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingDoc = '');
      deliveryToast(
        context,
        deliveryErrorText(e, 'Could not fetch the requested PDF.'),
      );
    }
  }

  Future<void> _pickStatus() async {
    final detail = _detail;
    if (detail == null || _busy) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StatusPickerSheet(current: detail.status),
    );
    if (picked == null || !mounted) return;
    final choice = await showModalBottomSheet<({bool notify, bool sms})>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StatusConfirmSheet(detail: detail, status: picked),
    );
    if (choice == null || !mounted) return;
    await _apply(picked, choice.notify, choice.sms);
  }

  Future<void> _apply(String status, bool notify, bool sms) async {
    setState(() => _busy = true);
    final res = await widget.service.updateDeliveryStatus(
      id: widget.brief.id,
      status: status,
      notify: notify,
      sms: sms,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      deliveryToast(
        context,
        res.message.trim().isEmpty ? 'Failed to update status.' : res.message,
      );
      return;
    }
    final channels = <String>[];
    if (notify && res.emailSent) channels.add('email');
    if (sms && res.smsSent) channels.add('SMS');
    if (notify && !res.emailSent && res.emailMessage.isNotEmpty) {
      deliveryToast(context, 'Email not sent: ${res.emailMessage}');
    } else if (sms && !res.smsSent && res.smsMessage.isNotEmpty) {
      deliveryToast(context, 'SMS not sent: ${res.smsMessage}');
    } else {
      deliveryToast(
        context,
        'Status updated to $status${channels.isEmpty ? '' : ' · notified via ${channels.join(' + ')}'}',
      );
    }
    final detail = _detail;
    setState(() {
      _changed = true;
      if (detail != null) _detail = detail.copyWithStatus(status);
    });
  }

  Widget _bottomBar() {
    final b = context.brand;
    return Material(
      color: b.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: b.rule)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SignalButton(
              label: 'Update status',
              icon: Icons.published_with_changes_rounded,
              busy: _busy,
              onPressed: _busy ? null : _pickStatus,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final detail = _detail;
    final status = detail?.status ?? widget.brief.status;
    final title = widget.brief.deliveryNo.isEmpty
        ? (detail?.deliveryNo.isNotEmpty == true
              ? detail!.deliveryNo
              : 'Delivery')
        : widget.brief.deliveryNo;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: StationScaffold(
        stationNumber: '15',
        stationLabel: 'Delivery note',
        title: title,
        subtitle: widget.brief.invoiceNo.isEmpty
            ? ''
            : 'Ref ${widget.brief.invoiceNo}',
        showBottomBrand: false,
        onBack: () => Navigator.of(context).pop(_changed),
        trailing: StationAction(
          icon: Icons.refresh_rounded,
          tooltip: 'Refresh',
          onPressed: _loading ? () {} : _load,
        ),
        bottomBar: detail == null ? null : _bottomBar(),
        child: _loading
            ? const SkeletonList(count: 6)
            : detail == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 40),
                  EmptyState(
                    icon: Icons.error_outline_rounded,
                    label: 'Delivery unavailable',
                    hint: _error.isEmpty
                        ? 'This delivery could not be loaded.'
                        : _error,
                    action: GhostButton(
                      label: 'Try again',
                      icon: Icons.refresh_rounded,
                      onPressed: _load,
                    ),
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  AppCard(
                    radius: Brand.radiusLg,
                    borderColor: deliveryStatusColor(
                      context,
                      status,
                    ).withValues(alpha: 0.3),
                    child: Row(
                      children: [
                        IconTile(
                          icon: deliveryStatusIcon(status),
                          color: deliveryStatusColor(context, status),
                          size: 44,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                detail.companyLabel,
                                style: Theme.of(context).textTheme.titleSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              StatusPill(
                                label: status.isEmpty ? '—' : status,
                                color: deliveryStatusColor(context, status),
                                dot: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SectionHeader(title: 'Delivery'),
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        StationDataRow(label: 'Date', value: _or(detail.date)),
                        StationDataRow(
                          label: 'Delivery date',
                          value: _or(deliveryDateLine(detail.deliveryDate)),
                        ),
                        StationDataRow(
                          label: 'Customer',
                          value: _or(detail.customerName),
                        ),
                        StationDataRow(
                          label: 'Recipient',
                          value: _or(detail.recipientName),
                        ),
                        StationDataRow(
                          label: 'Address',
                          value: _or(detail.recipientAddress),
                        ),
                        StationDataRow(
                          label: 'Invoice',
                          value: _or(detail.invoiceNo),
                        ),
                        StationDataRow(
                          label: 'Internal note',
                          value: _or(detail.internalNote),
                        ),
                      ],
                    ),
                  ),
                  if (detail.items.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SectionHeader(
                      title: 'Items',
                      trailing: Text(
                        '${detail.items.length}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      child: Column(
                        children: [
                          for (final item in detail.items)
                            StationDataRow(
                              label: item.description.isEmpty
                                  ? 'Item'
                                  : item.description,
                              value: _quantityLine(item),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const SectionHeader(title: 'Documents'),
                  for (final entry in kDeliveryDocuments.entries) ...[
                    _DocRow(
                      label: entry.value,
                      busy: _pendingDoc == entry.key,
                      disabled: _pendingDoc.isNotEmpty,
                      onTap: () => _openDoc(entry.key),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    'Documents are fetched from the invoice service — tap one at a time.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: b.paperDim),
                  ),
                ],
              ),
      ),
    );
  }
}

String _or(String value) => value.trim().isEmpty ? '—' : value.trim();

String _quantityLine(DeliveryItem item) {
  final parts = <String>[];
  if (item.quantity.isNotEmpty) parts.add('Qty ${item.quantity}');
  if (item.deliveredQuantity.isNotEmpty) {
    parts.add('Delivered ${item.deliveredQuantity}');
  }
  if (item.amount.isNotEmpty) parts.add(item.amount);
  return parts.isEmpty ? '—' : parts.join(' · ');
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.label,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return AppCard(
      onTap: disabled ? null : onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          IconTile(icon: Icons.picture_as_pdf_rounded, color: Brand.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: b.signal),
            )
          else
            Icon(Icons.download_rounded, size: 20, color: b.paperDim),
        ],
      ),
    );
  }
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          border: Border.all(color: b.rule),
        ),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

class _StatusPickerSheet extends StatelessWidget {
  const _StatusPickerSheet({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Set status to', style: text.titleSmall),
          const SizedBox(height: 12),
          for (final status in kDeliverySettableStatuses) ...[
            Material(
              color: status == current ? b.surfaceHi : b.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Brand.radius),
                side: BorderSide(color: b.rule),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(status),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: deliveryStatusColor(context, status),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(status, style: text.titleSmall)),
                      if (status == current)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: context.brand.signal,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          GhostButton(
            label: 'Cancel',
            icon: Icons.close_rounded,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _StatusConfirmSheet extends StatefulWidget {
  const _StatusConfirmSheet({required this.detail, required this.status});

  final DeliveryDetail detail;
  final String status;

  @override
  State<_StatusConfirmSheet> createState() => _StatusConfirmSheetState();
}

class _StatusConfirmSheetState extends State<_StatusConfirmSheet> {
  late bool _notify;
  late bool _sms;

  @override
  void initState() {
    super.initState();
    _notify = widget.detail.customerEmail.isNotEmpty;
    _sms = widget.detail.hasSms;
  }

  String get _smsBody {
    final d = widget.detail;
    final ref = d.invoiceNo.isNotEmpty
        ? 'Invoice #${d.invoiceNo}'
        : (d.deliveryNo.isNotEmpty
              ? 'Delivery #${d.deliveryNo}'
              : 'your order');
    return 'Hi ${d.recipientLabel}, your order ($ref) '
        '${deliverySmsPhrase(widget.status, d.deliveryDate)}. Thank you!';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final d = widget.detail;
    final hasEmail = d.customerEmail.isNotEmpty;
    final hasSms = d.hasSms;
    final canNotify = (_notify && hasEmail) || (_sms && hasSms);
    final sub =
        '${d.deliveryNo.isEmpty ? '' : '${d.deliveryNo} · '}'
        '${hasEmail ? 'Notify ${d.recipientLabel}?' : 'No email on file'}';
    return _SheetShell(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconTile(
                  icon: deliveryStatusIcon(widget.status),
                  color: deliveryStatusColor(context, widget.status),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set status to ${widget.status}',
                        style: text.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: text.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ChannelTile(
              icon: Icons.mail_outline_rounded,
              title: 'Email',
              subtitle: hasEmail ? d.customerEmail : 'No email address on file',
              value: _notify && hasEmail,
              enabled: hasEmail,
              onChanged: (v) => setState(() => _notify = v),
            ),
            if (hasEmail && _notify) ...[
              const SizedBox(height: 10),
              _PreviewCard(
                lines: <String>[
                  'to ${d.customerEmail}',
                  'Delivery Note #${d.deliveryNo} from ${d.companyLabel} — ${widget.status}',
                  'Dear ${d.recipientLabel},\n\nYour order (delivery note #${d.deliveryNo}) '
                      '${deliveryStatusPhrase(widget.status)}. Thank you for your business.',
                  d.deliveryNo.isEmpty
                      ? 'PDF attached'
                      : '${d.deliveryNo}.pdf attached',
                ],
              ),
            ],
            if (hasSms) ...[
              const SizedBox(height: 12),
              _ChannelTile(
                icon: Icons.sms_outlined,
                title: 'SMS',
                subtitle: d.smsPhone,
                value: _sms,
                enabled: true,
                onChanged: (v) => setState(() => _sms = v),
              ),
              if (_sms) ...[
                const SizedBox(height: 10),
                _PreviewCard(
                  lines: <String>[
                    'to ${d.smsPhone}',
                    _smsBody,
                    '${_smsBody.length} characters',
                  ],
                ),
              ],
            ],
            const SizedBox(height: 16),
            SignalButton(
              label: 'Update & Notify',
              icon: Icons.send_rounded,
              onPressed: canNotify
                  ? () => Navigator.of(
                      context,
                    ).pop((notify: _notify && hasEmail, sms: _sms && hasSms))
                  : null,
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'Update without notifying',
              icon: Icons.notifications_off_rounded,
              onPressed: () =>
                  Navigator.of(context).pop((notify: false, sms: false)),
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'Cancel',
              icon: Icons.close_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
            SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
            if (!hasEmail && !hasSms)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'No contact details on file — the status can still be updated without notifying.',
                  style: text.bodySmall?.copyWith(color: b.paperDim),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: AppCard(
        onTap: enabled ? () => onChanged(!value) : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: b.paperDim),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Switch(value: value, onChanged: enabled ? onChanged : null),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: b.surfaceHi,
        borderRadius: BorderRadius.circular(Brand.radius),
        border: Border.all(color: b.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Text(
              lines[i],
              style: i == 0
                  ? text.bodySmall?.copyWith(color: b.paperDim)
                  : (i == 1
                        ? text.titleSmall
                        : text.bodySmall?.copyWith(color: b.paperDim)),
            ),
          ],
        ],
      ),
    );
  }
}
