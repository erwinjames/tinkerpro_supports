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
  }) async {
    final res = await api.post('create_ticket', body: {
      'customerName': customerName,
      'customerEmail': customerEmail,
      'businessName': businessName,
      'vatReg': vatReg.toString(),
      'subject': subject,
      'description': description,
      'priority': priority,
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
}

class TicketSubmitResult {
  TicketSubmitResult({required this.ok, required this.message, this.ticketId});
  final bool ok;
  final String message;
  final int? ticketId;
}
