import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/email_models.dart';
import '../services/email_service.dart';
import '../theme.dart';
import '../widgets/pick_source.dart';
import '../widgets/premium.dart';

const List<String> _fields = ['to', 'cc', 'bcc'];
final RegExp _emailRe = RegExp(r'^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$');
const int _attachmentCap = 25 * 1024 * 1024;
const int _concurrentLimit = 8;

class _Attachment {
  const _Attachment({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;

  String get readableSize => size > 1024 * 1024
      ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(size / 1024).toStringAsFixed(0)} KB';
}

class _Suggestion {
  const _Suggestion({
    required this.chip,
    required this.title,
    required this.sub,
    required this.meta,
  });

  final RecipientChip chip;
  final String title;
  final String sub;
  final String meta;

  bool get isGroup => chip.isGroup;
}

class _Failure {
  const _Failure(this.email, this.reason);

  final String email;
  final String reason;
}

class _SendState extends ChangeNotifier {
  int sent = 0;
  int failed = 0;
  int total = 0;
  bool cancelled = false;
  bool finished = false;
  bool success = false;
  String phase = 'Working out who this goes to…';
  String elapsed = '';
  List<_Failure> failures = const [];

  void bump() => notifyListeners();
}

class InternalComposeScreen extends StatefulWidget {
  const InternalComposeScreen({super.key, required this.service, this.prefill});

  final EmailService service;
  final InternalRecipient? prefill;

  @override
  State<InternalComposeScreen> createState() => _InternalComposeScreenState();
}

class _InternalComposeScreenState extends State<InternalComposeScreen> {
  final Map<String, List<RecipientChip>> _chips = {
    'to': <RecipientChip>[],
    'cc': <RecipientChip>[],
    'bcc': <RecipientChip>[],
  };
  final Map<String, TextEditingController> _inputs = {
    'to': TextEditingController(),
    'cc': TextEditingController(),
    'bcc': TextEditingController(),
  };
  final Map<String, FocusNode> _focus = {
    'to': FocusNode(),
    'cc': FocusNode(),
    'bcc': FocusNode(),
  };

  final TextEditingController _subject = TextEditingController();
  final TextEditingController _message = TextEditingController();

  final Map<String, InternalSuggestions> _cache = {};
  final List<_Attachment> _attachments = [];

  String? _suggestField;
  List<_Suggestion> _suggestions = const [];
  int _hiddenPeople = 0;
  int _suggestSeq = 0;
  Timer? _suggestTimer;

  bool _showCc = false;
  bool _showBcc = false;
  bool _sending = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    if (prefill != null && prefill.email.isNotEmpty) {
      _chips['to']!.add(
        RecipientChip(
          kind: ChipKind.email,
          value: prefill.email,
          label: prefill.displayName,
          sub: prefill.email,
        ),
      );
    }
    for (final field in _fields) {
      _focus[field]!.addListener(() => _onFocusChange(field));
    }
  }

  @override
  void dispose() {
    _suggestTimer?.cancel();
    for (final field in _fields) {
      _inputs[field]!.dispose();
      _focus[field]!.dispose();
    }
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<RecipientChip> _allChips() => [
    for (final field in _fields) ..._chips[field]!,
  ];

  int get _recipientWeight =>
      _allChips().fold<int>(0, (sum, chip) => sum + chip.weight);

  bool _hasChip(String field, RecipientChip chip) =>
      _chips[field]!.any((existing) => existing.key == chip.key);

  bool _addChip(String field, RecipientChip chip) {
    if (!mounted) return false;
    final clash = _fields.firstWhere(
      (other) => other != field && _hasChip(other, chip),
      orElse: () => '',
    );
    if (clash.isNotEmpty) {
      _toast('${chip.label} is already in ${clash.toUpperCase()}.');
      return false;
    }
    if (_hasChip(field, chip)) return false;
    setState(() => _chips[field]!.add(chip));
    return true;
  }

  void _removeChip(String field, int index) {
    setState(() => _chips[field]!.removeAt(index));
  }

  void _commitTyped(String field) {
    final input = _inputs[field]!;
    final raw = input.text.trim().replaceAllMapped(
      RegExp(r'[^,;]*<([^>]+)>'),
      (m) => ' ${m.group(1)} ',
    );
    if (raw.trim().isEmpty) {
      input.clear();
      return;
    }
    for (final token in raw.split(RegExp(r'[,;\s]+'))) {
      final address = token.trim();
      if (address.isEmpty) continue;
      final valid = _emailRe.hasMatch(address);
      if (!valid) _toast('"$address" doesn\'t look like an email address.');
      _addChip(
        field,
        RecipientChip(
          kind: ChipKind.email,
          value: address,
          label: address,
          isNew: true,
          invalid: !valid,
        ),
      );
    }
    input.clear();
  }

  void _onFocusChange(String field) {
    if (!mounted) return;
    if (_focus[field]!.hasFocus) {
      _picking = false;
      _queueSuggest(field, _inputs[field]!.text.trim());
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (!mounted || _focus[field]!.hasFocus || _picking) return;
      if (_suggestField == field) _hideSuggest();
      _commitTyped(field);
    });
  }

  bool _picking = false;

  void _hideSuggest() {
    _picking = false;
    if (_suggestField == null && _suggestions.isEmpty) return;
    setState(() {
      _suggestField = null;
      _suggestions = const [];
      _hiddenPeople = 0;
    });
  }

  void _queueSuggest(String field, String term) {
    _suggestTimer?.cancel();
    _suggestTimer = Timer(
      const Duration(milliseconds: 140),
      () => _fetchSuggest(field, term),
    );
  }

  Future<void> _fetchSuggest(String field, String term) async {
    final key = term.toLowerCase();
    final seq = ++_suggestSeq;
    final cached = _cache[key];
    if (cached != null) {
      _paintSuggest(field, seq, cached);
      return;
    }
    final res = await widget.service.internalSuggestions(search: term);
    if (!mounted) return;
    _cache[key] = res;
    _paintSuggest(field, seq, res);
  }

  void _paintSuggest(String field, int seq, InternalSuggestions res) {
    if (!mounted || seq != _suggestSeq) return;
    final taken = _allChips().map((c) => c.key).toSet();
    final options = <_Suggestion>[];
    for (final group in res.groups) {
      final chip = RecipientChip(
        kind: ChipKind.group,
        value: group.id,
        label: group.label,
        sub: group.hint,
        count: group.count,
      );
      if (taken.contains(chip.key)) continue;
      options.add(
        _Suggestion(
          chip: chip,
          title: group.label,
          sub: group.hint,
          meta: '${group.count}',
        ),
      );
    }
    for (final person in res.people) {
      final chip = RecipientChip(
        kind: ChipKind.email,
        value: person.email,
        label: person.displayName,
        sub: person.email,
      );
      if (taken.contains(chip.key)) continue;
      options.add(
        _Suggestion(
          chip: chip,
          title: person.displayName,
          sub: person.email,
          meta: person.isStaff ? prettyRole(person.tag) : 'Added',
        ),
      );
    }
    setState(() {
      _suggestField = field;
      _suggestions = options;
      _hiddenPeople = res.peopleTotal - res.people.length;
    });
  }

  void _pickSuggest(String field, _Suggestion option) {
    _picking = false;
    _addChip(field, option.chip);
    _inputs[field]!.clear();
    _hideSuggest();
    _focus[field]!.requestFocus();
  }

  void _toggleCopyField(String field) {
    final showing = field == 'cc' ? _showCc : _showBcc;
    if (showing && _chips[field]!.isNotEmpty) {
      _toast('Remove the recipients first to hide this field.');
      return;
    }
    setState(() {
      if (field == 'cc') {
        _showCc = !showing;
      } else {
        _showBcc = !showing;
      }
    });
    if (!showing) _focus[field]!.requestFocus();
  }

  Future<void> _pickAttachments() async {
    final picked = await pickWithSource(
      context,
      multiple: true,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'pdf',
        'doc',
        'docx',
        'txt',
      ],
      cameraLabel: 'Take a photo',
      fileLabel: 'Choose files',
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final file in picked) {
        var size = 0;
        try {
          size = File(file.path).statSync().size;
        } catch (_) {}
        _attachments.add(
          _Attachment(path: file.path, name: file.name, size: size),
        );
      }
    });
  }

  int get _attachmentBytes =>
      _attachments.fold<int>(0, (sum, file) => sum + file.size);

  void _clearComposer() {
    if (!mounted) return;
    setState(() {
      for (final field in _fields) {
        _chips[field]!.clear();
        _inputs[field]!.clear();
      }
      _showCc = false;
      _showBcc = false;
      _subject.clear();
      _message.clear();
      _attachments.clear();
    });
  }

  bool get _hasDraft =>
      _allChips().isNotEmpty ||
      _subject.text.trim().isNotEmpty ||
      _message.text.trim().isNotEmpty ||
      _attachments.isNotEmpty;

  Future<void> _discard() async {
    if (!_hasDraft) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this draft?'),
        content: const Text(
          'The recipients, subject and message will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true) _clearComposer();
  }

  String _htmlBody(String plain) {
    final escaped = plain
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return escaped.split('\n').join('<br />');
  }

  Future<Map<String, List<String>>> _resolveRecipients() async {
    final resolved = <String, List<String>>{
      'to': <String>[],
      'cc': <String>[],
      'bcc': <String>[],
    };
    final groupCache = <String, List<String>>{};
    for (final field in _fields) {
      for (final chip in _chips[field]!) {
        if (!chip.isGroup) {
          resolved[field]!.add(chip.value);
          continue;
        }
        groupCache[chip.value] ??= await widget.service.internalGroupEmails(
          chip.value,
        );
        resolved[field]!.addAll(groupCache[chip.value]!);
      }
    }
    final seen = <String>{};
    for (final field in _fields) {
      resolved[field] = resolved[field]!.where((email) {
        final key = email.trim().toLowerCase();
        if (key.isEmpty || seen.contains(key)) return false;
        seen.add(key);
        return true;
      }).toList();
    }
    return resolved;
  }

  Future<void> _send() async {
    for (final field in _fields) {
      _commitTyped(field);
    }
    _hideSuggest();

    final all = _allChips();
    final invalid = all.where((chip) => chip.invalid).toList();
    if (invalid.isNotEmpty) {
      _toast('Fix or remove: ${invalid.map((c) => c.label).join(', ')}');
      return;
    }
    if (all.isEmpty) {
      _toast('Add at least one recipient.');
      _focus['to']!.requestFocus();
      return;
    }

    final subject = _subject.text.trim();
    final message = _htmlBody(_message.text.trim());

    if (subject.isEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Send without a subject?'),
          content: const Text('This email has no subject line.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Add a subject'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Send anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (_attachmentBytes > _attachmentCap) {
      _toast('Attachments total more than 25MB. Please remove some files.');
      return;
    }

    final typedByHand = all
        .where((chip) => !chip.isGroup && chip.isNew)
        .map((chip) => chip.value)
        .toList();

    final state = _SendState();
    setState(() => _sending = true);
    final started = DateTime.now();
    final ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final seconds = DateTime.now().difference(started).inMilliseconds / 1000;
      state.elapsed = 'Time: ${seconds.toStringAsFixed(1)}s';
      state.bump();
    });

    if (mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _SendProgressDialog(state: state),
        ),
      );
    }

    void finish(String phase, {bool success = false}) {
      state.phase = phase;
      state.success = success;
      state.finished = true;
      state.bump();
    }

    Map<String, List<String>> recipients;
    try {
      recipients = await _resolveRecipients();
    } catch (_) {
      ticker.cancel();
      finish('Could not work out the recipients. Please try again.');
      if (mounted) setState(() => _sending = false);
      return;
    }

    final toList = recipients['to']!;
    final ccList = recipients['cc']!;
    final bccList = recipients['bcc']!;
    final everyone = [...toList, ...ccList, ...bccList];

    if (everyone.isEmpty) {
      ticker.cancel();
      finish('No addresses matched — nothing was sent.');
      if (mounted) setState(() => _sending = false);
      return;
    }

    final messages = toList.isEmpty
        ? [(to: '', cc: ccList, bcc: bccList)]
        : [
            for (var i = 0; i < toList.length; i++)
              (
                to: toList[i],
                cc: i == 0 ? ccList : const <String>[],
                bcc: i == 0 ? bccList : const <String>[],
              ),
          ];

    state.total = messages.length;
    state.phase = 'Sending… 0 of ${messages.length}';
    state.bump();

    final failures = <_Failure>[];

    Future<void> sendOne(
      ({String to, List<String> cc, List<String> bcc}) item,
    ) async {
      if (state.cancelled) return;
      final label = item.to.isNotEmpty
          ? item.to
          : (item.cc.isNotEmpty
                ? item.cc.first
                : (item.bcc.isNotEmpty ? item.bcc.first : ''));
      final res = await widget.service.sendInternalMessage(
        to: item.to,
        subject: subject,
        message: message,
        cc: item.cc,
        bcc: item.bcc,
        attachmentPaths: [for (final file in _attachments) file.path],
      );
      if (res.ok) {
        state.sent++;
      } else {
        state.failed++;
        failures.add(_Failure(label, res.message ?? 'Unknown error'));
      }
      final processed = state.sent + state.failed;
      state.phase = 'Sending… $processed of ${messages.length}';
      state.failures = List<_Failure>.unmodifiable(failures);
      state.bump();
    }

    await sendOne(messages.first);
    for (var i = 1; i < messages.length; i += _concurrentLimit) {
      if (state.cancelled) break;
      final end = (i + _concurrentLimit) > messages.length
          ? messages.length
          : i + _concurrentLimit;
      await Future.wait(messages.sublist(i, end).map(sendOne));
      if (end < messages.length && !state.cancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    ticker.cancel();
    final duration = (DateTime.now().difference(started).inMilliseconds / 1000)
        .toStringAsFixed(1);

    if (state.cancelled) {
      finish('Cancelled by user');
    } else if (state.failed == 0) {
      finish('All done! Completed in ${duration}s', success: true);
      _clearComposer();
    } else {
      finish('${state.failed} failed to send');
    }

    if (mounted) setState(() => _sending = false);

    if (state.sent > 0) {
      _changed = true;
      unawaited(
        widget.service.logBulkSend(
          emails: everyone,
          subject: subject,
          attachmentCount: _attachments.length,
        ),
      );
      unawaited(
        widget.service.saveRecentTemplate(html: message, subject: subject),
      );
    }

    final bounced = failures.map((f) => f.email.toLowerCase()).toSet();
    final keepers = typedByHand
        .where((email) => !bounced.contains(email.toLowerCase()))
        .toList();
    if (keepers.isNotEmpty) {
      final res = await widget.service.rememberContacts(keepers);
      if (res.ok && res.added.isNotEmpty) {
        _changed = true;
        _toast(
          res.added.length == 1
              ? '${res.added.first} was saved to your added emails.'
              : '${res.added.length} new addresses were saved to your added emails.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final weight = _recipientWeight;
    return StationScaffold(
      stationNumber: '13',
      stationLabel: 'Internal Email',
      title: 'New message',
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(_changed),
      trailing: StationAction(
        icon: Icons.delete_outline_rounded,
        tooltip: 'Discard draft',
        onPressed: _discard,
      ),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          const SectionHeader(title: 'Recipients'),
          AppCard(
            radius: Brand.radiusLg,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _chipField(
                  field: 'to',
                  label: 'To',
                  hint: 'Type a name, an email, or "all"…',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CopyToggle(
                        label: 'Cc',
                        active: _showCc,
                        onTap: () => _toggleCopyField('cc'),
                      ),
                      const SizedBox(width: 6),
                      _CopyToggle(
                        label: 'Bcc',
                        active: _showBcc,
                        onTap: () => _toggleCopyField('bcc'),
                      ),
                    ],
                  ),
                ),
                if (_showCc) ...[
                  const SizedBox(height: 12),
                  const Hairline(),
                  const SizedBox(height: 12),
                  _chipField(field: 'cc', label: 'Cc', hint: 'Carbon copy…'),
                ],
                if (_showBcc) ...[
                  const SizedBox(height: 12),
                  const Hairline(),
                  const SizedBox(height: 12),
                  _chipField(field: 'bcc', label: 'Bcc', hint: 'Blind copy…'),
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
                TextField(
                  controller: _subject,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Subject',
                    prefixIcon: Icon(Icons.subject_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _message,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 7,
                  maxLines: 16,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    hintText: 'Write your message…',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Attachments',
            trailing: _attachments.isEmpty
                ? null
                : GlowBadge(
                    label: '${_attachments.length}',
                    color: b.info,
                    icon: Icons.attach_file_rounded,
                  ),
          ),
          AppCard(
            radius: Brand.radiusLg,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _attachments.length; i++) ...[
                  Row(
                    children: [
                      const IconTile(
                        icon: Icons.insert_drive_file_rounded,
                        color: Brand.info,
                        size: 38,
                        iconSize: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _attachments[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall,
                            ),
                            Text(
                              _attachments[i].readableSize,
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove attachment',
                        onPressed: () =>
                            setState(() => _attachments.removeAt(i)),
                        icon: Icon(Icons.close_rounded, color: b.paperDim),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                GhostButton(
                  label: _attachments.isEmpty
                      ? 'Attach files'
                      : 'Attach more files',
                  icon: Icons.attach_file_rounded,
                  onPressed: _pickAttachments,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            padding: const EdgeInsets.all(12),
            color: b.tint(b.info, 0.1),
            borderColor: b.info.withValues(alpha: 0.35),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 19, color: b.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Everyone in To gets their own copy — they never see each '
                    "other's address. Cc and Bcc are copied once. An address "
                    'you type by hand is saved to your added emails once it '
                    "sends, so it's there next time.",
                    style: text.bodySmall?.copyWith(color: b.paper),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SignalButton(
            label: weight > 0 ? 'Send · $weight' : 'Send',
            icon: Icons.send_rounded,
            busy: _sending,
            onPressed: _sending ? null : _send,
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _chipField({
    required String field,
    required String label,
    required String hint,
    Widget? trailing,
  }) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final chips = _chips[field]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(
                label,
                style: text.labelLarge?.copyWith(color: b.paperDim),
              ),
            ),
            Expanded(
              child: Text(
                chips.isEmpty
                    ? 'No recipients'
                    : '${chips.length} ${chips.length == 1 ? 'entry' : 'entries'}',
                style: text.labelSmall?.copyWith(color: b.paperDim),
              ),
            ),
            ?trailing,
          ],
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < chips.length; i++)
                _ChipTag(chip: chips[i], onRemove: () => _removeChip(field, i)),
            ],
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _inputs[field],
          focusNode: _focus[field],
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            prefixIcon: const Icon(Icons.person_search_rounded, size: 20),
          ),
          onChanged: (value) {
            if (value.contains(',') || value.contains(';')) {
              _commitTyped(field);
              _hideSuggest();
              return;
            }
            _queueSuggest(field, value.trim());
          },
          onSubmitted: (_) {
            _commitTyped(field);
            _hideSuggest();
            _focus[field]!.requestFocus();
          },
        ),
        if (_suggestField == field) ...[
          const SizedBox(height: 8),
          _SuggestPanel(
            options: _suggestions,
            hidden: _hiddenPeople,
            onPickStart: () => _picking = true,
            onPick: (option) => _pickSuggest(field, option),
          ),
        ],
      ],
    );
  }
}

class _CopyToggle extends StatelessWidget {
  const _CopyToggle({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? b.tint(b.signal, 0.16) : b.surfaceHi,
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? b.signal.withValues(alpha: 0.5) : b.rule,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: active ? b.signal : b.paperDim,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipTag extends StatelessWidget {
  const _ChipTag({required this.chip, required this.onRemove});

  final RecipientChip chip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final Color accent = chip.invalid
        ? Brand.danger
        : (chip.isGroup ? b.signal : b.info);
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: b.tint(accent, chip.isGroup || chip.invalid ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: chip.invalid ? 0.6 : 0.38),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chip.isGroup) ...[
            Icon(Icons.groups_rounded, size: 15, color: accent),
            const SizedBox(width: 6),
          ] else if (chip.isNew) ...[
            Icon(Icons.edit_rounded, size: 13, color: accent),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              chip.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: chip.isGroup ? FontWeight.w700 : FontWeight.w500,
                color: chip.invalid ? Brand.danger : b.paper,
              ),
            ),
          ),
          if (chip.isGroup && chip.count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: b.tint(accent, 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${chip.count}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
          const SizedBox(width: 2),
          Semantics(
            button: true,
            label: 'Remove ${chip.label}',
            child: InkResponse(
              canRequestFocus: false,
              onTap: onRemove,
              radius: 18,
              child: SizedBox(
                width: 26,
                height: 26,
                child: Icon(Icons.close_rounded, size: 15, color: b.paperDim),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestPanel extends StatelessWidget {
  const _SuggestPanel({
    required this.options,
    required this.hidden,
    required this.onPick,
    required this.onPickStart,
  });

  final List<_Suggestion> options;
  final int hidden;
  final ValueChanged<_Suggestion> onPick;
  final VoidCallback onPickStart;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    if (options.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: b.surfaceHi,
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          border: Border.all(color: b.rule),
        ),
        child: Text(
          'No match — press done to use what you typed as an address.',
          style: text.bodySmall,
        ),
      );
    }

    final rows = <Widget>[];
    bool? lastGroup;
    for (final option in options) {
      if (lastGroup != option.isGroup) {
        lastGroup = option.isGroup;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Text(
              option.isGroup ? 'GROUPS' : 'PEOPLE',
              style: text.labelSmall?.copyWith(
                color: b.paperDim,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      rows.add(
        InkWell(
          canRequestFocus: false,
          onTapDown: (_) => onPickStart(),
          onTap: () => onPick(option),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (option.isGroup)
                  IconTile(
                    icon: Icons.groups_rounded,
                    color: b.signal,
                    size: 36,
                    iconSize: 18,
                  )
                else
                  AppAvatar(name: option.title, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall,
                      ),
                      if (option.sub.isNotEmpty)
                        Text(
                          option.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (option.meta.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    option.meta,
                    style: text.labelSmall?.copyWith(color: b.paperDim),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    if (hidden > 0) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Text(
            '$hidden more — keep typing to narrow it down',
            style: text.labelSmall?.copyWith(color: b.paperDim),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: b.surface,
        borderRadius: BorderRadius.circular(Brand.radiusSm),
        border: Border.all(color: b.rule),
        boxShadow: b.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: ListView(shrinkWrap: true, children: rows),
      ),
    );
  }
}

class _SendProgressDialog extends StatelessWidget {
  const _SendProgressDialog({required this.state});

  final _SendState state;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final processed = state.sent + state.failed;
        final progress = state.total == 0
            ? 0.0
            : (processed / state.total).clamp(0.0, 1.0);
        final Color tone = state.finished
            ? (state.success
                  ? Brand.success
                  : (state.cancelled ? Brand.danger : Brand.warning))
            : b.signal;
        return AlertDialog(
          title: Text(state.finished ? 'Send report' : 'Sending…'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(state.phase, style: text.bodyMedium),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: state.total == 0 && !state.finished
                          ? null
                          : (state.finished ? 1.0 : progress),
                      minHeight: 8,
                      backgroundColor: b.surfaceHi,
                      color: tone,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          label: 'Sent',
                          value: '${state.sent}',
                          color: Brand.success,
                        ),
                      ),
                      Expanded(
                        child: _Stat(
                          label: 'Failed',
                          value: '${state.failed}',
                          color: Brand.danger,
                        ),
                      ),
                      Expanded(
                        child: _Stat(
                          label: 'Total',
                          value: '${state.total}',
                          color: b.info,
                        ),
                      ),
                    ],
                  ),
                  if (state.elapsed.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      state.elapsed,
                      style: text.labelSmall?.copyWith(color: b.paperDim),
                    ),
                  ],
                  if (state.failures.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: b.tint(Brand.warning, 0.1),
                        borderRadius: BorderRadius.circular(Brand.radiusSm),
                        border: Border.all(
                          color: Brand.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          Text('Failed:', style: text.labelLarge),
                          const SizedBox(height: 6),
                          for (final failure in state.failures)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${failure.email}: ${failure.reason}',
                                style: text.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            if (!state.finished)
              TextButton(
                onPressed: state.cancelled
                    ? null
                    : () {
                        state.cancelled = true;
                        state.phase = 'Cancelling…';
                        state.bump();
                      },
                child: const Text('Cancel Sending'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: text.titleLarge?.copyWith(color: b.paper)),
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
                style: text.labelSmall?.copyWith(color: b.paperDim),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
