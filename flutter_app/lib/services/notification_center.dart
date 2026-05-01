import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'services.dart';

/// Tracks new leads and customers since the user last opened the
/// notification panel. We persist the highest seen id per type — anything
/// with a larger id is treated as "new" until the user marks it seen.
class NotificationCenter extends ChangeNotifier {
  NotificationCenter({required this.leads, required this.customers});

  final LeadService leads;
  final CustomerService customers;

  static const _kLastLeadIdKey = 'notif_last_lead_id';
  static const _kLastCustomerIdKey = 'notif_last_customer_id';

  List<LeadBrief> _leads = const [];
  List<CustomerBrief> _customers = const [];
  int _lastSeenLeadId = 0;
  int _lastSeenCustomerId = 0;
  bool _initialised = false;
  bool _loading = false;

  bool get loading => _loading;

  List<LeadBrief> get unseenLeads =>
      _leads.where((l) => l.id > _lastSeenLeadId).toList();

  List<CustomerBrief> get unseenCustomers =>
      _customers.where((c) => c.id > _lastSeenCustomerId).toList();

  int get unseenCount => unseenLeads.length + unseenCustomers.length;

  Future<void> _ensureInit() async {
    if (_initialised) return;
    _initialised = true;
    final prefs = await SharedPreferences.getInstance();
    _lastSeenLeadId = prefs.getInt(_kLastLeadIdKey) ?? 0;
    _lastSeenCustomerId = prefs.getInt(_kLastCustomerIdKey) ?? 0;
  }

  Future<void> refresh() async {
    await _ensureInit();
    if (_loading) return;
    _loading = true;
    notifyListeners();
    final results = await Future.wait([
      leads.list(),
      customers.list(),
    ]);
    _leads = results[0] as List<LeadBrief>;
    _customers = results[1] as List<CustomerBrief>;
    _loading = false;
    notifyListeners();
  }

  Future<void> markAllSeen() async {
    await _ensureInit();
    final prefs = await SharedPreferences.getInstance();
    if (_leads.isNotEmpty) {
      _lastSeenLeadId = _leads
          .map((l) => l.id)
          .fold<int>(_lastSeenLeadId, (a, b) => a > b ? a : b);
      await prefs.setInt(_kLastLeadIdKey, _lastSeenLeadId);
    }
    if (_customers.isNotEmpty) {
      _lastSeenCustomerId = _customers
          .map((c) => c.id)
          .fold<int>(_lastSeenCustomerId, (a, b) => a > b ? a : b);
      await prefs.setInt(_kLastCustomerIdKey, _lastSeenCustomerId);
    }
    notifyListeners();
  }
}
