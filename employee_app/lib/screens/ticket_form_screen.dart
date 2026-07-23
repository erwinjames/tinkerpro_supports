import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api_client.dart';
import '../platform_info.dart';
import '../services/chat_service.dart' show EmployeeChatInfo;
import '../services/pos_shop_service.dart';
import '../services/session_store.dart';
import '../services/ticket_service.dart';
import '../theme.dart';

/// "Submit a ticket" screen — opened from the AI chat / Help guide /
/// `/ticket` chat command. Mirrors the marketing-site mock: a flat
/// header bar, two-up Subject/Category, four-tile Priority strip, large
/// description, optional screenshot attachment, and a read-only
/// "Included with this ticket" card showing the metadata that gets
/// stamped on the ticket automatically (tenant, branch, terminal IP,
/// user, app version, OS).
///
/// All the existing POS shop-info loading + manual setup logic is
/// preserved — it's just no longer the dominant UI element. Business
/// name and VAT label flow into the metadata card; the cashier never
/// types them.
class TicketFormScreen extends StatefulWidget {
  const TicketFormScreen({
    super.key,
    required this.tickets,
    required this.info,
    required this.store,
    required this.api,
  });

  final TicketService tickets;
  final EmployeeChatInfo info;
  final SessionStore store;
  final ApiClient api;

  @override
  State<TicketFormScreen> createState() => _TicketFormScreenState();
}

class _TicketFormScreenState extends State<TicketFormScreen> {
  // App version is shown in the "Included with this ticket" card.
  // Hardcoded to dodge a `package_info_plus` dependency for one string;
  // bump it when pubspec.yaml's version bumps.
  static const String _appVersion = '1.0.0';

  // Static category list — no backend column yet, the selected value is
  // prepended into the description so agents still see which bucket the
  // cashier picked. Order mirrors how often we see them in real tickets.
  static const List<String> _categories = [
    'Reports and reading',
    'Payments and refunds',
    'Hardware (printer, scanner, terminal)',
    'Inventory and products',
    'Sync and connectivity',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();

  String _priority = 'medium'; // low | medium | high | urgent
  String? _category;
  PlatformFile? _attachment;

  bool _loadingShop = true;
  bool _submitting = false;
  ShopInfo? _shop;
  String? _shopError;
  String _shopSource = 'pending';
  String _shopProgress = '';
  late final PosShopService _posShop = PosShopService(store: widget.store);

  // Auto-detected local IPv4 — shown as the "Terminal" line. Pulled
  // once on initState; null while resolving / when no usable interface
  // exists (rare on a POS box but possible in headless dev).
  String? _terminalIp;

  // Manual-setup panel — appears in the metadata card slot the very
  // first time /ticket runs on a fresh install before any admin has
  // pinned a POS host. After a successful Connect the host+port are
  // saved and we never show this panel again.
  bool _needsSetup = false;
  final _setupHost = TextEditingController();
  final _setupPort = TextEditingController(text: '3306');
  bool _setupBusy = false;
  String? _setupError;

  // Standalone install (installer "Standalone" mode): this PC is both
  // the POS server and the only register. We only ever look at the
  // local XAMPP; when there isn't one we ask for the shop name alone —
  // no host/port, no VAT/TIN — and remember it.
  late final bool _standalone = widget.store.isPosStandalone;
  bool _needsShopName = false;
  final _shopName = TextEditingController();
  bool _shopNameBusy = false;
  String? _shopNameError;

  /// Periodic silent retry while we're sitting on cached / fallback data.
  /// Heals a transient LAN / DB hiccup without forcing the user to tap
  /// Retry. Cancelled the moment we hit live POS data or the screen is
  /// disposed. 15s cadence keeps the noise low.
  Timer? _silentRetryTimer;
  static const _silentRetryInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _resolveTerminalIp();
    // Mobile (QR-synced phone): there is no local POS database to read, and
    // the store identity already came from the sync QR. Skip all POS
    // discovery / "server setup" and just attach the store name.
    if (kIsMobilePlatform) {
      _shop = ShopInfo(
        businessName: widget.store.storeName ?? '',
        vatReg: 0,
        vatLabel: '',
        tin: '',
        email: '',
        fullName: '',
      );
      _loadingShop = false;
      _needsSetup = false;
      return;
    }
    final cached = widget.store.cachedShop;
    final hasManual = widget.store.hasPosManualTarget;

    // Standalone: only ever probe the local XAMPP. Show cached shop
    // instantly if we have one (and silently re-read the local DB),
    // otherwise run the local-only lookup which either finds the local
    // POS, reuses a previously-typed shop name, or asks for one.
    if (_standalone) {
      if (cached != null) {
        _shop = ShopInfo(
          businessName: cached.businessName.isNotEmpty
              ? cached.businessName
              : (widget.store.storeName ?? ''),
          vatReg: cached.vatReg,
          vatLabel: cached.vatLabel,
          tin: cached.tin,
          email: cached.email,
          fullName: cached.fullName,
        );
        _shopSource = 'cache';
        _loadingShop = false;
        _loadShop(silent: true);
      } else {
        _loadShop();
      }
      return;
    }

    if (cached != null) {
      _shop = ShopInfo(
        businessName: cached.businessName.isNotEmpty
            ? cached.businessName
            : (widget.store.storeName ?? ''),
        vatReg: cached.vatReg,
        vatLabel: cached.vatLabel,
        tin: cached.tin,
        email: cached.email,
        fullName: cached.fullName,
      );
      _shopSource = 'cache';
      _loadingShop = false;
      if (hasManual) {
        _loadShop(silent: true);
        _startSilentRetryTimer();
      }
    } else if (hasManual) {
      _loadShop();
    } else {
      _loadingShop = false;
      _needsSetup = true;
    }
  }

  @override
  void dispose() {
    _silentRetryTimer?.cancel();
    _subject.dispose();
    _description.dispose();
    _setupHost.dispose();
    _setupPort.dispose();
    _shopName.dispose();
    super.dispose();
  }

  Future<void> _resolveTerminalIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      String? best;
      for (final i in ifaces) {
        for (final a in i.addresses) {
          final ip = a.address;
          if (ip.isEmpty) continue;
          // Prefer the first non-loopback IPv4 — that's the LAN address
          // the cashier and the support agent will use to talk about
          // "this terminal."
          best = ip;
          break;
        }
        if (best != null) break;
      }
      if (!mounted) return;
      setState(() => _terminalIp = best);
    } catch (_) {
      // Permissions / sandboxing on some platforms; metadata card just
      // shows "—" for the IP. Not worth surfacing.
    }
  }

  void _startSilentRetryTimer() {
    _silentRetryTimer?.cancel();
    _silentRetryTimer = Timer.periodic(_silentRetryInterval, (_) {
      if (!mounted) return;
      if (_shopSource == 'pos') return;
      if (!widget.store.hasPosManualTarget) return;
      _loadShop(silent: true);
    });
  }

  void _stopSilentRetryTimer() {
    _silentRetryTimer?.cancel();
    _silentRetryTimer = null;
  }

  Future<void> _loadShop({bool silent = false}) async {
    if (_standalone) {
      await _loadStandaloneShop(silent: silent);
      return;
    }
    if (!silent) {
      setState(() {
        _loadingShop = true;
        _shopError = null;
        _shopSource = 'pending';
        _shopProgress = 'Looking for the POS server…';
      });
    }
    final apiHost = _hostFromBaseUrl(widget.api.baseUrl);
    final hints = <String>[if (apiHost != null) apiHost];
    final pos = await _posShop.getShopInfo(
      hintHosts: hints,
      manualHost: widget.store.posManualHost,
      manualPort: widget.store.posManualPort,
      onProgress: silent
          ? null
          : (s) {
              if (!mounted) return;
              setState(() => _shopProgress = s);
            },
    );

    ShopInfo? fallback;
    if (pos == null && !silent) {
      fallback = await widget.tickets.getShopInfo();
    }
    if (!mounted) return;

    if (silent) {
      if (pos == null) return;
      final businessName = pos.businessName.isNotEmpty
          ? pos.businessName
          : (widget.store.storeName ?? '');
      final refreshed = ShopInfo(
        businessName: businessName,
        vatReg: pos.vatReg,
        vatLabel: pos.vatLabel,
        tin: pos.tin,
        email: '',
        fullName: '',
      );
      await widget.store.saveCachedShop(refreshed);
      if (!mounted) return;
      final current = _shop;
      if (current == null || !current.sameValuesAs(refreshed)) {
        setState(() {
          _shop = refreshed;
          _shopSource = 'pos';
          _shopError = null;
        });
      } else if (_shopSource != 'pos') {
        setState(() => _shopSource = 'pos');
      }
      _stopSilentRetryTimer();
      return;
    }

    setState(() {
      _loadingShop = false;
      if (pos == null && fallback == null) {
        _shop = null;
        _shopSource = 'none';
        final posErr = _posShop.lastError;
        _shopError = posErr == null
            ? 'Could not read shop info from the POS database.'
            : 'Could not read shop info from the POS database ($posErr).';
        return;
      }
      if (pos == null && fallback != null) {
        _shop = ShopInfo(
          businessName: fallback.businessName.isNotEmpty
              ? fallback.businessName
              : (widget.store.storeName ?? ''),
          vatReg: fallback.vatReg,
          vatLabel: fallback.vatLabel,
          tin: fallback.tin,
          email: fallback.email,
          fullName: fallback.fullName,
        );
        _shopSource = 'fallback';
        _shopError = null;
        _startSilentRetryTimer();
        return;
      }
      final resolvedPos = pos!;
      final businessName = resolvedPos.businessName.isNotEmpty
          ? resolvedPos.businessName
          : (widget.store.storeName ?? '');
      _shop = ShopInfo(
        businessName: businessName,
        vatReg: resolvedPos.vatReg,
        vatLabel: resolvedPos.vatLabel,
        tin: resolvedPos.tin,
        email: '',
        fullName: '',
      );
      _shopSource = 'pos';
      _shopError = null;
    });

    if (pos != null) {
      await widget.store.saveCachedShop(_shop!);
      _stopSilentRetryTimer();
    }
  }

  /// Standalone lookup: probe only the local XAMPP. On success use the
  /// shop row; on failure fall back to a previously-saved shop name, or
  /// (first run, no local DB) surface the shop-name-only form. Never
  /// shows a POS/DB error — "no local XAMPP is okay."
  Future<void> _loadStandaloneShop({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingShop = true;
        _shopError = null;
        _needsShopName = false;
        _shopSource = 'pending';
        _shopProgress = 'Looking for the local POS database…';
      });
    }

    final pos = await _posShop.getLocalShopInfo(
      onProgress: silent
          ? null
          : (s) {
              if (!mounted) return;
              setState(() => _shopProgress = s);
            },
    );
    if (!mounted) return;

    final posName = (pos?.businessName ?? '').trim();
    if (pos != null && posName.isNotEmpty) {
      final refreshed = ShopInfo(
        businessName: posName,
        vatReg: pos.vatReg,
        vatLabel: pos.vatLabel,
        tin: pos.tin,
        email: '',
        fullName: '',
      );
      await widget.store.saveCachedShop(refreshed);
      if (!mounted) return;
      setState(() {
        _loadingShop = false;
        _shop = refreshed;
        _shopSource = 'pos';
        _shopError = null;
        _needsShopName = false;
      });
      return;
    }

    // No readable local POS. On a silent background re-check, leave the
    // current view (cached shop / typed name) untouched.
    if (silent) return;

    final savedName = (widget.store.storeName ?? '').trim();
    if (savedName.isNotEmpty) {
      final info = ShopInfo(
        businessName: savedName,
        vatReg: 0,
        vatLabel: 'Non-VAT',
        tin: '',
        email: '',
        fullName: '',
      );
      setState(() {
        _loadingShop = false;
        _shop = info;
        _shopSource = 'manual-name';
        _shopError = null;
        _needsShopName = false;
      });
      return;
    }

    // First run, no local XAMPP and no saved name — ask for the shop
    // name (and nothing else).
    _shopName.text = savedName;
    setState(() {
      _loadingShop = false;
      _shop = null;
      _shopError = null;
      _needsShopName = true;
    });
  }

  /// Save the standalone shop name and adopt it as the ticket's
  /// business identity. No VAT/TIN/host — a standalone shop only needs
  /// its name on the ticket.
  Future<void> _saveShopName() async {
    final name = _shopName.text.trim();
    if (name.isEmpty) {
      setState(() => _shopNameError = 'Enter your shop name.');
      return;
    }
    setState(() {
      _shopNameBusy = true;
      _shopNameError = null;
    });
    await widget.store.saveStoreName(name);
    final info = ShopInfo(
      businessName: name,
      vatReg: 0,
      vatLabel: 'Non-VAT',
      tin: '',
      email: '',
      fullName: '',
    );
    await widget.store.saveCachedShop(info);
    if (!mounted) return;
    setState(() {
      _shopNameBusy = false;
      _needsShopName = false;
      _shop = info;
      _shopSource = 'manual-name';
      _shopError = null;
    });
  }

  Future<void> _saveSetupAndConnect() async {
    final host = _setupHost.text.trim();
    final portText = _setupPort.text.trim();
    final port = int.tryParse(portText);
    if (host.isEmpty) {
      setState(() => _setupError = 'Enter the POS server host (IP or hostname).');
      return;
    }
    if (port == null || port <= 0 || port > 65535) {
      setState(() => _setupError = 'Enter a valid port (1–65535). Default is 3306.');
      return;
    }
    setState(() {
      _setupBusy = true;
      _setupError = null;
    });
    final result = await _posShop.getShopInfo(
      manualHost: host,
      manualPort: port,
    );
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _setupBusy = false;
        _setupError = _posShop.lastError ?? 'Connect failed. Check host/port.';
      });
      return;
    }
    final adopted = ShopInfo(
      businessName: result.businessName.isNotEmpty
          ? result.businessName
          : (widget.store.storeName ?? ''),
      vatReg: result.vatReg,
      vatLabel: result.vatLabel,
      tin: result.tin,
      email: result.email,
      fullName: result.fullName,
    );
    await widget.store.setPosManualTarget(host, port);
    await widget.store.saveCachedShop(adopted);
    if (!mounted) return;
    setState(() {
      _setupBusy = false;
      _needsSetup = false;
      _shop = adopted;
      _shopSource = 'pos';
      _shopError = null;
    });
  }

  void _setupTryAutoDiscover() {
    setState(() {
      _needsSetup = false;
      _setupError = null;
    });
    _loadShop();
  }

  String? _hostFromBaseUrl(String url) {
    try {
      final h = Uri.parse(url).host;
      return h.isEmpty ? null : h;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    // 10 MB cap matches the backend; reject early so we don't waste an
    // upload round-trip on a too-large file.
    if (f.size > 10 * 1024 * 1024) {
      _toast('That image is too large (10 MB max).');
      return;
    }
    setState(() => _attachment = f);
  }

  void _clearAttachment() {
    setState(() => _attachment = null);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final shop = _shop;
    if (shop == null) {
      _toast('Shop info is still loading.');
      return;
    }
    setState(() => _submitting = true);
    final attachmentPath = _attachment?.path;
    final result = await widget.tickets.createTicket(
      // Cashier no longer types their name — the chat identity is the
      // canonical "who sent this ticket" value.
      customerName: widget.info.meName,
      customerEmail: '',
      businessName: shop.businessName,
      vatReg: shop.vatReg,
      subject: _subject.text.trim(),
      description: _description.text.trim(),
      priority: _priority,
      category: _category,
      attachment: attachmentPath != null ? File(attachmentPath) : null,
      conversationId: widget.info.conversationId,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.ok) {
      Navigator.of(context).pop<TicketSubmitOutcome>(TicketSubmitOutcome(
        ticketId: result.ticketId,
        subject: _subject.text.trim(),
        priority: _priority,
        businessName: shop.businessName,
        vatLabel: shop.vatLabel,
      ));
    } else {
      _toast(result.message);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final wide = w >= 720.0;
          // On a real desktop monitor split into two columns so the whole
          // ticket fits in view with little or no scrolling. Below this we
          // fall back to the single stacked column (small windows / mobile).
          final twoCol = w >= 1000.0;
          final double pad = !wide ? 18.0 : (w >= 1600.0 ? 48.0 : 32.0);
          final double avail =
              (w - pad * 2).clamp(280.0, double.infinity).toDouble();
          // The form is laid out at a fixed "base" design width, then ZOOMED
          // UP proportionally once the screen is wider than that — so on a
          // big / ultrawide monitor the whole UI (text, cards, spacing)
          // scales instead of staying small with empty side margins. Below
          // the base width it renders 1:1 and just fills the available width.
          const double baseTwoCol = 1560.0;
          const double baseSingle = 860.0;
          const double maxZoom = 1.4;
          final bool zoom = twoCol && avail > baseTwoCol;
          final double scale =
              zoom ? (avail / baseTwoCol).clamp(1.0, maxZoom).toDouble() : 1.0;
          final double contentWidth =
              !twoCol ? baseSingle : (zoom ? baseTwoCol : avail);
          return SafeArea(
            child: Column(
              children: [
                Container(
                  color: Brand.canvas,
                  child: _buildHeaderBar(pad: pad),
                ),
                const _Divider(),
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: LayoutBuilder(
                      builder: (context, viewport) {
                        const vPad = 24.0 + 24.0;
                        return SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(pad, 24, pad, 24),
                          child: ConstrainedBox(
                            // Fill at least the viewport so the content can be
                            // vertically centred — kills the big empty band at
                            // the bottom on a desktop monitor — while still
                            // scrolling on short windows.
                            constraints: BoxConstraints(
                                minHeight: viewport.maxHeight - vPad),
                            child: Center(
                              child: scale == 1.0
                                  ? ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: contentWidth),
                                      child: _buildFormBody(
                                          wide: wide, twoCol: twoCol),
                                    )
                                  : SizedBox(
                                      // Reserve the scaled footprint so the
                                      // scroll view + vertical centring know
                                      // the real (zoomed) size.
                                      width: contentWidth * scale,
                                      child: FittedBox(
                                        fit: BoxFit.fitWidth,
                                        alignment: Alignment.topCenter,
                                        child: SizedBox(
                                          width: contentWidth,
                                          child: _buildFormBody(
                                              wide: wide, twoCol: twoCol),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const _Divider(),
                Container(
                  color: Brand.canvas,
                  child: _buildFooterBar(pad: pad),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Form body (responsive 1 / 2 column) ────────────────────────────────

  Widget _buildFormBody({required bool wide, required bool twoCol}) {
    final issueCard = _SectionCard(
      icon: Icons.subject_rounded,
      title: 'Issue details',
      subtitle: 'A clear subject helps us route this faster.',
      child: _buildSubjectAndCategory(wide: wide),
    );
    final priorityCard = _SectionCard(
      icon: Icons.flag_outlined,
      title: 'Priority',
      subtitle: 'How urgent is this for the store?',
      child: _buildPriority(),
    );
    final describeCard = _SectionCard(
      icon: Icons.edit_note_rounded,
      title: 'Describe the issue',
      titleRequired: true,
      subtitle: 'The more detail, the quicker we can help.',
      child: _buildDescription(),
    );
    final attachmentCard = _SectionCard(
      icon: Icons.attach_file_rounded,
      title: 'Attachment',
      titleTrailing: 'OPTIONAL',
      child: _buildAttachment(),
    );
    final includedCard = _buildIncludedCard();

    if (!twoCol) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          issueCard,
          const SizedBox(height: 16),
          priorityCard,
          const SizedBox(height: 16),
          describeCard,
          const SizedBox(height: 16),
          attachmentCard,
          const SizedBox(height: 16),
          includedCard,
          const SizedBox(height: 4),
        ],
      );
    }

    // Desktop: the main filling-out flow on the left, supporting cards
    // (attach + the read-only auto-included metadata) on the right.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 60,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              issueCard,
              const SizedBox(height: 16),
              priorityCard,
              const SizedBox(height: 16),
              describeCard,
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              attachmentCard,
              const SizedBox(height: 16),
              includedCard,
              const SizedBox(height: 16),
              _buildNextStepsCard(),
            ],
          ),
        ),
      ],
    );
  }

  /// Small reassurance card shown in the desktop sidebar — fills the
  /// right column so it reads even with the taller left column, and sets
  /// expectations for what happens after submitting.
  Widget _buildNextStepsCard() {
    const steps = [
      'A TinkerPro agent reviews your ticket.',
      'You can keep chatting while you wait.',
      'Please set an honest priority — use High or Urgent only when the '
          'store is affected, so real emergencies get help first.',
    ];
    return _SectionCard(
      icon: Icons.bolt_outlined,
      title: 'What happens next',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: Brand.signal.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Brand.signal,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    steps[i],
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Brand.textMuted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Header bar ─────────────────────────────────────────────────────────

  Widget _buildHeaderBar({required double pad}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 18, pad, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _IconButtonBox(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onTap: _submitting ? null : () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 16),
          // Brand mark — a gradient rounded square with a headset glyph,
          // anchoring the screen as part of the TinkerPro product family.
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: Brand.primary,
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: Brand.signal.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.support_agent_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submit a ticket',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Brand.textPrimary,
                    letterSpacing: -0.4,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Tell us what is wrong and we will get back to you',
                  style: TextStyle(
                    fontSize: 13,
                    color: Brand.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          if (Navigator.of(context).canPop())
            _OutlineButton(
              icon: Icons.menu_book_outlined,
              label: 'Help articles',
              onTap: _submitting ? null : () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );
  }

  // ── Subject + Category ─────────────────────────────────────────────────

  Widget _buildSubjectAndCategory({required bool wide}) {
    final subjectField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Subject', required_: true),
        TextFormField(
          controller: _subject,
          decoration: _inputDecoration('Brief description of your issue'),
          textInputAction: TextInputAction.next,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? 'Subject is required.'
              : null,
        ),
      ],
    );
    final categoryField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Category'),
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          icon: const Icon(Icons.expand_more_rounded, color: Brand.textMuted),
          decoration: _inputDecoration('Select a category'),
          style: const TextStyle(
            fontSize: 14,
            color: Brand.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          items: _categories
              .map((c) => DropdownMenuItem<String>(
                    value: c,
                    child: Text(c, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _category = v),
        ),
      ],
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          subjectField,
          const SizedBox(height: 18),
          categoryField,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: subjectField),
        const SizedBox(width: 20),
        Expanded(child: categoryField),
      ],
    );
  }

  // ── Priority strip ─────────────────────────────────────────────────────

  Widget _buildPriority() {
    const opts = <_PriorityOpt>[
      _PriorityOpt('low', 'Low', Color(0xFF64748B), Icons.arrow_downward_rounded),
      _PriorityOpt('medium', 'Normal', Color(0xFF2563EB), Icons.drag_handle_rounded),
      _PriorityOpt('high', 'High', Color(0xFFD97706), Icons.arrow_upward_rounded),
      _PriorityOpt('urgent', 'Urgent, store down', Color(0xFFDC2626),
          Icons.warning_amber_rounded),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 480;
      // Narrow viewport stacks into a 2x2 grid so labels don't truncate.
      if (narrow) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: opts.map((o) {
            return SizedBox(
              width: (constraints.maxWidth - 10) / 2,
              child: _priorityTile(o),
            );
          }).toList(),
        );
      }
      return Row(
        children: [
          for (var i = 0; i < opts.length; i++) ...[
            Expanded(child: _priorityTile(opts[i])),
            if (i < opts.length - 1) const SizedBox(width: 10),
          ],
        ],
      );
    });
  }

  Widget _priorityTile(_PriorityOpt o) {
    final selected = _priority == o.value;
    final accent = o.color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _priority = o.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.08) : Brand.canvas,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accent : Brand.stroke,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.16)
                      : Brand.subtle,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(o.icon,
                    size: 18, color: selected ? accent : Brand.textMuted),
              ),
              const SizedBox(height: 9),
              Text(
                o.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? accent : Brand.textPrimary,
                  letterSpacing: -0.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Description ───────────────────────────────────────────────────────

  Widget _buildDescription() {
    return TextFormField(
      controller: _description,
      minLines: 6,
      maxLines: 12,
      decoration: _inputDecoration(
        'What happened, what you tried, and what you expected. Paste error messages here too.',
      ),
      validator: (v) => (v == null || v.trim().isEmpty)
          ? 'A description is required.'
          : null,
    );
  }

  // ── Attachment row ─────────────────────────────────────────────────────

  Widget _buildAttachment() {
    final attached = _attachment;
    return DottedBorderBox(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              attached != null
                  ? Icons.image_outlined
                  : Icons.attach_file_rounded,
              size: 18,
              color: Brand.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: attached != null
                  ? Row(
                      children: [
                        Flexible(
                          child: Text(
                            attached.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Brand.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _humanSize(attached.size),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Brand.textMuted,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'Attach a screenshot or photo (optional, helps us a lot)',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Brand.textMuted,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            if (attached != null)
              TextButton.icon(
                onPressed: _submitting ? null : _clearAttachment,
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: Brand.textMuted,
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              OutlinedButton(
                onPressed: _submitting ? null : _pickAttachment,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Brand.stroke),
                  foregroundColor: Brand.textPrimary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Browse'),
              ),
          ],
        ),
      ),
    );
  }

  // ── "Included with this ticket" card ──────────────────────────────────

  Widget _buildIncludedCard() {
    return _SectionCard(
      icon: Icons.verified_outlined,
      title: 'Auto-included',
      titleTrailing: 'AUTOMATIC',
      // Mobile has no POS DB — just show the store identity that came from
      // the sync QR; never the host/port "server setup" panel.
      child: kIsMobilePlatform
          ? _includedMobile()
          : _needsShopName
              ? _buildShopNamePanel()
              : _needsSetup
                  ? _buildSetupPanel()
                  : _loadingShop
                      ? _includedLoading()
                      : _shop == null
                          ? _includedError()
                          : _includedDataGrid(),
    );
  }

  Widget _includedMobile() {
    final store = (widget.store.storeName ?? '').trim();
    return Row(
      children: [
        const Icon(Icons.storefront, size: 16, color: Brand.signal),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            store.isEmpty ? 'Your store' : store,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Brand.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _includedLoading() {
    return Row(
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Brand.signal),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _shopProgress.isEmpty ? 'Loading business info…' : _shopProgress,
            style: const TextStyle(
              fontSize: 12.5,
              color: Brand.textMuted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _includedError() {
    return Row(
      children: [
        const Icon(Icons.error_outline, size: 16, color: Brand.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _shopError ?? 'Could not load your business info.',
            style: const TextStyle(fontSize: 12.5, color: Brand.danger),
          ),
        ),
        TextButton(
          onPressed: _loadShop,
          style: TextButton.styleFrom(
            foregroundColor: Brand.danger,
            textStyle: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _includedDataGrid() {
    final shop = _shop!;
    final tenant = shop.businessName.isNotEmpty
        ? shop.businessName
        : (widget.store.storeName ?? '—');
    final branch = (widget.store.storeName ?? '').isNotEmpty
        ? widget.store.storeName!
        : (shop.businessName.isNotEmpty ? shop.businessName : '—');
    final terminal = _terminalIp != null && _terminalIp!.isNotEmpty
        ? 'ip ${_terminalIp!}'
        : '—';
    final user = widget.info.meName.isNotEmpty
        ? widget.info.meName
        : '—';
    final os = _osLabel();

    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 460;
      final rows = <List<_KV>>[
        [
          _KV('Tenant', tenant),
          _KV('Branch', branch),
        ],
        [
          _KV('Terminal', terminal),
          _KV('User', user),
        ],
        [
          _KV('App version', _appVersion),
          _KV('OS', os),
        ],
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            if (narrow) ...[
              _kvLine(rows[i][0], alignRight: false),
              const SizedBox(height: 10),
              _kvLine(rows[i][1], alignRight: false),
            ] else
              Row(
                children: [
                  Expanded(child: _kvLine(rows[i][0], alignRight: false)),
                  const SizedBox(width: 16),
                  Expanded(child: _kvLine(rows[i][1], alignRight: true)),
                ],
              ),
          ],
        ],
      );
    });
  }

  Widget _kvLine(_KV kv, {required bool alignRight}) {
    return Row(
      mainAxisAlignment:
          alignRight ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
      children: [
        Text(
          kv.key,
          style: const TextStyle(
            fontSize: 12.5,
            color: Brand.textMuted,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            kv.value,
            textAlign: alignRight ? TextAlign.right : TextAlign.left,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: Brand.textPrimary,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.05,
            ),
          ),
        ),
      ],
    );
  }

  /// Standalone, no local XAMPP found: ask for the shop name and
  /// nothing else. Deliberately minimal — no host, port, VAT, or TIN.
  Widget _buildShopNamePanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.signal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.signal.withValues(alpha: 0.35)),
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
                  color: Brand.signal.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.storefront_outlined,
                  size: 16,
                  color: Brand.signal,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "What's your shop name?",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Brand.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "We couldn't find a POS database on this PC — that's okay. "
            "Just tell us your shop name and we'll add it to your ticket. "
            "We'll remember it for next time.",
            style: TextStyle(fontSize: 12, color: Brand.textMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _shopName,
            enabled: !_shopNameBusy,
            autofocus: true,
            decoration: _inputDecoration("e.g. Juan's Store").copyWith(
              labelText: 'Shop name',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              isDense: true,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saveShopName(),
          ),
          if (_shopNameError != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 14, color: Brand.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _shopNameError!,
                    style: const TextStyle(
                        color: Brand.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _shopNameBusy ? null : _saveShopName,
                icon: _shopNameBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check, size: 16),
                label: Text(_shopNameBusy ? 'Saving…' : 'Save'),
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.signal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: _shopNameBusy ? null : _loadShop,
                style: TextButton.styleFrom(
                  foregroundColor: Brand.textMuted,
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                child: const Text('Look for local POS again'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSetupPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.warning.withValues(alpha: 0.45)),
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
                  color: Brand.warning.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.settings_input_antenna_outlined,
                  size: 16,
                  color: Color(0xFFB45309),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'POS server setup needed',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "A TinkerPro admin only needs to enter this once. We'll save it on this machine "
            "so future tickets open instantly.",
            style: TextStyle(fontSize: 12, color: Brand.textMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _setupHost,
                  enabled: !_setupBusy,
                  autofocus: true,
                  decoration: _inputDecoration('e.g. 192.168.1.40').copyWith(
                    labelText: 'Host',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _setupPort,
                  enabled: !_setupBusy,
                  decoration: _inputDecoration('3306').copyWith(
                    labelText: 'Port',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _saveSetupAndConnect(),
                ),
              ),
            ],
          ),
          if (_setupError != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 14, color: Brand.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _setupError!,
                    style: const TextStyle(
                        color: Brand.danger,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _setupBusy ? null : _saveSetupAndConnect,
                icon: _setupBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.link, size: 16),
                label: Text(_setupBusy ? 'Connecting…' : 'Connect & save'),
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.signal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              TextButton(
                onPressed: _setupBusy ? null : _setupTryAutoDiscover,
                style: TextButton.styleFrom(
                  foregroundColor: Brand.textMuted,
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                child: const Text('Try auto-discover'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────

  Widget _buildFooterBar({required double pad}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 14, pad, 14),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final replyText = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Brand.subtle,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.schedule_outlined, size: 14, color: Brand.textMuted),
              SizedBox(width: 6),
              Text(
                'Average reply within 2 hours',
                style: TextStyle(
                  fontSize: 12,
                  color: Brand.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Brand.textPrimary,
                side: const BorderSide(color: Brand.stroke),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 12),
            _GradientButton(
              busy: _submitting,
              label: _submitting ? 'Submitting…' : 'Submit ticket',
              icon: Icons.send_rounded,
              onTap: _submitting ? null : _submit,
            ),
          ],
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              actions,
              const SizedBox(height: 10),
              Center(child: replyText),
            ],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [replyText, actions],
        );
      }),
    );
  }

  // ── Field primitives ───────────────────────────────────────────────────

  Widget _label(String text, {bool required_ = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Brand.textPrimary,
              fontSize: 12.5,
              letterSpacing: -0.05,
            ),
          ),
          if (required_)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                '*',
                style: TextStyle(
                    color: Brand.signal,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Brand.textMuted.withValues(alpha: 0.7),
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        filled: true,
        fillColor: Brand.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.signal, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Brand.danger, width: 1.6),
        ),
      );

  String _osLabel() {
    final os = Platform.operatingSystem;
    if (os == 'windows') {
      final v = Platform.operatingSystemVersion;
      if (v.contains('11')) return 'Windows 11';
      if (v.contains('10')) return 'Windows 10';
      return 'Windows';
    }
    if (os == 'macos') return 'macOS';
    if (os.isEmpty) return '—';
    return os[0].toUpperCase() + os.substring(1);
  }

  String _humanSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var n = bytes.toDouble();
    var i = 0;
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024;
      i++;
    }
    final fixed = n >= 10 || i == 0 ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
    return '$fixed ${units[i]}';
  }
}

// ── Tiny widgets used by the screen ───────────────────────────────────────

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Brand.stroke);
}

/// Premium section container: white surface, soft layered shadow, a
/// tinted rounded icon chip in the header, a title with optional
/// required-marker + subtitle, and a pill-style trailing hint. The
/// stacked building block of the redesigned ticket form.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.subtitle,
    this.titleRequired = false,
    this.titleTrailing,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? subtitle;
  final bool titleRequired;
  final String? titleTrailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Brand.stroke),
        boxShadow: kCardShadow,
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Brand.signal.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: Brand.signal),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Brand.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (titleRequired)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Text(
                              '*',
                              style: TextStyle(
                                color: Brand.signal,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Brand.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (titleTrailing != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Brand.subtle,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    titleTrailing!,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Brand.textMuted,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

/// Subtle, premium layered shadow used across the ticket-form cards and
/// the primary CTA. Low-opacity slate so white cards lift off the grey
/// canvas without looking heavy.
const List<BoxShadow> kCardShadow = [
  BoxShadow(
    color: Color(0x0A0F172A), // slate-900 @ ~4%
    blurRadius: 14,
    offset: Offset(0, 6),
  ),
  BoxShadow(
    color: Color(0x080F172A), // slate-900 @ ~3%
    blurRadius: 4,
    offset: Offset(0, 1),
  ),
];

class _IconButtonBox extends StatelessWidget {
  const _IconButtonBox({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            border: Border.all(color: Brand.stroke),
            borderRadius: BorderRadius.circular(8),
            color: Brand.canvas,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: Brand.textPrimary),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: Brand.textPrimary),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.textPrimary,
        side: const BorderSide(color: Brand.stroke),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Premium primary CTA — a brand-gradient pill with a soft accent glow,
/// an inline spinner while busy, and a dimmed disabled state. Replaces
/// the flat ElevatedButton for a more high-end feel.
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Brand.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: Brand.signal.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(icon, size: 16, color: Colors.white),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Box with a 1.4px dashed border — used by the attachment row to mirror
/// the marketing-mock dropzone aesthetic. Implemented with a custom
/// painter rather than pulling in a dotted-border package for one widget.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: Brand.stroke,
        radius: 10,
        strokeWidth: 1.2,
        dash: 5,
        gap: 4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
  });
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dash != dash ||
      old.gap != gap;
}

class _PriorityOpt {
  const _PriorityOpt(this.value, this.label, this.color, this.icon);
  final String value;
  final String label;
  final Color color;
  final IconData icon;
}

class _KV {
  const _KV(this.key, this.value);
  final String key;
  final String value;
}

/// Returned to the chat screen when a ticket is successfully submitted —
/// the chat screen uses it to post a confirmation bubble back into the
/// thread so admins see it land in real time. The ticket id, when the
/// server returned one, is included so admins can correlate the chat
/// bubble with the row they're about to Accept in ticket.php.
class TicketSubmitOutcome {
  TicketSubmitOutcome({
    required this.subject,
    required this.priority,
    required this.businessName,
    required this.vatLabel,
    this.ticketId,
  });
  final int? ticketId;
  final String subject;
  final String priority;
  final String businessName;
  final String vatLabel;
}
