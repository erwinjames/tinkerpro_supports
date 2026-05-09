import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/customer_models.dart';
import '../services/pos_shop_service.dart';
import '../services/session_store.dart';
import '../services/ticket_service.dart';
import '../theme.dart';

/// Pushed when the customer types `/ticket` in the chat composer.
///
/// Mirrors the layout of the web portal's customer-ticket.php form, but
/// swaps the editable Email field for an auto-fetched read-only Business
/// Name + VAT/Non-VAT chip pulled from the POS shop record (server falls
/// back to the support customer row when the POS DB isn't present).
class TicketFormScreen extends StatefulWidget {
  const TicketFormScreen({
    super.key,
    required this.tickets,
    required this.customer,
    required this.store,
    required this.api,
  });

  final TicketService tickets;
  final Customer customer;
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

  @override
  void initState() {
    super.initState();
    _name.text = widget.customer.ownerName;
    _loadShop();
  }

  @override
  void dispose() {
    _name.dispose();
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadShop() async {
    setState(() {
      _loadingShop = true;
      _shopError = null;
      _shopSource = 'pending';
      _shopProgress = 'Looking for the POS server…';
    });
    // Two-tier read:
    //   1. Direct LAN MySQL query against the POS, with auto-discovery
    //      of the POS host (cached → hint hosts → /24 sweep). Works
    //      offline w.r.t. the cloud support backend — the common shop
    //      scenario (POS computer up, shop wifi up, internet flaky).
    //   2. HTTP fallback to the support backend's /getCustomerShopInfo,
    //      which reads the customer record. Used when the device isn't
    //      on the shop's LAN (filing a ticket from home / cellular) or
    //      the LAN sweep didn't find a POS.
    final apiHost = _hostFromBaseUrl(widget.api.baseUrl);
    final hints = <String>[?apiHost];
    final pos = await _posShop.getShopInfo(
      tin: widget.customer.tin,
      hintHosts: hints,
      onProgress: (s) {
        if (!mounted) return;
        setState(() => _shopProgress = s);
      },
    );
    final http = await widget.tickets.getShopInfo();

    final merged = _merge(pos, http);

    if (!mounted) return;
    setState(() {
      _loadingShop = false;
      _shop = merged;
      _shopSource = pos != null
          ? 'pos'
          : http != null
              ? 'cloud'
              : 'none';
      if (merged == null) {
        _shopError = 'Could not load your business info. Pull to retry.';
      } else {
        if (_name.text.trim().isEmpty && merged.fullName.isNotEmpty) {
          _name.text = merged.fullName;
        }
      }
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

  /// POS DB is the source of truth for vat_reg (matches what the POS
  /// prints on receipts). HTTP source carries the customer-record
  /// niceties (full name, email) and the company_name fallback for
  /// business name when the POS row didn't match by TIN.
  ShopInfo? _merge(ShopInfo? pos, ShopInfo? http) {
    if (pos == null && http == null) return null;
    if (pos == null) return http;
    final businessName = pos.businessName.isNotEmpty
        ? pos.businessName
        : (http?.businessName ?? widget.customer.companyName);
    return ShopInfo(
      businessName: businessName,
      vatReg: pos.vatReg,
      vatLabel: pos.vatLabel,
      tin: pos.tin.isNotEmpty ? pos.tin : (http?.tin ?? widget.customer.tin),
      email: http?.email ?? widget.customer.email,
      fullName: http?.fullName ?? widget.customer.ownerName,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final shop = _shop;
    if (shop == null) {
      _toast('Business info is still loading.');
      return;
    }
    setState(() => _submitting = true);
    final email = shop.email.isNotEmpty ? shop.email : widget.customer.email;
    final result = await widget.tickets.createTicket(
      customerName: _name.text.trim(),
      customerEmail: email,
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
            if (!_loadingShop && _shop != null) _buildSourceCaption(),
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

  Widget _buildSourceCaption() {
    final cfg = _posShop.config;
    final host = _posShop.resolvedHost ??
        (cfg.host.isNotEmpty ? cfg.host : 'unknown');
    final err = _posShop.lastError;
    final (icon, color, text) = switch (_shopSource) {
      'pos' => (
        Icons.lan_outlined,
        const Color(0xFF16A34A),
        'VAT status read live from POS at $host:${cfg.port}/${cfg.db}',
      ),
      'cloud' => (
        Icons.cloud_outlined,
        Brand.signal,
        err == null
            ? 'No POS server found on this network — using customer record from support backend'
            : 'POS unreachable ($err) — using customer record from support backend',
      ),
      _ => (
        Icons.warning_amber_outlined,
        const Color(0xFFB45309),
        'No shop data available — VAT status may be stale',
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
/// thread so support sees it land in real time. The ticket id, when
/// the server returned one, is included so admins can correlate the
/// chat bubble with the row they're about to Accept in ticket.php.
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
