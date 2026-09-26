import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../api_client.dart';
import '../../services/desktop_notifier.dart';
import '../../services/live_sync.dart';
import '../../services/saved_logins.dart';
import '../../services/sound_engine.dart';
import '../../services/theme_prefs.dart';
import '../../services/web_settings_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../admin/admin_list.dart';
import '../../widgets/tp_loader.dart';

class WebSettingsScreen extends StatefulWidget {
  const WebSettingsScreen({
    super.key,
    required this.api,
    this.themePrefs,
    this.onLogout,
  });
  final ApiClient api;
  final ThemePrefs? themePrefs;
  final VoidCallback? onLogout;

  static final ValueNotifier<int?> requestTab = ValueNotifier<int?>(null);
  static const int desktopTab = 4;

  @override
  State<WebSettingsScreen> createState() => _WebSettingsScreenState();
}

class _Tab {
  const _Tab(this.label, this.hint, this.icon);
  final String label;
  final String hint;
  final IconData icon;
}

const _tabs = <_Tab>[
  _Tab('Account', 'Update the personal info shown across your workspace.',
      Icons.person_outline),
  _Tab('Security', 'Keep your account safe with a strong password and 2FA.',
      Icons.shield_outlined),
  _Tab('Appearance', 'Choose how dates and times appear across the workspace.',
      Icons.palette_outlined),
  _Tab('Preferences', 'Notification sounds and workspace-wide options.',
      Icons.tune),
  _Tab('Desktop app', 'Settings that only apply to this app on this computer.',
      Icons.desktop_windows_outlined),
];

class _WebSettingsScreenState extends State<WebSettingsScreen>
    with LiveRefresh<WebSettingsScreen> {
  late final WebSettingsService _svc = WebSettingsService(widget.api);
  int _tab = 0;
  bool _loading = true;
  String? _error;
  SelfSettings? _me;

  @override
  void initState() {
    super.initState();
    _load();
    WebSettingsScreen.requestTab.addListener(_onTabRequest);
    final dbgTab = kDebugMode
        ? int.tryParse(Platform.environment['TP_SETTINGS_TAB'] ?? '')
        : null;
    if (dbgTab != null) _tab = dbgTab;
    _onTabRequest();
  }

  void _onTabRequest() {
    final t = WebSettingsScreen.requestTab.value;
    if (t == null) return;
    WebSettingsScreen.requestTab.value = null;
    if (mounted && t >= 0 && t < _tabs.length) setState(() => _tab = t);
  }

  @override
  void dispose() {
    WebSettingsScreen.requestTab.removeListener(_onTabRequest);
    super.dispose();
  }

  @override
  List<String> get liveKeys => const ['settings'];

  @override
  void onLiveChange() {
    if (_me == null || _loading) return;
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final me = await _svc.load();
      if (!mounted) return;
      setState(() {
        _me = me;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '30',
      stationLabel: 'SETTINGS',
      title: 'Settings',
      showBottomBrand: false,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      leading: SizedBox(
        height: 56,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _NavItem(
                  tab: _tabs[i],
                  selected: _tab == i,
                  onTap: () => setState(() => _tab = i),
                ),
            ],
          ),
        ),
      ),
      trailing: const _VersionBadge(),
      child: _body(),
    );
  }

  Widget _body() {
    if (_tab == WebSettingsScreen.desktopTab) {
      return DesktopAppPane(
          api: widget.api,
          themePrefs: widget.themePrefs,
          onLogout: widget.onLogout);
    }
    if (_loading) {
      return const Center(child: TpLoader());
    }
    if (_error != null || _me == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
                label: 'Could not load settings',
                hint: _error ?? 'Failed to load settings.'),
            const SizedBox(height: 12),
            _StBtn(label: 'Retry', icon: Icons.refresh, onPressed: _load),
          ],
        ),
      );
    }
    final me = _me!;
    return IndexedStack(
      index: _tab,
      children: [
        _AccountPane(
            svc: _svc,
            me: me,
            onChanged: (m) => setState(() => _me = m),
            reload: _load),
        _SecurityPane(svc: _svc, me: me),
        _AppearancePane(
            svc: _svc,
            me: me,
            themePrefs: widget.themePrefs,
            onSaved: (prefs) => setState(() => _me = SelfSettings(
                  fullName: me.fullName,
                  email: me.email,
                  emailVerified: me.emailVerified,
                  username: me.username,
                  role: me.role,
                  chatAlias: me.chatAlias,
                  mfaEnabled: me.mfaEnabled,
                  profilePicture: me.profilePicture,
                  preferences: prefs,
                  soundSettings: me.soundSettings,
                ))),
        _PreferencesPane(
            svc: _svc, me: me, onSoundsSaved: () => _load(silent: true)),
        const SizedBox.shrink(),
      ],
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem(
      {required this.tab, required this.selected, required this.onTap});
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.selected;
    final color = on
        ? Brand.signal
        : (_hover ? context.brand.paper : context.brand.paperDim);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: on ? Brand.signal : Colors.transparent, width: 2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.tab.icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(widget.tab.label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title, this.subtitle, required this.child, this.action});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.brand.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: text.labelLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
      {required this.title,
      required this.desc,
      required this.value,
      required this.onChanged});
  final String title;
  final String desc;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border.all(color: context.brand.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(desc, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: Brand.signal),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(
      {required this.label,
      this.note,
      required this.child,
      this.hint,
      this.badge});
  final String label;
  final String? note;
  final Widget? badge;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(label,
                  style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.brand.paper)),
            ),
            if (note != null) ...[
              const SizedBox(width: 6),
              Text(note!, style: text.bodySmall?.copyWith(fontSize: 11.5)),
            ],
            ?badge,
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint!, style: text.bodySmall),
        ],
      ],
    );
  }
}

Widget _cols(List<Widget> children, {double gap = 24, double breakAt = 820}) {
  return LayoutBuilder(builder: (ctx, c) {
    if (c.maxWidth < breakAt) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap / 2),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  });
}

Widget _pane(_Tab tab, List<Widget> children) {
  return Builder(builder: (context) {
    final text = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        decoration: BoxDecoration(
          color: context.brand.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.brand.rule),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tab.label,
                          style: text.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(tab.hint, style: text.bodySmall),
                    ],
                  ),
                ),
                IconTile(icon: tab.icon, size: 30),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  });
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) {
    final p = parts.first;
    return p.substring(0, p.length < 2 ? p.length : 2).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class _AccountPane extends StatefulWidget {
  const _AccountPane(
      {required this.svc,
      required this.me,
      required this.onChanged,
      required this.reload});
  final WebSettingsService svc;
  final SelfSettings me;
  final ValueChanged<SelfSettings> onChanged;
  final Future<void> Function() reload;

  @override
  State<_AccountPane> createState() => _AccountPaneState();
}

class _AccountPaneState extends State<_AccountPane> {
  late final _name = TextEditingController(text: widget.me.fullName);
  late final _email = TextEditingController(text: widget.me.email);
  late final _alias = TextEditingController(text: widget.me.chatAlias);
  final _otp = TextEditingController();
  bool _saving = false;
  bool _avatarBusy = false;
  bool _otpStage = false;
  bool _otpBusy = false;
  int _avatarNonce = DateTime.now().millisecondsSinceEpoch;
  Timer? _otpTimer;
  int _otpLeft = 0;

  void _startOtpTimer(int seconds) {
    _otpTimer?.cancel();
    _otpLeft = seconds;
    void tick() {
      _otpLeft--;
      if (_otpLeft <= 0) _otpTimer?.cancel();
      if (mounted) setState(() {});
    }

    tick();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String get _otpTimerLabel {
    if (_otpLeft <= 0) return 'Code expired — request a new one.';
    final m = _otpLeft ~/ 60;
    final sec = _otpLeft % 60;
    return '(expires in $m:${sec < 10 ? '0' : ''}$sec)';
  }

  @override
  void didUpdateWidget(covariant _AccountPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_saving || _otpStage) return;
    final o = oldWidget.me, n = widget.me;
    for (final (c, before, after) in [
      (_name, o.fullName, n.fullName),
      (_email, o.email, n.email),
      (_alias, o.chatAlias, n.chatAlias),
    ]) {
      if (c.text == before && before != after) c.text = after;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _alias.dispose();
    _otp.dispose();
    _otpTimer?.cancel();
    super.dispose();
  }

  SelfSettings _copy({
    String? fullName,
    String? email,
    bool? emailVerified,
    String? chatAlias,
    String? profilePicture,
    bool clearPicture = false,
  }) {
    final m = widget.me;
    return SelfSettings(
      fullName: fullName ?? m.fullName,
      email: email ?? m.email,
      emailVerified: emailVerified ?? m.emailVerified,
      username: m.username,
      role: m.role,
      chatAlias: chatAlias ?? m.chatAlias,
      mfaEnabled: m.mfaEnabled,
      profilePicture: clearPicture ? null : (profilePicture ?? m.profilePicture),
      preferences: m.preferences,
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty) {
      toast(context, 'Full name is required.');
      return;
    }
    if (email.isEmpty) {
      toast(context, 'Email is required.');
      return;
    }
    setState(() => _saving = true);
    try {
      final r = await widget.svc.updateAccount(
          fullName: name, email: email, chatAlias: _alias.text.trim());
      if (!mounted) return;
      toast(context, r.ok ? 'Account updated.' : r.message);
      if (r.ok) {
        final emailChanged = email != widget.me.email;
        widget.onChanged(_copy(fullName: name, email: email, chatAlias: _alias.text.trim()));
        if (emailChanged) await widget.reload();
      }
    } catch (e) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() {
    _name.text = widget.me.fullName;
    _email.text = widget.me.email;
    _alias.text = widget.me.chatAlias;
  }

  Future<void> _pickAvatar() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    );
    final picked = res?.files.single;
    final path = picked?.path;
    if (picked == null || path == null) return;
    if (!RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false)
        .hasMatch(path)) {
      if (mounted) toast(context, 'Please choose a PNG, JPG, GIF, or WEBP image.');
      return;
    }
    if (picked.size > 3 * 1024 * 1024) {
      if (mounted) toast(context, 'Image must be 3 MB or smaller.');
      return;
    }
    setState(() => _avatarBusy = true);
    try {
      final r = await widget.svc.uploadAvatar(path);
      if (!mounted) return;
      toast(context, r.ok ? 'Profile picture updated.' : r.message);
      if (r.ok) {
        _avatarNonce = DateTime.now().millisecondsSinceEpoch;
        widget.onChanged(
            _copy(profilePicture: (r.data['profile_picture'] ?? '').toString()));
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error uploading picture.');
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    final previous = widget.me.profilePicture;
    widget.onChanged(_copy(clearPicture: true));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Profile picture removed'),
            duration: const Duration(seconds: 5),
            persist: false,
            action: SnackBarAction(label: 'Undo', onPressed: () {}),
          ),
        )
        .closed;
    if (!mounted) return;
    if (reason == SnackBarClosedReason.action) {
      widget.onChanged(_copy(profilePicture: previous));
      return;
    }
    setState(() => _avatarBusy = true);
    try {
      final r = await widget.svc.removeAvatar();
      if (!mounted) return;
      if (!r.ok) {
        toast(context, r.message);
        widget.onChanged(_copy(profilePicture: previous));
      }
    } catch (_) {
      if (mounted) {
        toast(context, 'Network error.');
        widget.onChanged(_copy(profilePicture: previous));
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _sendCode() async {
    setState(() => _otpBusy = true);
    try {
      final r = await widget.svc.sendEmailOtp();
      if (!mounted) return;
      toast(context, r.ok ? 'Verification code sent.' : r.message);
      if (r.ok) {
        _otp.clear();
        setState(() => _otpStage = true);
        _startOtpTimer(600);
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _otpBusy = false);
    }
  }

  Future<void> _verify() async {
    final otp = _otp.text.trim();
    if (otp.length < 6) {
      toast(context, 'Enter the 6-digit code.');
      return;
    }
    setState(() => _otpBusy = true);
    try {
      final r = await widget.svc.verifyEmail(otp);
      if (!mounted) return;
      toast(context, r.ok ? 'Email verified.' : r.message);
      if (r.ok) {
        _otpTimer?.cancel();
        setState(() => _otpStage = false);
        widget.onChanged(_copy(emailVerified: true));
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _otpBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final me = widget.me;
    final pic = me.profilePicture;
    final display = me.fullName.isEmpty ? me.username : me.fullName;
    return _pane(_tabs[0], [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.brand.surfaceHi,
          border: Border.all(color: context.brand.rule),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Tooltip(
              message: 'Change profile picture',
              child: InkWell(
                onTap: _avatarBusy ? null : _pickAvatar,
                customBorder: const CircleBorder(),
                mouseCursor: SystemMouseCursors.click,
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: Brand.signal,
                  child: _avatarBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: TpLoader(
                              strokeWidth: 2, color: Colors.white))
                      : pic == null
                          ? Text(_initials(display),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17))
                          : ClipOval(
                              child: Image.network(
                                '${widget.svc.resolveUrl(pic)}${pic.contains('?') ? '' : '?t=$_avatarNonce'}',
                                headers: widget.svc.api.authHeaders(),
                                width: 52,
                                height: 52,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Text(
                                    _initials(display),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 17)),
                              ),
                            ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(display.isEmpty ? 'User' : display,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  Text(me.email.isEmpty ? '—' : me.email,
                      style: text.bodySmall),
                ],
              ),
            ),
            if (me.role.isNotEmpty) ...[
              StatusPill(
                  label: me.role.replaceAll('_', ' ').toUpperCase(),
                  color: Brand.signal),
              const SizedBox(width: 12),
            ],
            _StBtn(ghost: true, 
              label: 'Change photo',
              icon: Icons.photo_camera_outlined,
              onPressed: _avatarBusy ? null : _pickAvatar,
            ),
            if (pic != null) ...[
              const SizedBox(width: 8),
              _StBtn(ghost: true, 
                label: 'Remove',
                icon: Icons.delete_outline,
                onPressed: _avatarBusy ? null : _removeAvatar,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 18),
      _cols([
        _Field(
          label: 'Full Name',
          note: 'required',
          child: TextField(
            controller: _name,
            decoration:
                const InputDecoration(hintText: 'Enter your full name'),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              label: 'Email Address',
              badge: me.email.isEmpty
                  ? null
                  : _VerifiedPill(verified: me.emailVerified),
              child: TextField(
                controller: _email,
                decoration: const InputDecoration(
                  hintText: 'you@example.com',
                ),
              ),
            ),
            if (me.email.isNotEmpty && !me.emailVerified) _verifyBox(text),
          ],
        ),
        _Field(
          label: 'Username',
          note: 'read-only',
          child: InputDecorator(
            decoration: InputDecoration(
                filled: true, fillColor: context.brand.surfaceHi),
            child: Text(me.username.isEmpty ? 'username' : me.username,
                style:
                    text.bodyMedium?.copyWith(color: context.brand.paperDim)),
          ),
        ),
        _Field(
          label: 'Chat Alias',
          note: 'optional',
          hint:
              'Shown to website visitors instead of your real name once you accept their ticket. Leave blank to appear as “Support agent”.',
          child: TextField(
            controller: _alias,
            maxLength: 60,
            decoration:
                const InputDecoration(hintText: 'e.g. Maya', counterText: ''),
          ),
        ),
      ], gap: 16, breakAt: 900),
      const SizedBox(height: 20),
      Row(
        children: [
          _StBtn(
              label: 'Save changes',
              icon: Icons.check_circle_outline,
              busy: _saving,
              onPressed: _saving ? null : _save),
          const SizedBox(width: 10),
          _StBtn(ghost: true, label: 'Reset', icon: Icons.refresh, onPressed: _reset),
        ],
      ),
      const SizedBox(height: 8),
    ]);
  }

  Widget _verifyBox(TextTheme text) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x0FF59E0B),
        border: Border.all(color: const Color(0x40F59E0B)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: !_otpStage
          ? Row(
              children: [
                Expanded(
                    child: Text('Your email isn\'t verified yet.',
                        style: text.bodySmall)),
                TextButton.icon(
                  onPressed: _otpBusy ? null : _sendCode,
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: Text(_otpBusy ? 'Sending…' : 'Send code'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Enter the 6-digit code sent to ${_email.text.trim()}. $_otpTimerLabel',
                    style: text.bodySmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _otp,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            hintText: '000000', counterText: ''),
                        onSubmitted: (_) => _verify(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StBtn(
                        label: 'Verify',
                        busy: _otpBusy,
                        onPressed: _otpBusy ? null : _verify),
                    const SizedBox(width: 6),
                    _StBtn(ghost: true, 
                        label: 'Resend',
                        onPressed: _otpBusy ? null : _sendCode),
                  ],
                ),
              ],
            ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Brand.signal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Brand.signal.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.18),
                    spreadRadius: 3),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Text('v1.0.4 STABLE',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: Brand.signal)),
        ],
      ),
    );
  }
}

class _StBtn extends StatefulWidget {
  const _StBtn({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.ghost = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool ghost;

  @override
  State<_StBtn> createState() => _StBtnState();
}

class _StBtnState extends State<_StBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final fg = widget.ghost ? context.brand.paper : Colors.white;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(
              0, !widget.ghost && _hover && enabled ? -1 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          decoration: BoxDecoration(
            color: widget.ghost
                ? (_hover && enabled ? context.brand.canvas : Colors.transparent)
                : (enabled
                    ? (_hover ? const Color(0xFFE66F00) : Brand.signal)
                    : Brand.signal.withValues(alpha: 0.45)),
            borderRadius: BorderRadius.circular(999),
            border: widget.ghost
                ? Border.all(color: context.brand.rule, width: 1.5)
                : null,
            boxShadow: widget.ghost || !enabled
                ? null
                : [
                    BoxShadow(
                        color: Brand.signal
                            .withValues(alpha: _hover ? 0.4 : 0.25),
                        blurRadius: _hover ? 18 : 10,
                        offset: Offset(0, _hover ? 4 : 2)),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: TpLoader(strokeWidth: 2, color: fg),
                )
              else if (widget.icon != null)
                Icon(widget.icon, size: 16, color: fg),
              if (widget.busy || widget.icon != null) const SizedBox(width: 8),
              Text(widget.label,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifiedPill extends StatelessWidget {
  const _VerifiedPill({required this.verified});
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final color = verified ? const Color(0xFF10B981) : const Color(0xFFD97706);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(verified ? Icons.verified : Icons.error_outline,
                size: 12, color: color),
            const SizedBox(width: 4),
            Text(verified ? 'VERIFIED' : 'UNVERIFIED',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

class _SecurityPane extends StatefulWidget {
  const _SecurityPane({required this.svc, required this.me});
  final WebSettingsService svc;
  final SelfSettings me;

  @override
  State<_SecurityPane> createState() => _SecurityPaneState();
}

class _SecurityPaneState extends State<_SecurityPane>
    with LiveRefresh<_SecurityPane> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _pwBusy = false;
  late bool _mfa = widget.me.mfaEnabled;
  bool _mfaBusy = false;

  AgentHours? _hours;
  bool _hoursOn = false;
  String _start = '08:00';
  String _end = '17:00';
  bool _hoursBusy = false;

  TicketReminder? _reminder;
  bool _remOn = false;
  final _days = TextEditingController();
  bool _remBusy = false;

  List<PosApiKey>? _keys;
  bool _keysLoading = true;
  bool _showRevoked = false;
  String? _newToken;
  bool _keyBusy = false;

  @override
  void initState() {
    super.initState();
    _new.addListener(() => setState(() {}));
    _loadExtras();
  }

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _confirm.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _loadExtras() async {
    final results = await Future.wait([
      widget.svc.agentHours(),
      widget.svc.ticketReminder(),
      widget.svc.posApiKeys(),
    ]);
    if (!mounted) return;
    setState(() {
      _hours = results[0] as AgentHours?;
      if (_hours != null) {
        _hoursOn = _hours!.enabled;
        _start = _hours!.start;
        _end = _hours!.end;
      }
      _reminder = results[1] as TicketReminder?;
      if (_reminder != null) {
        _remOn = _reminder!.enabled;
        _days.text = '${_reminder!.days}';
      }
      _keys = results[2] as List<PosApiKey>?;
      _keysLoading = false;
    });
  }

  @override
  List<String> get liveKeys => const ['settings'];

  @override
  void onLiveChange() => _liveExtras();

  @override
  void didUpdateWidget(covariant _SecurityPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_mfaBusy && oldWidget.me.mfaEnabled != widget.me.mfaEnabled) {
      _mfa = widget.me.mfaEnabled;
    }
  }

  Future<void> _liveExtras() async {
    if (_keysLoading) return;
    final List<Object?> results;
    try {
      results = await Future.wait([
        widget.svc.agentHours(),
        widget.svc.ticketReminder(),
        widget.svc.posApiKeys(),
      ]);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final hours = results[0] as AgentHours?;
    final reminder = results[1] as TicketReminder?;
    final keys = results[2] as List<PosApiKey>?;
    setState(() {
      final h = _hours;
      final hoursDirty = h != null &&
          (_hoursOn != h.enabled || _start != h.start || _end != h.end);
      if (hours != null && !hoursDirty && !_hoursBusy) {
        _hours = hours;
        _hoursOn = hours.enabled;
        _start = hours.start;
        _end = hours.end;
      }
      final r = _reminder;
      final remDirty = r != null &&
          (_remOn != r.enabled || _days.text.trim() != '${r.days}');
      if (reminder != null && !remDirty && !_remBusy) {
        _reminder = reminder;
        _remOn = reminder.enabled;
        if (_days.text != '${reminder.days}') _days.text = '${reminder.days}';
      }
      if (keys != null && !_keyBusy) _keys = keys;
    });
  }

  Future<void> _reloadKeys() async {
    final keys = await widget.svc.posApiKeys();
    if (!mounted) return;
    setState(() => _keys = keys);
  }

  int _score(String pw) {
    if (pw.isEmpty) return 0;
    var s = 0;
    if (pw.length >= 8) s++;
    if (pw.length >= 12) s++;
    if (RegExp(r'[A-Z]').hasMatch(pw) && RegExp(r'[a-z]').hasMatch(pw)) s++;
    if (RegExp(r'\d').hasMatch(pw) && RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) {
      s++;
    }
    return s > 4 ? 4 : s;
  }

  Future<void> _changePassword() async {
    if (_new.text != _confirm.text) {
      toast(context, 'New password and confirmation do not match.');
      return;
    }
    if (_new.text.length < 8) {
      toast(context, 'New password must be at least 8 characters.');
      return;
    }
    setState(() => _pwBusy = true);
    try {
      final r = await widget.svc.changePassword(
          current: _cur.text, next: _new.text, confirm: _confirm.text);
      if (!mounted) return;
      toast(context, r.ok ? 'Password updated.' : r.message);
      if (r.ok) {
        _cur.clear();
        _new.clear();
        _confirm.clear();
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _pwBusy = false);
    }
  }

  Future<void> _toggleMfa(bool v) async {
    setState(() {
      _mfa = v;
      _mfaBusy = true;
    });
    try {
      final r = await widget.svc.setMfa(v);
      if (!mounted) return;
      toast(context, r.ok ? (r.message.isEmpty ? '2FA setting updated.' : r.message) : r.message);
      if (!r.ok) setState(() => _mfa = !v);
    } catch (_) {
      if (!mounted) return;
      toast(context, 'Network error.');
      setState(() => _mfa = !v);
    } finally {
      if (mounted) setState(() => _mfaBusy = false);
    }
  }

  Future<void> _pickTime(bool start) async {
    final cur = start ? _start : _end;
    final parts = cur.split(':');
    final initial = TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final v =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() => start ? _start = v : _end = v);
  }

  Future<void> _saveHours() async {
    setState(() => _hoursBusy = true);
    try {
      final r = await widget.svc
          .saveAgentHours(enabled: _hoursOn, start: _start, end: _end);
      if (mounted) toast(context, r.message);
      final h = _hours;
      if (mounted && r.ok && h != null) {
        _hours = AgentHours(
            enabled: _hoursOn, start: _start, end: _end, tz: h.tz);
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _hoursBusy = false);
    }
  }

  Future<void> _saveReminder() async {
    setState(() => _remBusy = true);
    try {
      final r = await widget.svc.saveTicketReminder(
          enabled: _remOn,
          days: _days.text.trim().isEmpty ? '3' : _days.text.trim());
      if (mounted) toast(context, r.message);
      final fresh = await widget.svc.ticketReminder();
      if (mounted && fresh != null) {
        setState(() {
          _reminder = fresh;
          _remOn = fresh.enabled;
          _days.text = '${fresh.days}';
        });
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _remBusy = false);
    }
  }

  Future<void> _generateKey() async {
    setState(() => _keyBusy = true);
    final r = await widget.svc.createPosApiKey();
    if (!mounted) return;
    setState(() => _keyBusy = false);
    final token = (r.data['token'] ?? '').toString();
    if (r.ok && token.isNotEmpty) {
      setState(() => _newToken = token);
      toast(context, 'Key created.');
      _reloadKeys();
    } else {
      toast(context, r.message);
    }
  }

  Future<void> _revoke(PosApiKey k) async {
    if (!await confirmDialog(context,
        title: 'Revoke this key?',
        message:
            'Every POS using it stops syncing immediately. This cannot be undone.',
        confirmLabel: 'Revoke')) {
      return;
    }
    final r = await widget.svc.revokePosApiKey(k.id);
    if (!mounted) return;
    toast(context, r.ok ? 'Key revoked.' : r.message);
    if (r.ok) _reloadKeys();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final score = _score(_new.text);
    const labels = ['Empty', 'Weak', 'Fair', 'Good', 'Strong'];
    const colors = [
      Color(0xFFDC2626),
      Color(0xFFDC2626),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFF059669),
    ];
    final password = _Section(
      title: 'Password',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            label: 'Current password',
            note: 'required',
            child: TextField(
              controller: _cur,
              obscureText: true,
              decoration: const InputDecoration(hintText: '••••••••'),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Field(
                      label: 'New password',
                      note: 'min 8 chars',
                      child: TextField(
                        controller: _new,
                        obscureText: true,
                        decoration:
                            const InputDecoration(hintText: '••••••••'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (var i = 0; i < 4; i++)
                          Expanded(
                            child: Container(
                              height: 4,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: i < score
                                    ? colors[score]
                                    : context.brand.rule,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(labels[score], style: text.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _Field(
                  label: 'Confirm new',
                  note: 'must match',
                  child: TextField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(hintText: '••••••••'),
                    onSubmitted: (_) => _changePassword(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: _StBtn(
                label: 'Update password',
                icon: Icons.key,
                busy: _pwBusy,
                onPressed: _pwBusy ? null : _changePassword),
          ),
        ],
      ),
    );
    final mfa = _Section(
      title: 'Two-factor authentication',
      child: _ToggleRow(
        title: 'Require 2FA at login',
        desc:
            'Adds an email OTP step every time you sign in. Saves automatically.',
        value: _mfa,
        onChanged: _mfaBusy ? null : _toggleMfa,
      ),
    );
    final hours = _hours == null
        ? null
        : _Section(
            title: 'Agent operating hours',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ToggleRow(
                  title: 'Enable operating hours',
                  desc:
                      'If enabled, the chatbot will only escalate to an agent during these hours. Outside these hours, visitors will be asked to leave a message.',
                  value: _hoursOn,
                  onChanged: (v) => setState(() => _hoursOn = v),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _TimeField(
                        label: 'Start Time',
                        value: _start,
                        onTap: () => _pickTime(true)),
                    const SizedBox(width: 16),
                    _TimeField(
                        label: 'End Time',
                        value: _end,
                        onTap: () => _pickTime(false)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule,
                        size: 14, color: context.brand.paperDim),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          'Times are in the server timezone (${_hours!.tz.isEmpty ? '—' : _hours!.tz}).',
                          style: text.bodySmall),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _StBtn(
                      label: 'Save operating hours',
                      icon: Icons.schedule,
                      busy: _hoursBusy,
                      onPressed: _hoursBusy ? null : _saveHours),
                ),
              ],
            ),
          );
    final reminder = _reminder == null
        ? null
        : _Section(
            title: 'Unresolved ticket reminder',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ToggleRow(
                  title: 'Remind agents about open tickets',
                  desc:
                      'Shows a pop-up in the middle of the screen listing tickets — from the Tickets page or from chat — that are still not resolved after the number of days below. Agents see their own tickets plus any nobody has accepted.',
                  value: _remOn,
                  onChanged: (v) => setState(() => _remOn = v),
                ),
                const SizedBox(height: 14),
                _Field(
                  label: 'Remind after',
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _days,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('day/s without being resolved',
                          style: text.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.notifications_none,
                        size: 14, color: context.brand.paperDim),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          'The pop-up shows how many days each ticket has been open. "Remind me later" hides it for 4 hours on that agent\'s browser.',
                          style: text.bodySmall),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _StBtn(
                      label: 'Save reminder settings',
                      icon: Icons.notifications_none,
                      busy: _remBusy,
                      onPressed: _remBusy ? null : _saveReminder),
                ),
              ],
            ),
          );
    return _pane(_tabs[1], [
      _cols([password, mfa]),
      if (hours != null || reminder != null)
        _cols([?hours, ?reminder]),
      if (!_keysLoading && _keys != null) _posKeys(text),
    ]);
  }

  Widget _posKeys(TextTheme text) {
    final keys = _keys!;
    final active = keys.where((k) => k.active).toList();
    final revoked = keys.where((k) => !k.active).toList();
    final shown = _showRevoked ? [...active, ...revoked] : active;
    return _Section(
      title: 'POS API key',
      subtitle:
          'One key for the whole TinkerPro POS product — every client is covered by it. Only the keys issued from your account are listed, and only you can revoke them.',
      action: _StBtn(
          label: 'Generate key',
          icon: Icons.key,
          busy: _keyBusy,
          onPressed: _keyBusy ? null : _generateKey),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_newToken != null)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1410B981),
                border: Border.all(color: const Color(0x5510B981)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Key created — copy it now', style: text.titleSmall),
                  Text(
                      'Only a hash is stored. Leave this page and it can never be shown again.',
                      style: text.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(_newToken!,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13)),
                      ),
                      _StBtn(ghost: true, 
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: _newToken!));
                          if (mounted) toast(context, 'Key copied to clipboard.');
                        },
                        icon: Icons.copy,
                        label: 'Copy',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                  revoked.isNotEmpty
                      ? 'No active key. Generate one and ship it with the POS.'
                      : 'No key yet. Generate one and ship it with the POS.',
                  style: text.bodySmall),
            ),
          for (final k in shown)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.brand.surface,
                border: Border.all(color: context.brand.rule),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(k.label, style: text.titleSmall),
                            const SizedBox(width: 8),
                            _Chip(
                                label: k.active ? 'ACTIVE' : 'REVOKED',
                                color: k.active
                                    ? const Color(0xFF10B981)
                                    : context.brand.paperDim),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          k.active
                              ? '${k.masked} · Created ${_fmt(k.createdAt)} · used ${k.requestCount}× · last ${_fmt(k.lastUsedAt)}'
                              : '${k.masked} · Revoked ${_fmt(k.revokedAt)}',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (k.active)
                    OutlinedButton.icon(
                      onPressed: () => _revoke(k),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Brand.danger,
                        side: const BorderSide(color: Brand.danger),
                        minimumSize: const Size(0, 36),
                      ),
                      icon: const Icon(Icons.block, size: 16),
                      label: const Text('Revoke'),
                    ),
                ],
              ),
            ),
          if (revoked.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showRevoked = !_showRevoked),
                icon: Icon(
                    _showRevoked ? Icons.visibility_off : Icons.history,
                    size: 16),
                label: Text(_showRevoked
                    ? 'Hide revoked'
                    : 'Show ${revoked.length} revoked key${revoked.length == 1 ? '' : 's'}'),
              ),
            ),
          const SizedBox(height: 6),
          Text(
              'The integration guide (endpoint, parameters and code samples) is on the web Settings page.',
              style: text.bodySmall),
        ],
      ),
    );
  }

  String _fmt(String raw) {
    if (raw.isEmpty) return 'never';
    final d = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (d == null) return raw;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${m[d.month - 1]} ${d.day}, ${d.year}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: _Field(
        label: label,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(6),
          child: InputDecorator(
            decoration: const InputDecoration(
              suffixIcon: Icon(Icons.schedule, size: 16),
            ),
            child: Text(value),
          ),
        ),
      ),
    );
  }
}

class _AppearancePane extends StatefulWidget {
  const _AppearancePane(
      {required this.svc,
      required this.me,
      required this.onSaved,
      this.themePrefs});
  final WebSettingsService svc;
  final SelfSettings me;
  final ThemePrefs? themePrefs;
  final ValueChanged<Map<String, dynamic>> onSaved;

  @override
  State<_AppearancePane> createState() => _AppearancePaneState();
}

class _AppearancePaneState extends State<_AppearancePane> {
  late String _fmt = const ['12h', '24h', 'relative'].contains(widget.me.dateFormat)
      ? widget.me.dateFormat
      : '12h';
  bool _busy = false;
  int _fmtRev = 0;

  static String _fmtOf(SelfSettings me) =>
      const ['12h', '24h', 'relative'].contains(me.dateFormat)
          ? me.dateFormat
          : '12h';

  @override
  void didUpdateWidget(covariant _AppearancePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = _fmtOf(oldWidget.me), after = _fmtOf(widget.me);
    if (!_busy && _fmt == before && before != after) {
      _fmt = after;
      _fmtRev++;
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final prefs = Map<String, dynamic>.from(widget.me.preferences)
      ..['dateFormat'] = _fmt;
    try {
      final r = await widget.svc.savePreferences(prefs);
      if (!mounted) return;
      toast(context, r.ok ? 'Appearance saved.' : r.message);
      if (r.ok) widget.onSaved(prefs);
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _pane(_tabs[2], [
      _Section(
        title: 'Date & time format',
        subtitle:
            'How dates appear in tables and timestamps on the web workspace. Saved to your account.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 380,
              child: DropdownButtonFormField<String>(
                key: ValueKey(_fmtRev),
                initialValue: _fmt,
                isDense: true,
                onChanged: (v) => setState(() => _fmt = v ?? _fmt),
                items: const [
                  DropdownMenuItem(
                      value: '12h',
                      child: Text('12-hour — May 8, 2026, 3:45 PM')),
                  DropdownMenuItem(
                      value: '24h',
                      child: Text('24-hour — 2026-05-08, 15:45')),
                  DropdownMenuItem(
                      value: 'relative',
                      child: Text('Relative — 2 hours ago')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _StBtn(
                label: 'Save appearance',
                icon: Icons.check_circle_outline,
                busy: _busy,
                onPressed: _busy ? null : _save),
          ],
        ),
      ),
      _Section(
        title: 'Theme',
        subtitle: 'Light or dark look for this app on this computer.',
        child: widget.themePrefs == null
            ? Text('Theme settings are unavailable here.', style: text.bodySmall)
            : _ThemePicker(prefs: widget.themePrefs!),
      ),
    ]);
  }
}

class _SbItem {
  const _SbItem(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

class _SbGroup {
  const _SbGroup(this.title, this.items);
  final String title;
  final List<_SbItem> items;
}

const _sidebarGroups = <_SbGroup>[
  _SbGroup('Overview & Support', [
    _SbItem('whatsnew', 'What\'s New', Icons.card_giftcard),
    _SbItem('dashboard', 'Dashboard', Icons.grid_view),
    _SbItem('ticket', 'Ticket', Icons.confirmation_number_outlined),
    _SbItem('chat', 'Chat', Icons.forum_outlined),
  ]),
  _SbGroup('Product Suite', [
    _SbItem('posversion', 'POS Version', Icons.account_tree_outlined),
    _SbItem('releasenotes', 'Release Notes', Icons.receipt_long_outlined),
    _SbItem('licensekey', 'License Key', Icons.badge_outlined),
    _SbItem('blogposts', 'Blog Posts', Icons.article_outlined),
  ]),
  _SbGroup('Clients & Accounts', [
    _SbItem('customer', 'BIR Registration', Icons.assignment_outlined),
    _SbItem('clientOffer', 'Leads / Forms', Icons.person_add_alt),
    _SbItem('client', 'Client Directory', Icons.business_center_outlined),
    _SbItem('zreading', 'Z-Reading Request', Icons.receipt_outlined),
    _SbItem('credentials', 'Credentials Storage', Icons.vpn_key_outlined),
  ]),
  _SbGroup('Workspace Modules', [
    _SbItem('user', 'User Management', Icons.manage_accounts_outlined),
    _SbItem('employment', 'Employment Info', Icons.contact_page_outlined),
    _SbItem('offers', 'Offers', Icons.local_offer_outlined),
    _SbItem('pricing', 'Pricing', Icons.attach_money),
    _SbItem('emails', 'Email', Icons.mail_outline),
    _SbItem('files', 'Files Management', Icons.folder_open),
    _SbItem('task', 'Task', Icons.list),
    _SbItem('activitylogs', 'Activity Logs', Icons.fact_check_outlined),
  ]),
  _SbGroup('System Tools', [
    _SbItem('helpPage', 'Help Page', Icons.help_outline),
    _SbItem('barcode', 'Barcode', Icons.qr_code),
    _SbItem('settings', 'Settings', Icons.settings_outlined),
    _SbItem('feedback', 'Feedback Button', Icons.chat_bubble_outline),
    _SbItem('feedbackinbox', 'Feedback Inbox', Icons.inbox_outlined),
    _SbItem('announcements', 'Announcements', Icons.campaign_outlined),
  ]),
];

class _PreferencesPane extends StatefulWidget {
  const _PreferencesPane(
      {required this.svc, required this.me, required this.onSoundsSaved});
  final WebSettingsService svc;
  final SelfSettings me;
  final VoidCallback onSoundsSaved;

  @override
  State<_PreferencesPane> createState() => _PreferencesPaneState();
}

class _PreferencesPaneState extends State<_PreferencesPane>
    with LiveRefresh<_PreferencesPane> {
  Map<String, bool>? _hidden;
  bool _sbBusy = false;
  GlobalReminder? _rem;
  String _remMode = 'own';
  int _remSrc = 0;
  bool _remBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, bool>? _hiddenBase;
  (String, int)? _remBase;

  @override
  List<String> get liveKeys => const ['settings'];

  @override
  void onLiveChange() => _load(silent: true);

  Future<void> _load({bool silent = false}) async {
    if (widget.me.isSuperAdmin) {
      try {
        final h = await widget.svc.sidebarHidden();
        if (mounted) {
          final dirty = _hiddenBase != null &&
              !mapEquals(_hidden ?? const {}, _hiddenBase);
          if (!silent || (!dirty && !_sbBusy)) {
            setState(() {
              _hidden = h;
              _hiddenBase = Map.of(h);
            });
          }
        }
      } catch (_) {
        if (mounted && !silent) setState(() => _hidden = <String, bool>{});
      }
    }
    final GlobalReminder? rem;
    try {
      rem = await widget.svc.globalReminder();
    } catch (_) {
      if (silent) return;
      rethrow;
    }
    if (!mounted) return;
    final remDirty = _remBase != null && (_remMode, _remSrc) != _remBase;
    setState(() {
      _rem = rem;
      if (rem != null && (!silent || (!remDirty && !_remBusy))) {
        _remMode = rem.mode;
        _remSrc = rem.sourceUserId;
        if (_remSrc == 0 && rem.users.isNotEmpty) _remSrc = rem.users.first.id;
        _remBase = (_remMode, _remSrc);
      }
    });
  }

  Future<void> _saveSidebar() async {
    setState(() => _sbBusy = true);
    try {
      final r = await widget.svc.saveSidebarHidden(_hidden ?? const {});
      if (!mounted) return;
      toast(
          context,
          r.ok
              ? 'Global sidebar settings saved for all accounts. Refreshing menu...'
              : r.message);
      if (r.ok) {
        _hiddenBase = Map.of(_hidden ?? const <String, bool>{});
        LiveSync.instance.pollNow();
      }
      if (r.ok && r.data['sidebar_hidden'] is Map) {
        final m = r.data['sidebar_hidden'] as Map;
        setState(() {
          _hidden = m.map((k, v) => MapEntry(k.toString(), v == true));
          _hiddenBase = Map.of(_hidden!);
        });
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error saving sidebar settings.');
    } finally {
      if (mounted) setState(() => _sbBusy = false);
    }
  }

  Future<void> _saveReminder() async {
    final src = _remMode == 'user' ? _remSrc : 0;
    if (_remMode == 'user' && src == 0) {
      toast(context, 'Pick an account to watch.');
      return;
    }
    setState(() => _remBusy = true);
    try {
      final r = await widget.svc.saveGlobalReminder(mode: _remMode, source: src);
      if (mounted) toast(context, r.message);
      if (mounted && r.ok) _remBase = (_remMode, _remSrc);
    } catch (_) {
      if (mounted) toast(context, 'Network connection error.');
    } finally {
      if (mounted) setState(() => _remBusy = false);
    }
  }

  String _remNote() {
    if (_remMode == 'off') return 'No account will see the Reminders panel.';
    if (_remMode == 'user') {
      final u = _rem?.users.where((u) => u.id == _remSrc).toList() ?? const [];
      final name = u.isEmpty ? 'that account' : u.first.name;
      return 'Every account will see $name’s due work.';
    }
    return 'Every account sees the tasks assigned to them.';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget? sidebar;
    if (widget.me.isSuperAdmin && _hidden != null) {
      sidebar = _Section(
        title: 'Global sidebar navigation items',
        subtitle:
            'Show or hide specific modules and pages in the sidebar menu across all accounts.',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StBtn(ghost: true, 
              onPressed: () => setState(() => _hidden = <String, bool>{}),
              icon: Icons.visibility_outlined,
              label: 'Show all',
            ),
            const SizedBox(width: 8),
            _StBtn(ghost: true, 
              onPressed: () => setState(() => _hidden = <String, bool>{}),
              icon: Icons.restart_alt,
              label: 'Reset',
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final g in _sidebarGroups)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: context.brand.surface,
                  border: Border.all(color: context.brand.rule),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.layers_outlined,
                              size: 14, color: Brand.signal),
                          const SizedBox(width: 6),
                          Text(g.title.toUpperCase(),
                              style: text.labelLarge
                                  ?.copyWith(color: context.brand.paper)),
                        ],
                      ),
                    ),
                    LayoutBuilder(builder: (ctx, c) {
                      final cols = (c.maxWidth / 220).floor().clamp(1, 6);
                      final w = (c.maxWidth - (cols - 1) * 10) / cols;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final it in g.items)
                            SizedBox(
                              width: w,
                              child: Container(
                                height: 46,
                                padding:
                                    const EdgeInsets.only(left: 12, right: 4),
                                decoration: BoxDecoration(
                                  color: context.brand.surface,
                                  border:
                                      Border.all(color: context.brand.rule),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(it.icon,
                                        size: 16, color: Brand.signal),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Text(it.label,
                                            style: text.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis)),
                                    Switch(
                                      value: _hidden![it.key] != true,
                                      activeThumbColor: Colors.white,
                                      activeTrackColor: Brand.signal,
                                      onChanged: (v) => setState(() {
                                        final next =
                                            Map<String, bool>.from(_hidden!);
                                        if (v) {
                                          next.remove(it.key);
                                        } else {
                                          next[it.key] = true;
                                        }
                                        _hidden = next;
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: _StBtn(
                  label: 'Save sidebar items',
                  icon: Icons.cloud_upload_outlined,
                  busy: _sbBusy,
                  onPressed: _sbBusy ? null : _saveSidebar),
            ),
          ],
        ),
      );
    }
    Widget? reminders;
    if (_rem != null) {
      reminders = _Section(
        title: 'Dashboard reminders',
        subtitle:
            'Applies to all accounts — choose whose task reminders everyone sees on their dashboard.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 280,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('mode-$_remMode'),
                    initialValue: const ['off', 'own', 'user'].contains(_remMode)
                        ? _remMode
                        : 'own',
                    isDense: true,
                    onChanged: _remBusy
                        ? null
                        : (v) {
                            setState(() => _remMode = v ?? 'own');
                            _saveReminder();
                          },
                    items: const [
                      DropdownMenuItem(
                          value: 'off', child: Text('Hidden for everyone')),
                      DropdownMenuItem(
                          value: 'own',
                          child: Text('Everyone sees their own tasks')),
                      DropdownMenuItem(
                          value: 'user',
                          child: Text('Everyone watches one account')),
                    ],
                  ),
                ),
                if (_remMode == 'user' && _rem!.users.isNotEmpty)
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('src-$_remSrc'),
                      initialValue: _rem!.users.any((u) => u.id == _remSrc)
                          ? _remSrc
                          : _rem!.users.first.id,
                      isDense: true,
                      isExpanded: true,
                      onChanged: _remBusy
                          ? null
                          : (v) {
                              setState(() => _remSrc = v ?? 0);
                              _saveReminder();
                            },
                      items: [
                        for (final u in _rem!.users)
                          DropdownMenuItem(
                              value: u.id,
                              child: Text(u.name,
                                  overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_remNote(), style: text.bodySmall),
          ],
        ),
      );
    }
    final sounds = _SoundsSection(
        svc: widget.svc, me: widget.me, onSaved: widget.onSoundsSaved);
    final List<Widget> children;
    if (sidebar != null && reminders != null) {
      children = [
        LayoutBuilder(builder: (ctx, c) {
          if (c.maxWidth < 1000) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [reminders!, sidebar!],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: reminders!),
              const SizedBox(width: 24),
              Expanded(flex: 3, child: sidebar!),
            ],
          );
        }),
      ];
    } else {
      children = [?reminders, ?sidebar];
    }
    return _pane(_tabs[3], [sounds, ...children]);
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.prefs});
  final ThemePrefs prefs;

  @override
  Widget build(BuildContext context) {
    const options = [
      (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
      (ThemeMode.light, 'Light', Icons.light_mode_outlined),
      (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
    ];
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final o in options)
            _ThemeOption(
              label: o.$2,
              icon: o.$3,
              selected: prefs.value == o.$1,
              onTap: () => prefs.setMode(o.$1),
            ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Brand.signal : context.brand.paper;
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Brand.signalGlow(0.08) : context.brand.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? Brand.signal : context.brand.rule,
              width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          if (selected) const Icon(Icons.check_circle, size: 16, color: Brand.signal),
        ]),
      ),
    );
  }
}

class DesktopAppPane extends StatefulWidget {
  const DesktopAppPane({
    super.key,
    required this.api,
    this.themePrefs,
    this.onLogout,
    this.embedded = false,
  });
  final ApiClient api;
  final ThemePrefs? themePrefs;
  final VoidCallback? onLogout;
  final bool embedded;

  @override
  State<DesktopAppPane> createState() => _DesktopAppPaneState();
}

class _DesktopAppPaneState extends State<DesktopAppPane> {
  List<SavedLogin> _saved = const [];
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final list = await SavedLogins.instance.list(widget.api.baseUrl);
    if (mounted) setState(() => _saved = list);
  }

  Future<void> _forget(SavedLogin login) async {
    final ok = await confirmDialog(context,
        title: 'Remove saved login',
        message: 'Remove the saved login for ${login.email} from this computer?',
        confirmLabel: 'Remove');
    if (!ok) return;
    await SavedLogins.instance.remove(widget.api.baseUrl, login.email);
    await _loadSaved();
    if (mounted) toast(context, 'Saved login removed.');
  }

  Future<void> _testNotification() async {
    setState(() => _testing = true);
    await DesktopNotifier.instance.show(
      id: 990001,
      title: 'TinkerPro Support',
      body: 'Desktop notifications are working.',
    );
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _changeServer() async {
    final controller = TextEditingController(text: widget.api.baseUrl);
    final result = await showWebModal<String>(
      context,
      title: 'Change server',
      subtitle: 'You will be signed out and asked to sign in again.',
      icon: Icons.dns_outlined,
      width: 520,
      builder: (ctx) => TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Server URL',
          hintText: 'https://support.tinkerpro.io',
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: (ctx) => [
        GhostButton(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
        SignalButton(
            label: 'Save & sign out',
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim())),
      ],
    );
    if (result == null) return;
    var url = result.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (url == widget.api.baseUrl) return;
    await widget.api.setBaseUrl(url);
    await widget.api.clearSession();
    widget.onLogout?.call();
  }

  Widget _kv(String label, Widget value) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 160, child: Text(label, style: text.bodySmall)),
          Expanded(child: value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sections = <Widget>[
      _Section(
        title: 'Connection',
        subtitle: 'The server this app talks to and who is signed in.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _kv('Signed in as',
                Text(widget.api.username ?? '—',
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            _kv(
              'Server',
              Row(children: [
                Flexible(
                  child: SelectableText(widget.api.baseUrl,
                      style: text.bodyMedium?.copyWith(
                          color: Brand.signal, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 12),
                _StBtn(
                    label: 'Change',
                    icon: Icons.edit_outlined,
                    ghost: true,
                    onPressed: _changeServer),
              ]),
            ),
          ],
        ),
      ),
      if (widget.embedded && widget.themePrefs != null)
        _Section(
          title: 'Theme',
          subtitle: 'Light or dark look for this app on this computer.',
          child: _ThemePicker(prefs: widget.themePrefs!),
        ),
      _Section(
        title: 'Notifications',
        subtitle: 'Pop-up alerts from this app on this computer.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: DesktopNotifier.instance.enabled,
              builder: (context, on, _) => _ToggleRow(
                title: 'Desktop notifications',
                desc:
                    'Show new chat messages and notifications as system pop-ups, even while the app is minimised.',
                value: on,
                onChanged: DesktopNotifier.instance.setEnabled,
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: DesktopNotifier.instance.enabled,
              builder: (context, on, _) => _StBtn(
                  label: 'Send a test notification',
                  icon: Icons.notifications_active_outlined,
                  ghost: true,
                  busy: _testing,
                  onPressed: on && !_testing ? _testNotification : null),
            ),
          ],
        ),
      ),
      _Section(
        title: 'Saved logins',
        subtitle:
            'Accounts that can sign in with one click on this computer. Passwords are kept in the system keyring.',
        child: _saved.isEmpty
            ? Text('No saved logins for this server.', style: text.bodySmall)
            : Column(
                children: [
                  for (final login in _saved)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: context.brand.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.brand.rule),
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Brand.navy,
                          child: Text(
                              login.email.isEmpty
                                  ? '?'
                                  : login.email[0].toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(login.email,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600))),
                        _StBtn(
                            label: 'Remove',
                            icon: Icons.delete_outline,
                            ghost: true,
                            onPressed: () => _forget(login)),
                      ]),
                    ),
                ],
              ),
      ),
      if (widget.onLogout != null)
        _Section(
          title: 'Session',
          subtitle: 'Sign out of this app on this computer.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: DangerButton(
                label: 'Sign out',
                icon: Icons.logout,
                onPressed: widget.onLogout),
          ),
        ),
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: sections,
      );
    }
    return _pane(_tabs[WebSettingsScreen.desktopTab], sections);
  }
}

class _SoundsSection extends StatefulWidget {
  const _SoundsSection(
      {required this.svc, required this.me, required this.onSaved});
  final WebSettingsService svc;
  final SelfSettings me;
  final VoidCallback onSaved;

  @override
  State<_SoundsSection> createState() => _SoundsSectionState();
}

class _SoundsSectionState extends State<_SoundsSection> {
  late SoundState _state;
  Map<String, String> _sel = {};
  Map<String, String> _base = {};
  bool _busy = false;
  bool _resetBusy = false;
  final Set<String> _uploading = {};

  bool get _global => widget.me.isSuperAdmin;

  @override
  void initState() {
    super.initState();
    _adopt(SoundState.fromJson(widget.me.soundSettings), force: true);
  }

  @override
  void didUpdateWidget(covariant _SoundsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.me.soundSettings, widget.me.soundSettings)) {
      _adopt(SoundState.fromJson(widget.me.soundSettings));
    }
  }

  void _adopt(SoundState s, {bool force = false}) {
    final dirty = !mapEquals(_sel, _base);
    _state = s;
    if (!force && (dirty || _busy)) return;
    final next = <String, String>{};
    for (final e in SoundEngine.events) {
      final v = (_global ? s.global[e.event] : null) ??
          s.effective[e.event] ??
          SoundEngine.factory[e.event]!;
      next[e.event] = _options.contains(v) ? v : SoundEngine.factory[e.event]!;
    }
    _sel = next;
    _base = Map.of(next);
  }

  static final List<String> _options = [
    ...SoundEngine.presetLabels.keys,
    'custom',
    'none',
  ];

  String _label(String v) {
    if (v == 'custom') return 'Custom (uploaded)…';
    if (v == 'none') return 'None (silent)';
    return SoundEngine.presetLabels[v] ?? v;
  }

  void _applyServer(Object? raw) {
    final s = SoundState.fromJson(raw);
    SoundEngine.instance.apply(s);
    setState(() => _adopt(s, force: true));
  }

  Future<void> _save() async {
    final sounds = Map<String, String>.from(_sel);
    for (final e in sounds.entries) {
      SoundEngine.instance.setPref(e.key, e.value);
    }
    setState(() => _busy = true);
    try {
      if (_global) {
        final r = await widget.svc.saveGlobalSounds(sounds);
        if (!mounted) return;
        if (r.ok) {
          _applyServer(r.data['sound_settings']);
          toast(context,
              r.message.isEmpty ? 'Sounds saved for all accounts.' : r.message);
          widget.onSaved();
        } else {
          toast(context, r.message);
        }
        return;
      }
      final fresh = await widget.svc.load();
      final prefs = Map<String, dynamic>.from(fresh.preferences);
      sounds.forEach((k, v) => prefs['snd_$k'] = v);
      prefs['snd_user_set'] = true;
      final r = await widget.svc.savePreferences(prefs);
      if (!mounted) return;
      if (r.ok) {
        final s = SoundState(
            effective: sounds, global: _state.global, inheritsGlobal: false);
        SoundEngine.instance.apply(s);
        setState(() => _adopt(s, force: true));
        toast(context, 'Sounds saved.');
        widget.onSaved();
      } else {
        toast(context, r.message);
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    setState(() => _resetBusy = true);
    try {
      final r = await widget.svc.resetOwnSounds();
      if (!mounted) return;
      if (r.ok) {
        _applyServer(r.data['sound_settings']);
        toast(context,
            r.message.isEmpty ? 'Using the system default sounds.' : r.message);
        widget.onSaved();
      } else {
        toast(context, r.message);
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error.');
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  void _preview(String event) {
    unawaited(SoundEngine.instance.preview(event, _sel[event] ?? 'none'));
  }

  void _change(String event, String? v) {
    if (v == null) return;
    setState(() => _sel[event] = v);
    if (v == 'none' || v == 'custom') return;
    unawaited(SoundEngine.instance.preview(event, v));
  }

  Future<void> _upload(String event) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'ogg', 'm4a'],
      dialogTitle: 'Choose a sound file',
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    final size = picked!.files.single.size;
    if (size > 1024 * 1024) {
      toast(context, 'Sound file is too large (max 1 MB).');
      return;
    }
    setState(() => _uploading.add(event));
    try {
      final r = await widget.svc.uploadSound(event, path);
      if (!mounted) return;
      if (r.ok) {
        setState(() => _sel[event] = 'custom');
        SoundEngine.instance.setPref(event, 'custom');
        SoundEngine.instance.invalidateCustom(event);
        unawaited(SoundEngine.instance.preview(event, 'custom'));
        toast(context, 'Custom sound uploaded. Click "Save sounds" to keep it.');
      } else {
        toast(context, r.message);
      }
    } catch (_) {
      if (mounted) toast(context, 'Network error uploading sound.');
    } finally {
      if (mounted) setState(() => _uploading.remove(event));
    }
  }

  String _note() {
    if (_global) {
      return 'Every account starts with these sounds. Accounts that saved their own sounds keep theirs.';
    }
    if (!_state.inheritsGlobal) {
      return 'You are using your own sounds, so system default changes will not reach you until you pick Use system default.';
    }
    return 'You are following the system default sounds.';
  }

  Widget _row(BuildContext context, SoundEventInfo e) {
    final text = Theme.of(context).textTheme;
    final meta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(e.title, style: text.titleSmall),
        const SizedBox(height: 2),
        Text(e.desc, style: text.bodySmall),
      ],
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 196,
          child: DropdownButtonFormField<String>(
            key: ValueKey('snd-${e.event}-${_sel[e.event]}'),
            initialValue: _sel[e.event],
            isDense: true,
            isExpanded: true,
            onChanged: _busy ? null : (v) => _change(e.event, v),
            items: [
              for (final v in _options)
                DropdownMenuItem(
                    value: v,
                    child: Text(_label(v), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _SndIconBtn(
          icon: Icons.play_arrow_rounded,
          tooltip: 'Preview',
          onTap: () => _preview(e.event),
        ),
        const SizedBox(width: 6),
        _SndIconBtn(
          icon: Icons.upload_rounded,
          tooltip: 'Upload custom sound',
          busy: _uploading.contains(e.event),
          onTap: _uploading.contains(e.event) ? null : () => _upload(e.event),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.brand.surface,
        border: Border.all(color: context.brand.rule),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(builder: (ctx, c) {
        if (c.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [meta, const SizedBox(height: 10), controls],
          );
        }
        return Row(
          children: [
            Expanded(child: meta),
            const SizedBox(width: 12),
            controls,
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _Section(
      title: 'Notification sounds',
      subtitle: _global
          ? 'Pick a sound for each event, ▶ to preview, or upload your own (mp3/wav, max 1 MB). Saving applies these to all accounts, except accounts that picked their own sounds.'
          : 'Pick a sound for each event, ▶ to preview, or upload your own (mp3/wav, max 1 MB). Saved to your account, and your picks override the system default.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (ctx, c) {
            final cols = c.maxWidth >= 1180 ? 2 : 1;
            final w = (c.maxWidth - (cols - 1) * 10) / cols;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in SoundEngine.events)
                  SizedBox(width: w, child: _row(context, e)),
              ],
            );
          }),
          const SizedBox(height: 10),
          Text(_note(), style: text.bodySmall),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StBtn(
                  label: _global ? 'Save sounds for everyone' : 'Save sounds',
                  icon: Icons.cloud_upload_outlined,
                  busy: _busy,
                  onPressed: _busy ? null : _save),
              if (!_global)
                _StBtn(
                    ghost: true,
                    label: 'Use system default',
                    icon: Icons.restart_alt,
                    busy: _resetBusy,
                    onPressed: _resetBusy ? null : _reset),
            ],
          ),
        ],
      ),
    );
  }
}

class _SndIconBtn extends StatefulWidget {
  const _SndIconBtn(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.busy = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  State<_SndIconBtn> createState() => _SndIconBtnState();
}

class _SndIconBtnState extends State<_SndIconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final fg = _hover && enabled ? Brand.signal : context.brand.paper;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _hover && enabled
                  ? Brand.signal.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _hover && enabled ? Brand.signal : context.brand.rule,
                  width: 1.5),
            ),
            child: Center(
              child: widget.busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: TpLoader(
                          strokeWidth: 2, color: fg))
                  : Icon(widget.icon, size: 18, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
