import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'notification_service.dart';
import 'services.dart';

class NotificationCenter extends ChangeNotifier {
  NotificationCenter({
    required this.leads,
    required this.customers,
    this.allowLeads,
    this.allowCustomers,
  });

  final LeadService leads;
  final CustomerService customers;
  final bool Function()? allowLeads;
  final bool Function()? allowCustomers;

  static const _kLegacyLeadKey = 'notif_last_lead_id';
  static const _kLegacyCustomerKey = 'notif_last_customer_id';

  List<LeadBrief> _leads = const [];
  List<CustomerBrief> _customers = const [];
  int _lastSeenLeadId = 0;
  int _lastSeenCustomerId = 0;
  String? _initialisedFor;
  bool _baselineLeads = false;
  bool _baselineCustomers = false;
  bool _loading = false;

  String get _scope => '${leads.api.userId ?? 0}';

  String get _leadKey => 'notif_seen_lead_u$_scope';

  String get _customerKey => 'notif_seen_customer_u$_scope';

  bool get loading => _loading;

  List<LeadBrief> get unseenLeads =>
      _leads.where((l) => l.id > _lastSeenLeadId).toList();

  List<CustomerBrief> get unseenCustomers =>
      _customers.where((c) => c.id > _lastSeenCustomerId).toList();

  AppNotificationCenter? _alerts;

  AppNotificationCenter? get alerts => _alerts;

  int get unreadAlerts => _alerts?.unread ?? 0;

  int get unseenCount =>
      unseenLeads.length + unseenCustomers.length + unreadAlerts;

  void attachAlerts(AppNotificationCenter? center) {
    if (identical(_alerts, center)) return;
    _alerts?.removeListener(_onAlertsChanged);
    _alerts = center;
    _alerts?.addListener(_onAlertsChanged);
    notifyListeners();
  }

  void _onAlertsChanged() => notifyListeners();

  @override
  void dispose() {
    _alerts?.removeListener(_onAlertsChanged);
    _alerts = null;
    super.dispose();
  }

  Future<void> _ensureInit() async {
    final scope = _scope;
    if (_initialisedFor == scope) return;
    _initialisedFor = scope;
    final prefs = await SharedPreferences.getInstance();
    final legacyLead = prefs.getInt(_kLegacyLeadKey);
    final legacyCustomer = prefs.getInt(_kLegacyCustomerKey);
    if (legacyLead != null && prefs.getInt(_leadKey) == null) {
      await prefs.setInt(_leadKey, legacyLead);
    }
    if (legacyCustomer != null && prefs.getInt(_customerKey) == null) {
      await prefs.setInt(_customerKey, legacyCustomer);
    }
    await prefs.remove(_kLegacyLeadKey);
    await prefs.remove(_kLegacyCustomerKey);
    final lead = prefs.getInt(_leadKey);
    final customer = prefs.getInt(_customerKey);
    _lastSeenLeadId = lead ?? 0;
    _lastSeenCustomerId = customer ?? 0;
    _baselineLeads = lead == null;
    _baselineCustomers = customer == null;
  }

  int _maxId(Iterable<int> ids, int floor) =>
      ids.fold<int>(floor, (a, b) => a > b ? a : b);

  Future<void> refresh() async {
    await _ensureInit();
    final alerts = _alerts;
    if (alerts != null && !alerts.loading) {
      unawaited(alerts.load());
    }
    if (_loading) return;
    _loading = true;
    notifyListeners();
    final wantLeads = allowLeads?.call() ?? true;
    final wantCustomers = allowCustomers?.call() ?? true;
    final results = await Future.wait([
      wantLeads ? leads.list() : Future.value(const <LeadBrief>[]),
      wantCustomers ? customers.list() : Future.value(const <CustomerBrief>[]),
    ]);
    _leads = results[0] as List<LeadBrief>;
    _customers = results[1] as List<CustomerBrief>;
    final prefs = await SharedPreferences.getInstance();
    if (_baselineLeads && _leads.isNotEmpty) {
      _lastSeenLeadId = _maxId(_leads.map((l) => l.id), _lastSeenLeadId);
      _baselineLeads = false;
      await prefs.setInt(_leadKey, _lastSeenLeadId);
    }
    if (_baselineCustomers && _customers.isNotEmpty) {
      _lastSeenCustomerId = _maxId(
        _customers.map((c) => c.id),
        _lastSeenCustomerId,
      );
      _baselineCustomers = false;
      await prefs.setInt(_customerKey, _lastSeenCustomerId);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> markAllSeen() async {
    await _ensureInit();
    final prefs = await SharedPreferences.getInstance();
    if (_leads.isNotEmpty) {
      _lastSeenLeadId = _maxId(_leads.map((l) => l.id), _lastSeenLeadId);
      _baselineLeads = false;
      await prefs.setInt(_leadKey, _lastSeenLeadId);
    }
    if (_customers.isNotEmpty) {
      _lastSeenCustomerId = _maxId(
        _customers.map((c) => c.id),
        _lastSeenCustomerId,
      );
      _baselineCustomers = false;
      await prefs.setInt(_customerKey, _lastSeenCustomerId);
    }
    notifyListeners();
  }
}
