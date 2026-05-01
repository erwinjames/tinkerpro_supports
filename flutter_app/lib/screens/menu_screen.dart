import 'package:flutter/material.dart';

import '../api_client.dart';
import '../push_service.dart';
import '../services/chat_prefs.dart';
import '../services/services.dart';
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
  });

  final ApiClient api;
  final AuthService auth;
  final PushService push;
  final ChatPrefs chatPrefs;

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
              ),
            ),
          );
        },
      ),
      child: ListView(
        children: [
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
    final size = (MediaQuery.of(context).size.width - 24 * 2 - 12) / 2;
    return SizedBox(
      width: size,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(
            color: Brand.surface,
            border: Border.all(color: Brand.rule, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Brand.paper, size: 22),
              const SizedBox(height: 28),
              Text(label,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('OPEN →',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Brand.signal,
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
