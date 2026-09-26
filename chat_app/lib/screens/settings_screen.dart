import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../platform_info.dart';
import '../models/profile_models.dart';
import '../push_service.dart';
import '../services/chat_prefs.dart';
import '../services/profile_service.dart';
import '../services/announcement_service.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth.dart';
import '../services/bubble_permission.dart';
import '../services/chat_head.dart';
import '../services/tone_prefs.dart';
import '../services/theme_prefs.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'auth_screens.dart';
import 'tone_picker_screen.dart';

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

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _loggingOut = false;
  BubbleStatus? _bubbleStatus;
  ToneChoice _messageTone = ToneChoice.web;
  ToneChoice _callTone = ToneChoice.web;
  bool _bubbleBusy = false;
  _BubbleWait _bubbleWait = _BubbleWait.none;
  bool _changingServer = false;
  bool _checkingAnnouncements = false;
  String _announcementStatus = 'Not checked yet';

  late final ProfileService _profile = ProfileService(widget.api);
  ProfileInfo? _account;
  bool _loadingProfile = true;
  bool _avatarBusy = false;

  late final BiometricAuth _biometrics = BiometricAuth(widget.api);
  bool _fingerprintSupported = false;
  bool _fingerprintEnabled = false;
  bool _fingerprintBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.chatPrefs?.addListener(_onPrefsChanged);
    _loadProfile();
    _loadFingerprint();
    _refreshBubbleStatus();
    _loadTones();
    if (widget.api.isSuperAdmin) _loadAgentHours();
  }

  String _hoursLabel = 'Loading…';

  Future<void> _loadAgentHours() async {
    final hours = await _profile.agentHours();
    if (!mounted) return;
    setState(() {
      _hoursLabel = hours == null
          ? 'Unavailable'
          : hours.enabled
          ? '${hours.start} – ${hours.end}'
          : 'Off';
    });
  }

  Future<void> _editAlias() async {
    final account = _account;
    if (account == null) {
      _toast('Profile not loaded yet');
      return;
    }
    final controller = TextEditingController(text: account.chatAlias);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chat alias'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(hintText: 'e.g. Maya'),
            ),
            Text(
              'Shown to website visitors instead of your real name once you '
              'accept their ticket. Leave blank to appear as “Support agent”.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    final res = await _profile.saveChatAlias(account, value);
    if (!mounted) return;
    if (res.ok) {
      setState(() => _account = account.copyWith(chatAlias: value.trim()));
      _toast('Chat alias saved');
    } else {
      _toast(res.message ?? 'Could not save the alias');
    }
  }

  Future<void> _editAgentHours() async {
    final hours = await _profile.agentHours();
    if (!mounted) return;
    if (hours == null) {
      _toast('Could not load operating hours');
      return;
    }
    TimeOfDay parse(String raw, TimeOfDay fallback) {
      final parts = raw.split(':');
      final h = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
      final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (h == null || m == null) return fallback;
      return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
    }

    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    var enabled = hours.enabled;
    var start = parse(hours.start, const TimeOfDay(hour: 8, minute: 0));
    var end = parse(hours.end, const TimeOfDay(hour: 17, minute: 0));
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Agent operating hours'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged: (v) => setLocal(() => enabled = v),
                  title: const Text('Enable operating hours'),
                  subtitle: const Text(
                    'If enabled, the chatbot will only escalate to an agent '
                    'during these hours. Outside these hours, visitors will '
                    'be asked to leave a message.',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Start Time'),
                  trailing: Text(start.format(ctx)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: start,
                    );
                    if (picked != null) setLocal(() => start = picked);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('End Time'),
                  trailing: Text(end.format(ctx)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime: end,
                    );
                    if (picked != null) setLocal(() => end = picked);
                  },
                ),
                Text(
                  'Times are in the server timezone '
                  '(${hours.tz.isEmpty ? '—' : hours.tz}).',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save != true || !mounted) return;
    final res = await _profile.saveAgentHours(
      enabled: enabled,
      start: fmt(start),
      end: fmt(end),
    );
    if (!mounted) return;
    _toast(res.ok ? 'Agent hours saved' : (res.message ?? 'Could not save'));
    if (res.ok) _loadAgentHours();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_bubbleWait == _BubbleWait.none) {
      _refreshBubbleStatus();
    } else {
      _resumeBubbleGrant();
    }
  }

  Future<void> _loadTones() async {
    final message = await TonePrefs.read(ToneSlot.message);
    final call = await TonePrefs.read(ToneSlot.call);
    if (!mounted) return;
    setState(() {
      _messageTone = message;
      _callTone = call;
    });
  }

  Future<void> _pickTone(ToneSlot slot) async {
    final current = slot == ToneSlot.message ? _messageTone : _callTone;
    final picked = await Navigator.of(context).push<ToneChoice>(
      MaterialPageRoute<ToneChoice>(
        builder: (_) => TonePickerScreen(slot: slot, current: current),
      ),
    );
    if (picked == null) return;
    await TonePrefs.write(slot, picked);
    if (!mounted) return;
    setState(() {
      if (slot == ToneSlot.message) {
        _messageTone = picked;
      } else {
        _callTone = picked;
      }
    });
  }

  Future<BubbleStatus> _refreshBubbleStatus() async {
    final st = await BubblePermission.status();
    if (mounted) setState(() => _bubbleStatus = st);
    return st;
  }

  Future<void> _onBubbleToggle(bool on) async {
    final cp = widget.chatPrefs;
    if (cp == null || _bubbleBusy) return;
    if (!on) {
      await cp.setBubbleEnabled(false);
      await ChatHead.close();
      return;
    }
    setState(() => _bubbleBusy = true);
    try {
      await _enableBubbles(cp);
    } finally {
      if (mounted) setState(() => _bubbleBusy = false);
    }
  }

  Future<void> _enableBubbles(ChatPrefs cp) async {
    var st = await _refreshBubbleStatus();
    if (!st.supported) {
      _toast('Chat heads need Android 6 or newer.');
      return;
    }
    if (!st.notifications) {
      await BubblePermission.requestNotifications();
      st = await _refreshBubbleStatus();
      if (!st.notifications) {
        if (!mounted) return;
        final go = await _askForSettings(
          title: 'ALLOW NOTIFICATIONS',
          body: 'Chat heads are built on notifications. Turn on '
              'notifications for TinkerPro Chat, then come back here.',
        );
        if (go != true) return;
        _bubbleWait = _BubbleWait.notifications;
        await BubblePermission.openNotificationSettings();
        return;
      }
    }
    if (!st.overlay) {
      if (!mounted) return;
      final go = await _askForSettings(
        title: 'ALLOW CHAT HEADS',
        body: 'Chat heads float over other apps, like Messenger. On the next '
            'screen, turn on "Display over other apps" for TinkerPro Chat, '
            'then go back.',
      );
      if (go != true) return;
      await BubblePermission.requestOverlay();
      st = await _refreshBubbleStatus();
      if (!st.overlay) {
        _toast('Display over other apps is still off for TinkerPro Chat.');
        return;
      }
    }
    await cp.setBubbleEnabled(true);
    _toast('Chat heads are on.');
  }

  Future<void> _resumeBubbleGrant() async {
    final wait = _bubbleWait;
    _bubbleWait = _BubbleWait.none;
    final cp = widget.chatPrefs;
    final st = await _refreshBubbleStatus();
    if (cp == null || !mounted) return;
    if (st.ready) {
      await cp.setBubbleEnabled(true);
      _toast('Chat heads are on.');
      return;
    }
    if (wait == _BubbleWait.notifications && st.notifications) {
      await _onBubbleToggle(true);
      return;
    }
    _toast(st.notifications
        ? 'Display over other apps is still off for TinkerPro Chat.'
        : 'Notifications are still off for TinkerPro Chat.');
  }

  Future<bool?> _askForSettings({required String title, required String body}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.brand.surface,
        shape: const RoundedRectangleBorder(),
        title: Text(title, style: Theme.of(context).textTheme.labelLarge),
        content: Text(body, style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('NOT NOW',
                style: Theme.of(context).textTheme.labelMedium),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('OPEN SETTINGS',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Brand.signal)),
          ),
        ],
      ),
    );
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

  Future<void> _onFingerprintToggle(bool value) async {
    setState(() => _fingerprintBusy = true);
    try {
      if (value) {
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

  Future<void> _loadProfile() async {
    final info = await _profile.load();
    if (!mounted) return;
    setState(() {
      _account = info;
      _loadingProfile = false;
    });
  }

  Future<String?> _pickAvatarPath() async {
    if (kIsDesktopPlatform) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: false,
      );
      return result?.files.single.path;
    }
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    return file?.path;
  }

  Future<void> _pickAndUploadAvatar() async {
    final path = await _pickAvatarPath();
    if (path == null || !mounted) return;
    setState(() => _avatarBusy = true);
    final res = await _profile.uploadPicture(path);
    if (!mounted) return;
    setState(() {
      _avatarBusy = false;
      if (res.ok && res.profilePicture != null) {
        _account =
            _account?.copyWith(profilePicture: res.profilePicture);
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
      backgroundColor: context.brand.surface,
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          try { entity.deleteSync(recursive: true); } catch (_) {}
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
                'SettingsScreen.logout requires chatPrefs + themePrefs')
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

  Future<void> _checkAnnouncements() async {
    setState(() => _checkingAnnouncements = true);
    final service = AnnouncementService(widget.api);
    await service.refresh();
    if (!mounted) return;
    setState(() {
      _checkingAnnouncements = false;
      _announcementStatus = service.lastStatus;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(service.lastStatus),
        duration: const Duration(seconds: 6),
      ),
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
      backgroundColor: context.brand.surface,
      isScrollControlled: true,
      builder: (_) => _ThemePickerSheet(current: cp.theme),
    );
    if (picked != null) await cp.setTheme(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cp = widget.chatPrefs;
    final tp = widget.themePrefs;
    return StationScaffold(
      title: 'Settings',
      onBack: () => Navigator.of(context).pop(),
      showBottomBrand: false,
      child: ListView(
        children: [
          Text('Profile', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          const Hairline(),
          const SizedBox(height: 16),
          _ProfileRow(
            account: _account,
            loading: _loadingProfile,
            busy: _avatarBusy,
            avatarUrl: _profile.avatarUrl(_account?.profilePicture),
            imageHeaders: _profile.imageHeaders,
            onEdit: _openAvatarActions,
          ),
          const SizedBox(height: 40),
          Text('Connection',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          const Hairline(),
          const SizedBox(height: 16),
          StationDataRow(label: 'Server', value: widget.api.baseUrl),
          const SizedBox(height: 20),
          StationDataRow(
              label: 'Session',
              value: widget.api.hasSession ? 'Active' : 'Not signed in'),
          const SizedBox(height: 20),
          SignalButton(
            label: _changingServer ? 'Switching…' : 'Change server',
            busy: _changingServer,
            icon: Icons.dns_outlined,
            onPressed: _changeServer,
          ),
          const SizedBox(height: 20),
          StationDataRow(
            label: 'Signed in as',
            value: widget.api.userId == null
                ? 'unknown'
                : '${widget.api.username ?? '?'} (id ${widget.api.userId})',
          ),
          const SizedBox(height: 20),
          StationDataRow(label: 'Announcements', value: _announcementStatus),
          const SizedBox(height: 20),
          SignalButton(
            label: _checkingAnnouncements ? 'Checking…' : 'Check announcements',
            busy: _checkingAnnouncements,
            icon: Icons.campaign_outlined,
            onPressed: _checkAnnouncements,
          ),
          if (tp != null) ...[
            const SizedBox(height: 40),
            Text('Appearance', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            const Hairline(),
            const SizedBox(height: 16),
            _ThemeModeRow(prefs: tp),
          ],
          if (cp != null) ...[
            const SizedBox(height: 40),
            Text('Chat', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            const Hairline(),
            const SizedBox(height: 16),
            if (TonePrefs.supported) ...[
              _ToneRow(
                label: 'Message tone',
                value: _messageTone.displayLabel,
                icon: Icons.notifications_active_outlined,
                onTap: () => _pickTone(ToneSlot.message),
              ),
              const SizedBox(height: 20),
              _ToneRow(
                label: 'Call ringtone',
                value: _callTone.displayLabel,
                icon: Icons.ring_volume_outlined,
                onTap: () => _pickTone(ToneSlot.call),
              ),
              const SizedBox(height: 20),
            ],
            if (_fingerprintSupported) ...[
              _FingerprintToggleRow(
                enabled: _fingerprintEnabled,
                busy: _fingerprintBusy,
                onChanged: _onFingerprintToggle,
              ),
              const SizedBox(height: 20),
            ],
            if (BubblePermission.platformSupported) ...[
              _BubbleToggleRow(
                enabled: cp.bubbleEnabled && (_bubbleStatus?.ready ?? false),
                blocked: cp.bubbleEnabled &&
                    _bubbleStatus != null &&
                    !_bubbleStatus!.ready,
                supported: _bubbleStatus?.supported ?? true,
                busy: _bubbleBusy,
                onChanged: _onBubbleToggle,
              ),
              const SizedBox(height: 20),
            ],
            _ThemeRow(
              current: cp.theme,
              onTap: _pickTheme,
            ),
          ],
          const SizedBox(height: 40),
          Text('Chat agent', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          const Hairline(),
          const SizedBox(height: 16),
          _ToneRow(
            label: 'Chat alias',
            value: _loadingProfile
                ? 'Loading…'
                : (_account?.chatAlias.isNotEmpty ?? false)
                ? _account!.chatAlias
                : 'Support agent (default)',
            icon: Icons.badge_outlined,
            onTap: _editAlias,
          ),
          if (widget.api.isSuperAdmin) ...[
            const SizedBox(height: 20),
            _ToneRow(
              label: 'Agent operating hours',
              value: _hoursLabel,
              icon: Icons.schedule_outlined,
              onTap: _editAgentHours,
            ),
          ],
          const SizedBox(height: 40),
          Text('App', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          const Hairline(),
          const SizedBox(height: 16),
          const StationDataRow(label: 'Build', value: 'TinkerPro Chat 2.0.4'),

          const SizedBox(height: 40),
          SignalButton(
            label: _loggingOut ? 'Signing out…' : 'Sign out',
            busy: _loggingOut,
            icon: Icons.logout,
            onPressed: _logout,
          ),
          const SizedBox(height: 20),
          Text(
            'Signing out clears your session and FCM registration on this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
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

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    String first(String s) => s.isEmpty ? '' : s.substring(0, 1).toUpperCase();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return first(parts.first);
    return first(parts.first) + first(parts.last);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = account?.displayName ?? '';
    final url = avatarUrl;

    return Row(
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
                    color: context.brand.surfaceHi,
                    border: Border.all(color: context.brand.rule, width: 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url,
                          httpHeaders: imageHeaders,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => _initialsFallback(context, name, text),
                          errorWidget: (_, _, _) =>
                              _initialsFallback(context, name, text),
                        )
                      : _initialsFallback(context, name, text),
                ),
                if (busy)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.brand.canvas.withValues(alpha: 0.55),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Brand.signal),
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
                      color: Brand.signal,
                      border: Border.all(color: context.brand.canvas, width: 2),
                    ),
                    child: Icon(Icons.photo_camera,
                        size: 12, color: context.brand.canvas),
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
            children: [
              Text(
                loading
                    ? 'Loading…'
                    : (name.isEmpty ? 'Your account' : name),
                style: text.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                account?.email.isNotEmpty == true
                    ? account!.email
                    : (account?.username ?? ''),
                style: text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                busy ? 'UPDATING…' : 'TAP PHOTO TO CHANGE',
                style: text.labelMedium?.copyWith(color: context.brand.paperDim),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _initialsFallback(
      BuildContext context, String name, TextTheme text) {
    return Center(
      child: Text(
        _initials(name),
        style: text.titleLarge?.copyWith(color: context.brand.paperDim),
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
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: context.brand.surface,
          border: Border(top: BorderSide(color: Brand.signal, width: 2)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: context.brand.paper),
              title: Text('Choose from gallery', style: text.titleSmall),
              onTap: () => Navigator.of(context).pop('pick'),
            ),
            if (canRemove)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Brand.signal),
                title: Text('Remove photo',
                    style: text.titleSmall?.copyWith(color: Brand.signal)),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            ListTile(
              leading: Icon(Icons.close, color: context.brand.paperDim),
              title: Text('Cancel',
                  style: text.titleSmall?.copyWith(color: context.brand.paperDim)),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow({required this.prefs});

  final ThemePrefs prefs;

  static const _options = <(ThemeMode, String, IconData)>[
    (ThemeMode.system, 'System', Icons.brightness_auto_outlined),
    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final brand = context.brand;

    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: text.labelMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: brand.surfaceHi,
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
            child: Row(
              children: [
                for (final option in _options)
                  Expanded(
                    child: _ThemeModeTab(
                      label: option.$2,
                      icon: option.$3,
                      selected: prefs.value == option.$1,
                      onTap: () => prefs.setMode(option.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            prefs.value == ThemeMode.system
                ? 'Follows your device setting.'
                : 'Always ${prefs.value == ThemeMode.dark ? 'dark' : 'light'}, '
                    'whatever the device is set to.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ThemeModeTab extends StatelessWidget {
  const _ThemeModeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.radiusSm),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? brand.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(Brand.radiusSm),
          border: Border.all(
            color: selected ? brand.rule : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 19,
              color: selected ? brand.signal : brand.paperDim,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? brand.paper : brand.paperDim,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToneRow extends StatelessWidget {
  const _ToneRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: context.brand.paperDim),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: text.labelMedium),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: Brand.signal),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: context.brand.paperDim),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: context.brand.rule),
        ],
      ),
    );
  }
}

enum _BubbleWait { none, notifications }

class _BubbleToggleRow extends StatelessWidget {
  const _BubbleToggleRow({
    required this.enabled,
    required this.blocked,
    required this.supported,
    required this.busy,
    required this.onChanged,
  });

  final bool enabled;
  final bool blocked;
  final bool supported;
  final bool busy;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chat heads', style: text.labelMedium),
                  const SizedBox(height: 4),
                  Text(
                    !supported
                        ? 'Needs Android 6 or newer.'
                        : blocked
                            ? 'Display over other apps is off. Turn on to '
                                'allow chat heads again.'
                            : 'Float a Messenger-style chat head over other '
                                'apps for new messages. Tap it to open the '
                                'chat, drag it to the X to dismiss.',
                    style: blocked
                        ? text.bodySmall?.copyWith(color: Brand.signal)
                        : text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: enabled,
              activeThumbColor: Brand.signal,
              onChanged: (!supported || busy)
                  ? null
                  : (v) {
                      onChanged(v);
                    },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: context.brand.rule),
      ],
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.current, required this.onTap});
  final ChatTheme current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bubble colour', style: text.labelMedium),
                    const SizedBox(height: 6),
                    Text(
                      current.displayName,
                      style: text.bodyMedium?.copyWith(color: current.accent),
                    ),
                  ],
                ),
              ),
              _BubblePreview(theme: current, size: 28),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: context.brand.paperDim, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: context.brand.rule),
        ],
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
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: context.brand.surface,
          border: Border(top: BorderSide(color: Brand.signal, width: 2)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('Bubble colour', style: text.labelLarge),
            ),
            const SizedBox(height: 8),
            const Hairline(),
            const SizedBox(height: 4),
            ...ChatTheme.all.map((t) {
              final selected = t.key == current.key;
              return InkWell(
                onTap: () => Navigator.of(context).pop(t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 8),
                  child: Row(
                    children: [
                      _BubblePreview(theme: t, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          t.displayName,
                          style: text.titleSmall?.copyWith(
                            color: selected ? t.accent : context.brand.paper,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check, color: t.accent, size: 20),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
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
              fill: context.brand.surface,
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
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _FingerprintToggleRow extends StatelessWidget {
  const _FingerprintToggleRow({
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final bool enabled;
  final bool busy;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fingerprint sign-in', style: text.labelMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Scan your fingerprint to sign in on this phone instead '
                    'of typing your password.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: enabled,
              activeThumbColor: Brand.signal,
              onChanged: busy ? null : (v) => onChanged(v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: context.brand.rule),
      ],
    );
  }
}
