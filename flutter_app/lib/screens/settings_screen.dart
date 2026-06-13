import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../api_client.dart';
import '../push_service.dart';
import '../services/chat_prefs.dart';
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

  @override
  void initState() {
    super.initState();
    widget.chatPrefs?.addListener(_onPrefsChanged);
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
