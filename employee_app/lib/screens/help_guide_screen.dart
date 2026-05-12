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

/// First screen the employee sees after the bootstrap has resolved
/// their store + chat session. POS-focused self-serve FAQ — common
/// register / sales / BIR / inventory questions the cashier hits day
/// to day. A live search field at the top filters the article list
/// as the user types (matches title or body, case-insensitive) so
/// they don't have to scroll through every collapsed tile.
///
/// "Contact Support" is the only escape hatch: it pushes the existing
/// TicketFormScreen, posts the same "🎫 Ticket #N submitted…" note as
/// the /ticket slash-command, then pushReplacement's into
/// EmployeeChatScreen with the ticket id as the history anchor so the
/// freshly-opened chat starts at the new ticket bubble (no unrelated
/// past-ticket chatter).
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

  /// Articles currently driving the list. Starts as the baked-in
  /// fallback so the screen has something to show on a fresh install
  /// before the first network call lands; gets replaced by the
  /// admin-managed list once `help.public` responds (or the cached
  /// JSON from last launch is decoded).
  List<HelpArticle> _articles = _fallbackArticles;

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
    final list = await _helpSvc.load();
    if (!mounted) return;
    // Only swap in when the server (or cache) returned something —
    // otherwise stay on the baked-in fallback so the screen never
    // shows an empty FAQ.
    if (list.isEmpty) return;
    setState(() {
      _articles = List<HelpArticle>.unmodifiable(list);
    });
  }

  /// Offline-bootstrap defaults. Used until the server response (or
  /// the cached JSON from a prior session) supersedes them. Kept
  /// intentionally short — the admin web app's Help Center is the
  /// source of truth, this only exists so a brand-new install can
  /// still show something useful before its first network call.
  static const _fallbackArticles = <HelpArticle>[
    HelpArticle(
      title: 'Log in to the POS',
      body: 'On the POS terminal, enter your cashier username and PIN, then '
          'press LOG IN.\n\n'
          'If the screen says "License invalid" or "License expired", call '
          'your manager before continuing — do not try to re-enter the PIN; '
          'every wrong attempt is logged.'
    ),
    HelpArticle(
      title: 'Open a shift / starting cash',
      body: 'After login, the POS asks for the starting cash in the drawer. '
          'Count the float, type the exact amount and press CONFIRM. The '
          'shift is now open and any sale you ring will be tied to your '
          'cashier ID for the day-end Z-reading.',
    ),
    HelpArticle(
      title: 'Still stuck?',
      body: 'If none of the above answers your question, tap "Contact '
          'Support" below. Fill in the form with the OR number / item '
          'code / error message and we will reach out in chat as soon '
          'as we see your ticket.',
    ),
  ];

  List<HelpArticle> get _visibleArticles {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _articles;
    return _articles
        .where((a) =>
            a.title.toLowerCase().contains(q) ||
            a.body.toLowerCase().contains(q))
        .toList(growable: false);
  }

  Future<void> _contactSupport() async {
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

    final ticketRef = outcome.ticketId != null ? ' #${outcome.ticketId}' : '';
    final note = '🎫 Ticket$ticketRef submitted: "${outcome.subject}"\n'
        'Business: ${outcome.businessName} (${outcome.vatLabel})\n'
        'Priority: ${outcome.priority.toUpperCase()}';
    final sent = await widget.chat.send(
      convId: widget.info.conversationId,
      body: note,
      clientNonce: 'help-${DateTime.now().microsecondsSinceEpoch}',
    );
    final anchorId = sent?.persistedId;

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
          // When the admin resolves this ticket, chat hands control
          // back to a fresh HelpGuideScreen so the employee starts a
          // new self-serve flow (search the FAQ or file another
          // ticket). Using pushReplacement again so the closed chat
          // route is gone from the stack.
          onTicketClosed: (ctx) {
            Navigator.of(ctx).pushReplacement(
              MaterialPageRoute(
                builder: (_) => HelpGuideScreen(
                  api: widget.api,
                  chat: widget.chat,
                  realtime: widget.realtime,
                  calls: widget.calls,
                  lan: widget.lan,
                  store: widget.store,
                  info: widget.info,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final visible = _visibleArticles;
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        title: const Text('POS Help & Guide'),
        backgroundColor: Brand.canvas,
        foregroundColor: Brand.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: _buildHero(text),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: _buildSearchField(),
            ),
            Expanded(
              child: visible.isEmpty
                  ? _buildEmptyState(text)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      itemCount: visible.length,
                      itemBuilder: (_, i) =>
                          _buildArticle(visible[i], text),
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Brand.canvas,
                border: Border(top: BorderSide(color: Brand.stroke)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _contactSupport,
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Contact Support'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search the guide… (e.g., "refund", "Z-reading", "printer")',
        prefixIcon: const Icon(Icons.search, color: Brand.textMuted),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Clear',
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: Brand.canvas,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Brand.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Brand.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Brand.signal, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildEmptyState(TextTheme text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off,
                size: 48, color: Brand.textMuted),
            const SizedBox(height: 12),
            Text(
              'No matching guide entries.',
              style: text.bodyMedium?.copyWith(color: Brand.textMuted),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different keyword, or tap Contact Support below.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: Brand.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(TextTheme text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: Brand.primary,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Brand.signal.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.point_of_sale,
              color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${widget.info.storeName}',
                  style: text.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Quick answers to common POS questions live below. '
                  'Search for a topic, or tap Contact Support if your '
                  'question is not covered.',
                  style: text.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArticle(HelpArticle a, TextTheme text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Brand.canvas,
        border: Border.all(color: Brand.stroke),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ExpansionTile(
          // While a search query is active, auto-expand the tile so
          // the matching body text is visible without an extra tap.
          initiallyExpanded: _query.trim().isNotEmpty,
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            a.title,
            style: text.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Brand.textPrimary,
            ),
          ),
          iconColor: Brand.signal,
          collapsedIconColor: Brand.textMuted,
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedAlignment: Alignment.centerLeft,
          children: [
            if (a.body.isNotEmpty)
              Text(
                a.body,
                style: text.bodySmall?.copyWith(
                  color: Brand.textMuted,
                  height: 1.55,
                ),
              ),
            // Inline images attached to the topic (any help_content
            // row that carried an image_path). Hosted as static files
            // under /uploads/help/ on the support server — no auth.
            // Tap to expand into a full-screen viewer.
            for (final p in a.imagePaths)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildHelpImage(p),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpImage(String path) {
    final url = '${widget.api.baseUrl}/uploads/help/$path';
    return GestureDetector(
      onTap: () => _openImagePreview(url, path),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: Brand.subtle,
            border: Border.all(color: Brand.stroke),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                height: 160,
                child: Center(
                  child: SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              height: 80,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.broken_image_outlined,
                      size: 18, color: Brand.textMuted),
                  SizedBox(width: 6),
                  Text('Image unavailable',
                      style: TextStyle(
                          color: Brand.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openImagePreview(String url, String filename) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) {
        return Dialog(
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
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 8, right: 8,
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
        );
      },
    );
  }
}
