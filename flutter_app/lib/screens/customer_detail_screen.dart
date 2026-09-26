import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'bir_register_widgets.dart';
import 'customer_bir_actions.dart';
import 'customer_form_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.service,
    required this.brief,
  });

  final CustomerService service;
  final CustomerBrief brief;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  CustomerDetail? _detail;
  bool _loading = true;
  bool _deleting = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.service.detailFull(widget.brief.id);
    if (!mounted) return;
    setState(() {
      _detail = data;
      _loading = false;
    });
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            CustomerFormScreen(service: widget.service, existing: detail),
      ),
    );
    if (saved == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _uploadRegistrationPdf() async {
    final detail = _detail;
    if (detail == null) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            BirRegistrationPdfScreen(service: widget.service, customer: detail),
      ),
    );
    if (done == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _uploadPtuDocument() async {
    final detail = _detail;
    if (detail == null) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            PtuUploadScreen(service: widget.service, customer: detail),
      ),
    );
    if (done == true) {
      _changed = true;
      _load();
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.delete_outline_rounded,
          color: Brand.danger,
          size: 28,
        ),
        title: const Text('Delete client?'),
        content: Text(
          'This permanently deletes "${widget.brief.companyName}" and its '
          'documents on the server. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Brand.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deleting = true);
    final ok = await widget.service.delete(widget.brief.id);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Client deleted.')));
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Delete failed. Please try again.')),
        );
    }
  }

  static String _or(String v) => v.trim().isEmpty ? '—' : v;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final d = _detail;
    final branch = d?.branchCode ?? widget.brief.branchCode;
    final address = (d?.address.isNotEmpty ?? false)
        ? d!.address
        : widget.brief.address;
    final rdo = d?.rdo ?? '';
    final software = d?.softwareName ?? '';
    final accNumber = d?.accNumber ?? '';
    final vat = d == null ? '' : (d.isVat ? 'VAT' : 'Non-VAT');
    final created = _formatCreated(d?.createdAt ?? '');
    final owner = (d?.ownerName.isNotEmpty ?? false)
        ? d!.ownerName
        : widget.brief.ownerName;
    final tin = (d?.tin.isNotEmpty ?? false) ? d!.tin : widget.brief.tin;
    final status = d?.status ?? widget.brief.status;
    final statusColor = customerStatusColor(status);
    final companyName = (d?.companyName.isNotEmpty ?? false)
        ? d!.companyName
        : widget.brief.companyName;

    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final header = AppHeaderBand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (Navigator.of(context).canPop()) ...[
                AppIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(_changed),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  'Client detail',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: Brand.orange,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: 16),
          GlassPanel(
            accent: statusColor,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: b.tint(b.signal, 0.1),
                        border: Border.all(
                          color: b.signal.withValues(alpha: 0.4),
                        ),
                      ),
                      child: AppAvatar(name: companyName, size: 56),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              companyName,
                              style: text.headlineSmall?.copyWith(
                                color: b.paper,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (owner.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              owner,
                              style: text.bodyMedium?.copyWith(
                                color: b.paperDim,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          if (created.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.event_rounded,
                                  size: 14,
                                  color: b.paperDim,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Created $created',
                                    style: text.bodySmall?.copyWith(
                                      color: b.paperDim,
                                    ),
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
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    GlowStatusPill(
                      label: status,
                      color: statusColor,
                      dot: true,
                    ),
                    if (d?.fromClientPortal ?? false)
                      GlowStatusPill(
                        label: 'Client',
                        color: Brand.navy,
                        icon: Icons.public_rounded,
                      ),
                    if (vat.isNotEmpty)
                      GlowStatusPill(
                        label: vat,
                        color: d!.isVat ? Brand.info : b.paperDim,
                        icon: Icons.receipt_long_rounded,
                      ),
                    if (tin.isNotEmpty)
                      GlowStatusPill(
                        label: branch.isEmpty ? 'TIN $tin' : 'TIN $tin-$branch',
                        color: b.signal,
                        icon: Icons.badge_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final Widget body = _loading
        ? const _DetailSkeleton()
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            physics: const BouncingScrollPhysics(),
            children: [
              FadeSlideIn(
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _edit,
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Edit client'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _deleting ? null : _delete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Brand.danger,
                            side: BorderSide(color: b.tint(Brand.danger, 0.4)),
                          ),
                          icon: _deleting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Brand.danger,
                                  ),
                                )
                              : const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                ),
                          label: const Text('Delete'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (d != null && _showRegistrationActions(d)) ...[
                const SizedBox(height: 22),
                FadeSlideIn(index: 1, child: _registrationActions(context, d)),
              ],
              const SizedBox(height: 22),
              FadeSlideIn(
                index: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(title: 'Business information'),
                    _section([
                      StationDataRow(
                        label: 'TIN · Branch',
                        value:
                            '${tin.isEmpty ? '—' : tin}${branch.isEmpty ? '' : '  ·  $branch'}',
                      ),
                      StationDataRow(label: 'Owner', value: _or(owner)),
                      StationDataRow(label: 'Address', value: _or(address)),
                      StationDataRow(label: 'RDO', value: _or(rdo)),
                      StationDataRow(label: 'VAT status', value: _or(vat)),
                      StationDataRow(label: 'Created', value: _or(created)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              FadeSlideIn(
                index: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(title: 'Point-of-sale'),
                    _section([
                      StationDataRow(label: 'Software', value: _or(software)),
                      StationDataRow(
                        label: 'ACC. number',
                        value: _or(accNumber),
                      ),
                      StationDataRow(
                        label: 'Serial number',
                        value: _or(d?.serialNumber ?? ''),
                      ),
                    ]),
                  ],
                ),
              ),
              if (d != null && d.serialEntries.isNotEmpty) ...[
                const SizedBox(height: 22),
                FadeSlideIn(
                  index: 3,
                  child: _serialEntries(context, d.serialEntries),
                ),
              ],
              if (d != null && d.documents.isNotEmpty) ...[
                const SizedBox(height: 22),
                FadeSlideIn(index: 4, child: _documents(context, d.documents)),
              ],
              const SizedBox(height: 24),
            ],
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: b.canvas,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: SafeArea(
                top: false,
                child: RefreshIndicator(
                  color: b.signal,
                  backgroundColor: b.surface,
                  onRefresh: _load,
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    child: body,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _showPtuAction(CustomerDetail d) =>
      d.step2 == 1 && d.finalStep != 1;

  static bool _showPdfAction(CustomerDetail d) =>
      d.cStatus == 1 && d.step2 != 1;

  static bool _showRegistrationActions(CustomerDetail d) =>
      _showPtuAction(d) || _showPdfAction(d);

  Widget _registrationActions(BuildContext context, CustomerDetail d) {
    final text = Theme.of(context).textTheme;
    final hasPdfFile = d.pdfFile.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Registration'),
        AppCard(
          padding: const EdgeInsets.all(14),
          radius: Brand.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showPtuAction(d)) ...[
                Text(
                  'Upload the Permit to Use Sales Machine PDF file.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 12),
                SignalButton(
                  label: 'Upload PTU Document',
                  icon: Icons.description_rounded,
                  onPressed: _uploadPtuDocument,
                ),
              ],
              if (_showPdfAction(d)) ...[
                Text(
                  'Upload the BIR registration PDF and extract it to advance '
                  'to Upload PTU',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 12),
                SignalButton(
                  label: hasPdfFile
                      ? 'Re-upload BIR Registration PDF'
                      : 'Upload Registration PDF',
                  icon: Icons.file_upload_rounded,
                  onPressed: _uploadRegistrationPdf,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(List<Widget> rows) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      radius: Brand.radiusLg,
      child: Column(children: rows),
    );
  }

  Widget _serialEntries(BuildContext context, List<SerialEntry> entries) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Serial entries',
          trailing: StatusPill(label: '${entries.length}', color: b.paperDim),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          radius: Brand.radiusLg,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Hairline(),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconTile(
                        icon: Icons.memory_rounded,
                        color: Brand.info,
                        size: 36,
                        iconSize: 18,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entries[i].serialNumber.isEmpty
                                  ? '—'
                                  : entries[i].serialNumber,
                              style: text.titleSmall,
                            ),
                            if (entries[i].brand.isNotEmpty ||
                                entries[i].model.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                [
                                  entries[i].brand,
                                  entries[i].model,
                                ].where((e) => e.isNotEmpty).join(' '),
                                style: text.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            if (entries[i].serialNumberType.isNotEmpty)
                              GlowStatusPill(
                                label: entries[i].serialNumberType,
                                color: b.signal,
                              ),
                            if (entries[i].serverType.isNotEmpty)
                              StatusPill(
                                label: entries[i].serverType,
                                color: b.paperDim,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static IconData _docIcon(CustomerDocument doc) {
    final m = doc.mimeType.toLowerCase();
    final n =
        (doc.originalFilename.isEmpty
                ? doc.storedFilename
                : doc.originalFilename)
            .toLowerCase();
    if (m.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|gif|webp|heic|bmp)$').hasMatch(n)) {
      return Icons.image_rounded;
    }
    if (m.contains('pdf') || n.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  static Color _docColor(CustomerDocument doc) {
    switch (doc.docType) {
      case 'valid_id':
        return Brand.info;
      case 'requirement':
        return Brand.success;
      default:
        return Brand.signal;
    }
  }

  static String _humanize(String s) {
    final v = s.replaceAll('_', ' ').trim();
    if (v.isEmpty) return v;
    return v[0].toUpperCase() + v.substring(1);
  }

  static String _size(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _documents(BuildContext context, List<CustomerDocument> docs) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Documents',
          trailing: StatusPill(label: '${docs.length}', color: b.paperDim),
        ),
        for (final doc in docs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              radius: Brand.radiusLg,
              child: Row(
                children: [
                  IconTile(
                    icon: _docIcon(doc),
                    color: _docColor(doc),
                    size: 44,
                    iconSize: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.originalFilename.isEmpty
                              ? doc.storedFilename
                              : doc.originalFilename,
                          style: text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_size(doc.fileSize).isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(_size(doc.fileSize), style: text.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (doc.docType.isNotEmpty)
                    GlowStatusPill(
                      label: _humanize(doc.docType),
                      color: _docColor(doc),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

String _formatCreated(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.startsWith('0000')) return '';
  final dt = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (dt == null) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $period';
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget card(int rows) => AppCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      radius: Brand.radiusLg,
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Skeleton(width: 90, height: 12),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Skeleton(width: i.isEven ? 160 : 120, height: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    return Semantics(
      label: 'Loading',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const Row(
            children: [
              Expanded(child: Skeleton(height: 48, radius: Brand.radius)),
              SizedBox(width: 10),
              Expanded(child: Skeleton(height: 48, radius: Brand.radius)),
            ],
          ),
          const SizedBox(height: 22),
          const Skeleton(width: 170, height: 16),
          const SizedBox(height: 12),
          card(6),
          const SizedBox(height: 22),
          const Skeleton(width: 120, height: 16),
          const SizedBox(height: 12),
          card(3),
        ],
      ),
    );
  }
}
