import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../models/profile_models.dart';
import '../push_service.dart';
import '../services/chat_prefs.dart';
import '../services/profile_service.dart';
import '../services/services.dart';
import '../services/theme_prefs.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'auth_screens.dart';

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

  /// Optional so older callsites still compile — when present, logout
  /// also unregisters the FCM token so push notifications stop landing
  /// on this device for the previous user.
  final PushService? push;

  /// Optional too, but when present the chat-tab section appears with
  /// the bubble toggle + theme picker.
  final ChatPrefs? chatPrefs;

  /// Optional — required for the post-logout LoginScreen push since
  /// the auth screens now thread the theme-mode prefs through.
  final ThemePrefs? themePrefs;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loggingOut = false;
  bool _changingServer = false;

  late final ProfileService _profile = ProfileService(widget.api);
  ProfileInfo? _account;
  bool _loadingProfile = true;
  bool _avatarBusy = false;

  @override
  void initState() {
    super.initState();
    widget.chatPrefs?.addListener(_onPrefsChanged);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final info = await _profile.load();
    if (!mounted) return;
    setState(() {
      _account = info;
      _loadingProfile = false;
    });
  }

  /// Pick an image from the gallery and upload it as the new avatar. The
  /// server returns a fresh filename each time, so the CachedNetworkImage URL
  /// changes and no cache-busting is needed.
  Future<void> _pickAndUploadAvatar() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _avatarBusy = true);
    final res = await _profile.uploadPicture(file.path);
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

  /// Bottom-sheet actions for the avatar: change, and (when set) remove.
  Future<void> _openAvatarActions() async {
    if (_avatarBusy) return;
    final hasPhoto = _account?.profilePicture != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Brand.surface,
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
    widget.chatPrefs?.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    // 1. Release the FCM token first so the *current* (about-to-be-old)
    //    user's cookie still authenticates the unregister call.
    await widget.push?.releaseCurrentDevice();
    // 2. Hit the server logout endpoint + clear all user-scoped local state
    //    (cookie, user id, notification cursors, etc.).
    await widget.auth.logout();
    // 3. Wipe any cached chat-attachment images so user A's images can't
    //    be served from the disk cache when user B opens a thread.
    try {
      await CachedNetworkImage.evictFromCache('');
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
    // 4. Wipe downloaded chat attachments in the temp dir (file_attachment
    //    bubbles save them there before opening with the OS handler).
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
            // Defensive — older callsites that don't supply both prefs
            // bundles would crash here. LoginScreen now requires both;
            // surface a clear error so the call-site gets fixed instead
            // of silently dropping the theme/chat state.
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

  /// Forget the saved server and return to the server-config screen so the
  /// user can point the app at a different backend (e.g. switch off a stale
  /// ngrok/dev URL onto the live server). A session cookie never crosses
  /// servers, so we sign out first, then clear the base URL.
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
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      builder: (_) => _ThemePickerSheet(current: cp.theme),
    );
    if (picked != null) await cp.setTheme(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cp = widget.chatPrefs;
    return StationScaffold(
      stationNumber: '··',
      stationLabel: 'SETTINGS',
      title: 'Device & account.',
      onBack: () => Navigator.of(context).pop(),
      showBottomBrand: false,
      child: ListView(
        children: [
          Text('PROFILE', style: Theme.of(context).textTheme.labelMedium),
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
          Text('CONNECTION',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          const Hairline(),
          const SizedBox(height: 16),
          StationDataRow(label: 'ENDPOINT', value: widget.api.baseUrl),
          const SizedBox(height: 20),
          StationDataRow(
              label: 'SESSION',
              value: widget.api.hasSession ? 'ACTIVE' : 'NOT SIGNED IN'),
          const SizedBox(height: 20),
          SignalButton(
            label: _changingServer ? 'Switching…' : 'Change server',
            busy: _changingServer,
            icon: Icons.dns_outlined,
            onPressed: _changeServer,
          ),
          if (cp != null) ...[
            const SizedBox(height: 40),
            Text('CHAT', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            const Hairline(),
            const SizedBox(height: 16),
            _BubbleToggleRow(
              enabled: cp.bubbleEnabled,
              onChanged: cp.setBubbleEnabled,
            ),
            const SizedBox(height: 20),
            _ThemeRow(
              current: cp.theme,
              onTap: _pickTheme,
            ),
          ],
          const SizedBox(height: 40),
          Text('APP', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          const Hairline(),
          const SizedBox(height: 16),
          const StationDataRow(label: 'BUILD', value: 'tinkerpro support'),
          const SizedBox(height: 20),
          const StationDataRow(label: 'PUSH CHANNEL', value: 'tinkerpro new'),
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

/// Profile header: an editable circular avatar (tap to change / remove) beside
/// the user's name and email. Mirrors the web Settings page avatar control.
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
        // Tappable avatar with a hover-style camera badge + busy overlay.
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
                    color: Brand.surfaceHi,
                    border: Border.all(color: Brand.rule, width: 1),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: url != null
                      ? CachedNetworkImage(
                          imageUrl: url,
                          httpHeaders: imageHeaders,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => _initialsFallback(name, text),
                          errorWidget: (_, _, _) =>
                              _initialsFallback(name, text),
                        )
                      : _initialsFallback(name, text),
                ),
                if (busy)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Brand.canvas.withValues(alpha: 0.55),
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
                // Camera badge, bottom-right.
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Brand.signal,
                      border: Border.all(color: Brand.canvas, width: 2),
                    ),
                    child: const Icon(Icons.photo_camera,
                        size: 12, color: Brand.canvas),
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
                style: text.labelMedium?.copyWith(color: Brand.paperDim),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _initialsFallback(String name, TextTheme text) {
    return Center(
      child: Text(
        _initials(name),
        style: text.titleLarge?.copyWith(color: Brand.paperDim),
      ),
    );
  }
}

/// Action sheet shown when the avatar is tapped.
class _AvatarActionSheet extends StatelessWidget {
  const _AvatarActionSheet({required this.canRemove});
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Brand.surface,
          border: Border(top: BorderSide(color: Brand.signal, width: 2)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Brand.paper),
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
              leading: const Icon(Icons.close, color: Brand.paperDim),
              title: Text('Cancel',
                  style: text.titleSmall?.copyWith(color: Brand.paperDim)),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleToggleRow extends StatelessWidget {
  const _BubbleToggleRow({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
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
                  Text('CHAT BUBBLE NOTIFICATIONS', style: text.labelMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Float a chat-head over other apps for new messages '
                    '(Android 11+ only; user must allow bubbles).',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: enabled,
              activeThumbColor: Brand.signal,
              onChanged: (v) {
                onChanged(v);
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(height: 1, color: Brand.rule),
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
                    Text('CHAT THEME', style: text.labelMedium),
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
              const Icon(Icons.chevron_right,
                  color: Brand.paperDim, size: 20),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Brand.rule),
        ],
      ),
    );
  }
}

/// Bottom sheet listing all themes with a small bubble swatch on each row.
class _ThemePickerSheet extends StatelessWidget {
  const _ThemePickerSheet({required this.current});
  final ChatTheme current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Brand.surface,
          border: Border(top: BorderSide(color: Brand.signal, width: 2)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('CHAT THEME', style: text.labelLarge),
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
                            color: selected ? t.accent : Brand.paper,
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

/// Two stacked mini-bubbles previewing the theme's "mine" colours over a
/// peer bubble. Used in the picker rows + the settings tile.
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
              fill: theme.theirBg,
              border: theme.theirBorder,
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
