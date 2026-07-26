import 'dart:async';
import 'dart:io' show File;
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../api_client.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/lan_presence.dart';
import '../services/session_store.dart';
import '../services/support_notifier.dart';
import '../services/ticket_service.dart';
import '../services/tinker_chat_service.dart';
import '../platform_info.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'help_guide_screen.dart';
import 'sync_mobile_screen.dart';
import 'ticket_form_screen.dart';

/// New landing screen for the employee app — AI-first POS support.
///
/// Replaces the FAQ-list HelpGuideScreen as the home view. The cashier
/// is greeted by the manager-configured chatbot ("tinker-chat") and can
/// ask freeform questions about refunds, Z-readings, printers, etc.
/// Two escape hatches in the top bar:
///
///   • Help articles  → opens the existing HelpGuideScreen (FAQ list)
///   • Submit ticket  → opens TicketFormScreen, then routes into the
///                       live EmployeeChatScreen the same way the old
///                       help guide did
///
/// Replies are fetched from the tinker-chat backend (REST `/api/chat/ask`
/// with `X-Api-Key`). History is preserved in-memory so the AI sees the
/// running conversation; session_id is a per-launch UUID so analytics
/// can group messages.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({
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
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  late final TinkerChatService _tinker = TinkerChatService(store: widget.store);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _sessionId = _newSessionId();

  final List<_Msg> _messages = [];
  bool _sending = false;

  // Real shop name used to fill the "[Business Name]" placeholder the
  // chatbot config / system prompt leaves in greetings and replies.
  // Resolved from the tinker-chat config (or the store name) in
  // _seedGreeting; empty until then.
  String _shopName = '';

  static const List<String> _suggestions = [
    'Reprint last receipt',
    'Z reading not generating',
    'Barcode scanner setup',
    'Apply a discount',
  ];

  // Mirrors SupportNotifier.unread so we can tell an increment (new agent
  // message → drop a banner) from a decrement (badge cleared on open).
  int _lastSeenUnread = 0;

  @override
  void initState() {
    super.initState();
    _seedGreeting();
    // This screen is the persistent landing route, so it owns the
    // "open the support chat" action a notification tap triggers, and it
    // listens for unread changes to paint the header badge + banner.
    _lastSeenUnread = SupportNotifier.instance.unread;
    SupportNotifier.instance.onOpenChat = _openSupportChat;
    SupportNotifier.instance.addListener(_onSupportChange);
  }

  @override
  void dispose() {
    SupportNotifier.instance.removeListener(_onSupportChange);
    if (SupportNotifier.instance.onOpenChat == _openSupportChat) {
      SupportNotifier.instance.onOpenChat = null;
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSupportChange() {
    if (!mounted) return;
    final n = SupportNotifier.instance;
    final increased = n.unread > _lastSeenUnread;
    _lastSeenUnread = n.unread;
    setState(() {}); // repaint the header/chat-entry badge
    // Chat is open → the thread shows messages inline, so the "Support sent you
    // a message" toast is noise. Clear any lingering one and never add another.
    if (n.chatOpen) {
      ScaffoldMessenger.of(context).clearSnackBars();
      return;
    }
    // Only drop an in-app banner when a NEW message arrived and this
    // landing screen is the one on top (the chat screen, when pushed,
    // shows messages inline and sets chatOpen so this won't fire).
    if (increased &&
        n.unread > 0 &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _showSupportBanner(n.lastMessage?.body ?? '');
    }
  }

  void _showSupportBanner(String body) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      backgroundColor: Brand.signal,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Row(
        children: [
          const Icon(Icons.chat_bubble, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Support sent you a message',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5)),
                if (body.trim().isNotEmpty)
                  Text(
                    SupportNotifier.messagePreview(body),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  ),
              ],
            ),
          ),
        ],
      ),
      action: SnackBarAction(
        label: 'Open',
        textColor: Colors.white,
        onPressed: _openSupportChat,
      ),
    ));
  }

  static String _newSessionId() {
    // Lightweight, non-cryptographic — only used to group chat logs
    // tenant-side. Uses millisecond clock + a small random suffix.
    final r = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'emp-${DateTime.now().millisecondsSinceEpoch}-$r';
  }

  Future<void> _seedGreeting() async {
    // Greet the cashier by their own name when we have it (captured on
    // setup); otherwise fall back to the store name.
    final greetSource = widget.info.employeeName.isNotEmpty
        ? widget.info.employeeName
        : widget.info.storeName;
    final first = _firstName(greetSource);
    var greeting = "Hi$first, I'm your TinkerPro POS assistant. "
        "I can help with refunds, Z readings, printers, scanners, "
        "discounts, and most day to day POS questions. What's going on?";

    // Best-effort: pull the manager-configured greeting from the
    // tinker-chat /config endpoint. If the call fails or the chatbot
    // isn't configured yet, fall back to the static greeting above.
    final cfg = await _tinker.loadConfig();
    if (cfg != null && cfg.greeting.trim().isNotEmpty) {
      greeting = cfg.greeting.trim();
    }
    // Resolve the real shop name: prefer the chatbot config's business
    // name, fall back to the store name captured during setup. Used to
    // replace the "[Business Name]" placeholder the config leaves behind.
    final cfgName = cfg?.businessName.trim() ?? '';
    _shopName = cfgName.isNotEmpty ? cfgName : widget.info.storeName.trim();
    greeting = _fillShopName(greeting);
    if (!mounted) return;
    setState(() {
      _messages.add(_Msg.bot(greeting, showSuggestions: true));
    });
  }

  /// Replace "[Business Name]" placeholders (and the `{business_name}` /
  /// `{{business_name}}` template variants) with the real shop name. If we
  /// never resolved a name, the text is returned untouched rather than
  /// substituting an empty string.
  String _fillShopName(String text) {
    if (_shopName.isEmpty) return text;
    return text
        .replaceAll(
          RegExp(r'\[\s*business\s*name\s*\]', caseSensitive: false),
          _shopName,
        )
        .replaceAll(
          RegExp(r'\{\{?\s*business[_\s]?name\s*\}?\}', caseSensitive: false),
          _shopName,
        );
  }

  String _firstName(String storeName) {
    // The user identity we have is the store name (set during setup).
    // Greet by that name if it looks like a person's name; otherwise
    // greet generically. Cheap heuristic: take the first whitespace
    // token, capitalise it.
    final t = storeName.trim();
    if (t.isEmpty) return '';
    final first = t.split(RegExp(r'\s+')).first;
    if (first.length < 2) return '';
    final pretty = first[0].toUpperCase() + first.substring(1).toLowerCase();
    return ' $pretty';
  }

  void _scrollToBottom() {
    // Defer so the new bubble is laid out before we measure.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send(String text) async {
    final body = text.trim();
    if (body.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _messages.add(_Msg.user(body));
      _sending = true;
    });
    _scrollToBottom();

    final history = _historyForApi();
    final reply = await _tinker.ask(
      question: body,
      sessionId: _sessionId,
      history: history,
    );
    if (!mounted) return;
    setState(() {
      if (reply == null) {
        _messages.add(_Msg.bot(
          "I couldn't reach the assistant. Check your connection or "
          "tap Submit ticket to escalate.",
          isError: true,
        ));
      } else {
        _messages.add(_Msg.bot(
          _fillShopName(reply.displayBody),
          logId: reply.logId,
          // Show "Open full guide / File a ticket" actions on every
          // bot reply — gives the cashier the same fallback the image
          // mock-up shows, regardless of whether the AI matched a KB
          // entry or escalated.
          showActions: true,
          // Add a "Set API key" pill alongside when the chatbot has no
          // tenant key configured, or the configured key was rejected
          // (401/403 "Invalid API key") — lets the cashier paste in a
          // freshly-issued `pk_live_…` instead of rebuilding the app.
          showSetApiKey: !_tinker.isConfigured || reply.authError,
        ));
      }
      _sending = false;
    });
    _scrollToBottom();
  }

  List<Map<String, String>> _historyForApi() {
    // tinker-chat's gemini service reads {role, text} pairs.
    final out = <Map<String, String>>[];
    for (final m in _messages) {
      // Skip the greeting + any error-only messages so they don't
      // confuse the model's "session language" / repetition checks.
      if (m.isError) continue;
      out.add({
        'role': m.fromUser ? 'user' : 'assistant',
        'text': m.body,
      });
    }
    return out;
  }

  Future<void> _pickAndSendImage() async {
    if (_sending) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;
    if (!mounted) return;

    final caption = _input.text.trim();
    final question =
        caption.isEmpty ? 'What is this? Help me with what you see.' : caption;
    _input.clear();
    setState(() {
      _messages.add(_Msg.user(
        caption.isEmpty ? '📎 ${picked.files.first.name}' : caption,
      ));
      _sending = true;
    });
    _scrollToBottom();

    final reply = await _tinker.askWithImage(
      image: File(path),
      sessionId: _sessionId,
      question: question,
      history: _historyForApi(),
    );
    if (!mounted) return;
    setState(() {
      if (reply == null) {
        _messages.add(_Msg.bot(
          "I couldn't process that image. Try a smaller JPG or PNG.",
          isError: true,
        ));
      } else {
        _messages.add(_Msg.bot(
          _fillShopName(reply.displayBody),
          logId: reply.logId,
          showActions: true,
          showSetApiKey: !_tinker.isConfigured || reply.authError,
        ));
      }
      _sending = false;
    });
    _scrollToBottom();
  }

  void _openHelpArticles() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HelpGuideScreen(
        api: widget.api,
        chat: widget.chat,
        realtime: widget.realtime,
        calls: widget.calls,
        lan: widget.lan,
        store: widget.store,
        info: widget.info,
      ),
    ));
  }

  /// Show a dialog to paste a tinker-chat tenant API key. Keys come
  /// from the tinker-chat admin panel (Settings → API keys →
  /// Regenerate) and are shaped `pk_live_<32+ chars>`. Persisted via
  /// [SessionStore] so the cashier doesn't have to re-enter on next
  /// launch; takes precedence over the build-time dart-define.
  Future<void> _setApiKey() async {
    final controller = TextEditingController(text: _tinker.apiKey);
    final key = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Tinker Chat API key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paste the tenant API key from the Tinker Chat admin '
              'panel (Settings → API keys). Looks like '
              '"pk_live_…".',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'pk_live_…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (key == null || key.isEmpty || !mounted) return;
    await _tinker.setApiKey(key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('API key saved. Try asking again.'),
      duration: Duration(seconds: 2),
    ));
    setState(() {});
  }

  /// Entry point behind the "Submit ticket" button. Instead of jumping
  /// straight into the ticket form, ask the cashier how they'd like to
  /// reach support: file a formal ticket, or just open a live chat with
  /// an agent (where they can also read their previous conversations).
  Future<void> _chooseSupportPath() async {
    // If support has already sent an unread message (the badge/banner the
    // cashier is reacting to), skip the picker and take them straight into the
    // live chat to read/reply — that's what they're tapping for.
    if (SupportNotifier.instance.hasUnread) {
      await _openSupportChat();
      return;
    }
    // A centered modal dialog (not a bottom sheet) — reads better on the
    // wide POS desktop and matches the rest of the app's dialogs.
    final choice = await showDialog<_SupportPath>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) =>
          _SupportPathDialog(unread: SupportNotifier.instance.unread),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _SupportPath.ticket:
        await _openTicketForm();
        break;
      case _SupportPath.chat:
        await _openSupportChat();
        break;
    }
  }

  /// Open the store's live support conversation directly — no ticket.
  /// Shows the full history (previous chats) and lets the cashier message
  /// an agent right away. Also the target of a tapped notification, so it
  /// foregrounds the window and no-ops if the chat is already open.
  Future<void> _openSupportChat() async {
    if (SupportNotifier.instance.chatOpen) return;
    // Opening the thread → hide the "Support sent you a message" banner; it
    // would otherwise linger over the chat (SnackBars float above the route).
    if (mounted) ScaffoldMessenger.of(context).clearSnackBars();
    if (kIsDesktopPlatform) {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    }
    SupportNotifier.instance.markAllRead();
    if (!mounted) return;
    // Re-engage support: if the last ticket is resolved, reopen it to 'new' so
    // an agent can accept + chat again (returning-customer flow). Returns the
    // current ticket, which we scope the chat to so it shows the right
    // waiting/active state instead of a read-only resolved thread.
    final ticket =
        await widget.chat.reopenSupportTicket(widget.info.conversationId);
    if (!mounted) return;
    final ticketNo = (ticket != null)
        ? int.tryParse((ticket['ticket_number'] ?? ticket['id'] ?? 0).toString())
        : null;
    final status = (ticket?['status'] ?? '').toString().toLowerCase();
    final claimed = status == 'in_progress' || status == 'assigned';
    final hasTicket = ticketNo != null && ticketNo > 0;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeChatScreen(
          api: widget.api,
          chat: widget.chat,
          realtime: widget.realtime,
          calls: widget.calls,
          lan: widget.lan,
          store: widget.store,
          info: widget.info,
          // Scope to the (re)active ticket so a fresh/unclaimed one shows the
          // "waiting for support to accept" card; a claimed one opens straight
          // into the chat. No ticket at all → ungated free chat as before.
          scopedTicketId: hasTicket ? ticketNo : null,
          initialAccepted: hasTicket ? claimed : true,
          onTicketClosed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  Future<void> _openTicketForm() async {
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

    // Same post-ticket flow HelpGuideScreen uses: drop a system note
    // into the live chat so admins see the ticket context, persist
    // the pending-ticket anchor, then route into the live chat.
    final ticketRef =
        outcome.ticketId != null ? ' ${fmtTicketNo(outcome.ticketId!)}' : '';
    final note = '🎫 Ticket$ticketRef submitted: "${outcome.subject}"\n'
        'Business: ${outcome.businessName} (${outcome.vatLabel})\n'
        'Priority: ${outcome.priority.toUpperCase()}';
    final sent = await widget.chat.send(
      convId: widget.info.conversationId,
      body: note,
      clientNonce: 'ai-${DateTime.now().microsecondsSinceEpoch}',
    );
    final anchorId = sent?.persistedId;
    if (anchorId != null && outcome.ticketId != null) {
      await widget.store.savePendingTicket(
        anchorMessageId: anchorId,
        ticketId: outcome.ticketId!,
      );
    }
    if (!mounted) return;
    Navigator.of(context).push(
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

  /// "Track ticket" — the employee types a ticket number they already
  /// have (e.g. one filed on the web). We look it up; if it's already
  /// claimed by an agent we drop them straight into the live chat,
  /// otherwise into the "waiting for support to accept" screen. A ticket
  /// not linked to this store's conversation is rejected (its accept /
  /// resolve events would never reach this app).
  ///
  /// The "Track ticket" header button is currently hidden (per request); this
  /// stays so it can be re-enabled by re-adding the _HeaderAction in _buildHeader.
  // ignore: unused_element
  Future<void> _trackTicket() async {
    final controller = TextEditingController();
    final numStr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Track a ticket'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a ticket number from this store\'s support to open its '
              'chat. Tickets filed elsewhere (e.g. the public web chat) can\'t '
              'be tracked here.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: '# ',
                hintText: 'e.g. 480312',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (numStr == null || numStr.isEmpty || !mounted) return;
    final id = int.tryParse(numStr.replaceAll(RegExp(r'[^0-9]'), ''));
    if (id == null || id <= 0) {
      _snack('Enter a valid ticket number.');
      return;
    }

    final detail = await TicketService(widget.api).getTicketDetail(id);
    if (!mounted) return;
    if (detail == null) {
      _snack('Ticket ${fmtTicketNo(id)} was not found.');
      return;
    }
    // A ticket already bound to a DIFFERENT live chat — e.g. the public web
    // login chatbox, which keeps its own standalone guest conversation —
    // can't be tracked here; its accept/resolve events would never reach
    // this app. A ticket with NO conversation yet (filed via the
    // customer-ticket web form) is fine — we open it as a fresh chat below.
    if (detail.conversationId != null &&
        detail.conversationId != widget.info.conversationId) {
      _snack(
          'Ticket ${fmtTicketNo(id)} was filed in a different chat and can\'t be tracked here.');
      return;
    }
    // A resolved/closed ticket has no live chat to join — its accept/reply
    // events are done. Don't open it; just tell the employee it's closed.
    if (detail.isResolved) {
      _snack(
          'Ticket ${fmtTicketNo(id)} is already resolved — nothing to open.');
      return;
    }
    // A ticket filed via the customer-ticket web form has no conversation
    // yet — adopt it into THIS store's thread so the admin can Accept/Resolve
    // it and those events reach this app. The server links the ticket and
    // posts its "🎫 submitted" bubble, which the scoped chat then anchors on.
    if (detail.conversationId == null) {
      final adopted = await TicketService(widget.api)
          .adoptTicket(detail.id, widget.info.conversationId);
      if (!mounted) return;
      if (!adopted) {
        _snack(
            'Couldn\'t open ticket ${fmtTicketNo(id)} right now. Please try again.');
        return;
      }
    }
    // Open into the support chat. The employee app always shows this store's
    // own thread, so we route there and scope to the ticket. Only a
    // brand-new (unclaimed) ticket lands on the waiting screen; a claimed
    // ticket opens straight into the chat.

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmployeeChatScreen(
          api: widget.api,
          chat: widget.chat,
          realtime: widget.realtime,
          calls: widget.calls,
          lan: widget.lan,
          store: widget.store,
          info: widget.info,
          scopedTicketId: id,
          // Anything past `new` opens straight into the chat; only an
          // unclaimed ticket shows the waiting-for-acceptance screen.
          initialAccepted: detail.isClaimed,
          initiallyResolved: detail.isResolved,
          onTicketClosed: (ctx) => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: Brand.stroke),
            Expanded(child: _buildMessages()),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'POS support',
          style: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Brand.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Chat with our AI assistant, anytime',
          style: text.bodySmall?.copyWith(color: Brand.textMuted),
        ),
        const SizedBox(height: 6),
        _buildSignedInAs(text),
      ],
    );

    // One source of truth for the header actions; rendered as labelled
    // buttons on wide screens and as an equal-width tile row on phones.
    final actions = <_HeaderAction>[
      _HeaderAction(
        icon: Icons.menu_book_outlined,
        label: 'Help articles',
        shortLabel: 'Help',
        onTap: _openHelpArticles,
      ),
      _HeaderAction(
        icon: Icons.headset_mic_outlined,
        label: 'Submit ticket',
        shortLabel: 'Submit',
        onTap: _chooseSupportPath,
        badge: SupportNotifier.instance.unread,
      ),
      // Desktop only — this is the device that generates the sync QR a
      // phone scans to sign in. The mobile build never shows it.
      if (kIsDesktopPlatform)
        _HeaderAction(
          icon: Icons.qr_code_2,
          label: 'Sync mobile',
          shortLabel: 'Sync',
          onTap: _openSyncMobile,
        ),
    ];

    List<Widget> spaced() {
      final out = <Widget>[];
      for (var i = 0; i < actions.length; i++) {
        if (i > 0) out.add(const SizedBox(width: 10));
        out.add(_HeaderButton(
          icon: actions[i].icon,
          label: actions[i].label,
          onTap: actions[i].onTap,
          badge: actions[i].badge,
        ));
      }
      return out;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
      color: Brand.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // On a phone the labelled buttons can't fit beside the title,
          // and a horizontally scrolling strip hides whatever falls off
          // the right edge. Instead show every action at once as an
          // equal-width tile row — nothing to discover by scrolling.
          if (constraints.maxWidth < 600) {
            final tiles = <Widget>[];
            for (var i = 0; i < actions.length; i++) {
              if (i > 0) tiles.add(const SizedBox(width: 8));
              tiles.add(Expanded(
                child: _MobileActionTile(
                  icon: actions[i].icon,
                  label: actions[i].shortLabel,
                  onTap: actions[i].onTap,
                  badge: actions[i].badge,
                ),
              ));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                Row(children: tiles),
              ],
            );
          }
          // Desktop / wide: title expands, buttons sit on the right.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: titleBlock),
              ...spaced(),
            ],
          );
        },
      ),
    );
  }

  void _openSyncMobile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SyncMobileScreen(api: widget.api, store: widget.store),
      ),
    );
  }

  /// "Signed in as {name} · Change" — lets the terminal be handed to a
  /// new operator (staff change) by editing just the person name; the
  /// store identity is untouched.
  Widget _buildSignedInAs(TextTheme text) {
    final name = widget.info.employeeName.trim();
    final label = name.isEmpty ? 'Set your name' : 'Signed in as $name';
    return InkWell(
      onTap: _editEmployeeName,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 14, color: Brand.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: text.bodySmall?.copyWith(
                color: Brand.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '· Change',
              style: text.bodySmall?.copyWith(
                color: Brand.signal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Edit the operator's full name (e.g. when a new employee takes over
  /// the terminal). Persists to SessionStore and updates the live
  /// EmployeeChatInfo so the greeting label and future tickets use the
  /// new name — no need to re-run store setup or re-enter the store name.
  Future<void> _editEmployeeName() async {
    final controller =
        TextEditingController(text: widget.info.employeeName.trim());
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Who is using this terminal?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the current employee\'s full name. This replaces '
                  'the previous name on new tickets — the store stays the '
                  'same.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Full name',
                    hintText: 'e.g. Maria Santos',
                    errorText: err,
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  onSubmitted: (_) {
                    if (controller.text.trim().isEmpty) {
                      setLocal(() => err = 'Enter a full name.');
                    } else {
                      Navigator.of(ctx).pop(controller.text.trim());
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final v = controller.text.trim();
                  if (v.isEmpty) {
                    setLocal(() => err = 'Enter a full name.');
                    return;
                  }
                  Navigator.of(ctx).pop(v);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    await widget.store.saveEmployeeFullName(newName);
    if (!mounted) return;
    setState(() => widget.info.employeeName = newName);
    // Push the new operator name to the server so the agent inbox shows
    // "Store — Employee" right away, not just on the next app launch.
    // Fire-and-forget: idempotent re-start, safe to ignore the result.
    final store = widget.info.storeName.trim();
    if (store.isNotEmpty) {
      unawaited(widget.chat.employeeStart(store, fullName: newName));
    }
    _snack('Now signed in as $newName');
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) return const _TypingIndicator();
        final m = _messages[i];
        if (m.fromUser) return _UserBubble(text: m.body);
        return _BotBubble(
          text: m.body,
          isError: m.isError,
          suggestions: m.showSuggestions ? _suggestions : const [],
          onSuggestion: _send,
          showActions: m.showActions,
          onOpenGuide: _openHelpArticles,
          onFileTicket: _openTicketForm,
          showSetApiKey: m.showSetApiKey,
          onSetApiKey: _setApiKey,
        );
      },
    );
  }

  Widget _buildComposer() {
    return Container(
      decoration: const BoxDecoration(
        color: Brand.canvas,
        border: Border(top: BorderSide(color: Brand.stroke)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Brand.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Brand.stroke),
            ),
            padding: const EdgeInsets.fromLTRB(20, 4, 6, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_sending,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 14, horizontal: 0),
                      filled: false,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Ask about refunds, Z reading, printers...',
                      hintStyle: TextStyle(color: Brand.textMuted),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Attach a screenshot',
                  icon: const Icon(Icons.attach_file,
                      color: Brand.textMuted, size: 22),
                  onPressed: _sending ? null : _pickAndSendImage,
                ),
                const SizedBox(width: 2),
                _SendButton(
                  enabled: !_sending,
                  onTap: () => _send(_input.text),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI can make mistakes, please verify important info with a real receipt',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Brand.textMuted, fontSize: 11.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Msg {
  _Msg.user(this.body)
      : fromUser = true,
        isError = false,
        showSuggestions = false,
        showActions = false,
        showSetApiKey = false,
        logId = null;

  _Msg.bot(
    this.body, {
    this.isError = false,
    this.showSuggestions = false,
    this.showActions = false,
    this.showSetApiKey = false,
    this.logId,
  }) : fromUser = false;

  final bool fromUser;
  final String body;
  final bool isError;
  final bool showSuggestions;
  final bool showActions;
  final bool showSetApiKey;
  final int? logId;
}

class _HeaderAction {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.shortLabel,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final String shortLabel;
  final VoidCallback onTap;

  /// Unread-count badge painted on the button (0 = none).
  final int badge;
}

/// Phone-width header action: icon stacked over a short label, sized by
/// the parent Row so every action stays visible without scrolling.
class _MobileActionTile extends StatelessWidget {
  const _MobileActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.canvas,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Brand.stroke),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconWithBadge(icon: icon, size: 20, badge: badge),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Brand.textPrimary,
                  fontSize: 12,
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

/// An icon with a small red unread-count badge in its top-right corner.
/// Badge hidden when [badge] is 0; caps the printed count at "9+".
class _IconWithBadge extends StatelessWidget {
  const _IconWithBadge({
    required this.icon,
    required this.size,
    required this.badge,
    this.color = Brand.signal,
  });

  final IconData icon;
  final double size;
  final int badge;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: size, color: color),
        if (badge > 0)
          Positioned(
            right: -6,
            top: -5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: Brand.danger,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Brand.canvas, width: 1.5),
              ),
              child: Text(
                badge > 9 ? '9+' : '$badge',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;

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
              _IconWithBadge(
                  icon: icon, size: 17, badge: badge, color: Brand.textPrimary),
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

class _BotAvatar extends StatelessWidget {
  const _BotAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: Brand.primary,
        borderRadius: BorderRadius.circular(17),
      ),
      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
    );
  }
}

class _BotBubble extends StatelessWidget {
  const _BotBubble({
    required this.text,
    required this.suggestions,
    required this.onSuggestion,
    required this.showActions,
    required this.onOpenGuide,
    required this.onFileTicket,
    required this.showSetApiKey,
    required this.onSetApiKey,
    this.isError = false,
  });

  final String text;
  final bool isError;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;
  final bool showActions;
  final VoidCallback onOpenGuide;
  final VoidCallback onFileTicket;
  final bool showSetApiKey;
  final VoidCallback onSetApiKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BotAvatar(),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    decoration: BoxDecoration(
                      color: Brand.canvas,
                      border: Border.all(
                        color: isError ? Brand.danger : Brand.stroke,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _RichBotBody(text: text),
                  ),
                ),
                if (suggestions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in suggestions)
                        _SuggestionChip(label: s, onTap: () => onSuggestion(s)),
                    ],
                  ),
                ],
                if (showActions) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ActionPill(
                        icon: Icons.menu_book_outlined,
                        label: 'Open full guide',
                        accent: true,
                        onTap: onOpenGuide,
                      ),
                      _ActionPill(
                        icon: Icons.headset_mic_outlined,
                        label: 'Still stuck? File a ticket',
                        onTap: onFileTicket,
                      ),
                      if (showSetApiKey)
                        _ActionPill(
                          icon: Icons.vpn_key_outlined,
                          label: 'Set API key',
                          onTap: onSetApiKey,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: Brand.signal,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RichBotBody extends StatelessWidget {
  const _RichBotBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    // Lightweight markdown-ish rendering: numbered lines ("1.", "2)")
    // and bullets ("- ", "• ", "* ") get formatted as indented list
    // items so the AI's answers look like the screenshot. Pulling in
    // a real markdown package felt heavy for the one feature we need.
    final lines = text.split('\n');
    final widgets = <Widget>[];
    final paragraph = StringBuffer();

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          paragraph.toString().trim(),
          style: const TextStyle(
            color: Brand.textPrimary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ));
      paragraph.clear();
    }

    final numRegex = RegExp(r'^\s*(\d+)[\.\)]\s+(.+)$');
    final bulletRegex = RegExp(r'^\s*[-•*]\s+(.+)$');

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flushParagraph();
        continue;
      }
      final num = numRegex.firstMatch(line);
      if (num != null) {
        flushParagraph();
        widgets.add(_listItem(marker: '${num.group(1)}.', body: num.group(2)!));
        continue;
      }
      final b = bulletRegex.firstMatch(line);
      if (b != null) {
        flushParagraph();
        widgets.add(_listItem(marker: '•', body: b.group(1)!));
        continue;
      }
      if (paragraph.isNotEmpty) paragraph.write(' ');
      paragraph.write(line);
    }
    flushParagraph();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );
  }

  Widget _listItem({required String marker, required String body}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              marker,
              style: const TextStyle(
                color: Brand.textPrimary,
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              body,
              style: const TextStyle(
                color: Brand.textPrimary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.canvas,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Brand.stroke),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Brand.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final bg = accent ? Brand.signal.withValues(alpha: 0.08) : Brand.canvas;
    final border = accent ? Brand.signal.withValues(alpha: 0.35) : Brand.stroke;
    final fg = accent ? Brand.signal : Brand.textPrimary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
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

class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: Brand.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Brand.signal.withValues(alpha: 0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child:
                const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BotAvatar(),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Brand.canvas,
              border: Border.all(color: Brand.stroke),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedBuilder(
              animation: _ctl,
              builder: (_, __) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _dot(0),
                    const SizedBox(width: 4),
                    _dot(1),
                    const SizedBox(width: 4),
                    _dot(2),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(int i) {
    final t = (_ctl.value + i * 0.18) % 1.0;
    final pulse = (sin(t * 2 * pi) + 1) / 2;
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: Brand.textMuted.withValues(alpha: 0.35 + pulse * 0.45),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Which path the cashier picked from the "how do you want to reach
/// support?" dialog.
enum _SupportPath { ticket, chat }

/// Centered modal dialog shown when the cashier taps "Submit ticket":
/// choose between filing a formal ticket or opening a live chat with an
/// agent (which also shows their previous conversations). The chat option
/// carries the unread badge so a waiting reply is obvious here too.
class _SupportPathDialog extends StatelessWidget {
  const _SupportPathDialog({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Brand.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Text(
                      'How can we help?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Brand.textPrimary,
                      ),
                    ),
                  ),
                  // Close affordance so the modal reads like a dialog.
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close,
                          size: 20, color: Brand.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'File a ticket for something that needs tracking, or chat with '
                'an agent now.',
                style: TextStyle(fontSize: 13, color: Brand.textMuted),
              ),
              const SizedBox(height: 18),
              _SupportPathCard(
                icon: Icons.confirmation_number_outlined,
                title: 'File a ticket',
                subtitle:
                    'Log an issue with priority — we\'ll track it to a fix.',
                onTap: () => Navigator.of(context).pop(_SupportPath.ticket),
              ),
              const SizedBox(height: 12),
              _SupportPathCard(
                icon: Icons.chat_bubble_outline,
                title: 'Chat with support',
                subtitle: 'Talk to an agent now and read your previous chats.',
                badge: unread,
                onTap: () => Navigator.of(context).pop(_SupportPath.chat),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportPathCard extends StatelessWidget {
  const _SupportPathCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.canvas,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Brand.stroke),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Brand.signal.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: _IconWithBadge(icon: icon, size: 22, badge: badge),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: Brand.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Brand.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Brand.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
