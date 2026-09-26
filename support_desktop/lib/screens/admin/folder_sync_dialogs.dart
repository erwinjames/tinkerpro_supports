import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../services/folder_sync_engine.dart';
import '../../services/folder_sync_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';
import '../../widgets/tp_loader.dart';

const _muted = Color(0xFF6B7280);
const _text = Color(0xFF1F2937);
const _border = Color(0xFFE5E7EB);

String fsAgo(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

Future<String?> fsPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String confirm,
  String initial = '',
  String hint = '',
  String emptyError = 'Please enter a name',
  IconData icon = Icons.edit_outlined,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _Prompt(
      title: title,
      label: label,
      confirm: confirm,
      initial: initial,
      hint: hint,
      emptyError: emptyError,
      icon: icon,
    ),
  );
}

class _Prompt extends StatefulWidget {
  const _Prompt({
    required this.title,
    required this.label,
    required this.confirm,
    required this.initial,
    required this.hint,
    required this.emptyError,
    required this.icon,
  });
  final String title;
  final String label;
  final String confirm;
  final String initial;
  final String hint;
  final String emptyError;
  final IconData icon;

  @override
  State<_Prompt> createState() => _PromptState();
}

class _PromptState extends State<_Prompt> {
  late final _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void initState() {
    super.initState();
    final dot = widget.initial.lastIndexOf('.');
    _ctrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: dot > 0 ? dot : widget.initial.length,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.trim().isEmpty) {
      setState(() => _error = widget.emptyError);
      return;
    }
    Navigator.pop(context, _ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: widget.title,
      icon: widget.icon,
      width: 480,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        SignalButton(label: widget.confirm, onPressed: _submit),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(widget.label),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: InputDecoration(
              errorText: _error,
              hintText: widget.hint.isEmpty ? null : widget.hint,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    );
  }
}

Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _text,
        ),
      ),
    );

Widget _hint(String t, {Color color = _muted}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(t, style: TextStyle(fontSize: 12, color: color)),
    );

Widget _rowName(IconData icon, Color color, String name, String? sub) => Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: name,
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _text),
              ),
              if (sub != null && sub.isNotEmpty)
                TextSpan(
                  text: '  $sub',
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

Widget _row({required Widget left, Widget? right}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        children: [
          Expanded(child: left),
          ?right,
        ],
      ),
    );

Widget _rowBtn(String label, IconData? icon, VoidCallback? onTap,
        {bool danger = false}) =>
    OutlinedButton.icon(
      onPressed: onTap,
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 14),
      label: Text(label,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? Brand.danger : Brand.signal,
        side: BorderSide(color: danger ? const Color(0xFFFCA5A5) : Brand.signal),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    );

class FsSettingsDialog extends StatefulWidget {
  const FsSettingsDialog({super.key, required this.onSync});
  final VoidCallback onSync;

  @override
  State<FsSettingsDialog> createState() => _FsSettingsDialogState();
}

class _FsSettingsDialogState extends State<FsSettingsDialog> {
  final engine = FolderSyncEngine.instance;

  @override
  void initState() {
    super.initState();
    engine.addListener(_changed);
  }

  @override
  void dispose() {
    engine.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _choose() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the folder to sync',
      initialDirectory: engine.settings.localPath,
    );
    if (path == null || path.isEmpty) return;
    await engine.setLocalPath(path);
  }

  Widget _check(bool value, ValueChanged<bool> onChanged, List<InlineSpan> text) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13.5, color: _text, height: 1.35),
                    children: text,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = engine.settings;
    final src = s.localPath;
    const bold = TextStyle(fontWeight: FontWeight.w700);
    return WebModal(
      title: 'Folder Sync Settings',
      icon: Icons.settings_outlined,
      width: 720,
      actions: [
        SignalButton(
          label: 'Save & Sync Folder',
          icon: Icons.cloud_upload_outlined,
          onPressed: engine.running
              ? null
              : () {
                  Navigator.pop(context);
                  if (engine.hasSource) widget.onSync();
                },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label('Source folder'),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _choose,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Choose Folder',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Brand.signal,
                  side: const BorderSide(color: Brand.signal),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: src == null
                    ? const Text('No folder selected yet.',
                        style: TextStyle(color: _muted, fontSize: 13.5))
                    : Row(
                        children: [
                          const Icon(Icons.folder, color: Brand.signal, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Tooltip(
                              message: src,
                              child: Text(
                                src,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: _text),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (src != null)
                IconButton(
                  tooltip: 'Clear selection',
                  onPressed: () => engine.setLocalPath(null),
                  icon: const Icon(Icons.close, size: 18, color: _muted),
                ),
            ],
          ),
          if (src != null)
            _hint('Remembered on this computer. Files are read only when a sync runs.',
                color: const Color(0xFF059669)),
          const SizedBox(height: 14),
          _check(s.stripTop, (v) => engine.setOption(stripTop: v), const [
            TextSpan(text: "Place the folder's "),
            TextSpan(text: 'contents', style: bold),
            TextSpan(
                text:
                    ' directly into the destination (uncheck to keep the folder itself as a sub-folder)'),
          ]),
          _check(s.force, (v) => engine.setOption(force: v), const [
            TextSpan(
                text:
                    'Re-sync everything (ignore already-synced files and sync all)'),
          ]),
          _check(s.mirror, (v) => engine.setOption(mirror: v), const [
            TextSpan(text: 'Mirror', style: bold),
            TextSpan(
                text:
                    ' — make the destination an exact copy of the source: delete anything not in the local folder. '),
            TextSpan(
              text:
                  'This erases files you renamed or created here on the web. Leave OFF if you manage files in this explorer.',
              style: TextStyle(color: Color(0xFFB91C1C)),
            ),
          ]),
          _check(s.twoWay, (v) => engine.setOption(twoWay: v), const [
            TextSpan(text: 'Two-way', style: bold),
            TextSpan(
                text:
                    ' — apply web edits (rename, move, new folder, delete, uploads) back to your local folder, and pull files added on the web into it, so the web side is authoritative. '),
            TextSpan(
              text: 'Needs a chosen folder and "contents" placement.',
              style: TextStyle(color: Color(0xFF9CA3AF)),
            ),
          ]),
          const Divider(height: 22),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Auto sync',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: _text)),
                    _hint(src == null
                        ? 'Choose a source folder first.'
                        : 'Watches the folder and syncs changes automatically while the app is open${s.twoWay ? ', and pulls web changes' : ''}.'),
                  ],
                ),
              ),
              Switch(
                value: s.auto,
                activeTrackColor: Brand.signal,
                activeThumbColor: Colors.white,
                onChanged: src == null
                    ? null
                    : (v) => engine.setOption(auto: v),
              ),
            ],
          ),
          if (engine.running || engine.status.isNotEmpty) ...[
            const SizedBox(height: 14),
            FsProgressBar(value: engine.running ? engine.progress : 1),
            const SizedBox(height: 8),
            Text(engine.status,
                style: const TextStyle(fontSize: 13, color: _text)),
            if ((engine.lastResult?.errors ?? const []).isNotEmpty &&
                !engine.running)
              FsErrorLog(errors: engine.lastResult!.errors),
          ],
        ],
      ),
    );
  }
}

class FsProgressBar extends StatelessWidget {
  const FsProgressBar({super.key, this.value});
  final double? value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 6,
        backgroundColor: const Color(0xFFF1F5F9),
        valueColor: const AlwaysStoppedAnimation(Brand.signal),
      ),
    );
  }
}

class FsErrorLog extends StatelessWidget {
  const FsErrorLog({super.key, required this.errors});
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 140),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          errors.join('\n'),
          style: const TextStyle(
              fontSize: 12, color: Color(0xFFB91C1C), height: 1.4),
        ),
      ),
    );
  }
}

class FsInviteDialog extends StatefulWidget {
  const FsInviteDialog({super.key, required this.api});
  final FolderSyncApi api;

  @override
  State<FsInviteDialog> createState() => _FsInviteDialogState();
}

class _FsInviteDialogState extends State<FsInviteDialog> {
  final _link = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;
  List<FsUser>? _results;
  final Set<int> _invited = {};
  final Set<int> _busy = {};
  final Set<int> _resent = {};
  List<FsMember> _members = const [];
  List<FsPending> _pending = const [];
  bool _loaded = false;
  final Map<int, Timer> _removing = {};

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final e in _removing.entries.toList()) {
      e.value.cancel();
      _commitRemove(e.key);
    }
    _link.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  Future<void> _loadMembers() async {
    try {
      final r = await widget.api.members();
      if (!mounted) return;
      setState(() {
        _members = r.members;
        _pending = r.pending;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _generate() async {
    try {
      final link = await widget.api.inviteLink();
      _link.text = link;
      _loadMembers();
    } catch (e) {
      _toast('Could not create link: $e');
    }
  }

  Future<void> _copy() async {
    if (_link.text.isEmpty) {
      _toast('Generate a link first.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: _link.text));
    _toast('Link copied.');
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) {
      setState(() => _results = null);
      return;
    }
    try {
      final r = await widget.api.searchUsers(q);
      if (mounted && _search.text.trim() == q) setState(() => _results = r);
    } catch (_) {}
  }

  Future<void> _invite(FsUser u) async {
    setState(() => _busy.add(u.id));
    try {
      final sent = await widget.api.inviteChat(u.id);
      _toast(sent ? 'Invite sent via chat.' : 'Invite created (chat unavailable).');
      if (mounted) setState(() => _invited.add(u.id));
      _loadMembers();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy.remove(u.id));
    }
  }

  Future<void> _resend(int uid) async {
    setState(() => _busy.add(-uid));
    try {
      final sent = await widget.api.inviteChat(uid);
      _toast(sent ? 'Invite re-sent via chat.' : 'Invite refreshed (chat unavailable).');
      if (mounted) setState(() => _resent.add(uid));
      Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _resent.remove(uid));
      });
    } catch (e) {
      _toast('Resend failed: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(-uid));
    }
  }

  void _remove(int uid) {
    setState(() {
      _removing[uid] = Timer(const Duration(seconds: 5), () {
        _removing.remove(uid);
        _commitRemove(uid);
      });
    });
  }

  void _undo(int uid) {
    _removing.remove(uid)?.cancel();
    setState(() {});
  }

  Future<void> _commitRemove(int uid) async {
    try {
      await widget.api.removeMember(uid);
    } catch (_) {}
    if (mounted) _loadMembers();
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      for (final m in _members)
        _removing.containsKey(m.userId)
            ? _row(
                left: _rowName(Icons.person_remove_outlined, _muted,
                    'Contributor removed', m.name),
                right: _rowBtn('Undo', Icons.undo, () => _undo(m.userId)),
              )
            : _row(
                left: _rowName(Icons.how_to_reg, const Color(0xFF10B981),
                    m.name, '@${m.username}'),
                right: _rowBtn('Remove', null, () => _remove(m.userId),
                    danger: true),
              ),
      for (final p in _pending)
        _row(
          left: _rowName(
            Icons.schedule,
            const Color(0xFFF59E0B),
            p.invitedTo ?? 'Link invite (pending)',
            p.invitedTo != null ? '(pending)' : null,
          ),
          right: p.invitedUserId == null
              ? null
              : _rowBtn(
                  _resent.contains(p.invitedUserId) ? 'Sent' : 'Resend',
                  _resent.contains(p.invitedUserId)
                      ? Icons.check
                      : Icons.send,
                  _busy.contains(-p.invitedUserId!)
                      ? null
                      : () => _resend(p.invitedUserId!),
                ),
        ),
    ];
    return WebModal(
      title: 'Invite contributors',
      icon: Icons.person_add_alt_1_outlined,
      width: 760,
      actions: [
        GhostButton(label: 'Close', onPressed: () => Navigator.pop(context)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 13.5, color: _muted),
              children: [
                TextSpan(text: 'Contributors get '),
                TextSpan(
                    text: 'view & download',
                    style: TextStyle(fontWeight: FontWeight.w700, color: _text)),
                TextSpan(text: " access to your folder (they can't change anything)."),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _label('Share link'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _link,
                  readOnly: true,
                  decoration:
                      const InputDecoration(hintText: 'Generate a link…'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Generate link',
                onPressed: _generate,
                icon: const Icon(Icons.sync, size: 18),
              ),
              const SizedBox(width: 8),
              SignalButton(label: 'Copy', icon: Icons.copy, onPressed: _copy),
            ],
          ),
          _hint('Anyone signed-in who opens this link becomes a contributor.'),
          const SizedBox(height: 18),
          _label('Invite a user (sends them a chat message)'),
          TextField(
            controller: _search,
            onChanged: _onSearch,
            decoration: const InputDecoration(
              hintText: 'Search name or username…',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
          if (_results != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _results!.isEmpty
                  ? _row(left: const Text('No users found', style: TextStyle(color: _muted)))
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final u in _results!)
                          _row(
                            left: _rowName(Icons.person_outline, _muted,
                                u.name, '@${u.username}'),
                            right: _rowBtn(
                              _invited.contains(u.id) ? 'Invited' : 'Invite',
                              _invited.contains(u.id) ? Icons.check : Icons.send,
                              (_invited.contains(u.id) || _busy.contains(u.id))
                                  ? null
                                  : () => _invite(u),
                            ),
                          ),
                      ],
                    ),
            ),
          const SizedBox(height: 18),
          _label('Current contributors'),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: !_loaded
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: Center(child: TpLoader()),
                  )
                : Column(
                    children: rows.isEmpty
                        ? [
                            _row(
                                left: const Text('No contributors yet.',
                                    style: TextStyle(color: _muted)))
                          ]
                        : rows,
                  ),
          ),
        ],
      ),
    );
  }
}

class FsEmailDialog extends StatefulWidget {
  const FsEmailDialog({
    super.key,
    required this.api,
    required this.owner,
    required this.rel,
    required this.name,
  });
  final FolderSyncApi api;
  final int owner;
  final String rel;
  final String name;

  @override
  State<FsEmailDialog> createState() => _FsEmailDialogState();
}

class _FsEmailDialogState extends State<FsEmailDialog> {
  final _to = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final to = _to.text.trim();
    if (to.isEmpty) {
      toast(context, 'Enter a recipient email.');
      return;
    }
    setState(() => _sending = true);
    try {
      final msg = await widget.api.sendEmail(widget.owner, widget.rel,
          to: to, subject: _subject.text.trim(), message: _message.text);
      if (!mounted) return;
      toast(context, msg);
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      toast(context, '$e');
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Send file by email',
      icon: Icons.email_outlined,
      width: 560,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        SignalButton(
            label: 'Send',
            icon: Icons.send,
            onPressed: _sending ? null : _send),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _rowName(Icons.attach_file, _muted, 'Attaching:', widget.name),
          const SizedBox(height: 16),
          _label('To'),
          TextField(
            controller: _to,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'recipient@example.com'),
          ),
          const SizedBox(height: 14),
          _label('Subject'),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(hintText: 'Optional'),
          ),
          const SizedBox(height: 14),
          _label('Message'),
          TextField(
            controller: _message,
            minLines: 4,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Optional message…'),
          ),
        ],
      ),
    );
  }
}

class FsChatDialog extends StatefulWidget {
  const FsChatDialog({
    super.key,
    required this.api,
    required this.owner,
    required this.rel,
    required this.name,
  });
  final FolderSyncApi api;
  final int owner;
  final String rel;
  final String name;

  @override
  State<FsChatDialog> createState() => _FsChatDialogState();
}

class _FsChatDialogState extends State<FsChatDialog> {
  final _message = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;
  List<FsUser>? _results;
  final Set<int> _busy = {};
  final Set<int> _sent = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _message.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) {
      setState(() => _results = null);
      return;
    }
    try {
      final r = await widget.api.chatDirectory(q);
      if (mounted && _search.text.trim() == q) setState(() => _results = r);
    } catch (_) {}
  }

  Future<void> _send(FsUser u) async {
    setState(() => _busy.add(u.id));
    try {
      await widget.api.sendFileToChat(
        owner: widget.owner,
        path: widget.rel,
        peerUserId: u.id,
        message: _message.text,
      );
      if (!mounted) return;
      toast(context, 'Sent “${widget.name}” to chat.');
      setState(() => _sent.add(u.id));
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy.remove(u.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: 'Send file to chat',
      icon: Icons.chat_bubble_outline,
      width: 560,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _rowName(Icons.attach_file, _muted, 'Sending:', widget.name),
          const SizedBox(height: 16),
          _label('Message'),
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(hintText: 'Optional message…'),
          ),
          const SizedBox(height: 14),
          _label('Send to'),
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: _onSearch,
            decoration: const InputDecoration(
              hintText: 'Search name or username…',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
          ),
          if (_results != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _results!.isEmpty
                  ? _row(
                      left: const Text('No users found',
                          style: TextStyle(color: _muted)))
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final u in _results!)
                          _row(
                            left: _rowName(Icons.person_outline, _muted,
                                u.name, '@${u.username}'),
                            right: _busy.contains(u.id)
                                ? _rowBtn('Sending', Icons.hourglass_top, null)
                                : _rowBtn(
                                    _sent.contains(u.id) ? 'Sent' : 'Send',
                                    _sent.contains(u.id)
                                        ? Icons.check
                                        : Icons.send,
                                    _sent.contains(u.id)
                                        ? null
                                        : () => _send(u),
                                  ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

String? fsInviteToken(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final uri = Uri.tryParse(t);
  final q = uri?.queryParameters['invite'];
  if (q != null && q.isNotEmpty) return q;
  final m = RegExp(r'invite=([A-Za-z0-9]+)').firstMatch(t);
  if (m != null) return m.group(1);
  if (RegExp(r'^[A-Za-z0-9]{8,64}$').hasMatch(t)) return t;
  return null;
}
