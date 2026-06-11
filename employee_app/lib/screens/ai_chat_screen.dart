import 'dart:async';
import 'dart:io' show File;
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/lan_presence.dart';
import '../services/session_store.dart';
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

  @override
  void initState() {
    super.initState();
    _seedGreeting();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static String _newSessionId() {
    // Lightweight, non-cryptographic — only used to group chat logs
    // tenant-side. Uses millisecond clock + a small random suffix.
    final r = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'emp-${DateTime.now().millisecondsSinceEpoch}-$r';
  }

  Future<void> _seedGreeting() async {
    final first = _firstName(widget.info.storeName);
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
    final question = caption.isEmpty
        ? 'What is this? Help me with what you see.'
        : caption;
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
            onPressed: () =>
                Navigator.of(ctx).pop(controller.text.trim()),
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

  Future<void> _submitTicket() async {
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
              'Enter the ticket number you were given (e.g. a ticket you '
              'filed on the web). We\'ll open its support chat.',
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
              onSubmitted: (_) =>
                  Navigator.of(ctx).pop(controller.text.trim()),
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
    // A resolved/closed ticket has no live chat to join — its accept/reply
    // events are done. Don't open it; just tell the employee it's closed.
    if (detail.isResolved) {
      _snack('Ticket ${fmtTicketNo(id)} is already resolved — nothing to open.');
      return;
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
        icon: Icons.confirmation_number_outlined,
        label: 'Track ticket',
        shortLabel: 'Track',
        onTap: _trackTicket,
      ),
      _HeaderAction(
        icon: Icons.headset_mic_outlined,
        label: 'Submit ticket',
        shortLabel: 'Submit',
        onTap: _submitTicket,
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
          onFileTicket: _submitTicket,
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
  });

  final IconData icon;
  final String label;
  final String shortLabel;
  final VoidCallback onTap;
}

/// Phone-width header action: icon stacked over a short label, sized by
/// the parent Row so every action stays visible without scrolling.
class _MobileActionTile extends StatelessWidget {
  const _MobileActionTile({
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
              Icon(icon, size: 20, color: Brand.signal),
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

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
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
    final bg = accent
        ? Brand.signal.withValues(alpha: 0.08)
        : Brand.canvas;
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
            child: const Icon(Icons.arrow_upward,
                color: Colors.white, size: 20),
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
