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
/// their store + chat session. The intent is to let employees self-
/// serve common questions (use the app, file a ticket, request a
/// remote session, etc.) so support's chat queue stays focused on
/// genuinely-new problems. The two CTAs at the bottom cover the
/// escape hatches:
///
/// * Contact Support → pushes the existing TicketFormScreen, posts a
///   confirmation note into the chat thread once submitted, and then
///   replaces the route with EmployeeChatScreen so the user lands on
///   the freshly-created ticket conversation.
/// * Open Chat → straight pass-through to EmployeeChatScreen for the
///   power-user who already knows the app and wants the thread.
class HelpGuideScreen extends StatelessWidget {
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

  /// Article-style content the FAQ list renders. Each entry is a
  /// (title, body) pair; body is plain text so it stays editable
  /// without hunting through Widget tree changes. Kept compact —
  /// employees with the patience to read every word probably aren't
  /// the ones who need to hit Contact Support anyway.
  static const _articles = <(String, String)>[
    (
      'Welcome — what is this app?',
      'TinkerPro Employee is your direct line to TinkerPro support.\n\n'
          'Use the chat to talk to support, share screenshots and videos, '
          'place voice/video calls, request remote access, and file tickets.'
    ),
    (
      'File a support ticket (/ticket)',
      'In the chat, type /ticket and press Send. A form opens where you '
          'fill in your name, the issue and a priority. When you submit, a '
          'ticket bubble appears in chat and support is notified instantly.\n\n'
          'You can also use the "Contact Support" button below — same form, '
          'no need to type the command.'
    ),
    (
      'Request a remote session (/request)',
      'Type /request in the chat to ask an admin to take over your screen. '
          'Once an admin confirms, you will see an Allow / Deny prompt — '
          'tap Allow to start. Only you (the requester) see the prompt; '
          'colleagues on the same conversation just see the request as text.'
    ),
    (
      'Send screenshots, files and videos',
      'Tap the paperclip on the composer to attach files. You can select '
          'multiple at once. Previews appear above the composer with a per-'
          'file progress bar while uploading. Up to 200 MB per file.\n\n'
          'Multiple images in one message collapse into a single stack — tap '
          'to flip through with arrow keys or the on-screen chevrons.'
    ),
    (
      'Call support (voice / video)',
      'Tap the phone or video icon in the chat header to ring every admin '
          'on the support team at once. The first admin to answer takes the '
          'call; the others stop ringing. Your colleagues on the same '
          'conversation see a "call in progress" banner so they do not '
          'fire a competing call.'
    ),
    (
      'Reply to a message · Delete · Unsend',
      'Hover a message and click the ⋮ to open the action menu.\n\n'
          '• Reply quotes the original above your reply (clickable to jump).\n'
          '• Delete for me hides the message on your machine only.\n'
          '• Unsend removes it for everyone — only available before anyone '
          'else has read the message.'
    ),
    (
      'Still stuck?',
      'If none of the above answers your question, tap "Contact Support" '
          'below. We will reach out in chat as soon as we see your ticket.'
    ),
  ];

  Future<void> _contactSupport(BuildContext context) async {
    final tickets = TicketService(api);
    final outcome = await Navigator.of(context).push<TicketSubmitOutcome>(
      MaterialPageRoute(
        builder: (_) => TicketFormScreen(
          tickets: tickets,
          info: info,
          store: store,
          api: api,
        ),
      ),
    );
    if (outcome == null || !context.mounted) return;

    // Mirror the chat_screen-side /ticket flow: post a ticket-
    // confirmation bubble so support sees the ticket land live.
    final ticketRef = outcome.ticketId != null ? ' #${outcome.ticketId}' : '';
    final note = '🎫 Ticket$ticketRef submitted: "${outcome.subject}"\n'
        'Business: ${outcome.businessName} (${outcome.vatLabel})\n'
        'Priority: ${outcome.priority.toUpperCase()}';
    await chat.send(
      convId: info.conversationId,
      body: note,
      clientNonce: 'help-${DateTime.now().microsecondsSinceEpoch}',
    );

    if (!context.mounted) return;
    // Replace (don't push) so a back button doesn't dump the employee
    // back on the help screen mid-conversation.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _chatScreen(),
      ),
    );
  }

  EmployeeChatScreen _chatScreen() => EmployeeChatScreen(
        api: api,
        chat: chat,
        realtime: realtime,
        calls: calls,
        lan: lan,
        store: store,
        info: info,
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Brand.surface,
      appBar: AppBar(
        title: const Text('Help & Guide'),
        backgroundColor: Brand.canvas,
        foregroundColor: Brand.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                children: [
                  _buildHero(text),
                  const SizedBox(height: 20),
                  ..._articles.map((a) => _buildArticle(a.$1, a.$2, text)),
                ],
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
                  onPressed: () => _contactSupport(context),
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
          const Icon(Icons.lightbulb_outline,
              color: Colors.white, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, ${info.storeName}',
                  style: text.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Quick answers to the most common questions live below. '
                  'If something is not covered, tap Contact Support and '
                  'we will reach out in chat right away.',
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
