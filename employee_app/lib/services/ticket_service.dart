import '../api_client.dart';

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
    int? conversationId,
  }) async {
    final res = await api.post('create_ticket', body: {
      'customerName': customerName,
      'customerEmail': customerEmail,
      'businessName': businessName,
      'vatReg': vatReg.toString(),
      'subject': subject,
      'description': description,
      'priority': priority,
      // Pass the conv we're already chatting in so the server can
      // link the ticket to it. Without this, admin-side resolve can't
      // post its "✅ resolved" announcement back to us (the server
      // gates that on a non-null conversation_id).
      if (conversationId != null && conversationId > 0)
        'conversation_id': conversationId.toString(),
    });
    final ok = res['status'] == 'success';
    return TicketSubmitResult(
      ok: ok,
      ticketId: int.tryParse((res['ticket_id'] ?? '').toString()),
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
