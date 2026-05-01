import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/customer_models.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/chat_realtime.dart';
import '../services/chat_service.dart';
import '../services/ringtone_service.dart';
import '../theme.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'feedback_screen.dart';
import 'login_screen.dart';

/// "REGISTERED CLIENT ACCESS" landing screen.
///
/// Visual hierarchy (top → bottom):
///   1. Hero band — black with orange brand accent on the customer's name
///   2. Status card — read-only registration details with status pip
///   3. Primary CTA — "Open Support Chat" (big orange gradient button)
///   4. Secondary actions — Feedback, Sign out (subtle row)
///
/// Download BIR PDF and Notes are intentionally not surfaced — they're
/// scoped out for v1 (placeholder data + half-wired endpoints). When the
/// underlying flows are real, drop them back in as additional tiles.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.auth,
    required this.initialCustomer,
  });

  final AuthService auth;
  final Customer initialCustomer;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Customer _customer;
  bool _refreshing = false;

  // Long-lived chat plumbing — owned by the dashboard so the customer
  // keeps receiving messages and incoming calls even when they're not
  // actively in the chat thread.
  late final ChatService _chat;
  late final ChatRealtimeService _realtime;
  CallService? _calls;
  PortalGroupInfo? _portalInfo;
  bool _callScreenOpen = false;
  bool _chatScreenOpen = false;
  StreamSubscription<dynamic>? _pingSub;

  @override
  void initState() {
    super.initState();
    _customer = widget.initialCustomer;
    _chat = ChatService(widget.auth.api);
    _realtime = ChatRealtimeService(widget.auth.api);
    _bootstrapChatPlumbing();
  }

  Future<void> _bootstrapChatPlumbing() async {
    PortalGroupInfo? info;
    try {
      info = await _chat.portalGroup();
    } catch (e) {
      debugPrint('[bootstrap] chat.portalGroup threw: $e');
    }
    if (!mounted) return;
    if (info == null) {
      // Most common reason: no portal session (customer not logged in
      // via TIN), or chat.portalGroup returned success:false. Surface
      // it so we don't sit forever on "warming up" with no clue why.
      debugPrint('[bootstrap] chat.portalGroup returned null — '
          'check that the customer is logged in (TIN + branch).');
      return;
    }
    _portalInfo = info;
    final meId = info.meId;
    try {
      await _realtime.connect(
          shadowUserId: meId, conversationId: info.conversationId);
    } catch (e) {
      debugPrint('[bootstrap] realtime.connect threw: $e — '
          'check Soketi (host=${widget.auth.api.baseUrl}).');
    }
    _calls = CallService(
      realtime: _realtime,
      chat: _chat,
      shadowUserId: meId,
    );
    _calls!.addListener(_onCallChange);
    // Ping on incoming chat messages even when the customer isn't on the
    // chat screen — the chat screen has its own ping that handles the
    // foreground case. ChatScreen filters on senderId; do the same here.
    _pingSub = _realtime.messageEvents.listen((m) {
      // Skip when the chat screen is foregrounded — its own listener
      // pings, and we'd otherwise double-ring on the same event.
      if (_chatScreenOpen) return;
      if (m.senderId != meId) {
        unawaited(RingtoneService.instance.ping());
      }
    });
    setState(() {});
  }

  void _onCallChange() {
    final c = _calls;
    if (c == null || !mounted) return;
    if (c.isActive && !_callScreenOpen) {
      _callScreenOpen = true;
      Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => CallScreen(calls: c),
          ))
          .whenComplete(() => _callScreenOpen = false);
    }
  }

  @override
  void dispose() {
    _pingSub?.cancel();
    _calls?.removeListener(_onCallChange);
    _calls?.dispose();
    _realtime.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final fresh = await widget.auth.restoreSession();
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      if (fresh != null) _customer = fresh;
    });
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign out'),
        content: const Text(
            'You\'ll need to enter your TIN again to sign back in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Brand.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(auth: widget.auth)),
      (_) => false,
    );
  }

  void _openFeedback() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FeedbackScreen(
        api: widget.auth.api,
        customer: _customer,
      ),
    ));
  }

  void _openChat() {
    _chatScreenOpen = true;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => ChatScreen(
            api: widget.auth.api,
            customer: _customer,
            chat: _chat,
            realtime: _realtime,
            calls: _calls,
            portalInfo: _portalInfo,
            store: widget.auth.store,
          ),
        ))
        .whenComplete(() => _chatScreenOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Brand.surface,
        body: SafeArea(
          top: false, // hero extends to the top edge
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: Brand.signal,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _Hero(
                  customer: _customer,
                  refreshing: _refreshing,
                ),
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _StatusCard(customer: _customer),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PrimaryCta(onTap: _openChat),
                      const SizedBox(height: 12),
                      _SecondaryRow(
                        hasFeedback: _customer.hasFeedback,
                        onFeedback: _openFeedback,
                        onLogout: _logout,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero ────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({required this.customer, required this.refreshing});
  final Customer customer;
  final bool refreshing;

  String get _firstName {
    final n = customer.firstName.trim();
    return n.isEmpty ? 'Client' : n;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topInset + 18, 20, 56),
      decoration: BoxDecoration(
        gradient: Brand.hero,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: Brand.primary,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Brand.signalGlow(0.36),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.key, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              const Text(
                'REGISTERED CLIENT ACCESS',
                style: TextStyle(
                  color: Brand.signal,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              if (refreshing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Brand.signal,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 26),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Welcome back,\n',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 26,
                    height: 1.15,
                    letterSpacing: -0.4,
                  ),
                ),
                TextSpan(
                  text: _firstName.toUpperCase(),
                  style: const TextStyle(
                    color: Brand.signal,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Brand.signal,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Status: ${customer.statusLabel}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Status card ─────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Brand.stroke),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Brand.signalGlow(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.business_outlined,
                    size: 16, color: Brand.signal),
              ),
              const SizedBox(width: 8),
              const Text(
                'YOUR REGISTRATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Brand.textMuted,
                  letterSpacing: 1.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // TIN + Owner intentionally hidden from the customer-facing
          // dashboard — they're sensitive identifiers and the customer
          // already entered the TIN to log in. Business Name + Address
          // are enough to confirm "this is my registration" at a glance.
          _DetailRow(
            label: 'Business Name',
            value: customer.companyName,
            isFirst: true,
          ),
          _DetailRow(
            label: 'Address',
            value: customer.address,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isFirst = false,
    this.isLast = false,
  });
  final String label;
  final String value;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : const BorderSide(color: Brand.subtle, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Brand.textMuted,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Brand.textPrimary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Primary call-to-action ──────────────────────────────────────────────

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            gradient: Brand.primary,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Brand.signalGlow(0.34),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Open Support Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: -0.1,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Message or call our admin team directly.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Secondary actions row ───────────────────────────────────────────────

class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({
    required this.hasFeedback,
    required this.onFeedback,
    required this.onLogout,
  });
  final bool hasFeedback;
  final VoidCallback onFeedback;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MutedAction(
            icon: hasFeedback
                ? Icons.check_circle_outline
                : Icons.star_outline_rounded,
            label: hasFeedback ? 'Feedback Sent' : 'Share Feedback',
            onTap: onFeedback,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MutedAction(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            onTap: onLogout,
            danger: true,
          ),
        ),
      ],
    );
  }
}

class _MutedAction extends StatelessWidget {
  const _MutedAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? Brand.danger : Brand.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Brand.canvas,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: danger ? Brand.danger.withValues(alpha: 0.35) : Brand.stroke,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
