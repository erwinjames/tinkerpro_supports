import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../services/admin_files_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import 'admin_list.dart';

Future<bool> fmConfirm(
  BuildContext context, {
  required String title,
  required String text,
  required String confirm,
  String cancel = 'Cancel',
  bool danger = false,
}) async {
  final ok = await showWebModal<bool>(
    context,
    title: title,
    icon: danger ? Icons.warning_amber_rounded : Icons.help_outline,
    width: 480,
    builder: (ctx) => Text(text, style: Theme.of(ctx).textTheme.bodyMedium),
    actions: (ctx) => [
      GhostButton(label: cancel, onPressed: () => Navigator.pop(ctx, false)),
      danger
          ? DangerButton(
              label: confirm,
              onPressed: () => Navigator.pop(ctx, true),
            )
          : SignalButton(
              label: confirm,
              onPressed: () => Navigator.pop(ctx, true),
            ),
    ],
  );
  return ok ?? false;
}

Future<String?> fmFolderPrompt(
  BuildContext context, {
  required String title,
  required String confirm,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _FolderPrompt(title: title, confirm: confirm, initial: initial),
  );
}

class _FolderPrompt extends StatefulWidget {
  const _FolderPrompt({
    required this.title,
    required this.confirm,
    required this.initial,
  });
  final String title;
  final String confirm;
  final String initial;

  @override
  State<_FolderPrompt> createState() => _FolderPromptState();
}

class _FolderPromptState extends State<_FolderPrompt> {
  late final _ctrl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a folder name');
      return;
    }
    Navigator.pop(context, _ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return WebModal(
      title: widget.title,
      icon: Icons.create_new_folder_outlined,
      width: 480,
      actions: [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        SignalButton(label: widget.confirm, onPressed: _submit),
      ],
      child: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 255,
        decoration: InputDecoration(errorText: _error, counterText: ''),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}

Future<({bool ok, String value})> fmMovePrompt(
  BuildContext context, {
  required String name,
  required String current,
  required List<({String id, String label})> options,
}) async {
  var value = options.any((o) => o.id == current) ? current : '';
  final ok = await showWebModal<bool>(
    context,
    title: 'Move "$name"',
    icon: Icons.open_with,
    width: 520,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Pick the folder it should live in. Everything inside moves with it.',
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            items: [
              const DropdownMenuItem(
                value: '',
                child: Text('All Collections (root level)'),
              ),
              for (final o in options)
                DropdownMenuItem(
                  value: o.id,
                  child: Text(o.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => set(() => value = v ?? ''),
          ),
        ],
      ),
    ),
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      SignalButton(
        label: 'Move folder',
        onPressed: () => Navigator.pop(ctx, true),
      ),
    ],
  );
  return (ok: ok == true, value: value);
}

Future<String?> fmReleaseNotesPrompt(
  BuildContext context, {
  required bool shared,
  required String initial,
}) async {
  final ctrl = TextEditingController(text: initial);
  final ok = await showWebModal<bool>(
    context,
    title: 'Release notes',
    icon: Icons.assignment_outlined,
    width: 560,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What this build contains. One change per line — '
          '${shared ? 'vendors see this on their portal dashboard as soon as you save.' : 'this installer is not published to vendors, so only staff see it.'}',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          minLines: 8,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText:
                'Added BIR 2303 auto-fill\nFixed receipt reprint on thermal printers',
          ),
        ),
      ],
    ),
    actions: (ctx) => [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      SignalButton(
        label: 'Save notes',
        onPressed: () => Navigator.pop(ctx, true),
      ),
    ],
  );
  final v = ctrl.text.trim();
  ctrl.dispose();
  return ok == true ? v : null;
}

Future<void> fmChangeTypeDialog(
  BuildContext context, {
  required AdminFilesApi api,
  required FmRow row,
  required VoidCallback onSaved,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ChangeTypeModal(api: api, row: row, onSaved: onSaved),
  );
}

class _ChangeTypeModal extends StatefulWidget {
  const _ChangeTypeModal({
    required this.api,
    required this.row,
    required this.onSaved,
  });
  final AdminFilesApi api;
  final FmRow row;
  final VoidCallback onSaved;

  @override
  State<_ChangeTypeModal> createState() => _ChangeTypeModalState();
}

class _ChangeTypeModalState extends State<_ChangeTypeModal> {
  late String _type = '${widget.row['collection_type']}' == 'distribution'
      ? 'distribution'
      : 'default';
  late final _play = TextEditingController(
    text: '${widget.row['play_store_url'] ?? ''}',
  );
  bool _busy = false;

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final type = _type == 'distribution' ? 'distribution' : 'default';
    final url = _play.text.trim();
    if (type == 'distribution' &&
        url.isNotEmpty &&
        !RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      toast(context, 'Play Store URL must start with http:// or https://');
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.api.updateType(
        '${widget.row['id']}',
        type,
        type == 'distribution' ? url : '',
      );
      if (!mounted) return;
      if (res['success'] != true) {
        toast(context, '${res['message'] ?? 'Could not change the type'}');
        return;
      }
      Navigator.pop(context);
      toast(
        context,
        type == 'distribution'
            ? 'Type changed to Distribution.'
            : 'Type changed to Default.',
      );
      widget.onSaved();
    } catch (_) {
      if (mounted) toast(context, 'Could not change the type');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dist = _type == 'distribution';
    return WebModal(
      title: 'Change type',
      icon: Icons.swap_horiz,
      width: 560,
      actions: [
        SignalButton(
          label: 'Save type',
          icon: Icons.check,
          busy: _busy,
          onPressed: _save,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Switch how '),
                TextSpan(
                  text: '${widget.row['name'] ?? 'this collection'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(
                  text: ' is shared. The files themselves are untouched.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text('Type', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: 'default',
                child: Text('Default — expiring + permanent link'),
              ),
              DropdownMenuItem(
                value: 'distribution',
                child: Text(
                  'Distribution — single permanent link (e.g. APK download)',
                ),
              ),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'default'),
          ),
          if (dist) ...[
            const SizedBox(height: 14),
            const Text(
              'Play Store URL (optional, Android mobile redirect)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _play,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText:
                    'https://play.google.com/store/apps/details?id=io.tinkerpro.app',
                counterText: '',
              ),
            ),
          ],
          const SizedBox(height: 14),
          FmNote(
            icon: Icons.info_outline,
            title: dist ? 'Distribution' : 'Default',
            text: dist
                ? 'Lists this collection on the public Downloads page and serves it over one permanent link — issued now if it has none. Anyone the link reaches keeps access until you revoke it.'
                : 'Removes it from the public Downloads page and goes back to a 2-hour expiring link, with a permanent link you generate on demand. Any Play Store redirect is cleared.',
          ),
        ],
      ),
    );
  }
}

class FmNote extends StatelessWidget {
  const FmNote({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.child,
  });
  final IconData icon;
  final String title;
  final String text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF3C98B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Brand.signal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(text, style: const TextStyle(fontSize: 12.5)),
                ?child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum FmPermChoice { copy, rotate, revoke }

Future<FmPermChoice?> fmPermanentLinkDialog(BuildContext context, String url) {
  return showWebModal<FmPermChoice>(
    context,
    title: 'Permanent link',
    icon: Icons.all_inclusive,
    width: 560,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            border: Border.all(color: const Color(0xFFFECACA)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text.rich(
            TextSpan(
              style: TextStyle(color: Color(0xFF991B1B)),
              children: [
                TextSpan(
                  text: 'Active.',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: ' Anyone with the URL can download these files.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            url,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    ),
    actions: (ctx) => [
      GhostButton(
        label: 'Revoke',
        icon: Icons.block,
        onPressed: () => Navigator.pop(ctx, FmPermChoice.revoke),
      ),
      SignalButton(
        label: 'Rotate',
        icon: Icons.sync,
        onPressed: () => Navigator.pop(ctx, FmPermChoice.rotate),
      ),
      SignalButton(
        label: 'Copy',
        icon: Icons.copy,
        onPressed: () => Navigator.pop(ctx, FmPermChoice.copy),
      ),
    ],
  );
}

Future<void> fmCopy(BuildContext context, String text, String message) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, message);
}

Future<bool> fmUndoWindow(BuildContext context, String message) async {
  var undone = false;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  final c = messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      persist: false,
      action: SnackBarAction(label: 'Undo', onPressed: () => undone = true),
    ),
  );
  await c.closed;
  if (undone) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Delete undone'),
        duration: Duration(milliseconds: 1800),
      ),
    );
  }
  return !undone;
}
