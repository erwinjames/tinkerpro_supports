import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/email_models.dart';
import '../services/email_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Emails — native subscriber list. Filter by source (ALL / EMAILS / LEADS),
/// search, delete a row, and compose either to one subscriber or to everyone.
/// Backed by the `getEmails` / `deleteEmail` / `sendSingleEmail` /
/// `sendEmailToAll` actions on api.php.
class EmailListScreen extends StatefulWidget {
  const EmailListScreen({super.key, required this.service});
  final EmailService service;

  @override
  State<EmailListScreen> createState() => _EmailListScreenState();
}

class _EmailListScreenState extends State<EmailListScreen> {
  List<EmailEntry> _rows = const [];
  bool _loading = true;
  String _source = 'all';
  final TextEditingController _search = TextEditingController();

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
    final rows = await widget.service.list(
      source: _source,
      search: _search.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _setSource(String source) {
    if (_source == source) return;
    setState(() => _source = source);
    _load();
  }

  Future<void> _openCompose({EmailEntry? to, bool sendAll = false}) async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _ComposeScreen(
          service: widget.service,
          to: to,
          sendAll: sendAll,
        ),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('EMAIL SENT')));
    }
  }

  Future<void> _confirmDelete(EmailEntry row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: Text(row.isLead ? 'Unsubscribe lead?' : 'Delete subscriber?'),
        content: Text(
          row.isLead
              ? 'This removes ${row.email} from the mailing list.'
              : 'This permanently removes ${row.email}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.service.delete(row.id, row.source);
    if (!mounted) return;
    if (res.ok) {
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text((res.message ?? 'Could not delete.').toUpperCase())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'EMAILS',
      title: 'Subscribers.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.campaign,
        tooltip: 'Mail all',
        onPressed: () => _openCompose(sendAll: true),
      ),
      child: Column(
        children: [
          _SourceFilter(value: _source, onChanged: _setSource),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              labelText: 'SEARCH EMAIL',
              suffixIcon: Icon(Icons.search, color: Brand.paperDim),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Hairline(),
          Expanded(
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
                            strokeWidth: 2, color: Brand.signal),
                      ),
                    )
                  : _rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 64),
                            EmptyState(
                              label: 'No subscribers',
                              hint: 'Adjust the filter or search. '
                                  'Pull to refresh.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => const Hairline(),
                          itemBuilder: (_, i) => _EmailRow(
                            row: _rows[i],
                            onTap: () => _openCompose(to: _rows[i]),
                            onDelete: () => _confirmDelete(_rows[i]),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented ALL / EMAILS / LEADS filter.
class _SourceFilter extends StatelessWidget {
  const _SourceFilter({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  static const _options = <List<String>>[
    ['all', 'ALL'],
    ['emails', 'EMAILS'],
    ['leads', 'LEADS'],
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Brand.rule),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: _options.map((opt) {
          final selected = value == opt[0];
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(opt[0]),
              behavior: HitTestBehavior.opaque,
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Brand.signal : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  opt[1],
                  style: text.labelMedium?.copyWith(
                    color: selected ? Brand.canvas : Brand.paperDim,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmailRow extends StatelessWidget {
  const _EmailRow({
    required this.row,
    required this.onTap,
    required this.onDelete,
  });
  final EmailEntry row;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final subtitle = row.businessType.isEmpty
        ? (row.createdAt.isEmpty ? 'Subscriber' : row.createdAt)
        : row.businessType;
    return Dismissible(
      key: ValueKey('${row.source}-${row.id}-${row.email}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        color: Brand.signal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Brand.canvas),
      ),
      child: InkWell(
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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: row.isLead ? Brand.rule : Brand.signal,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.email,
                        style: text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(row.isLead ? 'LEAD' : 'EMAIL',
                  style: text.labelMedium?.copyWith(
                    color: row.isLead ? Brand.paperDim : Brand.signal,
                    letterSpacing: 2.2,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compose screen — single recipient (prefilled To) or a broadcast to all.
class _ComposeScreen extends StatefulWidget {
  const _ComposeScreen({required this.service, this.to, this.sendAll = false});
  final EmailService service;
  final EmailEntry? to;
  final bool sendAll;

  @override
  State<_ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<_ComposeScreen> {
  late final TextEditingController _to;
  final TextEditingController _subject = TextEditingController();
  final TextEditingController _message = TextEditingController();
  late bool _all;
  String? _attachmentPath;
  String? _attachmentName;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _to = TextEditingController(text: widget.to?.email ?? '');
    _all = widget.sendAll;
  }

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.path == null) return;
      setState(() {
        _attachmentPath = file.path;
        _attachmentName = file.name;
      });
    } catch (_) {
      _toast('Could not pick file.');
    }
  }

  void _clearAttachment() {
    setState(() {
      _attachmentPath = null;
      _attachmentName = null;
    });
  }

  Future<void> _send() async {
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (subject.isEmpty) {
      _toast('Subject is required.');
      return;
    }
    if (message.isEmpty) {
      _toast('Message is required.');
      return;
    }
    if (!_all) {
      final to = _to.text.trim();
      if (to.isEmpty) {
        _toast('Recipient email is required.');
        return;
      }
    }
    setState(() => _sending = true);
    final EmailResult res;
    if (_all) {
      res = await widget.service.sendAll(
        subject: subject,
        message: message,
        attachmentPath: _attachmentPath,
      );
    } else {
      res = await widget.service.sendSingle(
        email: _to.text.trim(),
        subject: subject,
        message: message,
        attachmentPath: _attachmentPath,
      );
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not send the email.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: _all ? 'MAIL ALL' : 'COMPOSE',
      title: _all ? 'Broadcast.' : 'Compose.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          _ToggleRow(
            label: 'SEND TO ALL SUBSCRIBERS',
            value: _all,
            onChanged: (v) => setState(() => _all = v),
          ),
          const SizedBox(height: 16),
          if (!_all) ...[
            TextField(
              controller: _to,
              decoration: const InputDecoration(labelText: 'TO'),
              keyboardType: TextInputType.emailAddress,
              style: text.titleMedium,
            ),
            const SizedBox(height: 16),
          ] else ...[
            Text(
              'This email goes out to every subscriber.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _subject,
            decoration: const InputDecoration(labelText: 'SUBJECT'),
            style: text.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _message,
            decoration: const InputDecoration(labelText: 'MESSAGE'),
            style: text.titleMedium,
            minLines: 5,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: 16),
          StationDataRow(
            label: 'ATTACHMENT',
            value: _attachmentName ?? 'Tap to attach a file',
            onTap: _pickAttachment,
            trailingIcon: Icons.attach_file,
          ),
          if (_attachmentPath != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: 'Remove attachment',
                onPressed: _clearAttachment,
              ),
            ),
          ],
          const SizedBox(height: 32),
          SignalButton(
            label: _all ? 'Send to all' : 'Send email',
            icon: Icons.send,
            busy: _sending,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Brand.signal,
        ),
      ],
    );
  }
}
