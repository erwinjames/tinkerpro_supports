import 'package:flutter/material.dart';

import '../models/help_models.dart';
import '../services/help_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

/// Help Center — native CRUD. Lists help topics with create / edit / delete,
/// backed by the `*HelpTopic` actions on api.php. Each topic pairs a title +
/// body with a FontAwesome icon and a colour; those are stored verbatim so a
/// topic authored on mobile renders the same in the web admin.
class HelpListScreen extends StatefulWidget {
  const HelpListScreen({super.key, required this.service});
  final HelpService service;

  @override
  State<HelpListScreen> createState() => _HelpListScreenState();
}

class _HelpListScreenState extends State<HelpListScreen> {
  List<HelpTopic> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.service.list();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _openForm([HelpTopic? existing]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            _HelpFormScreen(service: widget.service, existing: existing),
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '··',
      stationLabel: 'HELP CENTER',
      title: 'Help topics.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add,
        tooltip: 'New help topic',
        onPressed: _openForm,
      ),
      child: RefreshIndicator(
        color: Brand.signal,
        backgroundColor: Brand.surface,
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.signal),
                ),
              )
            : _rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 64),
                      EmptyState(
                        label: 'No help topics',
                        hint: 'Tap + to add the first topic. Pull to refresh.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _rows.length,
                    separatorBuilder: (_, _) => const Hairline(),
                    itemBuilder: (_, i) => _HelpRow(
                      row: _rows[i],
                      onTap: () => _openForm(_rows[i]),
                    ),
                  ),
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  const _HelpRow({required this.row, required this.onTap});
  final HelpTopic row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final preview = _stripHtml(row.description);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              helpIconData(row.icon),
              size: 20,
              color: parseHelpColor(row.iconColor) ?? Brand.signal,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.title.isEmpty ? 'Untitled topic' : row.title,
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview.isEmpty ? 'No description' : preview,
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add / edit form. Title + description are text fields; the icon comes from
/// a small grid (matching the web icon set) and the colour from a palette.
class _HelpFormScreen extends StatefulWidget {
  const _HelpFormScreen({required this.service, this.existing});
  final HelpService service;
  final HelpTopic? existing;

  @override
  State<_HelpFormScreen> createState() => _HelpFormScreenState();
}

class _HelpFormScreenState extends State<_HelpFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _icon;
  late String _iconColor;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _description =
        TextEditingController(text: _stripHtml(e?.description ?? ''));
    _icon = (e?.icon.isNotEmpty ?? false) ? e!.icon : kDefaultHelpIcon;
    _iconColor =
        (e?.iconColor.isNotEmpty ?? false) ? e!.iconColor : kDefaultHelpColor;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast('Title is required.');
      return;
    }
    setState(() => _saving = true);
    final HelpResult res;
    if (_isEdit) {
      res = await widget.service.update(
        id: widget.existing!.id,
        title: title,
        description: _description.text,
        icon: _icon,
        iconColor: _iconColor,
      );
    } else {
      res = await widget.service.add(
        title: title,
        description: _description.text,
        icon: _icon,
        iconColor: _iconColor,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not save the topic.');
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('Delete help topic?'),
        content: const Text(
            'This permanently removes the topic and its content.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    final res = await widget.service.delete(widget.existing!.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Could not delete the topic.');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toUpperCase())));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = parseHelpColor(_iconColor) ?? Brand.signal;
    return StationScaffold(
      stationNumber: '··',
      stationLabel: _isEdit ? 'EDIT TOPIC' : 'NEW TOPIC',
      title: _isEdit ? 'Edit topic.' : 'Add topic.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        children: [
          // Live preview of how the topic's badge reads.
          Row(
            children: [
              Icon(helpIconData(_icon), size: 28, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _title.text.trim().isEmpty
                      ? 'Topic preview'
                      : _title.text.trim(),
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'TITLE'),
            style: text.titleMedium,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'DESCRIPTION'),
            style: text.titleMedium,
            minLines: 4,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 24),
          Text('ICON', style: text.labelMedium),
          const SizedBox(height: 12),
          _IconGrid(
            selected: _icon,
            color: color,
            onSelected: (v) => setState(() => _icon = v),
          ),
          const SizedBox(height: 24),
          Text('ICON COLOR', style: text.labelMedium),
          const SizedBox(height: 12),
          _ColorPalette(
            selected: _iconColor,
            onSelected: (v) => setState(() => _iconColor = v),
          ),
          const SizedBox(height: 32),
          SignalButton(
            label: _isEdit ? 'Save changes' : 'Create topic',
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 12),
            GhostButton(label: 'Delete topic', onPressed: _delete),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// Selectable grid of the icons offered by the web help editor.
class _IconGrid extends StatelessWidget {
  const _IconGrid({
    required this.selected,
    required this.color,
    required this.onSelected,
  });
  final String selected;
  final Color color;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: kHelpIconMap.keys.map((fa) {
        final active = fa == selected;
        return InkWell(
          onTap: () => onSelected(fa),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: active ? Brand.surfaceHi : Brand.surface,
              border: Border.all(
                color: active ? color : Brand.rule,
                width: active ? 2 : 1,
              ),
            ),
            child: Icon(
              kHelpIconMap[fa],
              size: 20,
              color: active ? color : Brand.paperDim,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Palette of preset icon colours (stored as hex strings).
class _ColorPalette extends StatelessWidget {
  const _ColorPalette({required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: kHelpColors.map((hex) {
        final active = hex.toUpperCase() == selected.toUpperCase();
        final color = parseHelpColor(hex)!;
        return InkWell(
          onTap: () => onSelected(hex),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? Brand.paper : Brand.rule,
                width: active ? 3 : 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

const String kDefaultHelpIcon = 'fa-question-circle';
const String kDefaultHelpColor = '#FF7D00';

/// FontAwesome class → nearest Material icon. Kept in sync with the icon list
/// in assets/js/helpModal.js so mobile and web offer the same palette.
const Map<String, IconData> kHelpIconMap = {
  'fa-question-circle': Icons.help_outline,
  'fa-lightbulb': Icons.lightbulb_outline,
  'fa-info-circle': Icons.info_outline,
  'fa-cogs': Icons.settings_suggest_outlined,
  'fa-book': Icons.menu_book_outlined,
  'fa-comments': Icons.forum_outlined,
  'fa-envelope': Icons.mail_outline,
  'fa-headset': Icons.headset_mic_outlined,
  'fa-globe': Icons.public,
  'fa-bell': Icons.notifications_none,
  'fa-wrench': Icons.build_outlined,
  'fa-user': Icons.person_outline,
  'fa-shield-alt': Icons.shield_outlined,
  'fa-lock': Icons.lock_outline,
  'fa-paper-plane': Icons.send_outlined,
  'fa-star': Icons.star_border,
  'fa-thumbs-up': Icons.thumb_up_off_alt,
  'fa-heart': Icons.favorite_border,
  'fa-exclamation-triangle': Icons.warning_amber_outlined,
  'fa-bug': Icons.bug_report_outlined,
  'fa-calendar': Icons.calendar_today_outlined,
  'fa-camera': Icons.photo_camera_outlined,
  'fa-chart-bar': Icons.bar_chart,
  'fa-check-circle': Icons.check_circle_outline,
  'fa-cloud': Icons.cloud_outlined,
  'fa-database': Icons.storage_outlined,
  'fa-edit': Icons.edit_outlined,
  'fa-flag': Icons.flag_outlined,
  'fa-gift': Icons.card_giftcard,
  'fa-home': Icons.home_outlined,
  'fa-key': Icons.vpn_key_outlined,
  'fa-magic': Icons.auto_fix_high,
  'fa-map-marker': Icons.location_on_outlined,
  'fa-microphone': Icons.mic_none,
  'fa-phone': Icons.phone_outlined,
  'fa-rocket': Icons.rocket_launch_outlined,
  'fa-search': Icons.search,
  'fa-shopping-cart': Icons.shopping_cart_outlined,
  'fa-signal': Icons.signal_cellular_alt,
  'fa-sitemap': Icons.account_tree_outlined,
  'fa-tag': Icons.sell_outlined,
  'fa-th-large': Icons.grid_view,
  'fa-tools': Icons.handyman_outlined,
  'fa-truck': Icons.local_shipping_outlined,
  'fa-tv': Icons.tv_outlined,
  'fa-video': Icons.videocam_outlined,
  'fa-wifi': Icons.wifi,
  'fa-barcode': Icons.qr_code_2,
  'fa-receipt': Icons.receipt_long_outlined,
  'fa-computer': Icons.desktop_windows_outlined,
  'fa-laptop-code': Icons.laptop_mac_outlined,
  'fa-print': Icons.print_outlined,
  'fa-keyboard': Icons.keyboard_outlined,
  'fa-mouse': Icons.mouse_outlined,
};

/// Preset colours offered in the form. Values are stored verbatim.
const List<String> kHelpColors = [
  '#FF7D00', // signal orange
  '#000000',
  '#0066CC',
  '#198754',
  '#DC3545',
  '#6F42C1',
  '#FD7E14',
  '#20C997',
  '#6C757D',
];

/// Resolve a FontAwesome class to a Material icon, falling back to a generic
/// help glyph for anything not in the map (e.g. icons authored on the web).
IconData helpIconData(String fa) => kHelpIconMap[fa] ?? Icons.help_outline;

/// Parse a "#RRGGBB" (or "RRGGBB" / "#AARRGGBB") hex string to a [Color].
/// Returns null when the string isn't a usable hex colour.
Color? parseHelpColor(String hex) {
  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return null;
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// Reduce stored HTML to readable plain text for list previews / editing.
String _stripHtml(String html) {
  if (html.isEmpty) return '';
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
}
