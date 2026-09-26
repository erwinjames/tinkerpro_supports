import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/live_sync.dart';
import '../services/ops_data_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'ops_widgets.dart';

const opsAvatarColors = <Color>[
  Color(0xFFFF7D00),
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFFDC2626),
  Color(0xFFD97706),
  Color(0xFF7C3AED),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
];

Color opsAvatarColor(String name) {
  final s = name.isEmpty ? '?' : name;
  return opsAvatarColors[s.codeUnitAt(0) % opsAvatarColors.length];
}

String opsInitials(String name) {
  final t = (name.isEmpty ? '?' : name).trim();
  return (t.length > 2 ? t.substring(0, 2) : t).toUpperCase();
}

Color opsPriorityColor(String p) {
  switch (p) {
    case 'high':
      return opsRed;
    case 'low':
      return opsGreen;
    case 'medium':
      return opsAmber;
    default:
      return const Color(0xFF6B7280);
  }
}

Color opsStatusColor(String s) {
  switch (s) {
    case 'new':
      return opsBlue;
    case 'progress':
    case 'in_progress':
      return opsAmber;
    case 'resolved':
      return opsGreen;
    default:
      return const Color(0xFF6B7280);
  }
}

class OpsAvatar extends StatelessWidget {
  const OpsAvatar({super.key, required this.name, this.size = 42});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: opsAvatarColor(name),
        shape: BoxShape.circle,
      ),
      child: Text(
        opsInitials(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.33,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class OpsTicketCtx {
  OpsTicketCtx({
    required this.svc,
    required this.userId,
    required this.agentName,
  });
  final OpsDataService svc;
  final int userId;
  String agentName;
  List<Json> agents = const [];
  List<Json> helpTopics = const [];
}

bool opsIsClosed(Json t) => opsStr(t['status']).toLowerCase() == 'closed';
String opsClaimedVerb(Json t) {
  final s = opsStr(t['status']);
  if (s == 'resolved') return 'Resolved';
  if (s == 'closed') return 'Closed';
  return 'Accepted';
}

String opsTicketRef(Json t) {
  final n = opsStr(t['ticket_number']);
  return n.isNotEmpty ? '#$n' : '#${opsStr(t['id'])}';
}

bool opsHasAgent(Json t) =>
    t['assigned_agent_id'] != null && opsStr(t['assigned_agent_id']).isNotEmpty;

List<Widget> opsTicketBadges(Json t) {
  final num = opsStr(t['ticket_number']);
  final status = opsStr(t['status']);
  final pr = opsStr(t['priority']);
  return [
    if (num.isNotEmpty)
      OpsBadge(label: '#$num', fg: Colors.white, bg: opsNavy),
    OpsBadge.tone(pr, opsPriorityColor(pr)),
    OpsBadge.tone(status.replaceAll('_', ' '), opsStatusColor(status)),
  ];
}

String _greetHint(Json t) {
  final n = opsStr(t['customer_name']).trim();
  return 'The email already opens with "Hi ${n.isEmpty ? 'there' : n},", so start with what you want to say.';
}

Future<bool> opsOpenAccept(BuildContext context, OpsTicketCtx c, Json t) async {
  final email = opsStr(t['customer_email']).trim();
  final hasEmail = email.isNotEmpty;
  var send = hasEmail;
  var busy = false;
  final subj = TextEditingController(
      text: 'An agent is working on your TinkerPro ticket ${opsTicketRef(t)}');
  final who = c.agentName.isEmpty ? 'One of our agents' : c.agentName;
  final s = opsStr(t['subject']);
  final msg = TextEditingController(
      text:
          '$who has accepted your support ticket ${opsTicketRef(t)}${s.isNotEmpty ? ' ("$s")' : ''} and is working on it now — '
          'it is open and no longer waiting in the queue.\n\n'
          'We will keep you posted here, and you can reply to this email or open the support chat and paste '
          'your reference number to continue the conversation.');
  final name = opsStr(t['customer_name']);
  var refreshed = false;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Future<void> submit() async {
        if (send && msg.text.trim().isEmpty) {
          opsToast(ctx, 'Write a message or turn off the email.');
          return;
        }
        set(() => busy = true);
        final res = await c.svc.acceptTicket(
          opsInt(t['id']),
          sendEmail: send,
          subject: subj.text.trim(),
          message: msg.text.trim(),
        );
        if (!ctx.mounted) return;
        set(() => busy = false);
        if (res.ok) {
          opsToast(context,
              send ? 'Ticket accepted — email sent to the ticket owner' : 'Ticket accepted');
          Navigator.of(ctx).pop(true);
        } else {
          refreshed = true;
          opsToast(ctx, res.message.isEmpty ? 'Failed to accept ticket' : res.message,
              error: true);
        }
      }

      return WebModal(
        title: 'Accept ticket',
        width: 560,
        actions: [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
          OpsButton(
            label: send ? 'Accept & send' : 'Accept ticket',
            icon: send ? Icons.send : Icons.check,
            color: Brand.signal,
            busy: busy,
            onPressed: submit,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Accepting '),
                TextSpan(
                    text: 'ticket ${opsTicketRef(t)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(
                    text:
                        ' assigns it to you and lets you start working on it. You can also let the customer know right away.'),
              ]),
              style: TextStyle(fontSize: 14, color: ctx.brand.paperDim, height: 1.5),
            ),
            const SizedBox(height: 14),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: send,
              onChanged: hasEmail ? (v) => set(() => send = v ?? false) : null,
              title: const Text('Email the ticket owner that it was accepted',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (!hasEmail)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: opsAmber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                    'This ticket has no email address on file, so no email will be sent.',
                    style: TextStyle(fontSize: 13)),
              ),
            if (send) ...[
              const SizedBox(height: 10),
              OpsField(
                label: 'To',
                child: TextField(
                  readOnly: true,
                  controller: TextEditingController(
                      text: '${name.isNotEmpty ? '$name — ' : ''}$email'),
                ),
              ),
              OpsField(
                label: 'Subject',
                child: TextField(controller: subj, maxLength: 200,
                    decoration: const InputDecoration(counterText: '')),
              ),
              OpsField(
                label: 'Message',
                hint: _greetHint(t),
                child: TextField(controller: msg, minLines: 6, maxLines: 10, maxLength: 4000,
                    decoration: const InputDecoration(counterText: '')),
              ),
            ],
          ],
        ),
      );
    }),
  );
  return r == true || refreshed;
}

Future<void> opsOpenCompose(BuildContext context, OpsTicketCtx c, Json t) async {
  final email = opsStr(t['customer_email']).trim();
  if (email.isEmpty) {
    opsToast(context, 'This ticket has no email address on file.');
    return;
  }
  final name = opsStr(t['customer_name']);
  final subj = TextEditingController(
      text:
          'Re: ${opsStr(t['subject']).isEmpty ? 'your TinkerPro ticket' : opsStr(t['subject'])} (${opsTicketRef(t)})');
  final msg = TextEditingController();
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Future<void> submit() async {
        if (msg.text.trim().isEmpty) {
          opsToast(ctx, 'Write a message before sending.');
          return;
        }
        set(() => busy = true);
        final r = await c.svc
            .sendTicketEmail(opsInt(t['id']), subj.text.trim(), msg.text.trim());
        if (!ctx.mounted) return;
        set(() => busy = false);
        if (r.ok) {
          opsToast(context, r.message.isEmpty ? 'Email sent' : r.message);
          Navigator.of(ctx).pop();
        } else {
          opsToast(ctx, r.message, error: true);
        }
      }

      return WebModal(
        title: 'Compose email',
        width: 560,
        actions: [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
          OpsButton(
              label: 'Send email',
              icon: Icons.send,
              color: Brand.signal,
              busy: busy,
              onPressed: submit),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Send the owner of '),
                TextSpan(
                    text: 'ticket ${opsTicketRef(t)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(
                    text:
                        ' an email. The ticket reference is included so they can follow up.'),
              ]),
              style: TextStyle(fontSize: 14, color: ctx.brand.paperDim, height: 1.5),
            ),
            const SizedBox(height: 14),
            OpsField(
              label: 'To',
              child: TextField(
                  readOnly: true,
                  controller: TextEditingController(
                      text: '${name.isNotEmpty ? '$name — ' : ''}$email')),
            ),
            OpsField(
              label: 'Subject',
              child: TextField(controller: subj, maxLength: 200,
                  decoration: const InputDecoration(counterText: '')),
            ),
            OpsField(
              label: 'Message',
              hint: _greetHint(t),
              child: TextField(
                controller: msg,
                autofocus: true,
                minLines: 8,
                maxLines: 12,
                maxLength: 4000,
                decoration: const InputDecoration(
                    counterText: '', hintText: 'Write your message…'),
              ),
            ),
          ],
        ),
      );
    }),
  );
}

Future<bool> opsOpenReassign(BuildContext context, OpsTicketCtx c, Json t) async {
  if (c.agents.isEmpty) c.agents = await c.svc.agents();
  if (!context.mounted) return false;
  final current = opsStr(t['assigned_agent_id']);
  final options =
      c.agents.where((a) => opsStr(a['id']) != current).toList();
  int? pick;
  var busy = false;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Future<void> submit() async {
        if (pick == null) {
          opsToast(ctx, 'Please choose an agent.');
          return;
        }
        set(() => busy = true);
        final res = await c.svc.reassignTicket(opsInt(t['id']), pick!);
        if (!ctx.mounted) return;
        set(() => busy = false);
        if (res.ok) {
          opsToast(context, res.message.isEmpty ? 'Ticket reassigned' : res.message);
          Navigator.of(ctx).pop(true);
        } else {
          opsToast(ctx, res.message, error: true);
        }
      }

      return WebModal(
        title: 'Reassign ticket',
        width: 520,
        actions: [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
          OpsButton(
              label: 'Reassign',
              icon: Icons.manage_accounts_outlined,
              color: Brand.signal,
              busy: busy,
              onPressed: submit),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Currently handled by '),
                TextSpan(
                    text: opsStr(t['agent_name']).isEmpty
                        ? 'Unassigned'
                        : opsStr(t['agent_name']),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: '.'),
              ]),
              style: TextStyle(fontSize: 14, color: ctx.brand.paperDim),
            ),
            const SizedBox(height: 14),
            OpsField(
              label: 'Reassign to',
              required: true,
              child: DropdownButtonFormField<int>(
                initialValue: pick,
                hint: const Text('— Select an agent —'),
                items: [
                  for (final a in options)
                    DropdownMenuItem(
                        value: opsInt(a['id']), child: Text(opsStr(a['name']))),
                ],
                onChanged: (v) => set(() => pick = v),
              ),
            ),
          ],
        ),
      );
    }),
  );
  return r == true;
}

class OpsStepType {
  const OpsStepType(this.label, this.icon, this.color, this.option);
  final String label;
  final IconData icon;
  final Color color;
  final String option;
}

const opsStepTypes = <String, OpsStepType>{
  'diagnosis': OpsStepType('Diagnosis', Icons.medical_services_outlined,
      Color(0xFF2563EB), '🩺 Diagnosis — what\'s wrong'),
  'action': OpsStepType('Action taken', Icons.build_outlined, Color(0xFFFF7D00),
      '🛠️ Action taken — what you did'),
  'suggestion': OpsStepType('Suggestion', Icons.lightbulb_outline,
      Color(0xFFD97706), '💡 Suggestion — advice to customer'),
  'help_reference': OpsStepType('Help / KB ref', Icons.menu_book_outlined,
      Color(0xFF7C3AED), '📖 Help / KB reference'),
  'resource': OpsStepType('Tool / resource', Icons.handyman_outlined,
      Color(0xFF0891B2), '🧰 Tool / resource used'),
  'follow_up': OpsStepType('Follow-up', Icons.history, Color(0xFFDC2626),
      '⏳ Follow-up needed'),
  'resolution': OpsStepType('Resolution', Icons.check_circle_outline,
      Color(0xFF16A34A), '✅ Resolution — the fix'),
  'note': OpsStepType(
      'Note', Icons.sticky_note_2_outlined, Color(0xFF6B7280), '📝 Note'),
  'message': OpsStepType('Support reply', Icons.chat_bubble_outline,
      Color(0xFF0F766E), ''),
};

OpsStepType opsStepType(String k) => opsStepTypes[k] ?? opsStepTypes['note']!;

class OpsStepChip extends StatelessWidget {
  const OpsStepChip({super.key, required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final m = opsStepType(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: m.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(m.icon, size: 12, color: m.color),
        const SizedBox(width: 4),
        Text(m.label,
            style: TextStyle(
                color: m.color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

String opsRefLabel(OpsTicketCtx c, String url) {
  final m = RegExp(r'^help\.php\?topic=(\d+)$').firstMatch(url);
  if (m != null) {
    final t = c.helpTopics.where((h) => opsStr(h['id']) == m.group(1));
    return t.isEmpty ? 'Help page' : opsStr(t.first['title']);
  }
  return url;
}

void opsOpenRef(OpsTicketCtx c, String ref) {
  if (ref.isEmpty) return;
  launchUrl(Uri.parse(c.svc.url(ref)));
}

Future<bool> opsOpenAddStep(BuildContext context, OpsTicketCtx c, int ticketId) async {
  if (c.helpTopics.isEmpty) c.helpTopics = await c.svc.helpTopics();
  if (!context.mounted) return false;
  var type = 'action';
  var ref = '';
  final title = TextEditingController();
  final details = TextEditingController();
  final custom = TextEditingController();
  var busy = false;
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      Future<void> submit() async {
        if (title.text.isEmpty) {
          opsToast(ctx, 'Please fill out the Title field.');
          return;
        }
        set(() => busy = true);
        final res = await c.svc.addStep(
          ticketId: ticketId,
          type: type,
          title: title.text,
          details: details.text,
          reference: ref == '__custom__' ? custom.text : ref,
        );
        if (!ctx.mounted) return;
        set(() => busy = false);
        if (res.ok) {
          opsToast(context, 'Step added');
          Navigator.of(ctx).pop(true);
        } else {
          opsToast(ctx, res.message, error: true);
        }
      }

      return WebModal(
        title: 'Add support step',
        width: 560,
        actions: [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
          OpsButton(
              label: 'Save step',
              icon: Icons.check,
              color: Brand.signal,
              busy: busy,
              onPressed: submit),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            OpsField(
              label: 'Step type',
              child: DropdownButtonFormField<String>(
                initialValue: type,
                items: [
                  for (final e in opsStepTypes.entries)
                    if (e.value.option.isNotEmpty)
                      DropdownMenuItem(value: e.key, child: Text(e.value.option)),
                ],
                onChanged: (v) => set(() => type = v ?? 'action'),
              ),
            ),
            OpsField(
              label: 'Title',
              required: true,
              child: TextField(
                controller: title,
                autofocus: true,
                maxLength: 255,
                decoration: const InputDecoration(
                    counterText: '', hintText: 'e.g. Reinstalled printer driver'),
              ),
            ),
            OpsField(
              label: 'Details',
              child: TextField(
                controller: details,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                    hintText:
                        'Steps, commands, settings changed, what the customer was advised…'),
              ),
            ),
            OpsField(
              label: 'Reference (help page / article)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: ref,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: '', child: Text('— None —')),
                      for (final h in c.helpTopics)
                        DropdownMenuItem(
                          value: 'help.php?topic=${opsStr(h['id'])}',
                          child: Text(
                            opsStr(h['title']).isEmpty
                                ? 'Topic #${opsStr(h['id'])}'
                                : opsStr(h['title']),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const DropdownMenuItem(
                          value: '__custom__',
                          child: Text('Other (custom link)…')),
                    ],
                    onChanged: (v) => set(() => ref = v ?? ''),
                  ),
                  if (ref == '__custom__') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: custom,
                      decoration: const InputDecoration(
                          hintText: 'https://… or help.php'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }),
  );
  return r == true;
}

void opsOpenStepView(BuildContext context, OpsTicketCtx c, Json s) {
  final m = opsStepType(opsStr(s['step_type']));
  final isSystem = opsInt(s['is_system']) == 1;
  final ref = opsStr(s['reference_url']);
  final agent = opsStr(s['agent_name']);
  final details = opsStr(s['details']);
  showWebModal<void>(
    context,
    title: 'Resolution step',
    width: 600,
    actions: (ctx) => [
      GhostButton(label: 'Close', onPressed: () => Navigator.of(ctx).pop()),
    ],
    builder: (ctx) {
      final b = ctx.brand;
      Widget field(String l, Widget v) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: b.paperDim)),
              const SizedBox(height: 3),
              v,
            ],
          );
      const valStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: m.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(m.icon, color: m.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      opsStr(s['title']).isEmpty
                          ? 'Untitled step'
                          : opsStr(s['title']),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 10, runSpacing: 4, children: [
                    Text(m.label,
                        style: TextStyle(
                            color: m.color,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    Text('⏱ ${opsTimeAgo(opsStr(s['created_at']))}',
                        style: TextStyle(fontSize: 13, color: b.paperDim)),
                    if (agent.isNotEmpty)
                      Text('👤 $agent',
                          style: TextStyle(fontSize: 13, color: b.paperDim)),
                    if (isSystem)
                      const OpsBadge(
                          label: 'Permanent',
                          fg: Color(0xFF6B7280),
                          bg: Color(0xFFF1F3F6),
                          dot: false),
                  ]),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: b.surfaceHi,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: b.rule),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('DETAILS',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: Brand.signal)),
                const SizedBox(height: 6),
                SelectableText(
                  details.isEmpty
                      ? 'No additional details were recorded for this step.'
                      : details,
                  style: const TextStyle(fontSize: 14, height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: field(
                'Reference',
                ref.isEmpty
                    ? Text('—', style: TextStyle(color: b.paperDim))
                    : InkWell(
                        onTap: () => opsOpenRef(c, ref),
                        child: Text(opsRefLabel(c, ref),
                            style: const TextStyle(color: opsBlue)),
                      ),
              ),
            ),
            Expanded(
                child: field(
                    'Agent', Text(agent.isEmpty ? '—' : agent, style: valStyle))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: field('Logged',
                    Text(opsFullDate(opsStr(s['created_at'])), style: valStyle))),
            Expanded(
                child: field('Record type',
                    Text(isSystem ? 'Auto-logged' : 'Manual note', style: valStyle))),
          ]),
        ],
      );
    },
  );
}

class OpsTicketDetail extends StatefulWidget {
  const OpsTicketDetail({
    super.key,
    required this.ctx,
    required this.ticket,
    required this.refetch,
    this.liveRefetch,
  });

  final OpsTicketCtx ctx;
  final Json ticket;
  final Future<Json?> Function(int id) refetch;
  final Future<Json?> Function(int id)? liveRefetch;

  static Future<void> show(
    BuildContext context, {
    required OpsTicketCtx ctx,
    required Json ticket,
    required Future<Json?> Function(int id) refetch,
    Future<Json?> Function(int id)? liveRefetch,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => OpsTicketDetail(
        ctx: ctx,
        ticket: ticket,
        refetch: refetch,
        liveRefetch: liveRefetch,
      ),
    );
  }

  @override
  State<OpsTicketDetail> createState() => _OpsTicketDetailState();
}

class _OpsTicketDetailState extends State<OpsTicketDetail>
    with LiveRefresh<OpsTicketDetail> {
  late Json _t = widget.ticket;
  List<Json>? _steps;
  bool _stepsError = false;
  bool _resolving = false;
  bool _removed = false;
  bool _liveBusy = false;

  @override
  List<String> get liveKeys => const ['ticket'];

  @override
  void onLiveChange() => _liveRefresh();

  Future<void> _liveRefresh() async {
    if (_liveBusy || _removed || _resolving) return;
    _liveBusy = true;
    final id = opsInt(_t['id']);
    Json? fresh;
    try {
      fresh = await (widget.liveRefetch ?? widget.refetch)(id);
    } catch (_) {
      _liveBusy = false;
      return;
    }
    _liveBusy = false;
    if (!mounted) return;
    if (fresh == null) {
      setState(() => _removed = true);
      return;
    }
    final next = fresh;
    setState(() => _t = next);
    _loadSteps();
  }

  OpsTicketCtx get c => widget.ctx;

  @override
  void initState() {
    super.initState();
    _loadSteps();
    if (c.helpTopics.isEmpty) {
      c.svc.helpTopics().then((v) {
        c.helpTopics = v;
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _loadSteps() async {
    final s = await c.svc.ticketSteps(opsInt(_t['id']));
    if (!mounted) return;
    setState(() {
      _steps = s ?? const [];
      _stepsError = s == null;
    });
  }

  Future<void> _refresh() async {
    final fresh = await widget.refetch(opsInt(_t['id']));
    if (!mounted) return;
    if (fresh == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _t = fresh);
    _loadSteps();
  }

  Future<void> _resolve() async {
    setState(() => _resolving = true);
    final r = await c.svc.resolveTicket(opsInt(_t['id']));
    if (!mounted) return;
    setState(() => _resolving = false);
    opsToast(context, r.ok ? 'Ticket resolved' : r.message, error: !r.ok);
    _refresh();
  }

  List<Widget> _actions() {
    final t = _t;
    final mine = opsStr(t['assigned_agent_id']) == '${c.userId}';
    final out = <Widget>[];
    if (!opsHasAgent(t)) {
      if (!opsIsClosed(t)) {
        out.add(OpsButton(
          label: 'Accept',
          icon: Icons.check,
          color: Brand.signal,
          onPressed: () async {
            if (await opsOpenAccept(context, c, t)) _refresh();
          },
        ));
      }
    } else if (mine) {
      if (opsStr(t['status']) != 'resolved') {
        out.add(OpsButton(
          label: _resolving ? 'Resolving…' : 'Resolve',
          icon: Icons.check_circle,
          color: opsGreen,
          busy: _resolving,
          onPressed: _resolve,
        ));
      }
    } else {
      final who = opsStr(t['agent_name']);
      out.add(Tooltip(
        message:
            '${opsClaimedVerb(t)} by ${who.isEmpty ? 'another agent' : who} — ask them to reassign it to you',
        child: OpsButton(
          label: '${opsClaimedVerb(t)}${who.isNotEmpty ? ' by $who' : ''}',
          icon: Icons.how_to_reg,
          color: Colors.grey,
          dashedMuted: true,
        ),
      ));
    }
    if (opsHasAgent(t) && mine && opsStr(t['status']) != 'resolved') {
      out.add(OpsButton(
        label: 'Reassign',
        icon: Icons.manage_accounts_outlined,
        color: opsBlue,
        outlined: true,
        onPressed: () async {
          if (await opsOpenReassign(context, c, t)) _refresh();
        },
      ));
    }
    if (opsHasAgent(t) &&
        mine &&
        !opsIsClosed(t) &&
        opsStr(t['customer_email']).trim().isNotEmpty) {
      out.add(OpsButton(
        label: 'Compose',
        icon: Icons.mail_outline,
        color: Brand.signal,
        outlined: true,
        onPressed: () => opsOpenCompose(context, c, t),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final b = context.brand;
    final locked =
        opsStr(t['status']) == 'resolved' || opsIsClosed(t);
    final atts = (t['attachments'] is List)
        ? (t['attachments'] as List).whereType<Map>().toList()
        : const <Map>[];
    const label = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: Brand.signal);
    Widget fieldCell(String l, String v) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: b.paperDim)),
            const SizedBox(height: 3),
            SelectableText(v,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        );
    final actions = _removed ? const <Widget>[] : _actions();
    return WebModal(
      title: 'Ticket ${opsTicketRef(t)}',
      subtitle: 'Opened ${opsFullDate(opsStr(t['created_at']))}',
      icon: Icons.confirmation_number_outlined,
      width: 1040,
      actions: [
        GhostButton(label: 'Back to tickets', icon: Icons.arrow_back,
            onPressed: () => Navigator.of(context).pop()),
      ],
      bodyPadding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_removed)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This record was removed',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.only(bottom: 20),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: b.rule))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OpsAvatar(name: opsStr(t['customer_name']), size: 52),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        opsStr(t['subject']).isEmpty
                            ? 'Untitled'
                            : opsStr(t['subject']),
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: b.paper,
                            height: 1.2),
                      ),
                      const SizedBox(height: 9),
                      Wrap(spacing: 8, runSpacing: 6, children: opsTicketBadges(t)),
                    ],
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ],
            ),
          ),
          const Text('DESCRIPTION', style: label),
          const SizedBox(height: 8),
          SelectableText(
            opsStr(t['description']).isEmpty ? '—' : opsStr(t['description']),
            style: TextStyle(fontSize: 14.5, height: 1.65, color: b.paper),
          ),
          if (atts.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('ATTACHMENTS', style: label),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in atts)
                OpsAttachmentThumb(
                    svc: c.svc,
                    path: opsStr(a['file_path']),
                    name: opsStr(a['original_name'])),
            ]),
          ],
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
                child: fieldCell('Customer',
                    opsStr(t['customer_name']).isEmpty ? 'Unknown' : opsStr(t['customer_name']))),
            const SizedBox(width: 24),
            Expanded(
                child: fieldCell('Email',
                    opsStr(t['customer_email']).isEmpty ? '—' : opsStr(t['customer_email']))),
            const SizedBox(width: 24),
            Expanded(
                child: fieldCell('Assigned agent',
                    opsStr(t['agent_name']).isEmpty ? 'Unassigned' : opsStr(t['agent_name']))),
            const SizedBox(width: 24),
            Expanded(
                child: fieldCell('Created', opsFullDate(opsStr(t['created_at'])))),
          ]),
          const SizedBox(height: 24),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RESOLUTION LOG', style: label),
                  const SizedBox(height: 3),
                  Text(
                    'Record every step taken to work this ticket — diagnosis, actions, suggestions, references & the final fix.',
                    style: TextStyle(fontSize: 12.5, color: b.paperDim),
                  ),
                ],
              ),
            ),
            if (!locked)
              OpsButton(
                label: 'Add step',
                icon: Icons.add,
                color: Brand.signal,
                onPressed: () async {
                  if (await opsOpenAddStep(context, c, opsInt(t['id']))) {
                    _loadSteps();
                  }
                },
              ),
          ]),
          const SizedBox(height: 12),
          _stepsBody(locked),
        ],
      ),
    );
  }

  Widget _stepsBody(bool locked) {
    final b = context.brand;
    Widget empty(Widget child) => Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: b.rule),
          ),
          alignment: Alignment.center,
          child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 13.5, color: b.paperDim),
              textAlign: TextAlign.center,
              child: child),
        );
    if (_steps == null) {
      return empty(const Text('Loading…'));
    }
    if (_stepsError) return empty(const Text('Could not load steps.'));
    final steps = _steps!;
    if (steps.isEmpty) {
      return empty(Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.assignment_outlined,
            size: 22, color: b.paperDim.withValues(alpha: 0.6)),
        const SizedBox(height: 6),
        Text(locked
            ? 'No steps were logged on this ticket.'
            : 'No steps logged yet. Click Add step to record how this ticket is being worked.'),
      ]));
    }
    final head = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: b.paperDim);
    Widget hcell(String s, {double? w, int flex = 0}) {
      final t = Text(s.toUpperCase(), style: head);
      if (w != null) return SizedBox(width: w, child: t);
      return Expanded(flex: flex, child: t);
    }

    return ColumnResizeScope(tableId: 'ticket:steps', child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: b.rule))),
        child: Builder(builder: (context) => Row(children: resizableRowCells(context, [
          hcell('#', w: 36),
          hcell('Type', w: 150),
          hcell('Step', flex: 5),
          hcell('Reference', flex: 2),
          hcell('Agent', flex: 2),
          hcell('When', w: 90),
          const SizedBox(width: 32),
        ], header: true, extra: 24))),
      ),
      for (var i = steps.length - 1; i >= 0; i--)
        _StepRow(
          index: i,
          step: steps[i],
          ctx: c,
          onOpen: () => opsOpenStepView(context, c, steps[i]),
          onDelete: () async {
            if (!await opsConfirm(context,
                title: 'Delete step', message: 'Delete this step?')) {
              return;
            }
            final stepId = opsInt(steps[i]['id']);
            if (!mounted) return;
            setState(() => _steps =
                (_steps ?? const <Json>[]).where((x) => opsInt(x['id']) != stepId).toList());
            if (!await opsUndoWindow(context, 'Step removed')) {
              _loadSteps();
              return;
            }
            final r = await c.svc.deleteStep(stepId);
            if (!mounted) return;
            if (!r.ok) {
              opsToast(context, r.message.isEmpty ? 'Could not delete step' : r.message,
                  error: true);
            }
            _loadSteps();
          },
        ),
    ]));
  }
}

class _StepRow extends StatefulWidget {
  const _StepRow({
    required this.index,
    required this.step,
    required this.ctx,
    required this.onOpen,
    required this.onDelete,
  });

  final int index;
  final Json step;
  final OpsTicketCtx ctx;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final s = widget.step;
    final ref = opsStr(s['reference_url']);
    final details = opsStr(s['details']);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: _hover ? Brand.signal.withValues(alpha: 0.10) : null,
            border: Border(bottom: BorderSide(color: b.rule)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: resizableRowCells(context, [
            SizedBox(
                width: 36,
                child: Text('${widget.index + 1}',
                    style: TextStyle(fontSize: 13, color: b.paperDim))),
            SizedBox(
                width: 150,
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: OpsStepChip(type: opsStr(s['step_type'])))),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(opsStr(s['title']),
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(details,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: b.paperDim)),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: ref.isEmpty
                  ? Text('—', style: TextStyle(color: b.paperDim))
                  : InkWell(
                      onTap: () => opsOpenRef(widget.ctx, ref),
                      child: Text(opsRefLabel(widget.ctx, ref),
                          style: const TextStyle(
                              color: opsBlue, fontSize: 13)),
                    ),
            ),
            Expanded(
                flex: 2,
                child: Text(
                    opsStr(s['agent_name']).isEmpty
                        ? '—'
                        : opsStr(s['agent_name']),
                    style: const TextStyle(fontSize: 13))),
            SizedBox(
              width: 90,
              child: Tooltip(
                message: opsFullDate(opsStr(s['created_at'])),
                child: Text(opsTimeAgo(opsStr(s['created_at'])),
                    style: TextStyle(fontSize: 13, color: b.paperDim)),
              ),
            ),
            SizedBox(
              width: 32,
              child: opsInt(s['is_system']) == 1
                  ? Tooltip(
                      message:
                          'Auto-logged — part of the permanent ticket record',
                      child: Icon(Icons.lock,
                          size: 13,
                          color: b.paperDim.withValues(alpha: 0.6)),
                    )
                  : IconButton(
                      tooltip: 'Delete step',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: opsRed),
                    ),
            ),
          ])),
        ),
      ),
    );
  }
}

class OpsAttachmentThumb extends StatelessWidget {
  const OpsAttachmentThumb({
    super.key,
    required this.svc,
    required this.path,
    required this.name,
    this.moreCount,
  });

  final OpsDataService svc;
  final String path;
  final String name;
  final int? moreCount;

  void _lightbox(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.of(ctx).pop(),
        child: Stack(children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Image.network(svc.url(path),
                  headers: svc.authHeaders, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              onPressed: () => Navigator.of(ctx).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
          if (name.isNotEmpty)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(name,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _lightbox(context),
        child: Container(
          width: 64,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.brand.rule),
            color: context.brand.surfaceHi,
          ),
          child: moreCount != null
              ? Center(
                  child: Text('+$moreCount',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)))
              : Image.network(
                  svc.url(path),
                  headers: svc.authHeaders,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 20),
                ),
        ),
      ),
    );
  }
}
