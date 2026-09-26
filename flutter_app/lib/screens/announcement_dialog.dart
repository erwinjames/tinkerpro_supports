import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../models/announcement_models.dart';
import '../services/announcement_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class AnnouncementDialog extends StatefulWidget {
  const AnnouncementDialog({
    super.key,
    required this.service,
    required this.api,
  });

  final AnnouncementService service;
  final ApiClient api;

  static bool _open = false;

  static bool get isOpen => _open;

  static Future<void> show(
    BuildContext context, {
    required AnnouncementService service,
    required ApiClient api,
  }) async {
    if (_open || !service.hasPending) return;
    _open = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color(0x8C0E1014),
        builder: (_) => AnnouncementDialog(service: service, api: api),
      );
    } finally {
      _open = false;
    }
  }

  @override
  State<AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<AnnouncementDialog> {
  late List<Announcement> _deck;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _deck = widget.service.pending.toList();
    widget.service.addListener(_onServiceChange);
  }

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChange);
    super.dispose();
  }

  void _onServiceChange() {
    if (!mounted) return;
    final incoming = widget.service.pending;
    final known = _deck.map((a) => a.id).toSet();
    final extras = incoming.where((a) => !known.contains(a.id)).toList();
    if (extras.isEmpty) return;
    setState(() => _deck = [..._deck, ...extras]);
  }

  Announcement? get _current =>
      _index >= 0 && _index < _deck.length ? _deck[_index] : null;

  bool get _mandatory {
    final item = _current;
    if (item == null) return false;
    if (!item.requireAck) return false;
    return widget.service.pending.any((a) => a.id == item.id && a.isPending);
  }

  bool get _isLast => _index >= _deck.length - 1;

  Future<void> _advance() async {
    final item = _current;
    if (item == null) {
      Navigator.of(context).pop();
      return;
    }

    _markRead(item);

    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
  }

  void _markRead(Announcement item) {
    final stillPending = widget.service.pending.any(
      (a) => a.id == item.id && a.isPending,
    );
    if (!stillPending) return;
    widget.service.markRead(item.id, acknowledged: item.requireAck);
  }

  void _dismiss() {
    if (_mandatory) return;
    final item = _current;
    if (item != null) _markRead(item);
    Navigator.of(context).pop();
  }

  String _resolveLink(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http')) return trimmed;
    final base = widget.api.baseUrl;
    return '$base/${trimmed.replaceFirst(RegExp(r'^/+'), '')}';
  }

  Future<void> _copyLink(String url) async {
    final resolved = _resolveLink(url);
    if (resolved.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: resolved));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied to clipboard'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  String _postedLabel(Announcement item) {
    final bits = <String>[];
    if (item.author.isNotEmpty) bits.add('Posted by ${item.author}');
    final posted = item.postedAt(widget.service.dbOffsetSeconds);
    if (posted != null) {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      bits.add('${months[posted.month - 1]} ${posted.day}, ${posted.year}');
    }
    return bits.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final item = _current;
    if (item == null) return const SizedBox.shrink();

    final brand =
        Theme.of(context).extension<BrandColors>() ??
        Brand.forBrightness(Theme.of(context).brightness);
    final tone = item.toneColors;

    return PopScope(
      canPop: !_mandatory,
      child: _DialogReveal(
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 32,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Material(
              color: brand.surface,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(item, tone),
                  Container(height: 3, color: tone.accent),
                  Flexible(child: _body(item, brand)),
                  _footer(item, tone, brand),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(Announcement item, AnnouncementTone tone) {
    final meta = _postedLabel(item);
    final brand = context.brand;
    return Container(
      width: double.infinity,
      color: brand.isDark ? const Color(0xFF12304F) : Brand.navy,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'Announcement',
                            style: TextStyle(
                              color: Brand.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                          _chip(item.toneLabel, tone.accent, Colors.white),
                          if (item.requireAck)
                            _chip(
                              'Action required',
                              Colors.white.withValues(alpha: 0.18),
                              Colors.white,
                            ),
                        ],
                      ),
                    ),
                    if (!_mandatory)
                      HeaderTone(
                        child: AppIconButton(
                          icon: Icons.close_rounded,
                          tooltip: 'Close',
                          onPressed: _dismiss,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Icon(
                        item.iconData,
                        color: tone.iconTint,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.white, height: 1.25),
                            ),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              meta,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _body(Announcement item, BrandColors brand) {
    final link = _resolveLink(item.linkUrl);
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              item.body,
              textAlign: TextAlign.start,
              style: TextStyle(color: brand.paper, fontSize: 15, height: 1.6),
            ),
            if (link.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: brand.surfaceHi,
                  borderRadius: BorderRadius.circular(Brand.radiusLg),
                  border: Border.all(color: brand.rule),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.linkLabel.isEmpty ? 'Related link' : item.linkLabel,
                      style: TextStyle(
                        color: brand.paper,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      link,
                      style: TextStyle(
                        color: brand.signalInk,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _copyLink(item.linkUrl),
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy link'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: brand.paper,
                          side: BorderSide(color: brand.rule),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Brand.radiusSm),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _footer(Announcement item, AnnouncementTone tone, BrandColors brand) {
    final ctaLabel = !_isLast
        ? 'Next'
        : (item.requireAck && _mandatory ? 'I understand' : 'Got it');
    final showDots = _deck.length > 1 && _deck.length <= 6;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: brand.rule)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showDots)
                  ...List.generate(_deck.length, (i) {
                    return Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index ? tone.accent : brand.rule,
                      ),
                    );
                  }),
                if (_deck.length > 1) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '${_index + 1} of ${_deck.length}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: brand.paperDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_index > 0)
            TextButton(
              onPressed: () => setState(() => _index--),
              style: TextButton.styleFrom(
                foregroundColor: brand.paperDim,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(64, 44),
              ),
              child: const Text('Back'),
            ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _advance,
            style: FilledButton.styleFrom(
              backgroundColor: tone.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              minimumSize: const Size(96, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Brand.radiusLg),
              ),
            ),
            child: Text(ctaLabel),
          ),
        ],
      ),
    );
  }
}

class _DialogReveal extends StatefulWidget {
  const _DialogReveal({required this.child});

  final Widget child;

  @override
  State<_DialogReveal> createState() => _DialogRevealState();
}

class _DialogRevealState extends State<_DialogReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
        child: widget.child,
      ),
    );
  }
}
