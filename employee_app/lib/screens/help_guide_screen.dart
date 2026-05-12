import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Article-style content the FAQ list renders. Each entry is a
  /// (title, body) pair; body is plain text so it stays editable
  /// without hunting through widget-tree changes. Focused on POS
  /// register operations the cashier actually does at the counter.
  static const _articles = <(String, String)>[
    (
      'Log in to the POS',
      'On the POS terminal, enter your cashier username and PIN, then '
          'press LOG IN.\n\n'
          'If the screen says "License invalid" or "License expired", call '
          'your manager before continuing — do not try to re-enter the PIN; '
          'every wrong attempt is logged.'
    ),
    (
      'Open a shift / starting cash',
      'After login, the POS asks for the starting cash in the drawer. '
          'Count the float, type the exact amount and press CONFIRM. The '
          'shift is now open and any sale you ring will be tied to your '
          'cashier ID for the day-end Z-reading.'
    ),
    (
      'Ring up a sale',
      'Scan the barcode or type the item code in the top search box. '
          'Use the +/- buttons to adjust quantity. Tap PAY when finished, '
          'pick the tender (Cash, Card, GCash, etc.), enter the amount '
          'received and press CONFIRM to print the OR.'
    ),
    (
      'Apply a discount (Senior / PWD / Promo)',
      'Tap the item row, then DISCOUNT. Pick the discount type — Senior '
          'Citizen and PWD need the ID number entered for the BIR report. '
          'Custom % or amount discounts require manager approval; the POS '
          'will prompt for the manager PIN.'
    ),
    (
      'Process a return / refund',
      'From the main menu tap RETURN, scan the OR number from the '
          'customer receipt, select the items being returned and press '
          'CONFIRM. The drawer opens for the refund cash. A returns slip '
          'prints — give the white copy to the customer and keep the '
          'duplicate for end-of-day reconciliation.'
    ),
    (
      'Void a transaction',
      'Before the customer pays: tap VOID on the active sale, enter your '
          'reason, and confirm. After payment, you cannot void — use '
          'RETURN instead. Both events are logged against your cashier '
          'ID and appear on the manager dashboard.'
    ),
    (
      'Reprint a receipt (OR)',
      'Main menu → REPRINT. Search by OR number, customer name or '
          'date. The reprint is watermarked "DUPLICATE" so it cannot be '
          'mistaken for an original. Up to 3 reprints per OR; beyond '
          'that needs manager override.'
    ),
    (
      'Customer accounts & loyalty',
      'On the sale screen, tap CUSTOMER and search by name, mobile '
          'number or loyalty card. Points are added automatically once '
          'the sale is confirmed. To redeem points, tap REDEEM before '
          'pressing PAY and pick the reward.'
    ),
    (
      'Pricing: item not in system',
      'If a barcode scan returns "Item not found", do NOT improvise a '
          'price. Tap MISC and ring it under the matching category with '
          'manager approval, then file a ticket via Contact Support so '
          'the item is added to the master list.'
    ),
    (
      'BIR / VAT and Non-VAT receipts',
      'The POS prints whichever receipt type your store is registered '
          'for (BIR-approved OR for VAT, sales invoice for Non-VAT). The '
          'serial range is loaded from your BIR permit. When you hit '
          '80% of the serial range, the POS shows a yellow banner — file '
          'a ticket immediately so a new range can be requested.'
    ),
    (
      'Cash drawer: skim / pickup',
      'Manager-only: tap CASH MGMT → PICKUP. Enter the amount removed '
          'and the reason (e.g., "bank deposit"). The drawer opens, the '
          'amount is logged, and the running cash-in-drawer total '
          'decreases. The pickup appears as a line item in the Z-reading.'
    ),
    (
      'End of shift: X-reading vs Z-reading',
      'X-reading is a mid-shift snapshot — sales totals so far, no '
          'reset. Print as many as you want. Z-reading is the day-end '
          'close-out: it locks the shift, resets counters, and is the '
          'document the BIR requires. Z-read once per day, after the '
          'last sale.'
    ),
    (
      'Inventory: check stock on hand',
      'Main menu → INVENTORY → search the item. The "On Hand" column is '
          'the live count for your store. If the on-hand looks wrong, '
          'file a ticket — do not adjust manually; the POS audits every '
          'manual change against the manager PIN.'
    ),
    (
      'Connection lost / offline mode',
      'If the top bar shows "OFFLINE" in red, the POS keeps accepting '
          'sales locally and syncs once the connection comes back. Card '
          'and e-wallet payments are blocked while offline — only Cash. '
          'If it stays offline more than 10 minutes, call IT or file a '
          'ticket.'
    ),
    (
      'Printer not printing receipts',
      'Check the paper roll first (lift the top cover — there should be '
          'a green LED and paper sticking out). If the LED is red or '
          'blinking, power-cycle the printer (off 10 sec, on). If the '
          'POS still does not print, file a ticket and capture the OR '
          'number of the missed receipt.'
    ),
    (
      'Barcode scanner not reading',
      'Aim the scanner at a clean printed barcode about 10 cm away. If '
          'no beep, unplug-replug the USB cable. If still dead, type the '
          'item code manually in the search box and file a ticket so '
          'the scanner can be replaced.'
    ),
    (
      'Still stuck?',
      'If none of the above answers your question, tap "Contact '
          'Support" below. Fill in the form with the OR number / item '
          'code / error message and we will reach out in chat as soon '
          'as we see your ticket.'
    ),
  ];

  /// Case-insensitive substring match on title or body. Empty query
  /// returns the full list so the first paint shows everything.
  List<(String, String)> get _visibleArticles {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _articles;
    return _articles
        .where((a) =>
            a.$1.toLowerCase().contains(q) || a.$2.toLowerCase().contains(q))
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
                          _buildArticle(visible[i].$1, visible[i].$2, text),
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

  Widget _buildArticle(String title, String body, TextTheme text) {
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
            title,
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
            Text(
              body,
              style: text.bodySmall?.copyWith(
                color: Brand.textMuted,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
