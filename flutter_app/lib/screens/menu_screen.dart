import 'package:flutter/material.dart';

import '../api_client.dart';
import '../push_service.dart';
import '../services/chat_prefs.dart';
import '../services/services.dart';
import '../services/theme_prefs.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'coming_soon_screen.dart';
import 'settings_screen.dart';

/// The "everything else" grid. Organised into three bands so the eye has
/// a hierarchy instead of facing twenty equally-weighted tiles.
class MenuScreen extends StatelessWidget {
  const MenuScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.push,
    required this.chatPrefs,
    required this.themePrefs,
  });

  final ApiClient api;
  final AuthService auth;
  final PushService push;
  final ChatPrefs chatPrefs;
  final ThemePrefs themePrefs;

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '07',
      stationLabel: 'DIRECTORY',
      title: 'Everything else.',
      showBottomBrand: false,
      trailing: StationAction(
        icon: Icons.settings_outlined,
        tooltip: 'Settings',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(
                api: api,
                auth: auth,
                push: push,
                chatPrefs: chatPrefs,
                themePrefs: themePrefs,
              ),
            ),
          );
        },
      ),
      child: ListView(
        children: [
          _AppearanceSection(themePrefs: themePrefs),
          const SizedBox(height: 32),
          _Group(
            label: 'Operations',
            // Chat lives in the bottom nav now; Task is disabled on the
            // web side and intentionally hidden here too.
            items: [
              _MenuTile(
                label: 'Email',
                icon: Icons.email_outlined,
                onTap: () => _openSoon(context, 'Email', 'emails'),
              ),
              _MenuTile(
                label: 'Files',
                icon: Icons.folder_outlined,
                onTap: () =>
                    _openSoon(context, 'Files Management', 'files-management'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _Group(
            label: 'Commerce',
            items: [
              _MenuTile(
                label: 'Offers',
                icon: Icons.sell_outlined,
                onTap: () => _openSoon(context, 'Offers', 'offers'),
              ),
              _MenuTile(
                label: 'Pricing',
                icon: Icons.price_check_outlined,
                onTap: () => _openSoon(context, 'Pricing', 'pricing'),
              ),
              _MenuTile(
                label: 'License',
                icon: Icons.verified_outlined,
                onTap: () => _openSoon(context, 'License Key', 'license'),
              ),
              _MenuTile(
                label: 'POS Version',
                icon: Icons.storage_outlined,
                onTap: () =>
                    _openSoon(context, 'POS Version', 'pos-version'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _Group(
            label: 'Knowledge · Admin',
            items: [
              _MenuTile(
                label: 'Release Notes',
                icon: Icons.article_outlined,
                onTap: () =>
                    _openSoon(context, 'Release Notes', 'release_notes'),
              ),
              _MenuTile(
                label: 'Blog',
                icon: Icons.edit_note,
                onTap: () => _openSoon(context, 'Blog Posts', 'blog'),
              ),
              _MenuTile(
                label: 'Credentials',
                icon: Icons.vpn_key_outlined,
                onTap: () => _openSoon(
                    context, 'Credentials Storage', 'client-credentials'),
              ),
              _MenuTile(
                label: 'Users',
                icon: Icons.group_outlined,
                onTap: () => _openSoon(context, 'User', 'user'),
              ),
              _MenuTile(
                label: 'Activity',
                icon: Icons.timeline_outlined,
                onTap: () =>
                    _openSoon(context, 'Activity Logs', 'activity_logs'),
              ),
              _MenuTile(
                label: 'Help',
                icon: Icons.help_outline,
                onTap: () => _openSoon(context, 'Help Page', 'help'),
              ),
              _MenuTile(
                label: 'Analyze',
                icon: Icons.query_stats,
                onTap: () => _openSoon(context, 'Analyze', 'analyze'),
              ),
              _MenuTile(
                label: 'Settings',
                icon: Icons.settings_outlined,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(
                api: api,
                auth: auth,
                push: push,
                chatPrefs: chatPrefs,
                themePrefs: themePrefs,
              ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _openSoon(BuildContext context, String title, String path) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ComingSoonScreen(
          title: title,
          webPath: path,
          baseUrl: api.baseUrl,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.items});
  final String label;
  final List<_MenuTile> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        const Hairline(),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items,
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.brand;
    final size = (MediaQuery.of(context).size.width - 24 * 2 - 12) / 2;
    return SizedBox(
      width: size,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.rule, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: c.paper, size: 22),
              const SizedBox(height: 28),
              Text(label,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('OPEN →',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: c.signal,
                        letterSpacing: 2.4,
                        fontSize: 9,
                      )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Theme-mode chooser. Three segmented chips: System / Light / Dark.
/// Listens to the [ThemePrefs] ValueNotifier so the active chip stays
/// in sync if the mode is changed from somewhere else later (e.g. an
/// OS-level setting via ThemeMode.system).
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.themePrefs});

  final ThemePrefs themePrefs;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('APPEARANCE', style: text.labelLarge),
        const SizedBox(height: 10),
        const Hairline(),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: themePrefs,
          builder: (context, _) {
            return Row(
              children: [
                _ThemeChip(
                  label: 'SYSTEM',
                  icon: Icons.brightness_auto_outlined,
                  active: themePrefs.value == ThemeMode.system,
                  onTap: () => themePrefs.setMode(ThemeMode.system),
                ),
                const SizedBox(width: 8),
                _ThemeChip(
                  label: 'LIGHT',
                  icon: Icons.light_mode_outlined,
                  active: themePrefs.value == ThemeMode.light,
                  onTap: () => themePrefs.setMode(ThemeMode.light),
                ),
                const SizedBox(width: 8),
                _ThemeChip(
                  label: 'DARK',
                  icon: Icons.dark_mode_outlined,
                  active: themePrefs.value == ThemeMode.dark,
                  onTap: () => themePrefs.setMode(ThemeMode.dark),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Pull live tokens from the active theme so this widget flips
    // colors correctly when the user themselves toggles the mode.
    final c = context.brand;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: active ? c.signalGlow(0.12) : c.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? c.signal : c.rule,
                width: active ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon,
                    size: 18, color: active ? c.signal : c.paperDim),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? c.signal : c.paperDim,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
