import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/profile_models.dart';
import '../push_service.dart';
import '../services/activity_service.dart';
import '../services/announcement_admin_service.dart';
import '../services/barcode_service.dart';
import '../services/blog_service.dart';
import '../services/chat_prefs.dart';
import '../services/client_service.dart';
import '../services/credential_service.dart';
import '../services/email_service.dart';
import '../services/feedback_service.dart';
import '../services/file_service.dart';
import '../services/help_service.dart';
import '../services/license_service.dart';
import '../services/offer_service.dart';
import '../services/posversion_service.dart';
import '../services/profile_service.dart';
import '../services/pricing_service.dart';
import '../services/reminder_service.dart';
import '../services/releasenotes_service.dart';
import '../services/services.dart';
import '../services/task_service.dart';
import '../services/theme_prefs.dart';
import '../services/user_admin_service.dart';
import '../services/vendor_admin_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'activity_list_screen.dart';
import 'blog_list_screen.dart';
import 'client_list_screen.dart';
import 'credentials_screen.dart';
import 'email_list_screen.dart';
import 'announcements_admin_screen.dart';
import 'barcode_screen.dart';
import 'employment_screen.dart';
import 'feedback_screen.dart';
import 'file_list_screen.dart';
import 'help_list_screen.dart';
import 'license_list_screen.dart';
import 'offer_list_screen.dart';
import 'posversion_list_screen.dart';
import 'pricing_list_screen.dart';
import 'releasenotes_list_screen.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';
import 'task_list_screen.dart';
import 'branches_admin_screen.dart';
import 'role_defaults_screen.dart';
import 'user_admin_list_screen.dart';
import 'vendor_admin_screen.dart';

class MenuShortcut {
  const MenuShortcut({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class MenuScreen extends StatelessWidget {
  const MenuScreen({
    super.key,
    required this.api,
    required this.auth,
    required this.push,
    required this.chatPrefs,
    required this.themePrefs,
    this.shortcuts = const [],
    this.onOpenShortcut,
  });

  final List<MenuShortcut> shortcuts;
  final ValueChanged<String>? onOpenShortcut;
  final ApiClient api;
  final AuthService auth;
  final PushService push;
  final ChatPrefs chatPrefs;
  final ThemePrefs themePrefs;

  void _openSettings(BuildContext context) {
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
  }

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: b.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeaderBand(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Directory',
                            style: text.labelMedium?.copyWith(
                              color: Brand.orange,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Semantics(
                            header: true,
                            child: Text(
                              'Menu',
                              style: text.headlineLarge?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StationAction(
                      icon: Icons.settings_rounded,
                      tooltip: 'Settings',
                      onPressed: () => _openSettings(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ProfileHeader(api: api, onTap: () => _openSettings(context)),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final groups = <_Group>[
                  _Group(
                    label: 'Workspace',
                    items: [
                      for (final sc in shortcuts)
                        _MenuTile(
                          label: sc.label,
                          subtitle: sc.subtitle,
                          icon: sc.icon,
                          color: sc.color,
                          onTap: () => onOpenShortcut?.call(sc.id),
                        ),
                    ],
                  ),
                  _Group(
                    label: 'Operations',
                    items: [
                      if (api.canAccess('task', 'task') ||
                          api.canAccess('customer', 'customer'))
                        _MenuTile(
                          label: 'Reminders',
                          subtitle: 'Tasks due, PTU uploads and your notes',
                          icon: Icons.notifications_active_rounded,
                          color: Brand.orange,
                          badge: const _ReminderBadge(),
                          onTap: () => _push(context, RemindersScreen(api: api)),
                        ),
                      if (api.canAccess('task', 'task'))
                        _MenuTile(
                          label: 'Task',
                          subtitle: 'Assignments and to-dos',
                          icon: Icons.task_alt_rounded,
                          color: const Color(0xFF10B981),
                          onTap: () => _openTask(context),
                        ),
                      if (api.canAccess('emails', 'emails'))
                        _MenuTile(
                          label: 'Email',
                          subtitle: 'Outgoing mail log',
                          icon: Icons.email_rounded,
                          color: Brand.info,
                          onTap: () => _push(
                            context,
                            EmailListScreen(service: EmailService(api)),
                          ),
                        ),
                      if (api.canAccess('files', 'files'))
                        _MenuTile(
                          label: 'Files',
                          subtitle: 'Shared documents',
                          icon: Icons.folder_rounded,
                          color: Brand.warning,
                          onTap: () => _push(
                            context,
                            FileListScreen(service: FileService(api)),
                          ),
                        ),
                      if (api.canAccess('barcode', 'barcode'))
                        _MenuTile(
                          label: 'Barcode',
                          subtitle: 'Scan codes to an invoice',
                          icon: Icons.qr_code_scanner_rounded,
                          color: const Color(0xFF0EA5E9),
                          onTap: () => _push(
                            context,
                            BarcodeScreen(service: BarcodeService(api)),
                          ),
                        ),
                      if (api.canAccess('client', 'client'))
                        _MenuTile(
                          label: 'Client',
                          subtitle: 'Client & data sheets',
                          icon: Icons.badge_rounded,
                          color: const Color(0xFF8B5CF6),
                          onTap: () => _push(
                            context,
                            ClientListScreen(service: ClientService(api)),
                          ),
                        ),
                    ],
                  ),
                  _Group(
                    label: 'Commerce',
                    items: [
                      if (api.canAccess('offers', 'user'))
                        _MenuTile(
                          label: 'Offers',
                          subtitle: 'Client offers',
                          icon: Icons.sell_rounded,
                          color: const Color(0xFFEC4899),
                          onTap: () => _push(
                            context,
                            OfferListScreen(
                              service: OfferService(api),
                              api: api,
                            ),
                          ),
                        ),
                      if (api.canAccess('pricing', 'user'))
                        _MenuTile(
                          label: 'Pricing',
                          subtitle: 'Price lists',
                          icon: Icons.price_check_rounded,
                          color: Brand.success,
                          onTap: () => _push(
                            context,
                            PricingListScreen(
                              service: PricingService(api),
                              api: api,
                            ),
                          ),
                        ),
                      if (api.canAccess('licensekey', 'licensekey'))
                        _MenuTile(
                          label: 'License',
                          subtitle: 'License keys',
                          icon: Icons.verified_rounded,
                          color: const Color(0xFF0EA5E9),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LicenseListScreen(
                                service: LicenseService(api),
                              ),
                            ),
                          ),
                        ),
                      if (api.canAccess('posversion', 'posversion'))
                        _MenuTile(
                          label: 'POS Version',
                          subtitle: 'Builds and downloads',
                          icon: Icons.storage_rounded,
                          color: const Color(0xFF14B8A6),
                          onTap: () => _push(
                            context,
                            PosVersionListScreen(
                              service: PosVersionService(api),
                            ),
                          ),
                        ),
                    ],
                  ),
                  _Group(
                    label: 'Knowledge & admin',
                    items: [
                      if (api.canAccess('releasenotes', 'releasenotes'))
                        _MenuTile(
                          label: 'Release Notes',
                          subtitle: 'What changed',
                          icon: Icons.article_rounded,
                          color: Brand.info,
                          onTap: () => _push(
                            context,
                            ReleaseNotesListScreen(
                              service: ReleaseNotesService(api),
                            ),
                          ),
                        ),
                      if (api.canAccess('blogposts', 'blogposts'))
                        _MenuTile(
                          label: 'Blog',
                          subtitle: 'Posts and articles',
                          icon: Icons.edit_note_rounded,
                          color: const Color(0xFFF97316),
                          onTap: () => _push(
                            context,
                            BlogListScreen(service: BlogService(api)),
                          ),
                        ),
                      if (api.canAccess('credentials', 'credentials'))
                        _MenuTile(
                          label: 'Credentials',
                          subtitle: 'Saved accounts',
                          icon: Icons.vpn_key_rounded,
                          color: Brand.warning,
                          onTap: () => _push(
                            context,
                            CredentialsScreen(service: CredentialService(api)),
                          ),
                        ),
                      if (api.canAccess('user', 'user'))
                        _MenuTile(
                          label: 'Users',
                          subtitle: 'Staff accounts',
                          icon: Icons.group_rounded,
                          color: const Color(0xFF8B5CF6),
                          onTap: () => _push(
                            context,
                            UserAdminListScreen(
                              service: UserAdminService(api),
                              api: api,
                            ),
                          ),
                        ),
                      if (api.canAccess('user', 'user'))
                        _MenuTile(
                          label: 'Vendors',
                          subtitle: 'Vendor accounts, invites and key pricing',
                          icon: Icons.storefront_rounded,
                          color: const Color(0xFF0EA5A4),
                          onTap: () => _push(
                            context,
                            VendorAdminScreen(service: VendorAdminService(api)),
                          ),
                        ),
                      if (api.isSuperAdmin)
                        _MenuTile(
                          label: 'Role defaults',
                          subtitle:
                              'Default clearance per role · super admin only',
                          icon: Icons.shield_outlined,
                          color: Brand.signal,
                          onTap: () => _push(
                            context,
                            RoleDefaultsScreen(service: UserAdminService(api)),
                          ),
                        ),
                      if (api.isSuperAdmin)
                        _MenuTile(
                          label: 'Branches',
                          subtitle: 'Office locations · super admin only',
                          icon: Icons.account_tree_rounded,
                          color: Brand.info,
                          onTap: () => _push(
                            context,
                            BranchesAdminScreen(service: UserAdminService(api)),
                          ),
                        ),
                      if (api.isSuperAdmin)
                        _MenuTile(
                          label: 'Announcements',
                          subtitle: 'Team pop-ups · super admin only',
                          icon: Icons.campaign_rounded,
                          color: const Color(0xFF2563EB),
                          onTap: () => _push(
                            context,
                            AnnouncementsAdminScreen(
                              service: AnnouncementAdminService(api),
                            ),
                          ),
                        ),
                      if (api.isSuperAdmin)
                        _MenuTile(
                          label: 'Feedback',
                          subtitle: 'What the team has sent in',
                          icon: Icons.inbox_rounded,
                          color: Brand.orange,
                          badge: _FeedbackNewBadge(api: api),
                          onTap: () => _push(
                            context,
                            FeedbackInboxScreen(service: FeedbackService(api)),
                          ),
                        ),
                      if (api.canManageEmployment)
                        _MenuTile(
                          label: 'Employment Info',
                          subtitle: 'Staff information sheets · admin only',
                          icon: Icons.assignment_ind_rounded,
                          color: Brand.orange,
                          onTap: () =>
                              _push(context, EmploymentScreen(api: api)),
                        ),
                      if (api.canAccess('activitylogs', 'activitylogs'))
                        _MenuTile(
                          label: 'Activity',
                          subtitle: 'Audit trail',
                          icon: Icons.timeline_rounded,
                          color: const Color(0xFF0EA5E9),
                          onTap: () => _push(
                            context,
                            ActivityListScreen(service: ActivityService(api)),
                          ),
                        ),
                      if (api.canAccess('helpPage', 'helpPage'))
                        _MenuTile(
                          label: 'Help',
                          subtitle: 'Help center articles',
                          icon: Icons.help_outline_rounded,
                          color: Brand.success,
                          onTap: () => _push(
                            context,
                            HelpListScreen(service: HelpService(api)),
                          ),
                        ),
                      _MenuTile(
                        label: 'Settings',
                        subtitle: 'Account, chat and server',
                        icon: Icons.settings_rounded,
                        color: const Color(0xFF64748B),
                        onTap: () => _openSettings(context),
                      ),
                    ],
                  ),
                ].where((g) => g.items.isNotEmpty).toList();

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  children: [
                    _Reveal(
                      index: 0,
                      child: _AppearanceSection(themePrefs: themePrefs),
                    ),
                    for (var g = 0; g < groups.length; g++) ...[
                      const SizedBox(height: 22),
                      _Reveal(index: g + 1, child: groups[g]),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openTask(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TaskListScreen(service: TaskService(api)),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _ProfileHeader extends StatefulWidget {
  const _ProfileHeader({required this.api, required this.onTap});

  final ApiClient api;
  final VoidCallback onTap;

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  late final ProfileService _profile = ProfileService(widget.api);
  ProfileInfo? _info;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await _profile.load();
    if (!mounted || info == null) return;
    setState(() => _info = info);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final info = _info;
    final username = widget.api.username ?? '';
    final name = info?.displayName.isNotEmpty == true
        ? info!.displayName
        : (username.isNotEmpty ? username : 'Your account');
    final secondary = info?.email.isNotEmpty == true
        ? info!.email
        : (username.isNotEmpty ? '@$username' : widget.api.baseUrl);
    final rawRole = widget.api.userRole.trim().toLowerCase();
    final isAdmin =
        rawRole.contains('admin') ||
        (rawRole.isEmpty && widget.api.hasPermission('user'));
    final roleLabel = rawRole.isEmpty || rawRole == 'user'
        ? (isAdmin ? 'Admin' : 'Staff')
        : rawRole
              .split(RegExp(r'[_\s]+'))
              .where((w) => w.isNotEmpty)
              .map(
                (w) => const {'ojt', 'it', 'hr', 'qa'}.contains(w)
                    ? w.toUpperCase()
                    : w[0].toUpperCase() + w.substring(1),
              )
              .join(' ');
    final b = context.brand;
    final dim = b.paperDim;
    final online = widget.api.hasSession;
    return Semantics(
      button: true,
      label: 'Account: $name. Open settings',
      child: GlassPanel(
        padding: EdgeInsets.zero,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Brand.orange.withValues(alpha: 0.8),
                      width: 2,
                    ),
                  ),
                  child: AppAvatar(
                    name: name,
                    size: 52,
                    imageUrl: _profile.avatarUrl(info?.profilePicture),
                    headers: _profile.imageHeaders,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: text.titleMedium?.copyWith(color: b.paper),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        secondary,
                        style: text.bodySmall?.copyWith(color: dim),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _GlassPill(
                            label: roleLabel,
                            leading: Icon(
                              isAdmin
                                  ? Icons.shield_rounded
                                  : Icons.person_rounded,
                              size: 13,
                              color: b.isDark ? Brand.orange : b.signalInk,
                            ),
                          ),
                          _GlassPill(
                            label: online ? 'Online' : 'Signed out',
                            leading: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: online
                                    ? (b.isDark
                                          ? const Color(0xFF4ADE80)
                                          : Brand.success)
                                    : dim,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: dim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.label, required this.leading});

  final String label;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: b.paperDim.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: b.paperDim.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: b.paper,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reveal extends StatefulWidget {
  const _Reveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
      return;
    }
    Future<void>.delayed(
      Duration(milliseconds: (widget.index * 55).clamp(0, 330).toInt()),
      () {
        if (mounted) _c.forward();
      },
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curve),
        child: widget.child,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: SectionHeader(title: label),
        ),
        AppCard(
          padding: EdgeInsets.zero,
          radius: Brand.radiusLg,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.only(left: 66),
                    child: Hairline(),
                  ),
                items[i],
              ],
            ],
          ),
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
    required this.color,
    this.subtitle,
    this.badge,
  });

  final String label;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
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
                      label,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 8), badge!],
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, size: 20, color: b.paperDim),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentIconTile extends StatelessWidget {
  const _AccentIconTile({
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: color.withValues(alpha: b.isDark ? 0.18 : 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

class _ReminderBadge extends StatelessWidget {
  const _ReminderBadge();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ReminderService.badge,
      builder: (context, count, _) {
        if (count <= 0) return const SizedBox.shrink();
        return StatusPill(
          label: count > 99 ? '99+' : '$count',
          color: Brand.orange,
          dot: true,
        );
      },
    );
  }
}

class _FeedbackNewBadge extends StatefulWidget {
  const _FeedbackNewBadge({required this.api});

  final ApiClient api;

  @override
  State<_FeedbackNewBadge> createState() => _FeedbackNewBadgeState();
}

class _FeedbackNewBadgeState extends State<_FeedbackNewBadge> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await FeedbackService(widget.api).newCount();
    if (!mounted) return;
    setState(() => _count = value);
  }

  @override
  Widget build(BuildContext context) {
    if (_count <= 0) return const SizedBox.shrink();
    return StatusPill(
      label: _count > 99 ? '99+ new' : '$_count new',
      color: Brand.orange,
      dot: true,
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.themePrefs});

  final ThemePrefs themePrefs;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: SectionHeader(title: 'Appearance'),
        ),
        AppCard(
          padding: const EdgeInsets.all(14),
          radius: Brand.radiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const _AccentIconTile(
                    icon: Icons.palette_rounded,
                    color: Color(0xFF8B5CF6),
                    size: 38,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Theme', style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          'Match your device or pick a mode',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AnimatedBuilder(
                animation: themePrefs,
                builder: (context, _) {
                  return _ThemeSegments(
                    value: themePrefs.value,
                    onChanged: themePrefs.setMode,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeSegments extends StatelessWidget {
  const _ThemeSegments({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  static const _modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
  static const _labels = ['System', 'Light', 'Dark'];
  static const _icons = [
    Icons.brightness_auto_rounded,
    Icons.light_mode_rounded,
    Icons.dark_mode_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final selected = _modes.indexOf(value).clamp(0, _modes.length - 1);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: b.surfaceHi,
        borderRadius: BorderRadius.circular(Brand.radius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segW = constraints.maxWidth / _modes.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: segW * selected,
                top: 0,
                bottom: 0,
                width: segW,
                child: Container(
                  decoration: BoxDecoration(
                    color: b.isDark ? b.tint(b.signal, 0.16) : b.surface,
                    borderRadius: BorderRadius.circular(Brand.radiusSm),
                    border: Border.all(
                      color: b.isDark
                          ? b.signal.withValues(alpha: 0.45)
                          : b.rule,
                    ),
                    boxShadow: b.shadow,
                  ),
                ),
              ),
              Positioned.fill(
                child: Row(
                  children: [
                    for (var i = 0; i < _modes.length; i++)
                      Expanded(
                        child: _Segment(
                          label: _labels[i],
                          icon: _icons[i],
                          active: i == selected,
                          onTap: () => onChanged(_modes[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
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
    final b = context.brand;
    final color = active ? b.signal : b.paperDim;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Brand.radiusSm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: active ? b.paper : b.paperDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
