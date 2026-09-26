import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/account_settings_models.dart';
import '../services/account_settings_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Widget _label(BuildContext context, String text, {String? hint}) {
  final t = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text.rich(
      TextSpan(
        text: text,
        style: t.labelLarge,
        children: [
          if (hint != null)
            TextSpan(
              text: '  $hint',
              style: t.labelSmall?.copyWith(color: context.brand.paperDim),
            ),
        ],
      ),
    ),
  );
}

Widget _note(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 6),
  child: Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: context.brand.paperDim),
  ),
);

String settingsDate(String raw) {
  final parsed = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
  if (parsed == null) return raw.trim();
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
  final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}, '
      '$hour:$minute ${parsed.hour < 12 ? 'AM' : 'PM'}';
}

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.service,
    this.showChatFields = true,
  });

  final AccountSettingsService service;
  final bool showChatFields;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _alias = TextEditingController();
  final TextEditingController _otp = TextEditingController();

  SelfSettings? _loaded;
  bool _loading = true;
  bool _saving = false;
  bool _sending = false;
  bool _verifying = false;
  bool _codeSent = false;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    _email.dispose();
    _alias.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await widget.service.load();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loaded = settings;
      if (settings != null) _fill(settings);
    });
  }

  void _fill(SelfSettings s) {
    _name.text = s.fullName;
    _email.text = s.email;
    _alias.text = s.chatAlias;
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _toast(context, 'Full name cannot be empty.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.updateAccount(
      fullName: _name.text,
      email: _email.text,
      chatAlias: widget.showChatFields ? _alias.text : null,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(
      context,
      res.message ??
          (res.ok ? 'Account updated.' : 'Failed to update account.'),
    );
    if (res.ok) {
      _timer?.cancel();
      setState(() => _codeSent = false);
      await _load();
    }
  }

  Future<void> _sendCode() async {
    setState(() => _sending = true);
    final res = await widget.service.sendEmailCode();
    if (!mounted) return;
    setState(() => _sending = false);
    if (!res.ok) {
      _toast(context, res.message ?? 'Failed to send code.');
      return;
    }
    _toast(context, 'Verification code sent.');
    _otp.clear();
    _timer?.cancel();
    setState(() {
      _codeSent = true;
      _secondsLeft = 600;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft = _secondsLeft > 0 ? _secondsLeft - 1 : 0);
      if (_secondsLeft == 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final otp = _otp.text.trim();
    if (otp.length < 6) {
      _toast(context, 'Enter the 6-digit code.');
      return;
    }
    setState(() => _verifying = true);
    final res = await widget.service.verifyEmail(otp);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (!res.ok) {
      _toast(context, res.message ?? 'Invalid code.');
      return;
    }
    _toast(context, 'Email verified.');
    _timer?.cancel();
    setState(() => _codeSent = false);
    await _load();
  }

  String get _timerText {
    if (_secondsLeft <= 0) return 'Code expired — request a new one.';
    final m = _secondsLeft ~/ 60;
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '(expires in $m:$s)';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final loaded = _loaded;
    return StationScaffold(
      stationLabel: 'Settings',
      title: 'Account',
      subtitle: 'Update the personal info shown across your workspace.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Column(
              children: [
                Skeleton(height: 56, radius: 12),
                SizedBox(height: 12),
                Skeleton(height: 56, radius: 12),
                SizedBox(height: 12),
                Skeleton(height: 56, radius: 12),
              ],
            )
          : loaded == null
          ? EmptyState(
              icon: Icons.person_off_rounded,
              label: 'Could not load your account',
              hint: 'Check your connection and try again.',
              action: GhostButton(label: 'Retry', onPressed: _load),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                AppCard(
                  radius: Brand.radiusLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (loaded.role.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GlowBadge(
                            label: loaded.role.replaceAll('_', ' '),
                            icon: Icons.badge_rounded,
                          ),
                        ),
                      const SizedBox(height: 14),
                      _label(context, 'Full Name', hint: 'required'),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        decoration: const InputDecoration(
                          hintText: 'Enter your full name',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _label(context, 'Email Address')),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: StatusPill(
                              label: loaded.emailVerified
                                  ? 'Verified'
                                  : 'Not verified',
                              color: loaded.emailVerified
                                  ? Brand.success
                                  : Brand.warning,
                              dot: true,
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          hintText: 'you@example.com',
                        ),
                      ),
                      if (!loaded.emailVerified) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Brand.warning.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(Brand.radiusSm),
                            border: Border.all(
                              color: Brand.warning.withValues(alpha: 0.3),
                            ),
                          ),
                          child: !_codeSent
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Your email isn\'t verified yet.',
                                        style: text.bodySmall,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _sending ? null : _sendCode,
                                      icon: const Icon(
                                        Icons.mark_email_unread_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _sending ? 'Sending…' : 'Send code',
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      'Enter the 6-digit code sent to '
                                      '${loaded.email}. $_timerText',
                                      style: text.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _otp,
                                      keyboardType: TextInputType.number,
                                      maxLength: 6,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      style: const TextStyle(
                                        letterSpacing: 6,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'monospace',
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: '000000',
                                        counterText: '',
                                      ),
                                      onSubmitted: (_) => _verify(),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: _verifying
                                                ? null
                                                : _verify,
                                            icon: const Icon(
                                              Icons.check_rounded,
                                            ),
                                            label: const Text('Verify'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: _sending
                                              ? null
                                              : _sendCode,
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                          ),
                                          label: const Text('Resend'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _label(context, 'Username', hint: 'read-only'),
                      InputDecorator(
                        decoration: const InputDecoration(enabled: false),
                        child: Text(
                          loaded.username.isEmpty ? '—' : loaded.username,
                          style: text.bodyLarge?.copyWith(color: b.paperDim),
                        ),
                      ),
                      if (widget.showChatFields) ...[
                        const SizedBox(height: 16),
                        _label(context, 'Chat Alias', hint: 'optional'),
                        TextField(
                          controller: _alias,
                          maxLength: 60,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Maya',
                            counterText: '',
                          ),
                        ),
                        _note(
                          context,
                          'Shown to website visitors instead of your real name '
                          'once you accept their ticket. Leave blank to appear '
                          'as “Support agent”.',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SignalButton(
                  label: 'Save changes',
                  icon: Icons.check_circle_outline_rounded,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
                const SizedBox(height: 10),
                GhostButton(
                  label: 'Reset',
                  icon: Icons.undo_rounded,
                  onPressed: () => setState(() => _fill(loaded)),
                ),
                if (!loaded.emailVerified)
                  _note(
                    context,
                    'Changing your email address marks it unverified until '
                    'you confirm the new one.',
                  ),
              ],
            ),
    );
  }
}

int passwordScore(String pw) {
  var score = 0;
  if (pw.length >= 8) score++;
  if (pw.length >= 12) score++;
  if (RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw)) score++;
  if (RegExp(r'\d').hasMatch(pw) && RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) {
    score++;
  }
  return score > 4 ? 4 : score;
}

const List<String> kStrengthLabels = [
  'Empty',
  'Weak',
  'Fair',
  'Good',
  'Strong',
];

class PasswordSettingsScreen extends StatefulWidget {
  const PasswordSettingsScreen({super.key, required this.service});

  final AccountSettingsService service;

  @override
  State<PasswordSettingsScreen> createState() => _PasswordSettingsScreenState();
}

class _PasswordSettingsScreenState extends State<PasswordSettingsScreen> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _show = false;
  bool _saving = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_current.text.isEmpty || _next.text.isEmpty) {
      _toast(context, 'Current and new password are required.');
      return;
    }
    if (_next.text.length < 8) {
      _toast(context, 'New password must be at least 8 characters.');
      return;
    }
    if (_next.text != _confirm.text) {
      _toast(context, 'New password and confirmation do not match.');
      return;
    }
    setState(() => _saving = true);
    final res = await widget.service.changePassword(
      current: _current.text,
      next: _next.text,
      confirm: _confirm.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(
      context,
      res.message ??
          (res.ok ? 'Password changed.' : 'Failed to change password.'),
    );
    if (res.ok) {
      _current.clear();
      _next.clear();
      _confirm.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final score = passwordScore(_next.text);
    final colors = [
      b.rule,
      Brand.danger,
      Brand.warning,
      Brand.info,
      Brand.success,
    ];
    Widget field(
      TextEditingController c,
      String hint,
      List<String> autofill, {
      ValueChanged<String>? onChanged,
    }) => TextField(
      controller: c,
      obscureText: !_show,
      autofillHints: autofill,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: IconButton(
          tooltip: _show ? 'Hide passwords' : 'Show passwords',
          icon: Icon(
            _show ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          ),
          onPressed: () => setState(() => _show = !_show),
        ),
      ),
    );
    return StationScaffold(
      stationLabel: 'Security',
      title: 'Password',
      subtitle: 'Keep your account safe with a strong password.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(context, 'Current password', hint: 'required'),
                  field(_current, '••••••••', const [AutofillHints.password]),
                  const SizedBox(height: 16),
                  _label(context, 'New password', hint: 'min 8 chars'),
                  field(_next, '••••••••', const [
                    AutofillHints.newPassword,
                  ], onChanged: (_) => setState(() {})),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            height: 5,
                            decoration: BoxDecoration(
                              color: i < score ? colors[score] : b.rule,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        if (i < 3) const SizedBox(width: 4),
                      ],
                      const SizedBox(width: 10),
                      Text(
                        _next.text.isEmpty ? 'Weak' : kStrengthLabels[score],
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _label(context, 'Confirm new', hint: 'must match'),
                  field(_confirm, '••••••••', const [
                    AutofillHints.newPassword,
                  ], onChanged: (_) => setState(() {})),
                  if (_confirm.text.isNotEmpty && _confirm.text != _next.text)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Passwords do not match.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Brand.danger),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SignalButton(
              label: 'Update password',
              icon: Icons.lock_reset_rounded,
              busy: _saving,
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

TimeOfDay _parseTime(String raw, TimeOfDay fallback) {
  final parts = raw.split(':');
  if (parts.length < 2) return fallback;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return fallback;
  return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
}

String _formatTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class AgentHoursScreen extends StatefulWidget {
  const AgentHoursScreen({super.key, required this.service});

  final AccountSettingsService service;

  @override
  State<AgentHoursScreen> createState() => _AgentHoursScreenState();
}

class _AgentHoursScreenState extends State<AgentHoursScreen> {
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  bool _enabled = false;
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);
  String _tz = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hours = await widget.service.agentHours();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = hours == null;
      if (hours != null) {
        _enabled = hours.enabled;
        _start = _parseTime(hours.start, _start);
        _end = _parseTime(hours.end, _end);
        _tz = hours.timezone;
      }
    });
  }

  Future<void> _pick(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await widget.service.saveAgentHours(
      enabled: _enabled,
      start: _formatTime(_start),
      end: _formatTime(_end),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(
      context,
      res.message ?? (res.ok ? 'Agent hours saved.' : 'Could not save.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationLabel: 'Security',
      title: 'Agent operating hours',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Skeleton(height: 200, radius: 16)
          : _failed
          ? EmptyState(
              icon: Icons.lock_outline_rounded,
              label: 'Could not load operating hours',
              hint: 'Only super admins can change this.',
              action: GhostButton(label: 'Retry', onPressed: _load),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                AppCard(
                  radius: Brand.radiusLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                        title: const Text('Enable operating hours'),
                        subtitle: const Text(
                          'If enabled, the chatbot will only escalate to an '
                          'agent during these hours. Outside these hours, '
                          'visitors will be asked to leave a message.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _TimeTile(
                              label: 'Start Time',
                              value: _start.format(context),
                              onTap: () => _pick(true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _TimeTile(
                              label: 'End Time',
                              value: _end.format(context),
                              onTap: () => _pick(false),
                            ),
                          ),
                        ],
                      ),
                      _note(
                        context,
                        'Times are in the server timezone '
                        '(${_tz.isEmpty ? '—' : _tz}).',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SignalButton(
                  label: 'Save operating hours',
                  icon: Icons.save_rounded,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: b.surfaceHi,
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          border: Border.all(color: b.rule),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.labelMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: b.signal),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    value,
                    style: text.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TicketReminderScreen extends StatefulWidget {
  const TicketReminderScreen({super.key, required this.service});

  final AccountSettingsService service;

  @override
  State<TicketReminderScreen> createState() => _TicketReminderScreenState();
}

class _TicketReminderScreenState extends State<TicketReminderScreen> {
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  bool _enabled = true;
  int _days = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await widget.service.ticketReminder();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = value == null;
      if (value != null) {
        _enabled = value.enabled;
        _days = value.days;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await widget.service.saveTicketReminder(
      enabled: _enabled,
      days: _days,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(
      context,
      res.message ?? (res.ok ? 'Reminder settings saved.' : 'Could not save.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StationScaffold(
      stationLabel: 'Security',
      title: 'Unresolved ticket reminder',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Skeleton(height: 200, radius: 16)
          : _failed
          ? EmptyState(
              icon: Icons.lock_outline_rounded,
              label: 'Could not load reminder settings',
              hint: 'Only super admins can change this.',
              action: GhostButton(label: 'Retry', onPressed: _load),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                AppCard(
                  radius: Brand.radiusLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                        title: const Text('Remind agents about open tickets'),
                        subtitle: const Text(
                          'Shows a pop-up in the middle of the screen listing '
                          'tickets — from the Tickets page or from chat — '
                          'that are still not resolved after the number of '
                          'days below. Agents see their own tickets plus any '
                          'nobody has accepted.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Remind after', style: text.labelLarge),
                      Row(
                        children: [
                          IconButton.outlined(
                            tooltip: 'Fewer days',
                            onPressed: _days > 1
                                ? () => setState(() => _days--)
                                : null,
                            icon: const Icon(Icons.remove_rounded),
                          ),
                          SizedBox(
                            width: 64,
                            child: Text(
                              '$_days',
                              textAlign: TextAlign.center,
                              style: text.headlineSmall,
                            ),
                          ),
                          IconButton.outlined(
                            tooltip: 'More days',
                            onPressed: _days < 90
                                ? () => setState(() => _days++)
                                : null,
                            icon: const Icon(Icons.add_rounded),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'day/s without being resolved',
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      _note(
                        context,
                        'The pop-up shows how many days each ticket has been '
                        'open. "Remind me later" hides it for 4 hours on that '
                        'agent\'s browser.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SignalButton(
                  label: 'Save reminder settings',
                  icon: Icons.save_rounded,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}

class PosApiKeysScreen extends StatefulWidget {
  const PosApiKeysScreen({super.key, required this.service});

  final AccountSettingsService service;

  @override
  State<PosApiKeysScreen> createState() => _PosApiKeysScreenState();
}

class _PosApiKeysScreenState extends State<PosApiKeysScreen> {
  List<PosApiKey>? _keys;
  bool _loading = true;
  bool _creating = false;
  bool _showRevoked = false;
  String? _fresh;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keys = await widget.service.posKeys();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _keys = keys;
    });
  }

  Future<void> _generate() async {
    setState(() => _creating = true);
    final res = await widget.service.createPosKey('TinkerPro POS');
    if (!mounted) return;
    setState(() {
      _creating = false;
      if (res.ok) _fresh = res.token;
    });
    if (!res.ok) {
      _toast(context, res.message ?? 'Could not create the key.');
      return;
    }
    _load();
  }

  Future<void> _revoke(PosApiKey key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke this key?'),
        content: Text(
          'Any POS install still sending ${key.masked} stops working '
          'immediately. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.service.revokePosKey(key.id);
    if (!mounted) return;
    _toast(
      context,
      res.ok ? 'Key revoked.' : (res.message ?? 'Could not revoke the key.'),
    );
    if (res.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final keys = _keys;
    final active = keys?.where((k) => k.active).toList() ?? const [];
    final revoked = keys?.where((k) => !k.active).toList() ?? const [];
    return StationScaffold(
      stationLabel: 'Security',
      title: 'POS API key',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'One key for the whole TinkerPro POS product — every '
                    'client is covered by it.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'What it returns. ',
                          style: text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(
                          text:
                              'The POS sends this key with the client\'s TIN '
                              'and gets that client\'s PTU number, MIN, '
                              'accreditation number and date issued back — no '
                              'separate key per client.',
                        ),
                      ],
                    ),
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Tied to your account. ',
                          style: text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(
                          text:
                              'You only see the keys issued from it, and only '
                              'you can revoke them. Other admins keep their '
                              'own.',
                        ),
                      ],
                    ),
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  SignalButton(
                    label: 'Generate key',
                    icon: Icons.key_rounded,
                    busy: _creating,
                    onPressed: _creating ? null : _generate,
                  ),
                ],
              ),
            ),
            if (_fresh != null) ...[
              const SizedBox(height: 12),
              AppCard(
                radius: Brand.radiusLg,
                borderColor: Brand.success,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Brand.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Key created — copy it now',
                            style: text.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Only a hash is stored. Leave this page and it can '
                      'never be shown again.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: b.surfaceHi,
                        borderRadius: BorderRadius.circular(Brand.radiusSm),
                        border: Border.all(color: b.rule),
                      ),
                      child: SelectableText(
                        _fresh!,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GhostButton(
                      label: 'Copy key',
                      icon: Icons.copy_rounded,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _fresh!));
                        if (context.mounted) _toast(context, 'Key copied.');
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SectionHeader(title: 'Active keys (${active.length})'),
            if (_loading)
              const Skeleton(height: 90, radius: 14)
            else if (keys == null)
              EmptyState(
                icon: Icons.lock_outline_rounded,
                label: 'Could not load your keys',
                hint: 'You need an admin or developer role.',
                action: GhostButton(label: 'Retry', onPressed: _load),
              )
            else if (active.isEmpty)
              _note(context, 'No active keys. Generate one to connect the POS.')
            else
              for (final key in active)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _KeyCard(apiKey: key, onRevoke: () => _revoke(key)),
                ),
            if (revoked.isNotEmpty) ...[
              const SizedBox(height: 6),
              GhostButton(
                label: _showRevoked
                    ? 'Hide revoked keys'
                    : 'Show revoked keys (${revoked.length})',
                icon: Icons.history_rounded,
                onPressed: () => setState(() => _showRevoked = !_showRevoked),
              ),
              if (_showRevoked)
                for (final key in revoked)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _KeyCard(apiKey: key),
                  ),
            ],
            const SizedBox(height: 20),
            AppCard(
              radius: Brand.radiusLg,
              onTap: () => launchUrl(
                Uri.parse(
                  widget.service.posApiEndpoint.replaceFirst(
                    '/open-api',
                    '/settings.php',
                  ),
                ),
                mode: LaunchMode.externalApplication,
              ),
              child: Row(
                children: [
                  Icon(Icons.menu_book_rounded, color: b.signal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to use this key in the POS application',
                          style: text.titleSmall,
                        ),
                        Text(
                          'Endpoint ${widget.service.posApiEndpoint} — full '
                          'guide with samples opens on the web.',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.open_in_new_rounded, color: b.paperDim, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({required this.apiKey, this.onRevoke});

  final PosApiKey apiKey;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final k = apiKey;
    final used = k.lastUsedAt.isEmpty
        ? 'Never used'
        : 'Last used ${settingsDate(k.lastUsedAt)}'
              '${k.lastUsedIp.isEmpty ? '' : ' · ${k.lastUsedIp}'}';
    return AppCard(
      radius: Brand.radiusLg,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        k.masked,
                        style: text.titleSmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(
                      label: k.active ? 'Active' : 'Revoked',
                      color: k.active ? Brand.success : Brand.danger,
                      dot: true,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${k.label.isEmpty ? 'TinkerPro POS' : k.label} · created '
                  '${settingsDate(k.createdAt)}',
                  style: text.bodySmall,
                ),
                Text(
                  k.active
                      ? '$used · ${k.requestCount} request(s)'
                      : 'Revoked ${settingsDate(k.revokedAt)}',
                  style: text.labelMedium,
                ),
              ],
            ),
          ),
          if (onRevoke != null)
            IconButton(
              tooltip: 'Revoke',
              onPressed: onRevoke,
              icon: const Icon(Icons.block_rounded, color: Brand.danger),
            ),
        ],
      ),
    );
  }
}

class GlobalSidebarScreen extends StatefulWidget {
  const GlobalSidebarScreen({super.key, required this.service, this.onSaved});

  final AccountSettingsService service;
  final Future<void> Function()? onSaved;

  @override
  State<GlobalSidebarScreen> createState() => _GlobalSidebarScreenState();
}

class _GlobalSidebarScreenState extends State<GlobalSidebarScreen> {
  Set<String>? _hidden;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hidden = await widget.service.sidebarHidden();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _hidden = hidden == null ? null : {...hidden};
    });
  }

  Future<void> _save() async {
    final hidden = _hidden;
    if (hidden == null) return;
    setState(() => _saving = true);
    final res = await widget.service.saveSidebarHidden(hidden);
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(
      context,
      res.message ??
          (res.ok
              ? 'Global sidebar settings saved.'
              : 'Failed to save global sidebar settings.'),
    );
    if (res.ok) await widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hidden = _hidden;
    return StationScaffold(
      stationLabel: 'Preferences',
      title: 'Global sidebar',
      subtitle: 'Show or hide modules for all accounts.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Skeleton(height: 240, radius: 16)
          : hidden == null
          ? EmptyState(
              icon: Icons.lock_outline_rounded,
              label: 'Could not load sidebar settings',
              hint: 'Check your connection and try again.',
              action: GhostButton(label: 'Retry', onPressed: _load),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Text.rich(
                  const TextSpan(
                    children: [
                      TextSpan(
                        text:
                            'Show or hide specific modules and pages in the '
                            'sidebar menu across ',
                      ),
                      TextSpan(
                        text: 'all accounts',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: '. Hidden items also disappear from this app.',
                      ),
                    ],
                  ),
                  style: text.bodySmall,
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: hidden.isEmpty
                        ? null
                        : () => setState(() => hidden.clear()),
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: const Text('Show all'),
                  ),
                ),
                const SizedBox(height: 10),
                for (final category in kSidebarCategories) ...[
                  SectionHeader(title: category.title),
                  AppCard(
                    radius: Brand.radiusLg,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (final item in category.items)
                          SwitchListTile(
                            dense: true,
                            value: !hidden.contains(item.key),
                            title: Text(item.label),
                            onChanged: (on) => setState(() {
                              if (on) {
                                hidden.remove(item.key);
                              } else {
                                hidden.add(item.key);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                SignalButton(
                  label: 'Save sidebar items',
                  icon: Icons.cloud_upload_rounded,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}

class DashboardRemindersScreen extends StatefulWidget {
  const DashboardRemindersScreen({super.key, required this.service});

  final AccountSettingsService service;

  @override
  State<DashboardRemindersScreen> createState() =>
      _DashboardRemindersScreenState();
}

class _DashboardRemindersScreenState extends State<DashboardRemindersScreen> {
  GlobalReminder? _state;
  bool _loading = true;
  String _mode = 'own';
  int _source = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await widget.service.globalReminder();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _state = state;
      if (state != null) {
        _mode = state.mode;
        _source = state.sourceUserId;
      }
    });
  }

  String _describe() {
    if (_mode == 'off') return 'No account will see the Reminders panel.';
    if (_mode == 'user') {
      final match = _state?.users.where((u) => u.id == _source);
      final name = match == null || match.isEmpty
          ? 'that account'
          : match.first.name;
      return 'Every account will see $name’s due work.';
    }
    return 'Every account sees the tasks assigned to them.';
  }

  Future<void> _save() async {
    if (_mode == 'user' && _source <= 0) {
      _toast(context, 'Pick an account to watch.');
      return;
    }
    final res = await widget.service.saveGlobalReminder(
      mode: _mode,
      sourceUserId: _mode == 'user' ? _source : 0,
    );
    if (!mounted) return;
    _toast(
      context,
      res.message ??
          (res.ok
              ? 'Dashboard reminders updated for all accounts.'
              : 'Could not save the reminder setting.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final state = _state;
    return StationScaffold(
      stationLabel: 'Preferences',
      title: 'Dashboard reminders',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Skeleton(height: 160, radius: 16)
          : state == null
          ? EmptyState(
              icon: Icons.lock_outline_rounded,
              label: 'Could not load this setting',
              hint:
                  'Only super admins can change it. If you are one, the '
                  'server may need updating.',
              action: GhostButton(label: 'Retry', onPressed: _load),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                AppCard(
                  radius: Brand.radiusLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text.rich(
                        const TextSpan(
                          children: [
                            TextSpan(text: 'Applies to '),
                            TextSpan(
                              text: 'all accounts',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(
                              text:
                                  ' — choose whose task reminders everyone '
                                  'sees on their dashboard.',
                            ),
                          ],
                        ),
                        style: text.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: _mode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Dashboard reminders for all accounts',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'off',
                            child: Text('Hidden for everyone'),
                          ),
                          DropdownMenuItem(
                            value: 'own',
                            child: Text('Everyone sees their own tasks'),
                          ),
                          DropdownMenuItem(
                            value: 'user',
                            child: Text('Everyone watches one account'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _mode = v;
                            if (v == 'user' &&
                                _source <= 0 &&
                                state.users.isNotEmpty) {
                              _source = state.users.first.id;
                            }
                          });
                          _save();
                        },
                      ),
                      if (_mode == 'user') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: state.users.any((u) => u.id == _source)
                              ? _source
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Account everyone watches',
                          ),
                          items: [
                            for (final u in state.users)
                              DropdownMenuItem(
                                value: u.id,
                                child: Text(
                                  u.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _source = v);
                            _save();
                          },
                        ),
                      ],
                      _note(context, _describe()),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
