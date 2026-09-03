import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../theme.dart';

class AcceptTicketChoice {
  const AcceptTicketChoice({
    required this.alias,
    required this.saveDefault,
    this.greetingMessage,
  });

  final String alias;
  final bool saveDefault;
  final String? greetingMessage;
}

class _GreetingTemplate {
  const _GreetingTemplate(this.label, this.value, this.text);
  final String label;
  final String value;
  final String? text;
}

const _kAutoValue = '__auto__';

const List<_GreetingTemplate> _kGreetings = [
  _GreetingTemplate('Auto (default announcement)', _kAutoValue, null),
  _GreetingTemplate(
    '👋 Standard welcome',
    'friendly',
    'Hello, my name is {name} and I will be assisting you with ticket '
        '{ticket}. I have reviewed your request and am ready to begin. '
        'Please share any additional details that may help me resolve this '
        'for you.',
  ),
  _GreetingTemplate(
    '🤝 Formal acknowledgement',
    'professional',
    'Good day. My name is {name} and I have accepted your support ticket '
        '{ticket}. I will be handling your request personally and will '
        'provide updates as the investigation progresses. Should you have '
        'any further information to add, please reply to this ticket at any '
        'time.',
  ),
  _GreetingTemplate(
    '⚡ Brief acknowledgement',
    'quick',
    'Hello, this is {name}. I have taken ownership of ticket {ticket} and '
        'have started reviewing it. I will follow up with an update shortly.',
  ),
  _GreetingTemplate(
    '🌟 Courteous welcome',
    'warm',
    'Hello and thank you for reaching out. My name is {name} and I will be '
        'your point of contact for ticket {ticket}. My goal is to see this '
        'fully resolved for you, so please do not hesitate to share anything '
        'further that may be relevant.',
  ),
  _GreetingTemplate(
    '🔍 Technical triage',
    'triage',
    'Hello, my name is {name} and I have been assigned to ticket {ticket}. '
        'To help me identify the cause as quickly as possible, could you '
        'please provide the following: a description of what occurred, what '
        'you expected to happen instead, the approximate date and time of '
        'the incident, and a screenshot or copy of any error message '
        'displayed. If you are able to reproduce the issue, the steps '
        'involved would also be very helpful.',
  ),
  _GreetingTemplate(
    '🛠️ Technical specialist',
    'technical',
    'Hello, my name is {name} and I am a technical specialist assigned to '
        'ticket {ticket}. I have begun reviewing the logs and configuration '
        'related to your report. As I work through the diagnosis I may ask '
        'you to confirm a few details or perform a short test on your end. I '
        'will keep you informed at each stage and let you know as soon as I '
        'have a clear finding.',
  ),
  _GreetingTemplate(
    '🧩 Escalated to specialist',
    'escalated',
    'Hello, my name is {name} and your ticket {ticket} has been escalated '
        'to me for deeper technical review. I have read through the previous '
        'correspondence, so there is no need to repeat anything you have '
        'already shared. I will investigate the underlying cause and update '
        'you with my findings, along with the expected time to resolution, '
        'once the initial analysis is complete.',
  ),
  _GreetingTemplate(
    '🌙 After hours reply',
    'afterhours',
    'Hello, my name is {name} and I have received your ticket {ticket}. '
        'Thank you for your patience: your request arrived outside our '
        'standard support hours, so there may be a brief delay before I can '
        'begin a full investigation. Your ticket has been logged and I will '
        'follow up as soon as I am back online. If the matter is urgent, '
        'please reply with any additional details so that I can prioritize '
        'it accordingly.',
  ),
];

String formatTicketNo(int id) => '#${id.toString().padLeft(4, '0')}';

class AcceptTicketDialog extends StatefulWidget {
  const AcceptTicketDialog({
    super.key,
    required this.ticketId,
    required this.conversationId,
    required this.service,
  });

  final int ticketId;
  final int conversationId;
  final ChatService service;

  static Future<AcceptTicketChoice?> show(
    BuildContext context, {
    required int ticketId,
    required int conversationId,
    required ChatService service,
  }) {
    return showDialog<AcceptTicketChoice>(
      context: context,
      builder: (_) => AcceptTicketDialog(
        ticketId: ticketId,
        conversationId: conversationId,
        service: service,
      ),
    );
  }

  @override
  State<AcceptTicketDialog> createState() => _AcceptTicketDialogState();
}

class _AcceptTicketDialogState extends State<AcceptTicketDialog> {
  final _alias = TextEditingController();
  bool _saveDefault = false;
  String _greeting = _kAutoValue;

  @override
  void initState() {
    super.initState();
    _prefillAlias();
  }

  Future<void> _prefillAlias() async {
    final res = await widget.service.myAlias(widget.conversationId);
    if (!mounted || _alias.text.isNotEmpty) return;
    final value = res.alias ?? res.defaultAlias ?? '';
    if (value.isEmpty) return;
    setState(() {
      _alias.text = value;
      _alias.selection =
          TextSelection(baseOffset: 0, extentOffset: value.length);
    });
  }

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  String get _resolvedName =>
      _alias.text.trim().isEmpty ? 'Support agent' : _alias.text.trim();

  String? get _previewText {
    final tpl = _kGreetings.firstWhere((t) => t.value == _greeting);
    final body = tpl.text;
    if (body == null) return null;
    return body
        .replaceAll('{name}', _resolvedName)
        .replaceAll('{ticket}', formatTicketNo(widget.ticketId));
  }

  void _submit() {
    Navigator.of(context).pop(AcceptTicketChoice(
      alias: _alias.text.trim(),
      saveDefault: _saveDefault,
      greetingMessage: _previewText,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final brand = context.brand;
    final preview = _previewText;

    return AlertDialog(
      title: const Text('Accept ticket'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: text.bodySmall,
                  children: [
                    const TextSpan(
                      text: 'Choose the name the customer sees on this ticket (',
                    ),
                    TextSpan(
                      text: formatTicketNo(widget.ticketId),
                      style: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: brand.paper,
                      ),
                    ),
                    const TextSpan(
                      text: '). Your real name stays visible to the team.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Alias for this ticket',
                style: text.labelLarge?.copyWith(color: brand.paperDim),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _alias,
                autofocus: true,
                maxLength: 60,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  hintText: 'e.g. Maya',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _saveDefault = !_saveDefault),
                borderRadius: BorderRadius.circular(Brand.radiusSm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _saveDefault,
                        onChanged: (v) =>
                            setState(() => _saveDefault = v ?? false),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('Save as my default alias', style: text.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Leave blank to appear as “Support agent”.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              Divider(color: brand.rule, height: 1),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 15, color: brand.signal),
                  const SizedBox(width: 6),
                  Text(
                    'Greeting message',
                    style: text.labelLarge?.copyWith(color: brand.paperDim),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _greeting,
                isExpanded: true,
                items: [
                  for (final t in _kGreetings)
                    DropdownMenuItem(value: t.value, child: Text(t.label)),
                ],
                onChanged: (v) =>
                    setState(() => _greeting = v ?? _kAutoValue),
              ),
              if (preview != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: brand.surfaceHi,
                    borderRadius: BorderRadius.circular(Brand.radiusSm),
                    border: Border.all(color: brand.rule),
                  ),
                  child: Text(preview, style: text.bodySmall),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Accept ticket'),
        ),
      ],
    );
  }
}
