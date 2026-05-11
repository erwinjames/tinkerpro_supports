import 'package:flutter/material.dart';

import '../api_client.dart';
import '../services/chat_service.dart' show EmployeeChatInfo;
import '../services/pos_discovery_service.dart';
import '../services/pos_shop_service.dart';
import '../services/session_store.dart';
import '../services/ticket_service.dart';
import '../theme.dart';

/// Pushed when the employee types `/ticket` in the chat composer.
///
/// Mirrors the layout of the web portal's customer-ticket.php form, but
/// auto-fills business name from the saved store name and pulls VAT/
/// Non-VAT status live from the local POS `tinkerpro.shop` table over
/// the LAN (single-terminal: localhost; multi-terminal: /24 sweep with
/// credential check). The employee enters their own name + the issue.
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
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _subject = TextEditingController();
  final _description = TextEditingController();

  String _priority = 'low';
  bool _loadingShop = true;
  bool _submitting = false;
  ShopInfo? _shop;
  String? _shopError;
  String _shopSource = 'pending';
  String _shopProgress = '';
  late final PosShopService _posShop = PosShopService(store: widget.store);

  // Manual-setup panel state — shown the very first time /ticket runs
  // on a fresh install before any admin has pinned a POS host. After a
  // successful Connect we save the host+port to SessionStore and never
  // show this panel again.
  bool _needsSetup = false;
  final _setupHost = TextEditingController();
  final _setupPort = TextEditingController(text: '3306');
  bool _setupBusy = false;
  String? _setupError;

  // Diagnostic panel state — see _buildDiagnosticsCard.
  bool _diagOpen = false;
  bool _diagScanning = false;
  String _diagProgress = '';
  PosScanReport? _diagReport;
  String? _diagBusyKey; // "host:port" currently being validated by tap-to-connect
  String? _diagConnectError;

  @override
  void initState() {
    super.initState();
    // Default the name field to whatever the employee identifies as in
    // chat. They can overwrite it.
    _name.text = widget.info.meName;
    // Three-way decision:
    //   - cached ShopInfo  → render instantly, silently refresh if we
    //                        have a configured target to talk to
    //   - manual target set but no cache → load visibly (single-shot
    //                                       connect, no LAN scan)
    //   - nothing configured             → show the setup panel so an
    //                                       admin can pin host+port
    final cached = widget.store.cachedShop;
    final hasManual = widget.store.hasPosManualTarget;
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
      if (hasManual) _loadShop(silent: true);
    } else if (hasManual) {
      _loadShop();
    } else {
      _loadingShop = false;
      _needsSetup = true;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    _description.dispose();
    _setupHost.dispose();
    _setupPort.dispose();
    super.dispose();
  }

  Future<void> _loadShop({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingShop = true;
        _shopError = null;
        _shopSource = 'pending';
        _shopProgress = 'Looking for the POS server…';
      });
    }
    // POS DB read is the source of truth for vat_reg. The session's
    // store name covers business-name display when no POS row matches
    // by TIN (almost always the case — shop_tin is rarely populated).
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

    // Fallback: if direct POS DB access fails (network/credentials/firewall),
    // use support-backend customer info so ticket creation can still proceed.
    // Skip the fallback on silent refreshes — we already have a cached
    // ShopInfo on screen, no point downgrading it to a less-trusted source.
    ShopInfo? fallback;
    if (pos == null && !silent) {
      fallback = await widget.tickets.getShopInfo();
    }

    if (!mounted) return;

    // Silent path: only mutate UI / cache when we actually got fresh POS
    // data. Failures during background refresh are intentionally
    // swallowed — the cached values stay on screen so offline still
    // works.
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
      }
      return;
    }

    setState(() {
      _loadingShop = false;
      if (pos == null && fallback == null) {
        _shop = null;
        _shopSource = 'none';
        final posErr = _posShop.lastError;
        _shopError = posErr == null
            ? 'Could not read shop info from the POS database. Tap Retry.'
            : 'Could not read shop info from the POS database ($posErr). Tap Retry.';
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
        return;
      }

      final resolvedPos = pos!;
      // Adopt the session's store name when the POS row didn't carry
      // one (typical — the shop table's shop_name is often the POS
      // provider's brand, not the merchant's business).
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

    // Persist successful POS reads so the next /ticket open is instant.
    if (pos != null) {
      await widget.store.saveCachedShop(_shop!);
    }
  }

  /// Admin-driven setup: connect to the typed host/port, and if it
  /// works, pin it to SessionStore so we never ask again on this
  /// install. On failure we leave the manual target unset — the admin
  /// can correct the values and retry.
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

  /// Escape hatch from the setup panel — try the existing LAN
  /// auto-discovery. Useful when the admin doesn't know the host but is
  /// on the same network as the POS.
  void _setupTryAutoDiscover() {
    setState(() {
      _needsSetup = false;
      _setupError = null;
    });
    _loadShop();
  }

  /// Re-open the setup panel to change a previously-pinned host (e.g.,
  /// the POS box got a new IP). Called from the diagnostic card.
  void _openSetupPanel() {
    setState(() {
      _setupHost.text = widget.store.posManualHost ?? '';
      _setupPort.text = (widget.store.posManualPort ?? 3306).toString();
      _setupError = null;
      _needsSetup = true;
    });
  }

  /// Pull "host" out of an http(s) base URL — the support backend often
  /// runs on the same machine as the POS, so its host is the strongest
  /// hint for the LAN scanner.
  String? _hostFromBaseUrl(String url) {
    try {
      final u = Uri.parse(url);
      final h = u.host;
      return h.isEmpty ? null : h;
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final shop = _shop;
    if (shop == null) {
      _toast('Shop info is still loading.');
      return;
    }
    setState(() => _submitting = true);
    final result = await widget.tickets.createTicket(
      customerName: _name.text.trim(),
      // Employee app has no portal customer email — the server-side
      // ticket facade is tolerant of an empty value here.
      customerEmail: '',
      businessName: shop.businessName,
      vatReg: shop.vatReg,
      subject: _subject.text.trim(),
      description: _description.text.trim(),
      priority: _priority,
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
      backgroundColor: const Color(0xFFF1F2F5),
      appBar: AppBar(
        backgroundColor: Brand.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: Brand.stroke)),
        title: const Text(
          'Create Support Ticket',
          style: TextStyle(
              fontWeight: FontWeight.w800, color: Brand.textPrimary),
        ),
        iconTheme: const IconThemeData(color: Brand.textPrimary),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            _buildInfoBox(),
            const SizedBox(height: 14),
            _buildFormCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF3F4F7), Color(0xFFF7F2F2)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Brand.stroke),
      ),
      child: const Column(
        children: [
          Text(
            '🎫 Create Support Ticket',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Brand.textPrimary),
          ),
          SizedBox(height: 6),
          Text(
            "We're here to help! Tell us about your issue and we'll get back to you soon.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Brand.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E8FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '📋 What happens after you submit?',
            style: TextStyle(
                color: Brand.signal,
                fontWeight: FontWeight.w800,
                fontSize: 14),
          ),
          SizedBox(height: 8),
          Text(
            "1. You'll get a ticket ID via email\n"
            '2. Our support team will be notified\n'
            '3. An agent will accept your ticket and start helping\n'
            '4. You can track progress and chat with the agent',
            style: TextStyle(color: Brand.textMuted, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.stroke),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('👤 Your Full Name *'),
            TextFormField(
              controller: _name,
              decoration: _fieldDecoration('Enter your full name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required.' : null,
            ),
            const SizedBox(height: 16),
            _label('🏢 Business Name *'),
            _buildBusinessField(),
            if (!_loadingShop && !_needsSetup && _shop != null)
              _buildSourceCaption(),
            if (!_loadingShop && !_needsSetup) _buildDiagnosticsCard(),
            const SizedBox(height: 16),
            _label('📝 Subject *'),
            TextFormField(
              controller: _subject,
              decoration: _fieldDecoration('Brief description of your issue'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Subject is required.'
                  : null,
            ),
            const SizedBox(height: 16),
            _label('⚡ Priority Level'),
            _buildPriority(),
            const SizedBox(height: 16),
            _label('📄 Describe Your Issue *'),
            TextFormField(
              controller: _description,
              minLines: 5,
              maxLines: 8,
              decoration: _fieldDecoration(
                  'Please provide as much detail as possible about your issue. Include any error messages, steps you\'ve tried, and what you expected to happen.'),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'A description is required.'
                  : null,
            ),
            const SizedBox(height: 22),
            _buildSubmit(),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Brand.textPrimary,
            fontSize: 13.5),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Brand.textMuted, fontSize: 13.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        filled: true,
        fillColor: const Color(0xFFF8F9FB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE1E5E9), width: 1.6),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE1E5E9), width: 1.6),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Brand.signal, width: 2),
        ),
      );

  Widget _buildBusinessField() {
    if (_needsSetup) return _buildSetupPanel();
    if (_loadingShop) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE1E5E9), width: 1.6),
        ),
        child: Row(
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Brand.signal)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _shopProgress.isEmpty
                    ? 'Loading business info…'
                    : _shopProgress,
                style: const TextStyle(color: Brand.textMuted, fontSize: 13.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    if (_shop == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFCA5A5), width: 1.6),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline,
                size: 18, color: Brand.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _shopError ?? 'Could not load your business info.',
                style: const TextStyle(color: Brand.danger, fontSize: 13),
              ),
            ),
            TextButton(onPressed: _loadShop, child: const Text('Retry')),
          ],
        ),
      );
    }
    final shop = _shop!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E5E9), width: 1.6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shop.businessName.isEmpty
                      ? 'Unnamed business'
                      : shop.businessName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: Brand.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                if (shop.tin.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'TIN ${shop.tin}',
                      style: const TextStyle(
                          fontSize: 11.5, color: Brand.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _VatChip(isVat: shop.isVat, label: shop.vatLabel),
        ],
      ),
    );
  }

  Widget _buildSetupPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCD34D), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.settings_input_antenna_outlined,
                  size: 18, color: Color(0xFF92400E)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'POS server setup needed',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'A TinkerPro admin only needs to enter this once — host and '
            'port for the POS MariaDB. We\'ll save it on this machine so '
            'future /ticket forms open instantly.',
            style: TextStyle(fontSize: 12, color: Brand.textMuted),
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
                  decoration: const InputDecoration(
                    labelText: 'Host (IP or hostname)',
                    hintText: 'e.g. 192.168.1.40',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _setupPort,
                  enabled: !_setupBusy,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _saveSetupAndConnect(),
                ),
              ),
            ],
          ),
          if (_setupError != null) ...[
            const SizedBox(height: 8),
            Text(
              _setupError!,
              style: const TextStyle(color: Brand.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
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
                    : const Icon(Icons.link, size: 18),
                label: Text(_setupBusy ? 'Connecting…' : 'Connect & save'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _setupBusy ? null : _setupTryAutoDiscover,
                child: const Text('Try auto-discover instead'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCaption() {
    final cfg = _posShop.config;
    final host = _posShop.resolvedHost ??
        (cfg.host.isNotEmpty ? cfg.host : 'unknown');
    final port = _posShop.resolvedPort ?? cfg.port;
    final err = _posShop.lastError;
    final (icon, color, text) = switch (_shopSource) {
      'pos' => (
        Icons.lan_outlined,
        const Color(0xFF16A34A),
        'VAT status read live from POS at $host:$port/${cfg.db}',
      ),
      'fallback' => (
        Icons.cloud_outlined,
        const Color(0xFFB45309),
        'POS DB unreachable; using support backend shop profile',
      ),
      _ => (
        Icons.warning_amber_outlined,
        const Color(0xFFB45309),
        err == null
            ? 'No POS server found on this network'
            : 'POS unreachable ($err)',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ),
          if (_shopSource != 'pos')
            InkWell(
              onTap: _loadShop,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleDiagnostics() async {
    setState(() {
      _diagOpen = !_diagOpen;
      _diagConnectError = null;
    });
    if (_diagOpen && _diagReport == null && !_diagScanning) {
      await _runDiagScan();
    }
  }

  Future<void> _runDiagScan() async {
    setState(() {
      _diagScanning = true;
      _diagProgress = 'Scanning network…';
      _diagReport = null;
      _diagConnectError = null;
    });
    final report = await _posShop.scanLan(
      onProgress: (s) {
        if (!mounted) return;
        setState(() => _diagProgress = s);
      },
    );
    if (!mounted) return;
    setState(() {
      _diagScanning = false;
      _diagReport = report;
      _diagProgress = '';
    });
  }

  Future<void> _diagConnect(PosScanRow row) async {
    final key = '${row.host}:${row.port}';
    setState(() {
      _diagBusyKey = key;
      _diagConnectError = null;
    });
    final result = await _posShop.tryTarget(host: row.host, port: row.port);
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _diagBusyKey = null;
        _diagConnectError = '$key: ${_posShop.lastError ?? 'connect failed'}';
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
    setState(() {
      _diagBusyKey = null;
      _shop = adopted;
      _shopSource = 'pos';
      _shopError = null;
      _diagOpen = false;
    });
    await widget.store.saveCachedShop(adopted);
  }

  Widget _buildDiagnosticsCard() {
    final report = _diagReport;
    final hasResults = report != null && report.openTargets.isNotEmpty;
    final headerLabel = _diagOpen
        ? 'Hide POS server diagnostics'
        : 'POS server diagnostics';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE1E5E9)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _toggleDiagnostics,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _diagOpen
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 18,
                      color: Brand.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.lan_outlined,
                        size: 14, color: Brand.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        headerLabel,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Brand.textMuted),
                      ),
                    ),
                    if (_diagScanning)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.6, color: Brand.signal),
                      )
                    else if (_diagOpen) ...[
                      InkWell(
                        onTap: _diagScanning ? null : _openSetupPanel,
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Text(
                            'Edit host',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Brand.signal,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _diagScanning ? null : _runDiagScan,
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Text(
                            'Rescan',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Brand.signal,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_diagOpen) const Divider(height: 1, color: Color(0xFFE1E5E9)),
            if (_diagOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_diagScanning)
                      Text(
                        _diagProgress.isEmpty ? 'Scanning…' : _diagProgress,
                        style: const TextStyle(
                            fontSize: 11.5, color: Brand.textMuted),
                      )
                    else if (report == null)
                      const Text(
                        'Tap Rescan to look for MariaDB on the LAN.',
                        style: TextStyle(
                            fontSize: 11.5, color: Brand.textMuted),
                      )
                    else
                      _buildDiagReport(report),
                    if (_diagConnectError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _diagConnectError!,
                        style: const TextStyle(
                            fontSize: 11.5, color: Brand.danger),
                      ),
                    ],
                    if (hasResults) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Tap a row to connect — we\'ll authenticate as root '
                        '(empty password) and read tinkerpro.shop.',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          color: Brand.textMuted,
                        ),
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

  Widget _buildDiagReport(PosScanReport report) {
    final ifaces = report.interfaces;
    final rows = report.openTargets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ifaces.isEmpty)
          const Text(
            'No usable IPv4 interface found on this machine.',
            style: TextStyle(fontSize: 11.5, color: Brand.danger),
          )
        else
          Text(
            'Scanned ${ifaces.length == 1 ? "interface" : "interfaces"}: '
            '${ifaces.map((i) => "${i.name} ${i.address} (${i.subnet})").join(", ")}',
            style: const TextStyle(fontSize: 11, color: Brand.textMuted),
          ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Text(
            'No host on the LAN had any of the MariaDB ports open. '
            'Check that the POS server is on the same subnet, that '
            'MariaDB is bound to 0.0.0.0 (not 127.0.0.1), and that '
            'its port isn\'t blocked by Windows Defender on the '
            'server side.',
            style: TextStyle(fontSize: 11.5, color: Brand.textMuted),
          )
        else ...[
          Text(
            '${rows.length} open '
            '${rows.length == 1 ? "target" : "targets"} — tap to connect:',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Brand.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          ...rows.map(_buildDiagRow),
        ],
      ],
    );
  }

  Widget _buildDiagRow(PosScanRow row) {
    final key = '${row.host}:${row.port}';
    final busy = _diagBusyKey == key;
    final disabled = _diagBusyKey != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: disabled ? null : () => _diagConnect(row),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE1E5E9)),
          ),
          child: Row(
            children: [
              Icon(
                row.deviceName == null
                    ? Icons.device_unknown_outlined
                    : Icons.computer_outlined,
                size: 16,
                color: Brand.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.deviceName ?? 'Unknown device',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Brand.textPrimary),
                    ),
                    Text(
                      '${row.host}:${row.port}',
                      style: const TextStyle(
                          fontSize: 11, color: Brand.textMuted),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.6, color: Brand.signal),
                )
              else
                Text(
                  disabled ? '' : 'Connect',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Brand.signal,
                    decoration: TextDecoration.underline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriority() {
    final opts = const [
      _PriorityOpt('low', '🟢', 'Low', 'General question', Color(0xFF28A745)),
      _PriorityOpt(
          'medium', '🟡', 'Medium', 'Need help soon', Color(0xFFFFC107)),
      _PriorityOpt('high', '🔴', 'Urgent', 'System down', Color(0xFFDC3545)),
    ];
    return Row(
      children: opts.map((o) {
        final selected = _priority == o.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: o == opts.last ? 0 : 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _priority = o.value),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? o.color : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? o.color : const Color(0xFFE1E5E9),
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '${o.emoji} ${o.label}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? (o.value == 'medium'
                                ? const Color(0xFF333333)
                                : Colors.white)
                            : Brand.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      o.subtitle,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: selected
                            ? (o.value == 'medium'
                                ? const Color(0xFF333333)
                                : Colors.white70)
                            : Brand.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSubmit() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1587F1),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB6D6F4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: _submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Text('🚀 Submit Ticket'),
      ),
    );
  }
}

class _VatChip extends StatelessWidget {
  const _VatChip({required this.isVat, required this.label});
  final bool isVat;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = isVat ? const Color(0xFF16A34A) : const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label.isEmpty ? (isVat ? 'VAT' : 'Non-VAT') : label,
        style: TextStyle(
            fontWeight: FontWeight.w800, fontSize: 11.5, color: color),
      ),
    );
  }
}

class _PriorityOpt {
  const _PriorityOpt(
      this.value, this.emoji, this.label, this.subtitle, this.color);
  final String value;
  final String emoji;
  final String label;
  final String subtitle;
  final Color color;
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
