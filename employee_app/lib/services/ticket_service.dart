import 'dart:io';

import 'package:dio/dio.dart' show MultipartFile;

import '../api_client.dart';

/// Format a ticket id as a zero-padded 4-digit reference (#0069). The
/// underlying id stays numeric for lookups; this is display-only.
String fmtTicketNo(int id) => '#${id.toString().padLeft(4, '0')}';

/// Thin HTTP wrapper around the support backend's ticket endpoints.
///
/// The customer app exposes ticket creation through a `/ticket` slash
/// command in the chat composer. Business name + VAT-registration flag
/// are auto-fetched from [getShopInfo] (sourced from the POS-side `shop`
/// table by TIN, with a fallback to the support DB's customer row).
class TicketService {
  TicketService(this.api);
  final ApiClient api;

  Future<ShopInfo?> getShopInfo() async {
    final res = await api.get('getCustomerShopInfo');
    if (res['status'] != 'success') return null;
    return ShopInfo(
      businessName: (res['business_name'] ?? '').toString(),
      vatReg: int.tryParse((res['vat_reg'] ?? 0).toString()) ?? 0,
      vatLabel: (res['vat_label'] ?? '').toString(),
      tin: (res['tin'] ?? '').toString(),
      email: (res['email'] ?? '').toString(),
      fullName: (res['full_name'] ?? '').toString(),
    );
  }

  Future<TicketSubmitResult> createTicket({
    required String customerName,
    required String customerEmail,
    required String businessName,
    required int vatReg,
    required String subject,
    required String description,
    required String priority,
    String? category,
    File? attachment,
    int? conversationId,
  }) async {
    // Category isn't a column in the `tickets` table — prepend it into
    // the description so the agent reading the ticket still sees which
    // bucket the cashier picked. Cheap and reversible if/when the
    // backend grows a real category column.
    var body = description.trim();
    final cat = (category ?? '').trim();
    if (cat.isNotEmpty) {
      body = 'Category: $cat\n\n$body';
    }

    final fields = <String, dynamic>{
      'customerName': customerName,
      'customerEmail': customerEmail,
      'businessName': businessName,
      'vatReg': vatReg.toString(),
      'subject': subject,
      'description': body,
      'priority': priority,
      // Pass the conv we're already chatting in so the server can
      // link the ticket to it. Without this, admin-side resolve can't
      // post its "✅ resolved" announcement back to us (the server
      // gates that on a non-null conversation_id).
      if (conversationId != null && conversationId > 0)
        'conversation_id': conversationId.toString(),
    };

    final Map<String, dynamic> res;
    if (attachment != null) {
      final fileName = attachment.path.split(Platform.pathSeparator).last;
      final mp = await MultipartFile.fromFile(
        attachment.path,
        filename: fileName,
      );
      res = await api.upload(
        'create_ticket',
        fields: fields,
        file: mp,
        fileField: 'attachment',
      );
    } else {
      res = await api.post('create_ticket', body: fields);
    }

    final ok = res['status'] == 'success';
    // The user-facing reference is the random `ticket_number` (not the
    // sequential `ticket_id`). Carry that through as the ticket identity
    // so the optimistic "🎫 Ticket #N" note, the pending-ticket anchor,
    // and the chat-event correlation all key on the same number the
    // server stamps into its accept/resolve bubbles. Falls back to the
    // internal id only if an older server doesn't return a number.
    return TicketSubmitResult(
      ok: ok,
      ticketId: int.tryParse((res['ticket_number'] ?? '').toString()) ??
          int.tryParse((res['ticket_id'] ?? '').toString()),
      message: (res['message'] ?? (ok ? 'Ticket created.' : 'Could not create ticket.'))
          .toString(),
    );
  }
}

/// Fetch a single ticket's full record. Used by the chat-screen
/// tap-to-view-details flow on the ticket status badges.
extension TicketDetailService on TicketService {
  Future<TicketDetail?> getTicketDetail(int id) async {
    if (id <= 0) return null;
    try {
      final res =
          await api.get('chat.getTicketDetail', params: {'id': id.toString()});
      if (res['success'] != true) return null;
      final raw = res['ticket'];
      if (raw is! Map) return null;
      return TicketDetail.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }
}

/// Full ticket record returned by `chat.getTicketDetail`.
class TicketDetail {
  TicketDetail({
    required this.id,
    required this.subject,
    required this.description,
    required this.status,
    required this.priority,
    required this.customerName,
    required this.businessName,
    required this.agentName,
    required this.createdAt,
    required this.updatedAt,
    this.conversationId,
  });

  final int id;
  final String subject;
  final String description;
  final String status; // new | assigned | in_progress | resolved | closed
  final String priority; // low | medium | high
  final String customerName;
  final String businessName;
  final String agentName;
  final String createdAt;
  final String updatedAt;

  /// Conversation this ticket is linked to (set when filed through chat).
  /// Used to decide whether a ticket entered by number belongs to this
  /// employee's support thread before routing them into it.
  final int? conversationId;

  /// Claimed = anything past the unassigned `new` state — an agent has
  /// picked it up (assigned/in_progress) or it's already done
  /// (resolved/closed). Only `new` still sits in the support queue, so
  /// only `new` should land on the "waiting to be accepted" screen.
  bool get isClaimed => status.isNotEmpty && status != 'new';
  bool get isResolved => status == 'resolved' || status == 'closed';

  factory TicketDetail.fromJson(Map<String, dynamic> j) => TicketDetail(
        id: int.tryParse((j['id'] ?? 0).toString()) ?? 0,
        subject: (j['subject'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        priority: (j['priority'] ?? 'low').toString(),
        customerName: (j['customer_name'] ?? '').toString(),
        businessName: (j['business_name'] ?? '').toString(),
        agentName: (j['agent_name'] ?? '').toString(),
        createdAt: (j['created_at'] ?? '').toString(),
        updatedAt: (j['updated_at'] ?? '').toString(),
        conversationId: j['conversation_id'] != null
            ? int.tryParse(j['conversation_id'].toString())
            : null,
      );
}

class ShopInfo {
  ShopInfo({
    required this.businessName,
    required this.vatReg,
    required this.vatLabel,
    required this.tin,
    required this.email,
    required this.fullName,
  });
  final String businessName;
  final int vatReg;
  final String vatLabel;
  final String tin;
  final String email;
  final String fullName;

  bool get isVat => vatReg == 1;

  Map<String, dynamic> toJson() => {
        'businessName': businessName,
        'vatReg': vatReg,
        'vatLabel': vatLabel,
        'tin': tin,
        'email': email,
        'fullName': fullName,
      };

  static ShopInfo? fromJson(Map<String, dynamic> j) {
    try {
      return ShopInfo(
        businessName: (j['businessName'] ?? '').toString(),
        vatReg: (j['vatReg'] is int)
            ? j['vatReg'] as int
            : int.tryParse((j['vatReg'] ?? '0').toString()) ?? 0,
        vatLabel: (j['vatLabel'] ?? '').toString(),
        tin: (j['tin'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        fullName: (j['fullName'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  bool sameValuesAs(ShopInfo other) =>
      businessName == other.businessName &&
      vatReg == other.vatReg &&
      vatLabel == other.vatLabel &&
      tin == other.tin &&
      email == other.email &&
      fullName == other.fullName;
}

class TicketSubmitResult {
  TicketSubmitResult({required this.ok, required this.message, this.ticketId});
  final bool ok;
  final String message;
  final int? ticketId;
}
