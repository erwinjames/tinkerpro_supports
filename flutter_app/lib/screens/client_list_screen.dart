import 'dart:async';

import 'package:flutter/material.dart';

import '../models/client_models.dart';
import '../services/client_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'client_detail_screen.dart';
import 'client_form_screen.dart';

/// Client & Data Sheet list — POS/hardware bundle records (web `client.php`).
class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key, required this.service});
  final ClientService service;

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<ClientBrief> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({String? search}) async {
    setState(() => _loading = true);
    final res = await widget.service.list(search: search);
    if (!mounted) return;
    setState(() {
      _rows = res.rows;
      _loading = false;
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _load(search: value);
    });
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ClientFormScreen(service: widget.service),
      ),
    );
    if (created == true) _load(search: _searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return StationScaffold(
      stationNumber: '15',
      stationLabel: 'CLIENT DATA SHEET',
      title: 'Clients.',
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.add,
        tooltip: 'New client',
        onPressed: _openCreate,
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              labelText: 'SEARCH · NAME · INVOICE',
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Brand.paperDim),
                      onPressed: () {
                        _searchController.clear();
                        _load();
                      },
                    ),
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: RefreshIndicator(
              color: Brand.signal,
              backgroundColor: Brand.surface,
              onRefresh: () => _load(search: _searchController.text),
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.signal),
                      ),
                    )
                  : _rows.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 64),
                            EmptyState(
                              label: 'No clients',
                              hint:
                                  'Nothing matched. Tap + to add a data sheet, or pull to refresh.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => const Hairline(),
                          itemBuilder: (_, i) {
                            final c = _rows[i];
                            return _ClientRow(
                              client: c,
                              onTap: () async {
                                final changed =
                                    await Navigator.of(context).push<bool>(
                                  MaterialPageRoute<bool>(
                                    builder: (_) => ClientDetailScreen(
                                      service: widget.service,
                                      brief: c,
                                    ),
                                  ),
                                );
                                if (changed == true) {
                                  _load(search: _searchController.text);
                                }
                              },
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client, required this.onTap});
  final ClientBrief client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasInvoice = client.invoiceNumber.trim().isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasInvoice ? Brand.signal : Brand.rule,
              ),
            ),
            Expanded(
              child: Text(
                client.name.isEmpty ? 'Untitled client' : client.name,
                style: text.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              hasInvoice ? client.invoiceNumber : '—',
              style: text.labelMedium?.copyWith(
                color: hasInvoice ? Brand.signal : Brand.paperDim,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
