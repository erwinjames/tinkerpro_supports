import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../theme.dart';
import '../widgets/premium.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.service,
    required this.brief,
  });

  final CustomerService service;
  final CustomerBrief brief;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await widget.service.detail(widget.brief.id);
    if (!mounted) return;
    setState(() {
      _detail = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail ?? {};
    final branch = (d['branch_code'] ?? '').toString();
    final rdo = (d['rdo'] ?? d['rdo_code'] ?? '').toString();
    final address = (d['address'] ?? widget.brief.address).toString();
    final serial = (d['serial_number'] ?? '—').toString();
    final software = (d['software_name'] ?? d['softwarename'] ?? '—')
        .toString();
    final accNumber = (d['acc_number'] ?? d['accreditation_number'] ?? '—')
        .toString();
    final vat = (d['vat_status'] ?? '').toString();

    return StationScaffold(
      stationNumber: widget.brief.id.toString().padLeft(2, '0'),
      stationLabel: 'CLIENT DETAIL',
      title: widget.brief.companyName,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      trailing: StationAction(
        icon: Icons.refresh,
        tooltip: 'Refresh',
        onPressed: _load,
      ),
      child: _loading
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Brand.signal,
                ),
              ),
            )
          : ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.brief.status == 'Processed'
                            ? Brand.signal
                            : Brand.rule,
                      ),
                    ),
                    Text(
                      widget.brief.status.toUpperCase(),
                      style:
                          Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: widget.brief.status == 'Processed'
                                    ? Brand.signal
                                    : Brand.paperDim,
                              ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                StationDataRow(
                  label: 'TIN · BRANCH',
                  value:
                      '${widget.brief.tin.isEmpty ? '—' : widget.brief.tin}${branch.isEmpty ? '' : '  ·  $branch'}',
                ),
                const SizedBox(height: 20),
                StationDataRow(
                  label: 'OWNER',
                  value: widget.brief.ownerName.isEmpty
                      ? '—'
                      : widget.brief.ownerName,
                ),
                const SizedBox(height: 20),
                StationDataRow(label: 'ADDRESS', value: address.isEmpty ? '—' : address),
                const SizedBox(height: 20),
                StationDataRow(label: 'RDO', value: rdo.isEmpty ? '—' : rdo),
                const SizedBox(height: 20),
                StationDataRow(
                  label: 'VAT STATUS',
                  value: vat.isEmpty ? '—' : vat.toUpperCase(),
                ),
                const SizedBox(height: 40),
                Text('Point-of-sale',
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Hairline(),
                const SizedBox(height: 20),
                StationDataRow(label: 'SOFTWARE', value: software),
                const SizedBox(height: 20),
                StationDataRow(label: 'ACC. NUMBER', value: accNumber),
                const SizedBox(height: 20),
                StationDataRow(label: 'SERIAL NUMBER', value: serial),
                const SizedBox(height: 40),
                Text(
                  'Uploads, edits, and VAT status changes are currently '
                  'available on the web portal. Open the record in a browser '
                  'to modify documents.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
