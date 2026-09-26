class ClientInvoiceItem {
  ClientInvoiceItem({
    this.itemName = '',
    this.component = '',
    this.optionValue = '',
    this.brandName = '',
    this.serialNumber = '',
  });

  final String itemName;
  final String component;
  final String optionValue;
  final String brandName;
  final String serialNumber;

  factory ClientInvoiceItem.fromJson(Map<String, dynamic> json) =>
      ClientInvoiceItem(
        itemName: (json['item_name'] ?? '').toString(),
        component: (json['component_name'] ?? json['component'] ?? '')
            .toString(),
        optionValue: (json['option_value'] ?? '').toString(),
        brandName: (json['brand_name'] ?? '').toString(),
        serialNumber: (json['serial_number'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
    'item_name': itemName,
    'component': component,
    'option_value': optionValue,
    'brand_name': brandName,
    'serial_number': serialNumber,
  };

  bool get isEmpty =>
      optionValue.trim().isEmpty &&
      brandName.trim().isEmpty &&
      serialNumber.trim().isEmpty;
}

class ClientSpecReplacement {
  ClientSpecReplacement({
    required this.id,
    required this.rowKey,
    required this.oldComponent,
    required this.oldSerial,
    required this.newComponent,
    required this.newSerial,
    required this.remarks,
    required this.replacedByName,
    required this.replacedAt,
  });

  final int id;
  final String rowKey;
  final String oldComponent;
  final String oldSerial;
  final String newComponent;
  final String newSerial;
  final String remarks;
  final String replacedByName;
  final String replacedAt;

  factory ClientSpecReplacement.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '').toString();
    final when = s('replaced_at').trim().isNotEmpty
        ? s('replaced_at')
        : s('created_at');
    return ClientSpecReplacement(
      id: _asInt(json['id']),
      rowKey: s('row_key'),
      oldComponent: s('old_component'),
      oldSerial: s('old_serial'),
      newComponent: s('new_component'),
      newSerial: s('new_serial'),
      remarks: s('remarks'),
      replacedByName: s('replaced_by_name'),
      replacedAt: when,
    );
  }
}

class ClientInvoiceCheck {
  const ClientInvoiceCheck({
    required this.exists,
    required this.branch,
    required this.branchMatched,
    required this.clientName,
  });

  final bool exists;
  final String branch;
  final bool branchMatched;
  final String clientName;

  static const ClientInvoiceCheck free = ClientInvoiceCheck(
    exists: false,
    branch: '',
    branchMatched: true,
    clientName: '',
  );
}

class ClientBrief {
  ClientBrief({
    required this.id,
    required this.name,
    required this.invoiceNumber,
    this.branch = '',
    this.birImported = false,
  });

  final int id;
  final String name;
  final String invoiceNumber;
  final String branch;
  final bool birImported;

  factory ClientBrief.fromJson(Map<String, dynamic> json) => ClientBrief(
    id: _asInt(json['id']),
    name: (json['name'] ?? '').toString(),
    invoiceNumber: (json['invoice_number'] ?? '').toString(),
    branch: (json['branch'] ?? '').toString(),
    birImported:
        json['bir_imported'] == true ||
        json['bir_imported'] == 1 ||
        json['bir_imported'] == '1',
  );
}

class ClientDetail {
  ClientDetail({
    required this.id,
    required this.name,
    required this.invoiceNumber,
    required this.branch,
    required this.datePrepared,
    required this.systemUnit,
    required this.systemUnitSerial,
    required this.ramConfig,
    required this.motherboardSerial,
    required this.storageConfig,
    required this.storageSerial,
    required this.monitorSize,
    required this.monitorBrand,
    required this.monitorType,
    required this.monitorSerial,
    required this.keyboardSerial,
    required this.mouseSerial,
    required this.barcodeScannerSerial,
    required this.thermalPrinterSerial,
    required this.cashDrawerSerial,
    required this.barcodePrinterSerial,
    required this.cusDisplaySerial,
    required this.systemSerial,
    required this.macAddress,
    required this.min,
    required this.ptu,
    required this.dateApproved,
    required this.tin,
    required this.registeredAddress,
    required this.isVat,
    required this.invoiceItems,
    required this.specReplacements,
  });

  final int id;
  final String name;
  final String invoiceNumber;
  final String branch;
  final String datePrepared;
  final String systemUnit;
  final String systemUnitSerial;
  final String ramConfig;
  final String motherboardSerial;
  final String storageConfig;
  final String storageSerial;
  final String monitorSize;
  final String monitorBrand;
  final String monitorType;
  final String monitorSerial;
  final String keyboardSerial;
  final String mouseSerial;
  final String barcodeScannerSerial;
  final String thermalPrinterSerial;
  final String cashDrawerSerial;
  final String barcodePrinterSerial;
  final String cusDisplaySerial;
  final String systemSerial;
  final String macAddress;
  final String min;
  final String ptu;
  final String dateApproved;
  final String tin;
  final String registeredAddress;
  final bool isVat;
  final List<ClientInvoiceItem> invoiceItems;
  final List<ClientSpecReplacement> specReplacements;

  factory ClientDetail.fromJson(Map<String, dynamic> json) {
    final rawItems = json['invoice_items'];
    final items = (rawItems is List)
        ? rawItems
              .whereType<Map>()
              .map(
                (e) => ClientInvoiceItem.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
        : <ClientInvoiceItem>[];
    final rawRepl = json['spec_replacements'];
    final replacements = (rawRepl is List)
        ? rawRepl
              .whereType<Map>()
              .map(
                (e) => ClientSpecReplacement.fromJson(
                  Map<String, dynamic>.from(e),
                ),
              )
              .toList()
        : <ClientSpecReplacement>[];
    String s(String key) => (json[key] ?? '').toString();
    return ClientDetail(
      id: _asInt(json['id']),
      name: s('name'),
      invoiceNumber: s('invoice_number'),
      branch: s('branch'),
      datePrepared: _cleanDate(json['date_prepared']),
      systemUnit: s('system_unit'),
      systemUnitSerial: s('system_unit_serialnum'),
      ramConfig: s('ram_config'),
      motherboardSerial: s('motherboard_serialnum'),
      storageConfig: s('storage_config'),
      storageSerial: s('storage_serialnum'),
      monitorSize: s('monitorsize_config'),
      monitorBrand: s('monitorbrand_config'),
      monitorType: s('monitorType_config'),
      monitorSerial: s('monitor_serialnum'),
      keyboardSerial: s('keyboard_serialnum'),
      mouseSerial: s('mouse_serialnum'),
      barcodeScannerSerial: s('barcodeScanner_serialnum'),
      thermalPrinterSerial: s('thermalPrinter_serialnum'),
      cashDrawerSerial: s('cashDrawer_serialnum'),
      barcodePrinterSerial: s('barcodePrinter_serialnum'),
      cusDisplaySerial: s('cusdisplay_serialnum'),
      systemSerial: s('system_serialnum'),
      macAddress: s('mac_address'),
      min: s('min'),
      ptu: s('ptu'),
      dateApproved: _cleanDate(json['date_approved']),
      tin: s('tin'),
      registeredAddress: s('registered_address'),
      isVat: _asInt(json['is_vat']) == 1,
      invoiceItems: items,
      specReplacements: replacements,
    );
  }
}

class ClientSaveResult {
  ClientSaveResult({required this.ok, required this.message, this.clientId});
  final bool ok;
  final String message;
  final int? clientId;
}

String _cleanDate(Object? value) {
  final s = (value ?? '').toString().trim();
  if (s.isEmpty || s.startsWith('0000')) return '';
  return s.split(' ').first.split('T').first;
}

int _asInt(Object? value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
