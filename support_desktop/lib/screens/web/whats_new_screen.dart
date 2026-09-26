import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../services/whats_new_service.dart';
import '../../theme.dart';
import '../../widgets/premium.dart';
import '../../widgets/tp_loader.dart';

const _faIcons = <String, IconData>{
  'fa-truck': Icons.local_shipping_outlined,
  'fa-paint-roller': Icons.format_paint_outlined,
  'fa-chart-line': Icons.show_chart,
  'fa-id-card-alt': Icons.badge_outlined,
  'fa-comments': Icons.forum_outlined,
  'fa-phone-volume': Icons.phone_in_talk_outlined,
  'fa-desktop': Icons.desktop_windows_outlined,
  'fa-ticket-alt': Icons.confirmation_number_outlined,
  'fa-headset': Icons.headset_mic_outlined,
  'fa-tasks': Icons.checklist,
  'fa-magic': Icons.auto_fix_high,
  'fa-file-invoice': Icons.receipt_long_outlined,
  'fa-file-excel': Icons.table_chart_outlined,
  'fa-bullhorn': Icons.campaign_outlined,
  'fa-key': Icons.vpn_key_outlined,
  'fa-folder-open': Icons.folder_open,
  'fa-clipboard-list': Icons.fact_check_outlined,
  'fa-bell': Icons.notifications_none,
  'fa-user-plus': Icons.person_add_alt,
  'fa-store': Icons.storefront_outlined,
  'fa-download': Icons.download_outlined,
  'fa-gift': Icons.card_giftcard,
};

IconData _icon(String fa) => _faIcons[fa] ?? Icons.new_releases_outlined;

class WhatsNewScreen extends StatefulWidget {
  const WhatsNewScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<WhatsNewScreen> createState() => _WhatsNewScreenState();
}

class _WhatsNewScreenState extends State<WhatsNewScreen> {
  late final WhatsNewService _svc = WhatsNewService(widget.api);
  bool _loading = true;
  String? _error;
  WhatsNew? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _svc.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  WhatsNewFeature? _guide;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _showGuide(WhatsNewFeature? f) {
    setState(() => _guide = f);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.brand.canvas,
      child: Padding(padding: const EdgeInsets.all(20), child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: TpLoader());
    }
    if (_error != null || _data == null) {
      return EmptyState(
        label: 'Could not load',
        hint: _error ?? 'No changelog available.',
      );
    }
    final d = _data!;
    final guide = _guide;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          decoration: BoxDecoration(
            color: context.brand.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x590C233E),
                blurRadius: 80,
                offset: Offset(0, 30),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _head(d),
              Flexible(
                child: ListView(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                  children: guide?.guide != null
                      ? [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: _GuideBody(
                              feature: guide!,
                              onBack: () => _showGuide(null),
                            ),
                          ),
                        ]
                      : [
                          _sectionLabel(
                            d.sectionLabel.isEmpty
                                ? 'What\'s new in this release'
                                : d.sectionLabel,
                          ),
                          for (var i = 0; i < d.features.length; i++)
                            _FeatureRow(
                              feature: d.features[i],
                              last: i == d.features.length - 1,
                              onTap: d.features[i].guide == null
                                  ? null
                                  : () => _showGuide(d.features[i]),
                            ),
                        ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(30, 16, 30, 22),
                decoration: const BoxDecoration(
                  color: Color(0xFFFAFAFA),
                  border: Border(top: BorderSide(color: Color(0xFFF1F1EF))),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 13,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Released for version ${d.version}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    _GotIt(onTap: () => _showGuide(null)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _head(WhatsNew d) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0C233E), Color(0xFF163A64)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -70,
            right: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x52FF7D00), Color(0x00FF7D00)],
                  stops: [0, 0.7],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(30, 28, 30, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Brand.signal,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'VERSION ${d.version}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.9,
                          letterSpacing: 0.65,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'WHAT\'S NEW',
                      style: TextStyle(
                        color: Color(0xFFFFCB99),
                        fontSize: 11.2,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  d.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    height: 1.15,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (d.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    d.subtitle,
                    style: const TextStyle(
                      color: Color(0xD1FFFFFF),
                      fontSize: 14.7,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: Brand.signal,
        ),
      ),
    );
  }
}

class _GotIt extends StatefulWidget {
  const _GotIt({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_GotIt> createState() => _GotItState();
}

class _GotItState extends State<_GotIt> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFE67000) : Brand.signal,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Got it',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatefulWidget {
  const _FeatureRow({required this.feature, required this.last, this.onTap});
  final WhatsNewFeature feature;
  final bool last;
  final VoidCallback? onTap;

  @override
  State<_FeatureRow> createState() => _FeatureRowState();
}

class _FeatureRowState extends State<_FeatureRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.feature;
    final pillFg = f.pillBeta
        ? const Color(0xFFB45309)
        : const Color(0xFF15803D);
    final pillBg = f.pillBeta
        ? const Color(0xFFFEF3C7)
        : const Color(0xFFDCFCE7);
    final clickable = widget.onTap != null;
    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFFAFAFA) : null,
            borderRadius: BorderRadius.circular(12),
            border: widget.last
                ? null
                : const Border(bottom: BorderSide(color: Color(0xFFF1F1EF))),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Brand.signal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon(f.icon), size: 19, color: Brand.signal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: f.title),
                          if (f.pill.isNotEmpty)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: pillBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  f.pill.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9.9,
                                    letterSpacing: 0.5,
                                    fontWeight: FontWeight.w700,
                                    color: pillFg,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 15.7,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0C233E),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      f.description,
                      style: const TextStyle(
                        fontSize: 13.6,
                        height: 1.45,
                        color: Color(0xFF5B6B7D),
                      ),
                    ),
                  ],
                ),
              ),
              if (clickable)
                AnimatedPadding(
                  duration: const Duration(milliseconds: 150),
                  padding: EdgeInsets.only(left: _hover ? 17 : 14),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: _hover ? Brand.signal : const Color(0xFFCBD5E1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideBody extends StatelessWidget {
  const _GuideBody({required this.feature, required this.onBack});
  final WhatsNewFeature feature;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final g = feature.guide!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, size: 15, color: Brand.signal),
                  SizedBox(width: 7),
                  Text(
                    'Back to what\'s new',
                    style: TextStyle(
                      fontSize: 13.6,
                      fontWeight: FontWeight.w700,
                      color: Brand.signal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Brand.signal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon(feature.icon), size: 21, color: Brand.signal),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                feature.title,
                style: const TextStyle(
                  fontSize: 18.9,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: Color(0xFF0C233E),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (g.intro.isNotEmpty) ...[
          Text(
            g.intro,
            style: const TextStyle(
              fontSize: 14.4,
              height: 1.5,
              color: Color(0xFF5B6B7D),
            ),
          ),
          const SizedBox(height: 20),
        ],
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 14),
          child: Text(
            'HOW TO USE IT',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: Brand.signal,
            ),
          ),
        ),
        for (var s = 0; s < g.steps.length; s++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 27,
                  child: Column(
                    children: [
                      Container(
                        width: 27,
                        height: 27,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Brand.signal,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${s + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (s < g.steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.only(bottom: 4),
                            color: const Color(0xFFFFE3C7),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 2,
                      bottom: s < g.steps.length - 1 ? 18 : 4,
                    ),
                    child: Text(
                      g.steps[s],
                      style: const TextStyle(
                        fontSize: 14.1,
                        height: 1.5,
                        color: Color(0xFF384B5F),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (g.tip.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              border: Border.all(color: const Color(0xFFFED7AA)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  size: 17,
                  color: Brand.signal,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    g.tip,
                    style: const TextStyle(
                      fontSize: 13.4,
                      height: 1.45,
                      color: Color(0xFF384B5F),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
