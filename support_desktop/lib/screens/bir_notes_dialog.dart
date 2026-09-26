import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/bir_data_service.dart';
import '../services/bir_misc_service.dart';
import '../theme.dart';
import 'bir_misc_ui.dart';
import 'bir_widgets.dart';

class BirNotesDialog extends StatefulWidget {
  const BirNotesDialog({
    super.key,
    required this.bir,
    required this.customerId,
    required this.rawNotes,
    required this.author,
  });

  final BirDataService bir;
  final int customerId;
  final String rawNotes;
  final String author;

  static Future<String?> show(
    BuildContext context, {
    required BirDataService bir,
    required int customerId,
    required String rawNotes,
    required String author,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => BirNotesDialog(
        bir: bir,
        customerId: customerId,
        rawNotes: rawNotes,
        author: author,
      ),
    );
  }

  @override
  State<BirNotesDialog> createState() => _BirNotesDialogState();
}

class _BirNotesDialogState extends State<BirNotesDialog> {
  static const _checks = [
    ('called', 'Called'),
    ('no_answer', 'No Answer'),
    ('emailed', 'Sent Email'),
    ('sms_sent', 'Sent SMS'),
    ('follow_up', 'Follow Up'),
    ('docs_received', 'Documents Received'),
  ];

  late final BirMiscService _svc = BirMiscService(widget.bir.api);
  final Set<String> _selected = {};
  final _text = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Map? parsed;
    final raw = widget.rawNotes.trim();
    if (raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) parsed = j;
      } catch (_) {}
    }
    final saved = (parsed != null && parsed['checks'] is List)
        ? (parsed['checks'] as List).map((e) => '$e').toList()
        : <String>[];
    _selected.addAll(_checks.map((e) => e.$1).where(saved.contains));
    final current = (parsed == null ? '' : (parsed['text'] ?? '').toString())
        .trim();
    if (current.isNotEmpty) {
      final cleaned = _normalizeBullets(current)
          .split('\n')
          .where((l) => l.trim() != '✅' && l.trim() != '✅ ')
          .join('\n');
      _setText(cleaned + (cleaned.isNotEmpty ? '\n✅ ' : '✅ '));
    } else {
      _setText('✅ ');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _normalizeBullets(String text) {
    return text
        .split('\n')
        .map((line) {
          final t = line.trim();
          if (t.isEmpty) return '';
          if (t.startsWith('✅ ')) return t;
          if (t.startsWith('• ')) return '✅ ${t.substring(2)}';
          if (t.startsWith('- ')) return '✅ ${t.substring(2)}';
          return '✅ $t';
        })
        .join('\n');
  }

  void _setText(String value, [int? cursor]) {
    _text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: cursor ?? value.length),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey != LogicalKeyboardKey.enter &&
        e.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final v = _text.value;
    final sel = v.selection;
    final start = sel.isValid ? sel.start : v.text.length;
    final end = sel.isValid ? sel.end : v.text.length;
    final text = '${v.text.substring(0, start)}\n✅ ${v.text.substring(end)}';
    _setText(text, start + 3);
    return KeyEventResult.handled;
  }

  void _onChanged(String value) {
    if (value.length == 1 && value != '✅') {
      _setText('✅ $value');
    }
  }

  void _toggle(String value, String label, bool checked) {
    setState(() {
      if (checked) {
        _selected.add(value);
      } else {
        _selected.remove(value);
      }
    });
    var lines = _text.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    bool isLineFor(String line) {
      for (final h in ['✅ $label', '• $label', '- $label', label]) {
        if (line == h || line.startsWith('$h — ')) return true;
      }
      return false;
    }

    if (checked) {
      if (!lines.any(isLineFor)) lines.add('✅ $label');
    } else {
      lines = lines.where((l) => !isLineFor(l)).toList();
    }
    lines = lines.where((l) => l != '✅' && l != '✅ ').toList();
    lines.add('✅ ');
    _setText(lines.join('\n'));
  }

  Future<void> _save() async {
    if (widget.customerId <= 0) return;
    setState(() => _saving = true);
    try {
      final r = await _svc.saveActionNote(
        customerId: widget.customerId,
        checks: [
          for (final c in _checks)
            if (_selected.contains(c.$1)) c.$1,
        ],
        text: _text.text,
      );
      if (!mounted) return;
      if (r['status'] == 'success') {
        final json = (r['action_notes'] ?? '').toString();
        final notes = r['notes'];
        if (notes is Map) _setText((notes['text'] ?? '').toString());
        Navigator.of(context).pop(json);
        return;
      }
      birToast(context, 'Failed to save notes.', kind: BirToastKind.error);
    } catch (_) {
      if (mounted) {
        birToast(context, 'Error saving notes.', kind: BirToastKind.error);
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      t.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
        color: Color(0xFF64748B),
      ),
    ),
  );

  Widget _card((String, String) c) {
    final on = _selected.contains(c.$1);
    return SizedBox(
      width: 236,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggle(c.$1, c.$2, !on),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFFFF7ED) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: on ? Brand.signal : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: on ? Brand.signal : Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: on ? Brand.signal : const Color(0xFFCBD5E1),
                  ),
                ),
                child: on
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                c.$2,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  color: Brand.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BirDialogShell(
      title: 'Notes',
      subtitle: 'Registration Checklist',
      icon: Icons.fact_check_outlined,
      width: 560,
      footer: Row(
        children: [
          const Spacer(),
          BirSolidButton(
            label: _saving ? 'Saving...' : 'Save & Close',
            icon: _saving ? null : Icons.check_circle,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Checklist'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final c in _checks) _card(c)],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 18),
          _label('Additional Notes'),
          TextField(
            controller: _text,
            focusNode: _focus,
            minLines: 4,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: '✅ Type your notes here... (auto check marks)',
            ),
          ),
        ],
      ),
    );
  }
}
