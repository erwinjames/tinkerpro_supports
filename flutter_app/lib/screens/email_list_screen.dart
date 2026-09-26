import 'package:flutter/material.dart';

import '../models/email_models.dart';
import '../services/email_service.dart';
import '../theme.dart';
import '../widgets/pick_source.dart';
import '../widgets/premium.dart';
import 'email_internal_compose.dart';
import 'email_internal_tab.dart';

enum _EmailTab { subscribers, internal }

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

  _EmailTab _tab = _EmailTab.subscribers;
  int? _internalCount;
  final ValueNotifier<int> _internalRefresh = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _internalRefresh.dispose();
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
        builder: (_) =>
            _ComposeScreen(service: widget.service, to: to, sendAll: sendAll),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email sent')));
    }
  }

  Future<void> _confirmDelete(EmailEntry row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(row.isLead ? 'Unsubscribe lead?' : 'Delete subscriber?'),
        content: Text(
          row.isLead
              ? 'This removes ${row.email} from the mailing list.'
              : 'This permanently removes ${row.email}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(row.isLead ? 'Unsubscribe' : 'Delete'),
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
        SnackBar(content: Text(res.message ?? 'Could not delete.')),
      );
    }
  }

  static const _sources = ['all', 'emails', 'leads'];

  String _sourceLabel(String s) => switch (s) {
    'emails' => 'Emails',
    'leads' => 'Leads',
    _ => 'All',
  };

  int? _countFor(String s) {
    if (_loading || _source != 'all') return null;
    return switch (s) {
      'emails' => _rows.where((r) => !r.isLead).length,
      'leads' => _rows.where((r) => r.isLead).length,
      _ => _rows.length,
    };
  }

  Future<void> _openInternalCompose(InternalRecipient? prefill) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            InternalComposeScreen(service: widget.service, prefill: prefill),
      ),
    );
    if (changed == true && mounted) _internalRefresh.value++;
  }

  String _tabLabel(_EmailTab tab) =>
      tab == _EmailTab.subscribers ? 'Subscribers' : 'Internal Email';

  int? _tabCount(_EmailTab tab) =>
      tab == _EmailTab.subscribers ? null : _internalCount;

  @override
  Widget build(BuildContext context) {
    final internal = _tab == _EmailTab.internal;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Marketing',
      title: internal ? 'Internal Email' : 'Subscribers',
      subtitle: internal
          ? (_internalCount == null
                ? 'Loading…'
                : '$_internalCount ${_internalCount == 1 ? 'recipient' : 'recipients'}')
          : (_loading
                ? 'Loading…'
                : '${_rows.length} ${_rows.length == 1 ? 'contact' : 'contacts'}'),
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: internal
          ? StationAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Refresh',
              onPressed: () => _internalRefresh.value++,
            )
          : StationAction(
              icon: Icons.campaign_rounded,
              tooltip: 'Mail all',
              onPressed: () => _openCompose(sendAll: true),
            ),
      fab: internal
          ? FloatingActionButton.extended(
              heroTag: 'email-internal-compose',
              onPressed: () => _openInternalCompose(null),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('New message'),
            )
          : FloatingActionButton.extended(
              heroTag: 'email-compose',
              onPressed: () => _openCompose(),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Compose'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChoicePills<_EmailTab>(
            options: _EmailTab.values,
            value: _tab,
            labelOf: _tabLabel,
            countOf: _tabCount,
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: IndexedStack(
              index: _EmailTab.values.indexOf(_tab),
              sizing: StackFit.expand,
              children: [
                _subscribersTab(context),
                InternalEmailTab(
                  service: widget.service,
                  refresh: _internalRefresh,
                  onCount: (value) {
                    if (!mounted || _internalCount == value) return;
                    setState(() => _internalCount = value);
                  },
                  onCompose: _openInternalCompose,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscribersTab(BuildContext context) {
    final b = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InboxStrip(
          total: _rows.length,
          unread: _rows.where((r) => _isRecent(r.createdAt)).length,
          loading: _loading,
        ),
        const SizedBox(height: 14),
        AppSearchField(
          controller: _search,
          hint: 'Search email',
          onSubmitted: (_) => _load(),
          onChanged: (v) {
            if (v.isEmpty) _load();
          },
        ),
        const SizedBox(height: 12),
        ChoicePills<String>(
          options: _sources,
          value: _source,
          onChanged: _setSource,
          labelOf: _sourceLabel,
          countOf: _countFor,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const SkeletonList(count: 8)
              : RefreshIndicator(
                  color: b.signal,
                  backgroundColor: b.surface,
                  onRefresh: _load,
                  child: _rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 64),
                            EmptyState(
                              icon: Icons.mark_email_unread_rounded,
                              label: 'No subscribers',
                              hint:
                                  'Adjust the filter or search. '
                                  'Pull to refresh.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _Stagger(
                            index: i,
                            child: _EmailRow(
                              row: _rows[i],
                              onTap: () => _openCompose(to: _rows[i]),
                              onDelete: () => _confirmDelete(_rows[i]),
                            ),
                          ),
                        ),
                ),
        ),
      ],
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
    final b = context.brand;
    final subtitle = row.businessType.isEmpty
        ? (row.isLead ? 'Lead' : 'Newsletter subscriber')
        : row.businessType;
    final date = row.createdAt.split(' ').first;
    final unread = _isRecent(row.createdAt);
    final accent = row.isLead ? b.info : b.signal;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motion = reduce ? Duration.zero : const Duration(milliseconds: 260);
    return Dismissible(
      key: ValueKey('${row.source}-${row.id}-${row.email}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: b.danger,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              row.isLead ? 'Unsubscribe' : 'Delete',
              style: text.labelLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.delete_outline_rounded, color: Colors.white),
          ],
        ),
      ),
      child: AnimatedContainer(
        duration: motion,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: b.surface,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          border: Border.all(
            color: unread
                ? accent.withValues(alpha: b.isDark ? 0.55 : 0.45)
                : b.rule,
          ),
          boxShadow: b.shadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.radiusLg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: motion,
                    curve: Curves.easeOut,
                    width: 3,
                    height: unread ? 40 : 0,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: accent,
                    ),
                  ),
                  AnimatedContainer(
                    duration: motion,
                    curve: Curves.easeOut,
                    width: unread ? 10 : 0,
                  ),
                  AppAvatar(name: row.email, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AnimatedDefaultTextStyle(
                                duration: motion,
                                curve: Curves.easeOut,
                                style:
                                    text.titleSmall?.copyWith(
                                      color: b.paper,
                                      fontWeight: FontWeight.w600,
                                    ) ??
                                    const TextStyle(),
                                child: Text(
                                  row.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            if (date.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                date,
                                style: text.labelSmall?.copyWith(
                                  color: b.paperDim,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                subtitle,
                                style: text.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedSize(
                              duration: motion,
                              curve: Curves.easeOut,
                              child: unread
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: _GlowChip(
                                        label: 'New',
                                        color: accent,
                                        icon: Icons.bolt_rounded,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            StatusPill(
                              label: row.isLead ? 'Lead' : 'Email',
                              color: accent,
                              icon: row.isLead
                                  ? Icons.person_pin_rounded
                                  : Icons.mail_outline_rounded,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'More actions',
                    icon: Icon(Icons.more_vert_rounded, color: b.paperDim),
                    onSelected: (v) {
                      if (v == 'mail') onTap();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'mail',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.send_rounded),
                          title: Text('Send email'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.delete_outline_rounded,
                            color: Brand.danger,
                          ),
                          title: Text(
                            row.isLead ? 'Unsubscribe' : 'Delete',
                            style: const TextStyle(color: Brand.danger),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    final picked = await pickWithSource(
      context,
      cameraLabel: 'Take a photo',
      fileLabel: 'Choose a file',
    );
    if (picked.isEmpty || !mounted) return;
    final file = picked.first;
    setState(() {
      _attachmentPath = file.path;
      _attachmentName = file.name;
    });
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Marketing',
      title: _all ? 'Broadcast email' : 'Compose email',
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          const SectionHeader(title: 'Recipients'),
          GlassPanel(
            accent: _all ? Brand.warning : b.signal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ToggleRow(
                  label: 'Send to all subscribers',
                  hint: _all
                      ? 'Goes out to every subscriber and lead'
                      : 'Send to a single address',
                  value: _all,
                  onChanged: (v) => setState(() => _all = v),
                ),
                if (!_all) ...[
                  const SizedBox(height: 12),
                  const Hairline(),
                  const SizedBox(height: 12),
                  _FieldLabel('To'),
                  TextField(
                    controller: _to,
                    decoration: const InputDecoration(
                      hintText: 'name@example.com',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textInputAction: TextInputAction.next,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: b.tint(Brand.warning, 0.12),
                      borderRadius: BorderRadius.circular(Brand.radiusSm),
                      border: Border.all(
                        color: Brand.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.campaign_rounded,
                          size: 20,
                          color: Brand.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This email goes out to every subscriber.',
                            style: text.bodySmall?.copyWith(color: b.paper),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Message'),
          AppCard(
            radius: Brand.radiusLg,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FieldLabel('Subject'),
                TextField(
                  controller: _subject,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Subject',
                    prefixIcon: Icon(Icons.subject_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                _FieldLabel('Message'),
                TextField(
                  controller: _message,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Write your message',
                    alignLabelWithHint: true,
                  ),
                  minLines: 6,
                  maxLines: 14,
                  keyboardType: TextInputType.multiline,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Attachment'),
          AppCard(
            onTap: _pickAttachment,
            radius: Brand.radiusLg,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _TypeTile(
                  icon: _attachmentName == null
                      ? Icons.attach_file_rounded
                      : Icons.insert_drive_file_rounded,
                  color: Brand.info,
                  size: 44,
                  iconSize: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _attachmentName ?? 'Attach a file',
                        style: text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _attachmentName == null
                            ? 'Optional · tap to choose'
                            : 'Tap to replace',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (_attachmentPath != null)
                  IconButton(
                    tooltip: 'Remove attachment',
                    onPressed: _clearAttachment,
                    icon: Icon(Icons.close_rounded, color: b.paperDim),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.add_rounded, color: b.signal),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SignalButton(
            label: _all ? 'Send to all' : 'Send email',
            icon: Icons.send_rounded,
            busy: _sending,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.titleSmall),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(hint!, style: text.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

bool _isRecent(String createdAt) {
  final raw = createdAt.trim();
  if (raw.isEmpty) return false;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return false;
  final age = DateTime.now().difference(parsed);
  return !age.isNegative && age.inDays < 7;
}

class _InboxStrip extends StatelessWidget {
  const _InboxStrip({
    required this.total,
    required this.unread,
    required this.loading,
  });

  final int total;
  final int unread;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motion = reduce ? Duration.zero : const Duration(milliseconds: 260);
    Widget metric(String label, int value, Color color) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: motion,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              loading ? '—' : '$value',
              key: ValueKey<String>('$label-${loading ? -1 : value}'),
              style: text.headlineSmall?.copyWith(color: b.paper),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(color: b.paperDim),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          metric('Contacts', total, b.signal),
          Container(width: 1, height: 34, color: b.rule),
          const SizedBox(width: 16),
          metric('New this week', unread, Brand.success),
        ],
      ),
    );
  }
}

class _Stagger extends StatelessWidget {
  const _Stagger({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce || index > 7) return child;
    final delay = index * 45;
    final total = 280 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutCubic),
      builder: (context, t, inner) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}

Color _chipInk(BuildContext context, Color color) {
  final b = context.brand;
  if (b.isDark) {
    return color.computeLuminance() < 0.22
        ? Color.lerp(color, Colors.white, 0.6)!
        : color;
  }
  return color.computeLuminance() > 0.3
      ? Color.lerp(color, Brand.navy, 0.45)!
      : color;
}

class _GlowChip extends StatelessWidget {
  const _GlowChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final ink = _chipInk(context, color);
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
          if (icon != null) ...[
            Icon(icon, size: 13, color: ink),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.icon,
    required this.color,
    this.size = 44,
    this.iconSize = 21,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: iconSize, color: _chipInk(context, color)),
    );
  }
}
