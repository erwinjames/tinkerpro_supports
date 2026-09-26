import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/bir_v1_models.dart';
import '../services/bir_v1_service.dart';
import '../theme.dart';
import '../widgets/pick_source.dart';
import '../widgets/premium.dart';
import 'bir_register_widgets.dart';

Color birV1StatusColor(BuildContext context, String status) {
  switch (status) {
    case 'completed':
      return Brand.success;
    case 'for_ptu':
      return Brand.warning;
    default:
      return context.brand.paperDim;
  }
}

void birV1Toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _errorText(Object error) {
  if (error is BirV1Exception) return error.fullMessage;
  return '$error';
}

String _or(String value) => value.trim().isEmpty ? '—' : value.trim();

class BirV1Pane extends StatefulWidget {
  const BirV1Pane({super.key, required this.service, this.onTotal});

  final BirV1Service service;
  final ValueChanged<int>? onTotal;

  @override
  State<BirV1Pane> createState() => BirV1PaneState();
}

class BirV1PaneState extends State<BirV1Pane> {
  static const int _pageSize = 30;
  static const List<(String, String)> _filters = <(String, String)>[
    ('', 'All'),
    ('draft', 'Draft'),
    ('for_ptu', 'For PTU'),
    ('completed', 'Completed'),
  ];

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  List<BirV1Record> _rows = const <BirV1Record>[];
  bool _loading = true;
  bool _loadingMore = false;
  String _status = '';
  String _error = '';
  int _page = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void reload() => _load();

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - 320) return;
    _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final page = await widget.service.list(
        search: _searchController.text,
        status: _status,
        page: 1,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _rows = page.rows;
        _page = page.page;
        _totalPages = page.totalPages;
        _loading = false;
      });
      widget.onTotal?.call(page.total);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = const <BirV1Record>[];
        _loading = false;
        _error = _errorText(e);
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _page >= _totalPages) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.service.list(
        search: _searchController.text,
        status: _status,
        page: _page + 1,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _rows = <BirV1Record>[..._rows, ...page.rows];
        _page = page.page;
        _totalPages = page.totalPages;
        _loadingMore = false;
      });
      widget.onTotal?.call(page.total);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = _errorText(e);
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _openDetail(BirV1Record record) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            BirV1DetailScreen(service: widget.service, recordId: record.id),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchField(
          controller: _searchController,
          hint: 'Search V1 company, TIN, PTU or owner',
          onChanged: _onSearchChanged,
          onSubmitted: (_) => _load(),
        ),
        const SizedBox(height: 12),
        ChoicePills<(String, String)>(
          options: _filters,
          value: _filters.firstWhere(
            (f) => f.$1 == _status,
            orElse: () => _filters.first,
          ),
          labelOf: (f) => f.$2,
          onChanged: (f) {
            if (f.$1 == _status) return;
            setState(() => _status = f.$1);
            _load();
          },
        ),
        const SizedBox(height: 12),
        if (_error.isNotEmpty)
          BirNotice(
            color: Brand.danger,
            icon: Icons.error_outline_rounded,
            title: 'V1 system',
            message: _error,
          ),
        Expanded(
          child: RefreshIndicator(
            color: b.signal,
            backgroundColor: b.surface,
            onRefresh: _load,
            child: _loading
                ? const SkeletonList()
                : _rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 48),
                      EmptyState(
                        icon: Icons.inventory_2_rounded,
                        label: 'No V1 records',
                        hint:
                            'Nothing matched this search or filter. '
                            'Pull down to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length + (_loadingMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      if (i >= _rows.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final record = _rows[i];
                      return FadeSlideIn(
                        key: ValueKey<int>(record.id),
                        index: i,
                        child: _BirV1Row(
                          record: record,
                          onTap: () => _openDetail(record),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _BirV1Row extends StatelessWidget {
  const _BirV1Row({required this.record, required this.onTap});

  final BirV1Record record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final accent = birV1StatusColor(context, record.status);
    final owner = record.ownerName;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: Brand.radiusLg,
      borderColor: b.isDark ? accent.withValues(alpha: 0.22) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppAvatar(name: record.title),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.title,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  owner.isEmpty ? '—' : owner,
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (record.tinWithBranch.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.badge_rounded,
                        size: 14,
                        color: context.brand.paperDim,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          record.tinWithBranch,
                          style: text.labelMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (record.softwareName.isNotEmpty ||
                    record.ptu.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (record.softwareName.isNotEmpty)
                        StatusPill(
                          label: record.softwareName,
                          color: b.paperDim,
                          icon: Icons.point_of_sale_rounded,
                        ),
                      if (record.ptu.isNotEmpty)
                        StatusPill(
                          label: 'PTU ${record.ptu}',
                          color: Brand.info,
                          icon: Icons.verified_rounded,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          GlowStatusPill(label: record.statusLabel, color: accent, dot: true),
        ],
      ),
    );
  }
}

class BirV1DetailScreen extends StatefulWidget {
  const BirV1DetailScreen({
    super.key,
    required this.service,
    required this.recordId,
  });

  final BirV1Service service;
  final int recordId;

  @override
  State<BirV1DetailScreen> createState() => _BirV1DetailScreenState();
}

class _BirV1DetailScreenState extends State<BirV1DetailScreen> {
  static const List<(String, String)> _tabs = <(String, String)>[
    ('details', 'Details'),
    ('edit', 'Edit'),
    ('workflow', 'Workflow'),
    ('docs', 'Documents'),
  ];

  final Map<String, TextEditingController> _edit =
      <String, TextEditingController>{};
  final TextEditingController _wfPtu = TextEditingController();
  final TextEditingController _wfMin = TextEditingController();
  final TextEditingController _wfDate = TextEditingController();

  BirV1Record? _record;
  BirV1Meta _meta = BirV1Meta.fallback;
  bool _loading = true;
  bool _saving = false;
  bool _applying = false;
  bool _busy = false;
  bool _showPassword = false;
  bool _isVat = false;
  bool _changed = false;
  String _error = '';
  String _tab = 'details';
  String _wfStatus = 'draft';

  static const List<String> _editFields = <String>[
    'company_name',
    'tin',
    'branch_code',
    'rdo',
    'address',
    'first_name',
    'middle_name',
    'last_name',
    'email',
    'softwarename',
    'acc_num',
    'business_line',
    'serial_number',
    'username',
    'password',
  ];

  @override
  void initState() {
    super.initState();
    for (final field in _editFields) {
      _edit[field] = TextEditingController();
    }
    _load();
    _loadMeta();
  }

  @override
  void dispose() {
    for (final controller in _edit.values) {
      controller.dispose();
    }
    _wfPtu.dispose();
    _wfMin.dispose();
    _wfDate.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final meta = await widget.service.meta();
    if (!mounted) return;
    setState(() => _meta = meta);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final record = await widget.service.detail(widget.recordId);
      if (!mounted) return;
      setState(() {
        _record = record;
        _loading = false;
      });
      _fill(record);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _errorText(e);
      });
    }
  }

  void _fill(BirV1Record record) {
    _edit['company_name']!.text = record.companyName;
    _edit['tin']!.text = record.tin;
    _edit['branch_code']!.text = record.branchCode;
    _edit['rdo']!.text = record.rdo;
    _edit['address']!.text = record.address;
    _edit['first_name']!.text = record.firstName;
    _edit['middle_name']!.text = record.middleName;
    _edit['last_name']!.text = record.lastName;
    _edit['email']!.text = record.email;
    _edit['softwarename']!.text = record.softwareName;
    _edit['acc_num']!.text = record.accNumber;
    _edit['business_line']!.text = record.businessLine;
    _edit['serial_number']!.text = record.serialNumber;
    _edit['username']!.text = record.username;
    _edit['password']!.text = record.password;
    _wfPtu.text = record.ptu;
    _wfMin.text = record.min;
    _wfDate.text = record.posDateIssued;
    setState(() {
      _isVat = record.isVat;
      _wfStatus = kBirV1Statuses.contains(record.status)
          ? record.status
          : 'draft';
    });
  }

  Future<void> _save() async {
    final record = _record;
    if (record == null || _saving) return;
    setState(() => _saving = true);
    try {
      final fields = <String, String>{
        for (final field in _editFields) field: _edit[field]!.text.trim(),
        'is_vat': _isVat ? '1' : '0',
      };
      final updated = await widget.service.update(record.id, fields);
      if (!mounted) return;
      setState(() {
        _record = updated;
        _saving = false;
        _changed = true;
        _tab = 'details';
      });
      _fill(updated);
      birV1Toast(context, 'The V1 record has been updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      birV1Toast(context, _errorText(e));
    }
  }

  Future<void> _applyWorkflow() async {
    final record = _record;
    if (record == null || _applying) return;
    setState(() => _applying = true);
    try {
      final updated = await widget.service.applyWorkflow(
        record.id,
        status: _wfStatus,
        ptu: _wfPtu.text,
        min: _wfMin.text,
        posDateIssued: _wfDate.text,
      );
      if (!mounted) return;
      setState(() {
        _record = updated;
        _applying = false;
        _changed = true;
        _tab = 'details';
      });
      _fill(updated);
      birV1Toast(context, 'This record is now "${updated.statusLabel}".');
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      birV1Toast(context, _errorText(e));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_wfDate.text.trim());
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2010),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    final month = picked.month.toString().padLeft(2, '0');
    final day = picked.day.toString().padLeft(2, '0');
    setState(() => _wfDate.text = '${picked.year}-$month-$day');
  }

  Future<void> _openRemote(
    Future<String> Function() task,
    String pendingLabel,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    birV1Toast(context, pendingLabel);
    try {
      final path = await task();
      final result = await OpenFilex.open(path);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (result.type != ResultType.done) {
        birV1Toast(context, 'No app available to open this file.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      birV1Toast(context, _errorText(e));
    }
  }

  Future<void> _openStep3() async {
    final record = _record;
    if (record == null || _busy) return;
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            BirV1PtuUploadScreen(service: widget.service, record: record),
      ),
    );
    if (completed != true || !mounted) return;
    _changed = true;
    await _load();
  }

  Future<void> _uploadDocument() async {
    final record = _record;
    if (record == null || _busy) return;

    final docType = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.brand.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'Document type',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final type in _meta.documentTypes)
              ListTile(
                minTileHeight: 48,
                leading: const Icon(Icons.description_rounded),
                title: Text(birV1Humanize(type)),
                onTap: () => Navigator.of(ctx).pop(type),
              ),
          ],
        ),
      ),
    );
    if (docType == null || !mounted) return;

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
    } catch (_) {
      if (!mounted) return;
      birV1Toast(context, 'Could not open the file picker.');
      return;
    }
    final path = picked?.files.single.path;
    if (path == null || path.isEmpty || !mounted) return;

    setState(() => _busy = true);
    birV1Toast(context, 'Uploading…');
    try {
      await widget.service.uploadDocument(
        record.id,
        filePath: path,
        docType: docType,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _changed = true;
      });
      birV1Toast(context, 'The document is attached to this V1 record.');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      birV1Toast(context, _errorText(e));
    }
  }

  Future<void> _deleteDocument(BirV1Document document) async {
    final record = _record;
    if (record == null) return;
    final confirmed = await _confirm(
      title: 'Delete document?',
      message:
          '${document.displayName} will be removed from the V1 system, '
          'including the file on disk.',
      confirmLabel: 'Delete',
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.service.deleteDocument(record.id, document.id);
      if (!mounted) return;
      _changed = true;
      await _load();
    } catch (e) {
      if (!mounted) return;
      birV1Toast(context, _errorText(e));
    }
  }

  Future<void> _deleteRecord() async {
    final record = _record;
    if (record == null) return;
    final confirmed = await _confirm(
      title: 'Delete this V1 record?',
      message:
          '${record.title} and all of its documents will be permanently '
          'removed from the V1 system.',
      confirmLabel: 'Delete',
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.service.deleteRecord(record.id);
      if (!mounted) return;
      birV1Toast(context, 'V1 record deleted.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      birV1Toast(context, _errorText(e));
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.delete_outline_rounded,
          color: Brand.danger,
          size: 28,
        ),
        title: Text(title),
        content: Text(message),
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
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final record = _record;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = birV1StatusColor(context, record?.status ?? 'draft');

    final header = AppHeaderBand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(_changed),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Version 1 record',
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
              const SizedBox(width: 8),
              AppIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete record',
                onPressed: record == null ? null : _deleteRecord,
              ),
            ],
          ),
          const SizedBox(height: 16),
          GlassPanel(
            accent: accent,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppAvatar(name: record?.title ?? 'V1', size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              record?.title ?? 'Loading…',
                              style: text.titleLarge?.copyWith(color: b.paper),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if ((record?.ownerName ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              record!.ownerName,
                              style: text.bodyMedium?.copyWith(
                                color: b.paperDim,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                    const GlowBadge(
                      label: 'V1',
                      color: Brand.warning,
                      icon: Icons.history_rounded,
                    ),
                    GlowStatusPill(
                      label: record?.statusLabel ?? 'Draft',
                      color: accent,
                      dot: true,
                    ),
                    if ((record?.tinWithBranch ?? '').isNotEmpty)
                      GlowStatusPill(
                        label: 'TIN ${record!.tinWithBranch}',
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
        ? const SkeletonList()
        : record == null
        ? ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 32),
              EmptyState(
                icon: Icons.error_outline_rounded,
                label: 'Record unavailable',
                hint: _error.isEmpty
                    ? 'This V1 record could not be loaded.'
                    : _error,
              ),
            ],
          )
        : ListView(
            key: ValueKey<String>('v1-$_tab-${record.id}'),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: _tabBody(record),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: ChoicePills<(String, String)>(
                options: _tabs,
                value: _tabs.firstWhere(
                  (t) => t.$1 == _tab,
                  orElse: () => _tabs.first,
                ),
                labelOf: (t) => t.$2,
                countOf: (t) => t.$1 == 'docs' && record != null
                    ? record.documents.length
                    : null,
                onChanged: (t) => setState(() => _tab = t.$1),
              ),
            ),
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
                        : const Duration(milliseconds: 200),
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

  List<Widget> _tabBody(BirV1Record record) {
    switch (_tab) {
      case 'edit':
        return _editTab(record);
      case 'workflow':
        return _workflowTab(record);
      case 'docs':
        return _documentsTab(record);
      default:
        return _detailsTab(record);
    }
  }

  Widget _section(List<Widget> rows) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      radius: Brand.radiusLg,
      child: Column(children: rows),
    );
  }

  List<Widget> _detailsTab(BirV1Record record) {
    return [
      if (!record.birCardReady && record.birCardMissingFields.isNotEmpty)
        BirNotice(
          color: Brand.warning,
          icon: Icons.info_outline_rounded,
          title: 'BIR card not available yet',
          message:
              'Missing: '
              '${record.birCardMissingFields.map(birV1Humanize).join(', ')}',
        ),
      if (record.isForPtu) ...[
        const BirNotice(
          color: Brand.warning,
          icon: Icons.description_rounded,
          title: 'Step 3 — Permit to Use',
          message:
              'Upload the Permit to Use PDF and this registration is '
              'completed. You can also type the PTU, MIN and issue date in '
              'the Workflow tab instead.',
        ),
        SignalButton(
          label: 'Upload PTU document',
          icon: Icons.upload_file_rounded,
          onPressed: _busy ? null : _openStep3,
        ),
        const SizedBox(height: 18),
      ],
      FadeSlideIn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Business information'),
            _section([
              StationDataRow(label: 'Company', value: _or(record.companyName)),
              StationDataRow(label: 'TIN', value: _or(record.tin)),
              StationDataRow(
                label: 'Branch code',
                value: _or(record.branchCode),
              ),
              StationDataRow(label: 'RDO', value: _or(record.rdo)),
              StationDataRow(label: 'Address', value: _or(record.address)),
              StationDataRow(label: 'Province', value: _or(record.province)),
              StationDataRow(label: 'City', value: _or(record.city)),
              StationDataRow(label: 'Barangay', value: _or(record.barangay)),
              StationDataRow(
                label: 'Line of business',
                value: _or(record.businessLine),
              ),
              StationDataRow(
                label: 'VAT registered',
                value: record.isVat ? 'Yes' : 'No',
              ),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 22),
      FadeSlideIn(
        index: 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Owner & account'),
            _section([
              StationDataRow(label: 'Owner name', value: _or(record.ownerName)),
              StationDataRow(label: 'Email', value: _or(record.email)),
              StationDataRow(label: 'Username', value: _or(record.username)),
              StationDataRow(
                label: 'TIN issuance date',
                value: _or(record.tinIssuanceDate),
              ),
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
              StationDataRow(
                label: 'Software',
                value: _or(record.softwareName),
              ),
              StationDataRow(
                label: 'Accreditation no.',
                value: _or(record.accNumber),
              ),
              StationDataRow(
                label: 'Serial number(s)',
                value: _or(record.serialNumber),
              ),
              StationDataRow(label: 'MIN', value: _or(record.min)),
              StationDataRow(label: 'PTU', value: _or(record.ptu)),
              StationDataRow(
                label: 'POS date issued',
                value: _or(record.posDateIssued),
              ),
              StationDataRow(label: 'V1 record', value: '#${record.id}'),
            ]),
          ],
        ),
      ),
      const SizedBox(height: 22),
      FadeSlideIn(index: 3, child: _printSection(record)),
    ];
  }

  Widget _printSection(BirV1Record record) {
    final rows = <Widget>[
      _FileAction(
        icon: Icons.picture_as_pdf_rounded,
        color: Brand.danger,
        title: 'Registration application',
        subtitle: record.pdfFile.isEmpty
            ? 'No registration PDF stored on this record.'
            : record.pdfFile,
        enabled: record.pdfFile.isNotEmpty && !_busy,
        onTap: () => _openRemote(
          () => widget.service.downloadArchiveFile(record.pdfFile),
          'Opening the application PDF…',
        ),
      ),
      for (final name in record.ptuFiles)
        _FileAction(
          icon: Icons.verified_rounded,
          color: Brand.success,
          title: 'Permit to Use',
          subtitle: name,
          enabled: !_busy,
          onTap: () => _openRemote(
            () => widget.service.downloadArchiveFile(name),
            'Opening the PTU file…',
          ),
        ),
      if (record.isCompleted)
        _FileAction(
          icon: Icons.credit_card_rounded,
          color: Brand.info,
          title: 'BIR card (Ask for Receipt)',
          subtitle: record.birCardReady
              ? 'Generated from this record'
              : 'Missing: '
                    '${record.birCardMissingFields.map(birV1Humanize).join(', ')}',
          enabled: record.birCardReady && !_busy,
          onTap: () => _openRemote(
            () => widget.service.downloadBirCard(record.id),
            'Generating the BIR card…',
          ),
        ),
      _FileAction(
        icon: Icons.gavel_rounded,
        color: Brand.signal,
        title: 'Sworn declaration',
        subtitle: 'Generate and open the sworn declaration',
        enabled: !_busy,
        onTap: () => _openRemote(
          () => widget.service.generateSwornDocument(
            record.id,
            'sworn_declaration',
          ),
          'Generating the sworn declaration…',
        ),
      ),
      _FileAction(
        icon: Icons.assignment_rounded,
        color: Brand.signal,
        title: 'Sworn statement',
        subtitle: 'Generate and open the sworn statement',
        enabled: !_busy,
        onTap: () => _openRemote(
          () => widget.service.generateSwornDocument(
            record.id,
            'sworn_statement',
          ),
          'Generating the sworn statement…',
        ),
      ),
      _FileAction(
        icon: Icons.library_books_rounded,
        color: Brand.signal,
        title: 'Declaration + statement',
        subtitle: 'Both documents in one PDF',
        enabled: !_busy,
        onTap: () => _openRemote(
          () => widget.service.generateSwornDocument(
            record.id,
            'sworn_declaration_and_statement',
          ),
          'Generating both documents…',
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: 'Print & documents'),
        for (final row in rows)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: row),
      ],
    );
  }

  List<Widget> _editTab(BirV1Record record) {
    return [
      FadeSlideIn(
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          radius: Brand.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BirField(
                label: 'Company Name',
                controller: _edit['company_name']!,
              ),
              BirField(label: 'TIN', controller: _edit['tin']!),
              BirField(label: 'Branch Code', controller: _edit['branch_code']!),
              BirField(label: 'RDO', controller: _edit['rdo']!),
              BirLabeled(
                label: 'VAT Registered',
                child: BirDropdown<bool>(
                  value: _isVat,
                  hint: 'VAT registered',
                  icon: Icons.receipt_long_rounded,
                  items: const [
                    DropdownMenuItem<bool>(value: true, child: Text('Yes')),
                    DropdownMenuItem<bool>(value: false, child: Text('No')),
                  ],
                  onChanged: (value) =>
                      setState(() => _isVat = value ?? _isVat),
                ),
              ),
              BirField(
                label: 'Business Address',
                controller: _edit['address']!,
                maxLines: 3,
              ),
              BirField(label: 'First Name', controller: _edit['first_name']!),
              BirField(label: 'Middle Name', controller: _edit['middle_name']!),
              BirField(label: 'Last Name', controller: _edit['last_name']!),
              BirField(
                label: 'Email',
                controller: _edit['email']!,
                keyboardType: TextInputType.emailAddress,
              ),
              BirField(
                label: 'Software Name',
                controller: _edit['softwarename']!,
              ),
              BirField(
                label: 'Accreditation No.',
                controller: _edit['acc_num']!,
              ),
              BirField(
                label: 'Line of Business',
                controller: _edit['business_line']!,
                maxLines: 2,
              ),
              BirField(label: 'Username', controller: _edit['username']!),
              BirLabeled(
                label: 'Password',
                child: TextField(
                  controller: _edit['password']!,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    suffixIcon: IconButton(
                      tooltip: _showPassword
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
              ),
              BirField(
                label: 'Serial Number(s)',
                controller: _edit['serial_number']!,
                hint: 'Separate multiple serials with /',
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_rounded, size: 18),
          label: Text(_saving ? 'Saving…' : 'Save changes'),
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'V1 record #${record.id}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
  }

  List<Widget> _workflowTab(BirV1Record record) {
    return [
      BirNotice(
        color: Brand.info,
        icon: Icons.timeline_rounded,
        title: 'Current status',
        message:
            '${record.statusLabel}. Completing a record requires PTU, MIN '
            'and the POS date issued.',
      ),
      FadeSlideIn(
        child: AppCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          radius: Brand.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BirLabeled(
                label: 'Status',
                child: BirDropdown<String>(
                  value: _wfStatus,
                  hint: 'Status',
                  icon: Icons.flag_rounded,
                  items: [
                    for (final status in _meta.statuses)
                      DropdownMenuItem<String>(
                        value: status,
                        child: Text(birV1StatusLabel(status)),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _wfStatus = value ?? _wfStatus),
                ),
              ),
              BirField(label: 'PTU', controller: _wfPtu),
              BirField(label: 'MIN', controller: _wfMin),
              BirField(
                label: 'POS Date Issued',
                controller: _wfDate,
                hint: 'YYYY-MM-DD',
                suffix: IconButton(
                  tooltip: 'Pick a date',
                  icon: const Icon(Icons.event_rounded, size: 20),
                  onPressed: _pickDate,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: _applying ? null : _applyWorkflow,
          icon: _applying
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.arrow_forward_rounded, size: 18),
          label: Text(_applying ? 'Applying…' : 'Apply transition'),
        ),
      ),
    ];
  }

  List<Widget> _documentsTab(BirV1Record record) {
    final docs = record.documents;
    return [
      SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: _busy ? null : _uploadDocument,
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('Upload document'),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'PDF, JPEG, PNG or WebP up to '
        '${(_meta.maxUploadBytes / 1048576).round()} MB.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 18),
      if (docs.isEmpty)
        const EmptyState(
          icon: Icons.folder_open_rounded,
          label: 'No documents',
          hint: 'No documents are attached to this V1 record yet.',
        )
      else
        for (var i = 0; i < docs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FadeSlideIn(
              index: i,
              child: _DocumentRow(
                document: docs[i],
                onOpen: docs[i].exists && !_busy
                    ? () => _openRemote(
                        () =>
                            widget.service.downloadDocument(record.id, docs[i]),
                        'Opening ${docs[i].displayName}…',
                      )
                    : null,
                onDelete: () => _deleteDocument(docs[i]),
              ),
            ),
          ),
    ];
  }
}

class _FileAction extends StatelessWidget {
  const _FileAction({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return AppCard(
      onTap: enabled ? onTap : null,
      padding: const EdgeInsets.all(12),
      radius: Brand.radiusLg,
      child: Row(
        children: [
          IconTile(
            icon: icon,
            color: enabled ? color : b.paperDim,
            size: 44,
            iconSize: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleSmall?.copyWith(
                    color: enabled ? b.paper : b.paperDim,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.open_in_new_rounded,
            size: 18,
            color: enabled ? b.signal : b.paperDim,
          ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.document,
    required this.onOpen,
    required this.onDelete,
  });

  final BirV1Document document;
  final VoidCallback? onOpen;
  final VoidCallback onDelete;

  IconData get _icon {
    final mime = document.mimeType.toLowerCase();
    final name = document.displayName.toLowerCase();
    if (mime.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|gif|webp|bmp)$').hasMatch(name)) {
      return Icons.image_rounded;
    }
    if (mime.contains('pdf') || name.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final missing = !document.exists;
    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(12),
      radius: Brand.radiusLg,
      child: Row(
        children: [
          IconTile(
            icon: _icon,
            color: missing ? Brand.danger : b.signal,
            size: 44,
            iconSize: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.displayName,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  missing
                      ? '${document.subtitle} · file missing on disk'
                      : document.subtitle,
                  style: text.bodySmall?.copyWith(
                    color: missing ? Brand.danger : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          AppIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete document',
            color: Brand.danger,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class BirV1PtuUploadScreen extends StatefulWidget {
  const BirV1PtuUploadScreen({
    super.key,
    required this.service,
    required this.record,
  });

  final BirV1Service service;
  final BirV1Record record;

  @override
  State<BirV1PtuUploadScreen> createState() => _BirV1PtuUploadScreenState();
}

class _BirV1PtuUploadScreenState extends State<BirV1PtuUploadScreen> {
  final List<PickedFile> _files = <PickedFile>[];
  final ScrollController _scroll = ScrollController();

  bool _processing = false;
  String _busyLabel = '';
  String _noticeTitle = '';
  String _noticeMessage = '';
  bool _noticeIsWarning = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (mounted) birV1Toast(context, message);
  }

  void _warn(String message) {
    setState(() {
      _noticeIsWarning = true;
      _noticeTitle = '';
      _noticeMessage = message;
    });
  }

  void _fail(String message, {String title = ''}) {
    setState(() {
      _processing = false;
      _busyLabel = '';
      _noticeIsWarning = false;
      _noticeTitle = title;
      _noticeMessage = message;
    });
    _toast(title.isEmpty ? message : '$title\n$message');
  }

  Future<void> _pick() async {
    final picked = await pickWithSource(
      context,
      allowCamera: false,
      multiple: true,
      allowedExtensions: const <String>['pdf'],
      fileLabel: 'Select PDF file',
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final file in picked) {
        if (!_files.any((e) => e.path == file.path)) _files.add(file);
      }
      _noticeTitle = '';
      _noticeMessage = '';
    });
  }

  List<String> _mergeMachineSerials(List<Map<String, dynamic>> items) {
    final found = <String>{};
    for (final item in items) {
      Object? raw = item['MergedMachineSerials'];
      if (raw == null || '$raw'.trim().isEmpty) {
        final software = item['SoftwareInfo'];
        if (software is List && software.isNotEmpty && software.first is Map) {
          raw = (software.first as Map)['MachineDetails'];
        }
      }
      if (raw == null) continue;
      for (final part in '$raw'.split('/')) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty) found.add(trimmed);
      }
    }
    return found.toList()..sort();
  }

  Future<void> _submit() async {
    if (_processing) return;
    if (_files.isEmpty) {
      _warn('Choose at least one Permit to Use PDF.');
      return;
    }

    setState(() {
      _processing = true;
      _busyLabel = 'Reading PDF…';
      _noticeTitle = '';
      _noticeMessage = '';
    });

    final List<Map<String, dynamic>> items;
    try {
      items = await widget.service.step3Extract(
        _files.map((e) => e.path).toList(growable: false),
      );
    } catch (e) {
      if (!mounted) return;
      _fail(_errorText(e));
      return;
    }
    if (!mounted) return;

    final stored = <String>[];
    for (final item in items) {
      final filename = '${item['filename'] ?? ''}'.trim();
      if (filename.isNotEmpty) stored.add(filename);
    }

    final merged = _mergeMachineSerials(items).join('/');
    final expected = widget.record.serialNumber.trim();
    if (expected != merged) {
      _fail(
        'PDF: ${merged.isEmpty ? '—' : merged}\n'
        'Record: ${expected.isEmpty ? '—' : expected}',
        title: 'Serial Number Not Match',
      );
      return;
    }

    if (stored.isEmpty) {
      _fail('The V1 system did not report where it stored the PDF.');
      return;
    }

    final first = items.first;
    final softwareList = first['SoftwareInfo'];
    final software =
        (softwareList is List &&
            softwareList.isNotEmpty &&
            softwareList.first is Map)
        ? Map<String, dynamic>.from(softwareList.first as Map)
        : <String, dynamic>{};

    final values = <String, String>{
      'ptu': '${software['PTU'] ?? ''}'.trim(),
      'min': '${software['MIN'] ?? ''}'.trim(),
      'pos_date_issued': '${first['PosDateIssued'] ?? ''}'.trim(),
    };
    final missing = values.entries
        .where((e) => e.value.isEmpty)
        .map((e) => e.key)
        .toList(growable: false);
    if (missing.isNotEmpty) {
      _fail(
        'The PDF is missing ${missing.join(', ')}. '
        'Enter them manually from the record\'s Workflow tab instead.',
      );
      return;
    }

    setState(() => _busyLabel = 'Completing…');
    try {
      await widget.service.step3Update(
        widget.record.id,
        posDateIssued: values['pos_date_issued']!,
        ptu: values['ptu']!,
        min: values['min']!,
        filename: stored.join(','),
        machineDetails: merged,
      );
    } catch (e) {
      if (!mounted) return;
      _fail(_errorText(e));
      return;
    }
    if (!mounted) return;

    setState(() {
      _processing = false;
      _busyLabel = '';
    });
    final company = widget.record.companyName.trim();
    birV1Toast(
      context,
      '${company.isEmpty ? 'This registration' : company} is now completed '
      '(PTU ${values['ptu']}).',
    );
    Navigator.of(context).pop(true);
  }

  void _handleBack() {
    if (_processing) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_processing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: StationScaffold(
        stationLabel: 'BIR Registration V1',
        title: 'Upload PTU Document',
        subtitle: widget.record.title,
        compact: true,
        showBottomBrand: false,
        onBack: _handleBack,
        bottomBar: BirBottomBar(
          children: [
            Expanded(
              child: SignalButton(
                label: _processing
                    ? (_busyLabel.isEmpty ? 'Working…' : _busyLabel)
                    : 'Continue',
                busy: _processing,
                onPressed: _files.isEmpty || _processing ? null : _submit,
              ),
            ),
          ],
        ),
        child: ListView(
          controller: _scroll,
          children: [
            BirSection(
              title: 'Upload PTU Document',
              subtitle: 'Upload the Permit to Use Sales Machine PDF file.',
              icon: Icons.description_rounded,
              iconColor: Brand.danger,
              children: [
                if (_noticeMessage.isNotEmpty)
                  BirNotice(
                    color: _noticeIsWarning ? Brand.warning : Brand.danger,
                    icon: _noticeIsWarning
                        ? Icons.info_outline_rounded
                        : Icons.error_outline_rounded,
                    title: _noticeTitle.isEmpty ? null : _noticeTitle,
                    message: _noticeMessage,
                  ),
                if (_processing)
                  const BirNotice(
                    color: Brand.info,
                    icon: Icons.hourglass_top_rounded,
                    title: 'Processing your document...',
                    message:
                        "This may take a moment. Please don't close this window.",
                  ),
                for (var i = 0; i < _files.length; i++)
                  BirFileRow(
                    name: _files[i].name,
                    caption: 'Ready to extract',
                    icon: Icons.picture_as_pdf_rounded,
                    iconColor: Brand.danger,
                    onRemove: _processing
                        ? null
                        : () => setState(() => _files.removeAt(i)),
                  ),
                BirUploadTile(
                  label: _files.isEmpty ? 'Select PDF File' : 'Add another PDF',
                  icon: Icons.cloud_upload_rounded,
                  onTap: _processing ? null : _pick,
                  hint: 'PDF files only, up to 10 at a time',
                ),
                const SizedBox(height: 10),
                Text(
                  'Registered serial number: '
                  '${_or(widget.record.serialNumber)}',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'The V1 system reads the PDF and completes this '
                  'registration. Use the Workflow tab to type the PTU, MIN '
                  'and issue date instead.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
