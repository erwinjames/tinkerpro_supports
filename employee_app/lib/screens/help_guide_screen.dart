import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/help_article_service.dart';
import '../services/lan_presence.dart';
import '../services/session_store.dart';
import '../services/ticket_service.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'ticket_form_screen.dart';

/// "Help articles" view — reached from the AI chat screen's top-bar
/// button. Replaces the older POS Help & Guide layout with a
/// category-driven browse + search experience:
///
///   • top bar: back arrow, "Help articles" + subtitle, "Submit ticket"
///   • search input (filters by title/body, live)
///   • BROWSE BY TOPIC row of category cards (counts per category)
///   • MOST ASKED list of articles (chevron → detail view)
///
/// Categories are derived client-side from keyword matches against the
/// article title + body — the admin's Help Center schema doesn't carry
/// an explicit category column yet, so this is the lightest path to
/// the mock-up without a server-side migration.
class HelpGuideScreen extends StatefulWidget {
  const HelpGuideScreen({
    super.key,
    required this.api,
    required this.chat,
    required this.realtime,
    required this.calls,
    required this.lan,
    required this.store,
    required this.info,
  });

  final ApiClient api;
  final ChatService chat;
  final ChatRealtimeService realtime;
  final CallService calls;
  final LanPresence lan;
  final SessionStore store;
  final EmployeeChatInfo info;

  @override
  State<HelpGuideScreen> createState() => _HelpGuideScreenState();
}

class _HelpGuideScreenState extends State<HelpGuideScreen> {
  final _search = TextEditingController();
  String _query = '';
  _CategoryDef? _activeCategory;

  // Help content is sourced exclusively from the live Help Center
  // (see HelpArticleService). We deliberately ship NO baked-in sample
  // articles — showing fake "Log in to the POS"-style placeholders when
  // the fetch fails reads as real content but isn't. Instead we show a
  // loader while fetching and an honest "couldn't load" state on failure.
  List<HelpArticle> _articles = const [];
  bool _loading = true;

  late final HelpArticleService _helpSvc =
      HelpArticleService(api: widget.api, store: widget.store);

  @override
  void initState() {
    super.initState();
    _fetchFromServer();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetchFromServer() async {
    if (!_loading) setState(() => _loading = true);
    final list = await _helpSvc.load();
    if (!mounted) return;
    setState(() {
      _articles = List<HelpArticle>.unmodifiable(list);
      _loading = false;
    });
  }

  // ── Categories ────────────────────────────────────────────────
  // Keyword buckets used to assign each article to a "Browse by topic"
  // card. Lowercase, longest-first so "z reading" beats a bare "z".
  static const _categories = <_CategoryDef>[
    _CategoryDef(
      label: 'Getting started',
      icon: Icons.flag_outlined,
      keywords: [
        'log in', 'login', 'sign in', 'setup', 'set up', 'configure',
        'install', 'first launch', 'get started', 'pin'
      ],
    ),
    _CategoryDef(
      label: 'Daily operations',
      icon: Icons.schedule_outlined,
      keywords: [
        'z reading', 'z-reading', 'x reading', 'x-reading',
        'end of shift', 'end of day', 'open shift', 'close shift',
        'starting cash', 'cash float', 'bir', 'audit'
      ],
    ),
    _CategoryDef(
      label: 'Sales and payments',
      icon: Icons.credit_card_outlined,
      keywords: [
        'refund', 'void', 'discount', 'payment', 'tender', 'cash',
        'card', 'change', 'or ', 'receipt', 'reprint', 'checkout',
        'pwd', 'senior'
      ],
    ),
    _CategoryDef(
      label: 'Hardware',
      icon: Icons.print_outlined,
      keywords: [
        'printer', 'scanner', 'barcode', 'drawer', 'usb', 'paper',
        'ribbon', 'offline', 'thermal', 'cable'
      ],
    ),
  ];

  // ── Filtering ─────────────────────────────────────────────────

  List<HelpArticle> get _searchFiltered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _articles;
    return _articles
        .where((a) =>
            a.title.toLowerCase().contains(q) ||
            a.body.toLowerCase().contains(q))
        .toList(growable: false);
  }

  /// Articles to show in the MOST ASKED list — search wins over category,
  /// category wins over "show everything".
  List<HelpArticle> get _visibleArticles {
    final base = _searchFiltered;
    final cat = _activeCategory;
    if (cat == null) return base;
    return base.where((a) => cat.matches(a)).toList(growable: false);
  }

  int _countFor(_CategoryDef c) {
    // Counts respect the live search query, so a search of "printer"
    // shrinks the "Hardware" badge to whatever's actually visible.
    return _searchFiltered.where((a) => c.matches(a)).length;
  }

  _CategoryDef? _categoryFor(HelpArticle a) {
    for (final c in _categories) {
      if (c.matches(a)) return c;
    }
    return null;
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _submitTicket() async {
    // One unresolved ticket at a time. If the cashier already has a
    // pending ticket pinned in SessionStore, jump them back into that
    // chat instead of letting them open a second one.
    if (widget.store.hasPendingTicket) {
      final pendingId = widget.store.pendingTicketId;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          pendingId != null
              ? 'You already have ticket #$pendingId pending — please wait for support to resolve it.'
              : 'You already have a ticket pending — please wait for support to resolve it.',
        ),
        duration: const Duration(seconds: 3),
      ));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EmployeeChatScreen(
            api: widget.api,
            chat: widget.chat,
            realtime: widget.realtime,
            calls: widget.calls,
            lan: widget.lan,
            store: widget.store,
            info: widget.info,
            sinceMessageId: widget.store.pendingTicketAnchorMessageId,
            onTicketClosed: (ctx) => Navigator.of(ctx).pop(),
          ),
        ),
      );
      return;
    }
    final tickets = TicketService(widget.api);
    final outcome = await Navigator.of(context).push<TicketSubmitOutcome>(
      MaterialPageRoute(
        builder: (_) => TicketFormScreen(
          tickets: tickets,
          info: widget.info,
          store: widget.store,
          api: widget.api,
        ),
      ),
    );
    if (outcome == null || !mounted) return;
    final ticketRef =
        outcome.ticketId != null ? ' ${fmtTicketNo(outcome.ticketId!)}' : '';
    final note = '🎫 Ticket$ticketRef submitted: "${outcome.subject}"\n'
        'Business: ${outcome.businessName} (${outcome.vatLabel})\n'
        'Priority: ${outcome.priority.toUpperCase()}';
    final sent = await widget.chat.send(
      convId: widget.info.conversationId,
      body: note,
      clientNonce: 'help-${DateTime.now().microsecondsSinceEpoch}',
    );
    final anchorId = sent?.persistedId;
    if (anchorId != null && outcome.ticketId != null) {
      await widget.store.savePendingTicket(
        anchorMessageId: anchorId,
        ticketId: outcome.ticketId!,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EmployeeChatScreen(
          api: widget.api,
          chat: widget.chat,
          realtime: widget.realtime,
          calls: widget.calls,
          lan: widget.lan,
          store: widget.store,
          info: widget.info,
          sinceMessageId: anchorId,
          onTicketClosed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  void _openArticle(HelpArticle a) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ArticleDetailScreen(
          article: a,
          baseUrl: _helpSvc.baseUrl,
          category: _categoryFor(a),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: Brand.stroke),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                children: [
                  _buildSearch(),
                  const SizedBox(height: 18),
                  _buildSectionLabel('BROWSE BY TOPIC'),
                  const SizedBox(height: 10),
                  _buildCategoryRow(),
                  const SizedBox(height: 22),
                  _buildSectionLabel(
                    _activeCategory == null
                        ? 'MOST ASKED'
                        : _activeCategory!.label.toUpperCase(),
                  ),
                  const SizedBox(height: 10),
                  _buildArticleList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      color: Brand.canvas,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CircleIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Help articles',
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Brand.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Browse guides for the POS',
                  style: text.bodySmall?.copyWith(color: Brand.textMuted),
                ),
              ],
            ),
          ),
          _OutlineButton(
            icon: Icons.headset_mic_outlined,
            label: 'Submit ticket',
            onTap: _submitTicket,
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Container(
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Brand.stroke),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.search, color: Brand.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                isCollapsed: true,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText:
                    'Search articles, e.g. "Z reading", "discount", "printer offline"',
                hintStyle: TextStyle(color: Brand.textMuted, fontSize: 14),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: Brand.textMuted),
              tooltip: 'Clear search',
              onPressed: () {
                _search.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Brand.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _buildCategoryRow() {
    // LayoutBuilder so the four cards collapse to two-per-row when the
    // window is narrow (POS dual-monitor portrait mode, mostly).
    return LayoutBuilder(builder: (_, c) {
      final twoCol = c.maxWidth < 700;
      final cards = [
        for (final cat in _categories)
          _CategoryCard(
            def: cat,
            count: _countFor(cat),
            active: _activeCategory == cat,
            onTap: () => setState(() {
              _activeCategory = _activeCategory == cat ? null : cat;
            }),
          ),
      ];
      if (!twoCol) {
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i < cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      }
      return Column(
        children: [
          Row(children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: cards[2]),
            const SizedBox(width: 12),
            Expanded(child: cards[3]),
          ]),
        ],
      );
    });
  }

  Widget _buildArticleList() {
    // Still fetching the live Help Center (and nothing cached to show yet).
    if (_loading && _articles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Brand.canvas,
          border: Border.all(color: Brand.stroke),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    final list = _visibleArticles;
    if (list.isEmpty) {
      // Nothing loaded at all (network/server failure) vs. a search or
      // category that simply matched nothing — different messages, and a
      // Retry on the load-failure case.
      final loadFailed =
          _articles.isEmpty && _query.isEmpty && _activeCategory == null;
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Brand.canvas,
          border: Border.all(color: Brand.stroke),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(loadFailed ? Icons.cloud_off_outlined : Icons.search_off,
                size: 36, color: Brand.textMuted),
            const SizedBox(height: 10),
            Text(
              loadFailed
                  ? "Couldn't load help articles."
                  : _query.isNotEmpty
                      ? 'No articles match "$_query".'
                      : 'No articles in this category yet.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Brand.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              loadFailed
                  ? 'Check your connection and try again, or tap Submit ticket above.'
                  : 'Try a different keyword, or tap Submit ticket above.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Brand.textMuted),
            ),
            if (loadFailed) ...[
              const SizedBox(height: 14),
              _OutlineButton(
                icon: Icons.refresh,
                label: 'Retry',
                onTap: _fetchFromServer,
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Brand.canvas,
        border: Border.all(color: Brand.stroke),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            _ArticleRow(
              key: ValueKey(list[i].title),
              article: list[i],
              category: _categoryFor(list[i]),
              onTap: () => _openArticle(list[i]),
            ),
            if (i < list.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: Brand.stroke,
                indent: 18,
                endIndent: 18,
              ),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────── Category model ─────────────────────────

class _CategoryDef {
  const _CategoryDef({
    required this.label,
    required this.icon,
    required this.keywords,
  });

  final String label;
  final IconData icon;
  final List<String> keywords;

  bool matches(HelpArticle a) {
    final haystack = '${a.title} ${a.body}'.toLowerCase();
    for (final k in keywords) {
      if (haystack.contains(k)) return true;
    }
    return false;
  }
}

// ───────────────────────── Components ─────────────────────────────

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Brand.canvas,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Brand.stroke),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, size: 18, color: Brand.textPrimary),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.canvas,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: Brand.stroke),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Brand.textPrimary),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Brand.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.def,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final _CategoryDef def;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = active ? Brand.signal : Brand.stroke;
    return Material(
      color: Brand.canvas,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: active ? 1.5 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Brand.signal.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(def.icon, color: Brand.signal, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      def.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Brand.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count article${count == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Brand.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  const _ArticleRow({
    super.key,
    required this.article,
    required this.category,
    required this.onTap,
  });

  final HelpArticle article;
  final _CategoryDef? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
        child: Row(
          children: [
            Icon(
              category?.icon ?? Icons.article_outlined,
              size: 20,
              color: Brand.textMuted,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                article.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Brand.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 20, color: Brand.textMuted),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Article detail ─────────────────────────

class _ArticleDetailScreen extends StatelessWidget {
  const _ArticleDetailScreen({
    required this.article,
    required this.baseUrl,
    required this.category,
  });

  final HelpArticle article;
  final String baseUrl;
  final _CategoryDef? category;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Brand.surface,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Brand.canvas,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  _CircleIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (category != null)
                          Text(
                            category!.label.toUpperCase(),
                            style: const TextStyle(
                              color: Brand.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Brand.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Brand.stroke),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                children: [
                  if (article.body.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Brand.canvas,
                        border: Border.all(color: Brand.stroke),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        article.body,
                        style: text.bodyMedium?.copyWith(
                          color: Brand.textPrimary,
                          height: 1.6,
                        ),
                      ),
                    ),
                  // Stable per-URL keys so Flutter never recycles one
                  // image's element for a different URL — without them a
                  // list of network images can briefly swap the first
                  // image for the second as they decode at different times.
                  for (var i = 0; i < article.imagePaths.length; i++) ...[
                    const SizedBox(height: 14),
                    _ArticleImage(
                      key: ValueKey('help-img-$i-${article.imagePaths[i]}'),
                      url: '$baseUrl/uploads/help/${article.imagePaths[i]}',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleImage extends StatelessWidget {
  const _ArticleImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openPreview(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: Brand.subtle,
            border: Border.all(color: Brand.stroke),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            // Hold the last decoded frame instead of flashing blank if the
            // provider is ever swapped during a rebuild.
            gaplessPlayback: true,
            loadingBuilder: (_, child, p) {
              if (p == null) return child;
              return const SizedBox(
                height: 180,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              height: 80,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.broken_image_outlined,
                      size: 18, color: Brand.textMuted),
                  SizedBox(width: 6),
                  Text('Image unavailable',
                      style: TextStyle(color: Brand.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openPreview(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: const SizedBox.expand(),
            ),
            Center(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(url, fit: BoxFit.contain, gaplessPlayback: true),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
