import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../models/profile_models.dart';
import '../push_service.dart';
import '../services/biometric_auth.dart';
import '../services/chat_app_launcher.dart';
import '../services/account_settings_service.dart';
import '../services/chat_prefs.dart';
import '../services/profile_service.dart';
import '../services/services.dart';
import '../services/theme_prefs.dart';
import '../theme.dart';
import '../widgets/pick_source.dart';
import '../widgets/premium.dart';
import 'account_settings_screens.dart';
import 'auth_screens.dart';
import 'feedback_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    required this.auth,
    this.push,
    this.chatPrefs,
    this.themePrefs,
  });
  final ApiClient api;
  final AuthService auth;

  final PushService? push;

  final ChatPrefs? chatPrefs;

  final ThemePrefs? themePrefs;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loggingOut = false;
  bool _changingServer = false;

  late final ProfileService _profile = ProfileService(widget.api);
  late final AccountSettingsService _settings = AccountSettingsService(
    widget.api,
  );
  ProfileInfo? _account;
  bool _loadingProfile = true;
  bool _avatarBusy = false;
  bool? _mfa;
  bool _mfaBusy = false;

  late final BiometricAuth _biometrics = BiometricAuth(widget.api);
  bool _fingerprintSupported = false;
  bool _fingerprintEnabled = false;
  bool _fingerprintBusy = false;

  @override
  void initState() {
    super.initState();
    widget.chatPrefs?.addListener(_onPrefsChanged);
    _loadProfile();
    _loadMfa();
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final supported = await _biometrics.deviceCanScan();
    final enabled = await _biometrics.isEnabledForCurrentUser();
    if (!mounted) return;
    setState(() {
      _fingerprintSupported = supported;
      _fingerprintEnabled = enabled;
    });
  }

  Future<void> _toggleFingerprint(bool enabled) async {
    if (_fingerprintBusy) return;
    setState(() => _fingerprintBusy = true);
    try {
      if (enabled) {
        final ok = await _biometrics.enable(
          label: _account?.displayName ?? widget.api.username ?? '',
        );
        if (mounted && ok) setState(() => _fingerprintEnabled = true);
      } else {
        await _biometrics.disable();
        if (mounted) setState(() => _fingerprintEnabled = false);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _fingerprintBusy = false);
    }
  }

  Future<void> _loadMfa() async {
    final self = await _settings.load();
    if (!mounted || self == null) return;
    setState(() => _mfa = self.mfaEnabled);
  }

  Future<void> _toggleMfa(bool enabled) async {
    if (_mfaBusy) return;
    final before = _mfa;
    setState(() {
      _mfa = enabled;
      _mfaBusy = true;
    });
    final res = await _settings.setMfa(enabled);
    if (!mounted) return;
    setState(() {
      _mfaBusy = false;
      if (!res.ok) _mfa = before;
    });
    _toast(
      res.message ??
          (res.ok ? '2FA setting updated.' : 'Failed to update 2FA.'),
    );
  }

  Future<void> _open(Widget screen, {bool reloadProfile = false}) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (reloadProfile && mounted) _loadProfile();
  }

  Future<void> _confirmClearCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear local cache?'),
        content: const Text(
          'Removes cached images and files on this device. You\'ll be '
          'signed out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear & sign out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _logout();
  }

  Widget _chevron(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    color: context.brand.paperDim,
    size: 20,
  );

  Future<void> _loadProfile() async {
    final info = await _profile.load();
    if (!mounted) return;
    setState(() {
      _account = info;
      _loadingProfile = false;
    });
  }

  Future<void> _pickAndUploadAvatar() async {
    final picked = await pickWithSource(
      context,
      cameraLabel: 'Take a photo',
      fileLabel: 'Choose an image file',
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      onError: _toast,
    );
    if (picked.isEmpty || !mounted) return;
    setState(() => _avatarBusy = true);
    final res = await _profile.uploadPicture(picked.first.path);
    if (!mounted) return;
    setState(() {
      _avatarBusy = false;
      if (res.ok && res.profilePicture != null) {
        _account = _account?.copyWith(profilePicture: res.profilePicture);
      }
    });
    if (!res.ok) _toast(res.message ?? 'Could not update your photo.');
  }

  Future<void> _removeAvatar() async {
    setState(() => _avatarBusy = true);
    final res = await _profile.removePicture();
    if (!mounted) return;
    setState(() {
      _avatarBusy = false;
      if (res.ok) _account = _account?.copyWith(clearPicture: true);
    });
    if (!res.ok) _toast(res.message ?? 'Could not remove your photo.');
  }

  Future<void> _openAvatarActions() async {
    if (_avatarBusy) return;
    final hasPhoto = _account?.profilePicture != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _AvatarActionSheet(canRemove: hasPhoto),
    );
    if (!mounted || action == null) return;
    if (action == 'pick') {
      await _pickAndUploadAvatar();
    } else if (action == 'remove') {
      await _removeAvatar();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    widget.chatPrefs?.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    await widget.push?.releaseCurrentDevice();
    await widget.auth.logout();
    try {
      await CachedNetworkImage.evictFromCache('');
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
    try {
      final tmp = await getTemporaryDirectory();
      for (final entity in tmp.listSync()) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('chat_')) {
          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (!mounted) return;
    final cp = widget.chatPrefs;
    final tp = widget.themePrefs;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => (cp == null || tp == null)
            ? throw StateError(
                'SettingsScreen.logout requires chatPrefs + themePrefs',
              )
            : LoginScreen(
                api: widget.api,
                auth: widget.auth,
                chatPrefs: cp,
                themePrefs: tp,
              ),
      ),
      (_) => false,
    );
  }

  Future<void> _changeServer() async {
    final cp = widget.chatPrefs;
    final tp = widget.themePrefs;
    if (cp == null || tp == null) return;
    setState(() => _changingServer = true);
    try {
      await widget.push?.releaseCurrentDevice();
      await widget.auth.logout();
    } catch (_) {}
    await widget.api.clearBaseUrl();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => ServerConfigScreen(
          api: widget.api,
          auth: widget.auth,
          chatPrefs: cp,
          themePrefs: tp,
        ),
      ),
      (_) => false,
    );
  }

  Future<void> _pickTheme() async {
    final cp = widget.chatPrefs;
    if (cp == null) return;
    final picked = await showModalBottomSheet<ChatTheme>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ThemePickerSheet(current: cp.theme),
    );
    if (picked != null) await cp.setTheme(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cp = widget.chatPrefs;
    final chatAppInstalled = ChatAppLauncher.instance.installed;
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    final active = widget.api.hasSession;
    return StationScaffold(
      stationNumber: '··',
      stationLabel: 'Settings',
      title: 'Device & account',
      subtitle: widget.api.username ?? '',
      onBack: () => Navigator.of(context).pop(),
      showBottomBrand: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _ProfileRow(
            account: _account,
            loading: _loadingProfile,
            busy: _avatarBusy,
            avatarUrl: _profile.avatarUrl(_account?.profilePicture),
            imageHeaders: _profile.imageHeaders,
            onEdit: _openAvatarActions,
          ),
          const SizedBox(height: 24),
          const _GroupLabel('Account'),
          _SettingsCard(
            children: [
              _SettingRow(
                icon: Icons.person_rounded,
                color: Brand.info,
                title: 'Account',
                subtitle: chatAppInstalled
                    ? 'Name and email'
                    : 'Name, email, chat alias',
                onTap: () => _open(
                  AccountSettingsScreen(
                    service: _settings,
                    showChatFields: !chatAppInstalled,
                  ),
                  reloadProfile: true,
                ),
                trailing: _chevron(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _GroupLabel('Security'),
          _SettingsCard(
            children: [
              _SettingRow(
                icon: Icons.password_rounded,
                color: b.signal,
                title: 'Password',
                subtitle: 'Change your password',
                onTap: () => _open(PasswordSettingsScreen(service: _settings)),
                trailing: _chevron(context),
              ),
              if (_fingerprintSupported)
                _SettingRow(
                  icon: Icons.fingerprint_rounded,
                  color: Brand.info,
                  title: 'Fingerprint sign-in',
                  subtitle:
                      'Scan your fingerprint to sign in on this phone instead '
                      'of typing your password.',
                  onTap: _fingerprintBusy
                      ? null
                      : () => _toggleFingerprint(!_fingerprintEnabled),
                  trailing: Switch(
                    value: _fingerprintEnabled,
                    onChanged: _fingerprintBusy ? null : _toggleFingerprint,
                  ),
                ),
              _SettingRow(
                icon: Icons.shield_rounded,
                color: Brand.success,
                title: 'Two-factor authentication',
                subtitle:
                    'Adds an email OTP step every time you sign in. Saves '
                    'automatically.',
                onTap: _mfa == null || _mfaBusy
                    ? null
                    : () => _toggleMfa(!(_mfa ?? false)),
                trailing: Switch(
                  value: _mfa ?? false,
                  onChanged: _mfa == null || _mfaBusy ? null : _toggleMfa,
                ),
              ),
              if (_settings.canEditAgentOps) ...[
                if (!chatAppInstalled)
                  _SettingRow(
                    icon: Icons.schedule_rounded,
                    color: const Color(0xFF0EA5E9),
                    title: 'Agent operating hours',
                    subtitle: 'When the chatbot hands chats to agents',
                    onTap: () => _open(AgentHoursScreen(service: _settings)),
                    trailing: _chevron(context),
                  ),
                _SettingRow(
                  icon: Icons.alarm_rounded,
                  color: Brand.warning,
                  title: 'Unresolved ticket reminder',
                  subtitle: 'Remind agents about open tickets',
                  onTap: () => _open(TicketReminderScreen(service: _settings)),
                  trailing: _chevron(context),
                ),
              ],
              if (_settings.canManagePosApiKey)
                _SettingRow(
                  icon: Icons.key_rounded,
                  color: const Color(0xFF8B5CF6),
                  title: 'POS API key',
                  subtitle: 'Keys the TinkerPro POS uses to read PTU details',
                  onTap: () => _open(PosApiKeysScreen(service: _settings)),
                  trailing: _chevron(context),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const _GroupLabel('Preferences'),
          _SettingsCard(
            children: [
              if (_settings.canEditGlobalSidebar)
                _SettingRow(
                  icon: Icons.view_sidebar_rounded,
                  color: Brand.info,
                  title: 'Global sidebar navigation',
                  subtitle: 'Show or hide modules for all accounts',
                  onTap: () => _open(
                    GlobalSidebarScreen(
                      service: _settings,
                      onSaved: () async {
                        await widget.auth.syncSession();
                      },
                    ),
                  ),
                  trailing: _chevron(context),
                ),
              if (_settings.isSuperAdmin)
                _SettingRow(
                  icon: Icons.checklist_rounded,
                  color: Brand.success,
                  title: 'Dashboard reminders',
                  subtitle: 'Whose task reminders everyone sees',
                  onTap: () =>
                      _open(DashboardRemindersScreen(service: _settings)),
                  trailing: _chevron(context),
                ),
              _SettingRow(
                icon: Icons.cleaning_services_rounded,
                color: Brand.danger,
                title: 'Clear local cache',
                subtitle:
                    'Removes cached images and files on this device. You\'ll '
                    'be signed out.',
                onTap: _loggingOut ? null : _confirmClearCache,
                trailing: _chevron(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _GroupLabel('Connection'),
          _SettingsCard(
            children: [
              _SettingRow(
                icon: Icons.dns_rounded,
                color: Brand.info,
                title: 'Endpoint',
                subtitle: widget.api.baseUrl,
              ),
              _SettingRow(
                icon: Icons.verified_user_rounded,
                color: active ? Brand.success : b.paperDim,
                title: 'Session',
                trailing: StatusPill(
                  label: active ? 'Active' : 'Not signed in',
                  color: active ? Brand.success : b.paperDim,
                  dot: true,
                ),
              ),
              _SettingRow(
                icon: Icons.swap_horiz_rounded,
                color: b.signal,
                title: _changingServer ? 'Switching…' : 'Change server',
                subtitle: 'Sign out and point the app at another backend',
                onTap: _changingServer ? null : _changeServer,
                trailing: _changingServer
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: b.signal,
                        ),
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        color: b.paperDim,
                        size: 20,
                      ),
              ),
            ],
          ),
          if (cp != null && !chatAppInstalled) ...[
            const SizedBox(height: 24),
            const _GroupLabel('Chat'),
            _SettingsCard(
              children: [
                _SettingRow(
                  icon: Icons.bubble_chart_rounded,
                  color: const Color(0xFF8B5CF6),
                  title: 'Chat bubble notifications',
                  subtitle:
                      'Float a chat-head over other apps for new messages '
                      '(Android 11+ only; user must allow bubbles).',
                  onTap: () => cp.setBubbleEnabled(!cp.bubbleEnabled),
                  trailing: Switch(
                    value: cp.bubbleEnabled,
                    onChanged: cp.setBubbleEnabled,
                  ),
                ),
                _SettingRow(
                  icon: Icons.palette_rounded,
                  color: cp.theme.accent,
                  title: 'Chat theme',
                  subtitle: cp.theme.displayName,
                  onTap: _pickTheme,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BubblePreview(theme: cp.theme, size: 24),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: b.paperDim,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (!widget.api.isSuperAdmin) ...[
            const SizedBox(height: 24),
            const _GroupLabel('Feedback'),
            _SettingsCard(
              children: [
                _SettingRow(
                  icon: Icons.chat_bubble_outline_rounded,
                  color: Brand.orange,
                  title: 'Send feedback',
                  subtitle:
                      'Tell us what is working, what is broken, or what you '
                      'wish this app could do.',
                  onTap: () => openFeedbackComposer(context, widget.api),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: b.paperDim,
                    size: 20,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          const _GroupLabel('App'),
          const _SettingsCard(
            children: [
              _SettingRow(
                icon: Icons.build_circle_rounded,
                color: Color(0xFF64748B),
                title: 'Build',
                subtitle: 'tinkerpro support',
              ),
              _SettingRow(
                icon: Icons.notifications_active_rounded,
                color: Brand.warning,
                title: 'Push channel',
                subtitle: 'tinkerpro new',
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _loggingOut ? null : _logout,
              style: FilledButton.styleFrom(
                backgroundColor: Brand.danger,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Brand.danger.withValues(alpha: 0.6),
                disabledForegroundColor: Colors.white,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loggingOut)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    const Icon(Icons.logout_rounded, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    _loggingOut ? 'Signing out…' : 'Sign out',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Signing out clears your session and FCM registration on this device.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 0, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          radius: 999,
          blur: 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: b.signal,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                label.toUpperCase(),
                style: text.labelMedium?.copyWith(
                  color: b.paper,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentIconTile extends StatelessWidget {
  const _AccentIconTile({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      radius: Brand.radiusLg,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.only(left: 66),
                child: Hairline(),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            _AccentIconTile(icon: icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: text.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.account,
    required this.loading,
    required this.busy,
    required this.avatarUrl,
    required this.imageHeaders,
    required this.onEdit,
  });

  final ProfileInfo? account;
  final bool loading;
  final bool busy;
  final String? avatarUrl;
  final Map<String, String> imageHeaders;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final name = account?.displayName ?? '';
    final url = avatarUrl;
    final fallback = AppAvatar(name: name.isEmpty ? 'U' : name, size: 64);

    return AppCard(
      padding: const EdgeInsets.all(16),
      radius: Brand.radiusLg,
      child: Row(
        children: [
          InkWell(
            onTap: busy ? null : onEdit,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 68,
              height: 68,
              child: Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: b.surfaceHi,
                      border: Border.all(
                        color: b.signal.withValues(alpha: 0.45),
                        width: 1.5,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: url != null
                        ? CachedNetworkImage(
                            imageUrl: url,
                            httpHeaders: imageHeaders,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => fallback,
                            errorWidget: (_, _, _) => fallback,
                          )
                        : fallback,
                  ),
                  if (busy)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: b.canvas.withValues(alpha: 0.6),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: b.signal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: b.signal,
                        border: Border.all(color: b.surface, width: 2),
                      ),
                      child: const Icon(
                        Icons.photo_camera_rounded,
                        size: 12,
                        color: Brand.onSignal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: loading
                  ? const [
                      Skeleton(width: 150, height: 16),
                      SizedBox(height: 8),
                      Skeleton(width: 190, height: 12),
                      SizedBox(height: 10),
                      Skeleton(width: 120, height: 22, radius: 11),
                    ]
                  : [
                      Text(
                        name.isEmpty ? 'Your account' : name,
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account?.email.isNotEmpty == true
                            ? account!.email
                            : (account?.username ?? ''),
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      StatusPill(
                        label: busy ? 'Updating…' : 'Tap photo to change',
                        color: busy ? Brand.warning : b.paperDim,
                        icon: busy ? null : Icons.photo_camera_rounded,
                        dot: busy,
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarActionSheet extends StatelessWidget {
  const _AvatarActionSheet({required this.canRemove});
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('Profile photo', style: text.titleMedium),
            ),
            ListTile(
              leading: const IconTile(
                icon: Icons.photo_library_rounded,
                color: Brand.info,
                size: 36,
                iconSize: 18,
              ),
              title: Text('Choose from gallery', style: text.titleSmall),
              onTap: () => Navigator.of(context).pop('pick'),
            ),
            if (canRemove)
              ListTile(
                leading: const IconTile(
                  icon: Icons.delete_outline_rounded,
                  color: Brand.danger,
                  size: 36,
                  iconSize: 18,
                ),
                title: Text(
                  'Remove photo',
                  style: text.titleSmall?.copyWith(color: Brand.danger),
                ),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            ListTile(
              leading: IconTile(
                icon: Icons.close_rounded,
                color: b.paperDim,
                size: 36,
                iconSize: 18,
              ),
              title: Text(
                'Cancel',
                style: text.titleSmall?.copyWith(color: b.paperDim),
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePickerSheet extends StatelessWidget {
  const _ThemePickerSheet({required this.current});
  final ChatTheme current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text('Chat theme', style: text.titleMedium),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final t in ChatTheme.all)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Builder(
                          builder: (context) {
                            final selected = t.key == current.key;
                            return AppCard(
                              onTap: () => Navigator.of(context).pop(t),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              borderColor: selected ? t.accent : null,
                              color: selected ? b.tint(t.accent, 0.08) : null,
                              child: Row(
                                children: [
                                  _BubblePreview(theme: t, size: 28),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      t.displayName,
                                      style: text.titleSmall?.copyWith(
                                        color: selected ? t.accent : b.paper,
                                      ),
                                    ),
                                  ),
                                  if (selected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: t.accent,
                                      size: 20,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubblePreview extends StatelessWidget {
  const _BubblePreview({required this.theme, required this.size});
  final ChatTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.6,
      height: size * 1.4,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: size * 0.4,
            child: _previewBubble(
              size: size,
              fill: context.brand.surfaceHi,
              border: context.brand.rule,
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: _previewBubble(
              size: size,
              fill: theme.mineBg,
              border: theme.mineBorder,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBubble({
    required double size,
    required Color fill,
    required Color border,
  }) {
    return Container(
      width: size,
      height: size * 0.7,
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
