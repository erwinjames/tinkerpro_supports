import '../api_client.dart';
import '../models/customer_models.dart';
import 'session_store.dart';

/// Portal auth — TIN-based instead of username/password.
///
/// Flow:
///   1. [fetchBranches] — given a TIN, server returns one or more branches.
///   2. [loginToBranch]  — picks a branch; server sets the portal session
///                          cookie (PHPSESSID linked to
///                          $_SESSION['client_portal_customer_id']) and
///                          returns the full Customer record.
///   3. [restoreSession]  — on app relaunch, asks server who we are based
///                          on the persisted cookie. Returns null if the
///                          server has expired our session.
///   4. [logout]          — clears server session + local prefs + cookies.
class AuthService {
  AuthService(this.api, this.store);

  final ApiClient api;
  final SessionStore store;

  /// Returns the list of branches for a TIN, or an empty list if there's
  /// no registration on file. Throws nothing — surfaces errors via the
  /// returned [BranchFetchResult.message].
  Future<BranchFetchResult> fetchBranches(String rawTin) async {
    final tin = _normalizeTin(rawTin);
    if (tin.isEmpty) {
      return const BranchFetchResult(
        branches: [],
        message: 'Enter your TIN first.',
      );
    }
    try {
      final res = await api.get('getCustomerBranchesByTin', params: {'tin': tin});
      if (res['status'] == 'success' && res['branches'] is List) {
        final list = (res['branches'] as List)
            .whereType<Map>()
            .map((m) => Branch.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        return BranchFetchResult(
          branches: list,
          message: list.isEmpty
              ? 'No registration found for that TIN.'
              : null,
        );
      }
      return BranchFetchResult(
        branches: const [],
        message: (res['message'] ?? 'No registration found for that TIN.')
            .toString(),
      );
    } catch (e) {
      return BranchFetchResult(
        branches: const [],
        message: 'Could not reach the server. Check your connection.',
      );
    }
  }

  /// Pick a specific branch and start the portal session. On success the
  /// PHPSESSID cookie now carries `client_portal_customer_id` server-side;
  /// downstream chat/call requests pick this up automatically.
  Future<Customer?> loginToBranch(String rawTin, String branchCode) async {
    final tin = _normalizeTin(rawTin);
    if (tin.isEmpty || branchCode.isEmpty) return null;
    try {
      final res = await api.get('getCustomerPortalByTin',
          params: {'tin': tin, 'branch_code': branchCode});
      if (res['status'] == 'success' && res['customer'] is Map) {
        final customer = Customer.fromJson(
            Map<String, dynamic>.from(res['customer'] as Map));
        await store.setLastTin(tin);
        await store.setLastBranch(branchCode);
        await store.setActiveCustomerId(customer.id);
        return customer;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Pulls the server's notion of the active portal customer based on the
  /// PHPSESSID cookie we saved last run. Returns null if the session has
  /// expired (backend session storage GC, server restart, manual logout
  /// from another device, etc.).
  Future<Customer?> restoreSession() async {
    final cachedId = store.activeCustomerId;
    if (cachedId == null) return null;
    try {
      final res = await api.get('getCustomerPortalSession');
      if (res['status'] == 'success' && res['customer'] is Map) {
        return Customer.fromJson(
            Map<String, dynamic>.from(res['customer'] as Map));
      }
      // Session no longer valid on the server — clear local cache so we
      // don't loop trying to restore on every launch.
      await store.setActiveCustomerId(null);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await api.post('logoutCustomerPortal');
    } catch (_) {}
    await store.setActiveCustomerId(null);
    await api.wipeCookies();
  }

  String _normalizeTin(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '').trim();
  }
}

class BranchFetchResult {
  const BranchFetchResult({required this.branches, this.message});
  final List<Branch> branches;
  final String? message;
}
