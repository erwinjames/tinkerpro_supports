import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinkerpro_support_flutter/api_client.dart';
import 'package:tinkerpro_support_flutter/models/models.dart';
import 'package:tinkerpro_support_flutter/services/notification_center.dart';
import 'package:tinkerpro_support_flutter/services/services.dart';

class _Leads extends LeadService {
  _Leads(super.api);
  List<int> ids = [];

  @override
  Future<List<LeadBrief>> list() async => [
    for (final id in ids) LeadBrief.fromJson({'id': id}),
  ];
}

class _Customers extends CustomerService {
  _Customers(super.api);
  List<int> ids = [];

  @override
  Future<List<CustomerBrief>> list({String? search, int limit = 50}) async => [
    for (final id in ids) CustomerBrief.fromJson({'id': id}),
  ];
}

Future<(ApiClient, _Leads, _Customers)> _setup(
  Map<String, Object> prefs,
) async {
  SharedPreferences.setMockInitialValues(prefs);
  final api = await ApiClient.load();
  return (api, _Leads(api), _Customers(api));
}

NotificationCenter _center(_Leads leads, _Customers customers) =>
    NotificationCenter(leads: leads, customers: customers);

void main() {
  test('first use counts existing leads and customers as seen', () async {
    final (api, leads, customers) = await _setup({});
    await api.setUserId(7);
    leads.ids = [1, 2, 3];
    customers.ids = [10, 11];
    final center = _center(leads, customers);
    await center.refresh();
    expect(center.unseenLeads, isEmpty);
    expect(center.unseenCustomers, isEmpty);

    leads.ids = [1, 2, 3, 4];
    await center.refresh();
    expect(center.unseenLeads.map((l) => l.id), [4]);
  });

  test('seen state survives logout and login for the same user', () async {
    final (api, leads, customers) = await _setup({});
    await api.setUserId(7);
    leads.ids = [1, 2];
    customers.ids = [10];
    final first = _center(leads, customers);
    await first.refresh();
    leads.ids = [1, 2, 3];
    customers.ids = [10, 12];
    await first.refresh();
    expect(first.unseenCount, 2);
    await first.markAllSeen();
    expect(first.unseenCount, 0);

    await api.clearSession();
    await api.setUserId(7);

    final again = _center(leads, customers);
    await again.refresh();
    expect(again.unseenLeads, isEmpty);
    expect(again.unseenCustomers, isEmpty);
  });

  test('another user on the same phone keeps their own seen state', () async {
    final (api, leads, customers) = await _setup({});
    await api.setUserId(7);
    leads.ids = [1];
    final a = _center(leads, customers);
    await a.refresh();
    leads.ids = [1, 2, 3];
    await a.refresh();
    expect(a.unseenLeads.length, 2);

    await api.clearSession();
    await api.setUserId(9);
    final b = _center(leads, customers);
    await b.refresh();
    expect(b.unseenLeads, isEmpty);

    await api.clearSession();
    await api.setUserId(7);
    final aAgain = _center(leads, customers);
    await aAgain.refresh();
    expect(aAgain.unseenLeads.map((l) => l.id), [2, 3]);
  });

  test('an existing marker is carried over from the old storage', () async {
    final (api, leads, customers) = await _setup({
      'notif_last_lead_id': 5,
      'notif_last_customer_id': 20,
    });
    await api.setUserId(7);
    leads.ids = [4, 5, 6];
    customers.ids = [20, 21];
    final center = _center(leads, customers);
    await center.refresh();
    expect(center.unseenLeads.map((l) => l.id), [6]);
    expect(center.unseenCustomers.map((c) => c.id), [21]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('notif_last_lead_id'), isNull);
  });
}
