import 'dart:convert';

class MultiDocExtractOutcome {
  const MultiDocExtractOutcome.done(Map<String, dynamic> this.data)
    : failure = null;
  const MultiDocExtractOutcome.failed(String this.failure) : data = null;

  final Map<String, dynamic>? data;
  final String? failure;
}

class PsicItem {
  const PsicItem(this.code, this.description);

  final String code;
  final String description;

  String get label => '$code - $description';
}

class LobCandidate {
  const LobCandidate({
    required this.code,
    required this.description,
    required this.label,
  });

  final String code;
  final String description;
  final String label;
}

class SoftwareVersionInfo {
  const SoftwareVersionInfo(this.version, this.accNumber);

  final String version;
  final String accNumber;
}

class OwnerName {
  const OwnerName({
    this.full = '',
    this.first = '',
    this.middle = '',
    this.last = '',
    this.isCorporate = false,
  });

  final String full;
  final String first;
  final String middle;
  final String last;
  final bool isCorporate;
}

class BirLogic {
  BirLogic._();

  static const brandOptions = <String>[
    'TinkerPro',
    'Cloned',
    'HP',
    'Dell',
    'Lenovo',
    'Acer',
    'Asus',
    'Apple',
    'Samsung',
    'MSI',
    'Toshiba',
    'Fujitsu',
    'Gigabyte',
    'Intel',
    'NEC',
    'Epson',
  ];

  static const modelOptions = <String>[
    'Generic',
    'Desktop',
    'Laptop',
    'Mini PC',
    'All-in-One',
    'Tower',
    'Workstation',
    'Tablet',
    'POS Terminal',
  ];

  static const serverTypeOptions = <String>['Consolidator', 'Global'];

  static const softwareVersionByName = <String, String>{
    'Wholesale/Retail V1.0': 'V1.0',
    'TinkerPro POS - QuickServe': '1',
  };

  static String s(Object? v) => v == null ? '' : v.toString();

  static String digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  static List<String> _words(String v) =>
      v.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();

  static ({String tin, String branch}) formatTin(
    String tinBranch,
    String branchCode,
  ) {
    final all = digits(tinBranch + branchCode);
    final tin9 = all.length > 9 ? all.substring(0, 9) : all;
    final branch = all.length > 9 ? all.substring(9) : '';
    String formatted;
    if (tin9.length == 9) {
      formatted =
          '${tin9.substring(0, 3)}-${tin9.substring(3, 6)}-${tin9.substring(6, 9)}';
    } else {
      final parts = <String>[];
      for (var i = 0; i < tin9.length; i += 3) {
        parts.add(tin9.substring(i, i + 3 > tin9.length ? tin9.length : i + 3));
      }
      formatted = parts.join('-');
    }
    return (tin: formatted, branch: branch);
  }

  static String branchFromTin(String currentBranch, String tin) {
    if (currentBranch.trim().isNotEmpty) return currentBranch;
    final d = digits(tin);
    if (d.length > 9) return d.substring(9);
    if (d.length == 9) return '00000';
    return currentBranch;
  }

  static String normalizeRegistrationType(String value) {
    final n = value.trim().toUpperCase();
    if (n.isEmpty) return '';
    if (n.contains('NON') && n.contains('VAT')) return 'NON-VAT';
    if (n.contains('EXEMPT') && n.contains('VAT')) return 'NON-VAT';
    if (n.contains('PERCENTAGE TAX')) return 'NON-VAT';
    if (n.contains('VAT')) return 'VAT';
    return '';
  }

  static ({String type, String source}) detectRegistrationType(
    Map<String, dynamic> r,
  ) {
    var vatType = normalizeRegistrationType(s(r['RegistrationType']));
    var vatSource = s(r['VATDetectedFrom']);
    final rawText = s(r['RawExtractedText']);

    if (vatType.isEmpty && rawText.isNotEmpty) {
      final u = rawText.toUpperCase();
      if (u.contains('NON-VAT') ||
          u.contains('NON VAT') ||
          u.contains('NONVAT') ||
          u.contains('VAT-EXEMPT') ||
          u.contains('VAT EXEMPT') ||
          u.contains('PERCENTAGE TAX') ||
          (u.contains('2551Q') &&
              !u.contains('2550M') &&
              !u.contains('2550Q'))) {
        vatType = 'NON-VAT';
        vatSource = 'raw_text';
      } else if (u.contains('VAT REGISTERED') ||
          u.contains('VALUE ADDED TAX') ||
          u.contains('2550M') ||
          u.contains('2550Q')) {
        vatType = 'VAT';
        vatSource = 'raw_text';
      }

      if (vatType.isEmpty) {
        if (RegExp(r'\b2[5S][5S][0O][MN]\b').hasMatch(u) ||
            RegExp(r'\b2[5S][5S][0O][QO]\b').hasMatch(u)) {
          vatType = 'VAT';
          vatSource = 'raw_text_ocr';
        } else if (RegExp(r'\b2[5S][5S][1I][QO]\b').hasMatch(u)) {
          vatType = 'NON-VAT';
          vatSource = 'raw_text_ocr';
        }
      }
    }

    final table = r['BIRTaxTypesTable'];
    if (vatType.isEmpty && table is List) {
      for (final row in table) {
        if (row is! Map) continue;
        final taxType = s(row['TaxType']).toUpperCase();
        final formType = s(row['FormType']).toUpperCase();
        if (taxType.contains('VALUE ADDED TAX') ||
            formType == '2550M' ||
            formType == '2550Q') {
          vatType = 'VAT';
          vatSource = 'tax_type_table';
          break;
        }
        if (taxType.contains('PERCENTAGE TAX') || formType == '2551Q') {
          vatType = 'NON-VAT';
          vatSource = 'tax_type_table';
        }
      }
    }
    return (type: normalizeRegistrationType(vatType), source: vatSource);
  }

  static ({String text, bool uncertain})? vatBadge(
    String vatStatus,
    String detectedFrom,
  ) {
    if (vatStatus.isEmpty) return null;
    const sourceLabels = <String, String>{
      'tax_type_table': 'BIR Tax Types',
      'form_codes': 'BIR Form Codes',
      'raw_text': 'Document Text',
      'registration_line': 'Registration Details',
      'form_code_scan': 'BIR Form Codes',
      'form_code_scan_conflict': 'BIR Form Codes (mixed)',
      'tax_type_wording': 'Tax Types Table',
      'explicit_wording': 'Document Text',
      'vat_keyword': 'Document Text',
    };
    const uncertainSources = <String, String>{
      'raw_text_ocr': 'blurred document text',
    };
    final uncertain =
        detectedFrom.isEmpty || uncertainSources.containsKey(detectedFrom);
    final sourceText =
        sourceLabels[detectedFrom] ??
        uncertainSources[detectedFrom] ??
        'an unconfirmed source';
    return (
      text: uncertain
          ? 'Best guess: $vatStatus from $sourceText — please verify'
          : 'Detected as $vatStatus from $sourceText',
      uncertain: uncertain,
    );
  }

  static ({String text, bool guess})? lobBadge(String lobValue, String source) {
    if (lobValue.isEmpty || source.isEmpty) return null;
    final guess = source == 'inferred_business_name';
    const labels = <String, String>{
      'psic_row': 'PSIC row on the document',
      'document': 'Document',
    };
    return (
      text: guess
          ? 'Guessed from the business name — not read off the document, please verify'
          : 'Detected from ${labels[source] ?? 'Document'}',
      guess: guess,
    );
  }

  static final _particleRe = RegExp(
    r'^(DE|DEL|DELA|DELAS|DELOS|DELAS|DI|LA|LAS|LOS|SAN|SANTA|STA|SANTO|STO|VDA|VAN|VON|Y)\.?$',
    caseSensitive: false,
  );

  static OwnerName splitOwnerNameParts(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return const OwnerName();
    var first = '', middle = '', last = '', suffix = '';

    final suffixMatch = RegExp(
      r'[\s,]+(JR|SR|II|III|IV|VI|VII)\.?$',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (suffixMatch != null &&
        cleaned
                .substring(0, suffixMatch.start)
                .trim()
                .split(RegExp(r'[\s,]+'))
                .where((e) => e.isNotEmpty)
                .length >=
            2) {
      suffix = suffixMatch.group(1)!.toUpperCase();
      cleaned = cleaned
          .substring(0, suffixMatch.start)
          .trim()
          .replaceAll(RegExp(r',+$'), '')
          .trim();
    }

    if (cleaned.contains(',')) {
      final commaParts = cleaned.split(',');
      last = commaParts[0].trim();
      final restWords = _words(commaParts.sublist(1).join(' ').trim());
      if (restWords.length >= 2) {
        first = restWords.sublist(0, restWords.length - 1).join(' ');
        middle = restWords.last;
      } else if (restWords.length == 1) {
        first = restWords[0];
      }
    } else {
      final words = _words(cleaned);
      if (words.length == 1) {
        first = words[0];
      } else if (words.length == 2) {
        first = words[0];
        last = words[1];
      } else if (words.length > 2) {
        var lastStart = words.length - 1;
        while (lastStart - 1 >= 1 &&
            _particleRe.hasMatch(words[lastStart - 1])) {
          lastStart--;
        }
        last = words.sublist(lastStart).join(' ');
        final head = words.sublist(0, lastStart);
        if (head.length >= 2) {
          middle = head.last;
          first = head.sublist(0, head.length - 1).join(' ');
        } else {
          first = head.join(' ');
        }
      }
    }

    if (suffix.isNotEmpty) last = '$last $suffix'.trim();
    return OwnerName(first: first, middle: middle, last: last);
  }

  static const _garbageWords = <String>[
    'REPUBLIKA',
    'PILIPINAS',
    'KAGAWARAN',
    'PANANALAPI',
    'KAWANIHAN',
    'KAWANEAN',
    'RENTAS',
    'INTERNAS',
    'KAGAWARA',
    'EUITWAS',
    'PANANALA',
    'PANANALAP',
    'PANAN',
    'RERIO',
    'RNAS',
    'BUREAU OF INTERNAL REVENUE',
    'CERTIFICATE OF REGISTRATION',
    'BIR FORM',
    'ASSISTANT REVENUE',
    'DISTRICT OFFICER',
    'TIN ISSUANCE',
    'NAME OF TAXPAYER',
    'OF TAXPAYER',
    'TIN & BRANCH',
    'BRANCH CODE',
    'REGISTERED NAME',
    'DATE OF REGISTRATION',
    'BUSINESS ADDRESS',
    'RDO CODE',
    'LINE OF BUSINESS',
    'REGISTRATION TYPE',
    'DATE OCN GENERATED',
    'OCN GENERATED',
    'PAYMENT MODE',
    'QUARTERLY',
    'MONTHLY',
    'ANNUALLY',
    'SEMI-ANNUALLY',
    'HEAD OFFICE',
    'REGISTERING OFFICE',
    'TRADE NAME',
    'BUSINESS INFORMATION',
  ];

  static OwnerName parseOwnerName(String raw) {
    var cleaned = raw
        .replaceAll(RegExp(r'^[\s.,\-_:;|/\\#*]+'), '')
        .replaceAll(RegExp(r'[\s.,\-_:;|/\\#*]+$'), '')
        .trim()
        .toUpperCase();
    if (cleaned.isEmpty) return const OwnerName();

    cleaned = cleaned
        .replaceAll(RegExp(r',\s*;'), ',')
        .replaceAll(RegExp(r';\s*,'), ',')
        .replaceAll(';', ',');

    for (final g in _garbageWords) {
      if (cleaned.contains(g)) return const OwnerName();
    }
    if (RegExp(r'^(N/A|NA|NONE|NULL|-+)$').hasMatch(cleaned)) {
      return const OwnerName();
    }

    final corpSuffixes = RegExp(
      r'\b(INC\.?|INCS?|ING\.?|CORP\.?|CORPORATION|LLC|LTD\.?|LIMITED|ENTERPRISES?|OPC|FOUNDATION|ASSOCIATION)\b',
    );
    final bizKeywords = RegExp(
      r'\b(CAFE|RESTAURANT|TRADING|SHOP|STORE|MART|SALON|BAKERY|PHARMACY|HARDWARE|HOTEL|RESORT|CONSTRUCTION|SERVICES|SUPPLY|MANUFACTURING|FOOD|BEVERAGES|REALTY|PROPERTIES|DEVELOPMENT|LOGISTICS|TRANSPORT|FREIGHT|PRINTING|MARKETING)\b',
    );
    var isCorporate = corpSuffixes.hasMatch(cleaned);
    if (!isCorporate) {
      final bizHits = bizKeywords.allMatches(cleaned).length;
      final wordCount = _words(cleaned).length;
      isCorporate = bizHits >= 2 || (bizHits >= 1 && wordCount >= 4);
    }
    if (isCorporate) return OwnerName(full: cleaned, isCorporate: true);

    if (RegExp(r'^\d{3}[-\s]?\d{2,3}').hasMatch(cleaned)) {
      return const OwnerName();
    }
    if (RegExp(r'[A-Z]').allMatches(cleaned).length < 3) {
      return const OwnerName();
    }

    const months =
        'JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER';
    cleaned = cleaned
        .replaceAll(RegExp(r'\s+(' + months + r')\s+\d{1,2},?\s+\d{4}\s*$'), '')
        .trim();
    cleaned = cleaned
        .replaceAll(RegExp(r'\s+(' + months + r')\s*$'), '')
        .trim();
    if (cleaned.isEmpty) return const OwnerName();

    final parts = splitOwnerNameParts(cleaned);
    if (cleaned.contains(',')) {
      cleaned = [
        parts.first,
        parts.middle,
        parts.last,
      ].where((e) => e.isNotEmpty).join(' ');
    }
    return OwnerName(
      full: cleaned,
      first: parts.first,
      middle: parts.middle,
      last: parts.last,
    );
  }

  static OwnerName splitManualHolderName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
    if (cleaned.isEmpty) return const OwnerName();
    var first = '', middle = '', last = '';
    if (cleaned.contains(',')) {
      final commaParts = cleaned.split(',');
      last = commaParts[0].trim();
      final restWords = _words(commaParts.sublist(1).join(',').trim());
      if (restWords.length >= 2) {
        first = restWords.sublist(0, restWords.length - 1).join(' ');
        middle = restWords.last;
      } else if (restWords.length == 1) {
        first = restWords[0];
      }
    } else {
      final words = _words(cleaned);
      if (words.length >= 3) {
        first = words[0];
        middle = words.sublist(1, words.length - 1).join(' ');
        last = words.last;
      } else if (words.length == 2) {
        first = words[0];
        last = words[1];
      } else {
        last = words[0];
      }
    }
    return OwnerName(
      full: [first, middle, last].where((e) => e.isNotEmpty).join(' '),
      first: first,
      middle: middle,
      last: last,
    );
  }

  static PsicItem? findPsicMatch(List<PsicItem> data, String rawLob) {
    if (data.isEmpty) return null;
    final raw = rawLob.trim();
    if (raw.isEmpty) return null;

    final codeMatch = RegExp(r'\b(\d{4,5})\b').firstMatch(raw);
    if (codeMatch != null) {
      final code = codeMatch.group(1)!;
      for (final item in data) {
        if (item.code == code) return item;
      }
    }

    final needle = raw
        .toLowerCase()
        .replaceFirst(RegExp(r'^\d{3,6}\s*[-–—]\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (needle.isEmpty) return null;

    PsicItem? exact, startsWith, wordMatch, contains;
    final wordRx = RegExp(r'\b' + RegExp.escape(needle) + r'\b');
    for (final item in data) {
      final desc = item.description
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (desc.isEmpty) continue;
      if (desc == needle) {
        exact = item;
        break;
      }
      if (desc.startsWith('$needle ') ||
          desc == '${needle}s' ||
          desc.startsWith('$needle (')) {
        if (startsWith == null || desc.length < startsWith.description.length) {
          startsWith = item;
        }
        continue;
      }
      if (wordRx.hasMatch(desc)) {
        if (wordMatch == null || desc.length < wordMatch.description.length) {
          wordMatch = item;
        }
        continue;
      }
      if (desc.contains(needle)) {
        if (contains == null || desc.length < contains.description.length) {
          contains = item;
        }
      }
    }
    return exact ?? startsWith ?? wordMatch ?? contains;
  }

  static List<LobCandidate> resolveLobCandidates(
    List<PsicItem> data,
    Object? candidates,
  ) {
    final resolved = <LobCandidate>[];
    final seen = <String>{};
    if (candidates is! List) return resolved;
    for (final raw in candidates) {
      final match = findPsicMatch(data, s(raw));
      String label, code, description;
      if (match != null) {
        code = match.code;
        description = match.description;
        label = '$code - $description';
      } else {
        label = s(raw).trim();
        code = RegExp(r'\b(\d{4,5})\b').firstMatch(label)?.group(1) ?? label;
        description = label.replaceFirst(RegExp(r'^\s*\d{3,6}\s*[-–—]\s*'), '');
      }
      if (label.isEmpty || seen.contains(code)) continue;
      seen.add(code);
      resolved.add(
        LobCandidate(code: code, description: description, label: label),
      );
    }
    return resolved;
  }

  static String lobCodeFromValue(String v) =>
      RegExp(r'\b(\d{4,5})\b').firstMatch(v)?.group(1) ?? '';

  static List<PsicItem> searchPsic(List<PsicItem> data, String input) {
    final q = input.trim();
    if (q.isEmpty) return const [];
    final lower = q.toLowerCase();
    return data
        .where(
          (i) =>
              i.code.contains(q) || i.description.toLowerCase().contains(lower),
        )
        .toList();
  }

  static const _lobInferMap = <String, List<String>>{
    'RESTAURANTS': [
      'SEAFOOD',
      'GRILL',
      'EATERY',
      'BISTRO',
      'DINER',
      'RESTAURANT',
      'CARENDERIA',
      'CARINDERIA',
      'CANTEEN',
      'FOOD HOUSE',
      'FOOD HUB',
      'FOOD PARK',
      'CAFE',
      'COFFEE',
      'RAMEN',
      'SUSHI',
      'PIZZA',
      'BURGER',
      'CHICKEN',
      'BBQ',
      'BARBECUE',
      'BAR AND GRILL',
      'BAR & GRILL',
      'KITCHENETTE',
    ],
    'BAKERY AND BAKESHOP': [
      'BAKERY',
      'BAKESHOP',
      'BAKE SHOP',
      'BREAD',
      'PASTRY',
      'PANDESAL',
    ],
    'SARI-SARI STORE': ['SARI-SARI', 'SARI SARI'],
    'GROCERY STORE': ['GROCERY', 'SUPERMARKET', 'MINIMART', 'MINI MART'],
    'DRUGSTORE AND PHARMACY': ['PHARMACY', 'DRUGSTORE', 'DRUG STORE', 'BOTICA'],
    'HARDWARE STORE': ['HARDWARE', 'CONSTRUCTION SUPPLY', 'BUILDING MATERIALS'],
    'WATER REFILLING STATION': ['WATER REFILLING', 'WATER STATION'],
    'GASOLINE STATION': ['GASOLINE', 'GAS STATION', 'FUEL STATION', 'PETROL'],
    'LAUNDRY AND DRY CLEANING SERVICES': [
      'LAUNDRY',
      'LAUNDROMAT',
      'DRY CLEANING',
    ],
    'BARBER AND BEAUTY SHOPS': [
      'SALON',
      'BARBER',
      'BARBERSHOP',
      'BEAUTY',
      'PARLOR',
      'PARLOUR',
      'SPA',
      'NAIL',
    ],
    'INTERNET CAFE': [
      'INTERNET CAFE',
      'COMPUTER SHOP',
      'GAMING',
      'PC RENTAL',
      'PISONET',
    ],
    'PRINTING AND SERVICE ACTIVITIES RELATED TO PRINTING': [
      'PRINTING',
      'PRINT SHOP',
    ],
    'RETAIL SELLING IN CONVENIENCE STORES': [
      'CONVENIENCE STORE',
      'RETAIL STORE',
    ],
    'RETAIL SELLING IN NON-SPECIALIZED STORES': [
      'GENERAL MERCHANDISE',
      'DEPARTMENT STORE',
      'VARIETY STORE',
    ],
  };

  static String inferLobFromBusinessName(String bizName) {
    final upper = bizName.toUpperCase();
    if (upper.isEmpty) return '';
    for (final entry in _lobInferMap.entries) {
      for (final k in entry.value) {
        if (upper.contains(k)) return entry.key;
      }
    }
    return '';
  }

  static String normalizeSoftwareName(
    String rawName,
    Iterable<String> catalogNames,
  ) {
    String matching(String needle) {
      for (final n in catalogNames) {
        if (n.toUpperCase().contains(needle)) return n;
      }
      return '';
    }

    final upper = rawName.toUpperCase();
    if (upper.contains('QUICKSERVE')) {
      final m = matching('QUICKSERVE');
      return m.isNotEmpty ? m : 'TinkerPro POS - QuickServe';
    }
    if (upper.contains('WHOLESALE') || upper.contains('RETAIL')) {
      final w = matching('WHOLESALE');
      if (w.isNotEmpty) return w;
      final r = matching('RETAIL');
      return r.isNotEmpty ? r : 'Wholesale/Retail V1.0';
    }
    return '';
  }

  static Map<String, List<SoftwareVersionInfo>> parseCatalog(Object? data) {
    final out = <String, List<SoftwareVersionInfo>>{};
    if (data is! Map) return out;
    data.forEach((k, v) {
      final list = <SoftwareVersionInfo>[];
      if (v is List) {
        for (final e in v) {
          if (e is Map) {
            list.add(SoftwareVersionInfo(s(e['version']), s(e['acc_number'])));
          }
        }
      }
      out[s(k)] = list;
    });
    return out;
  }

  static List<PsicItem> parsePsic(String body) {
    var text = body.trim();
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    text = text.substring(start, end + 1);
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      try {
        decoded = jsonDecode(
          text.replaceAllMapped(RegExp(r',\s*([\]}])'), (m) => m.group(1)!),
        );
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! List) return const [];
    final out = <PsicItem>[];
    for (final e in decoded) {
      if (e is! Map) continue;
      final code = s(e['code']).trim();
      final desc = s(e['description']).trim();
      if (code.isEmpty && desc.isEmpty) continue;
      out.add(PsicItem(code, desc));
    }
    return out;
  }

  static List<String> serialTypeOptions(List<String> allTypes, int index) {
    var serverTaken = false, hasServerOrTerminal = false, hasStandalone = false;
    for (final v in allTypes) {
      if (v == 'Server') {
        serverTaken = true;
        hasServerOrTerminal = true;
      } else if (v == 'Terminal') {
        hasServerOrTerminal = true;
      } else if (v == 'Standalone') {
        hasStandalone = true;
      }
    }
    final current = allTypes[index];
    return [
      if (current == 'Server' || (!serverTaken && !hasStandalone)) 'Server',
      if (current == 'Terminal' || !hasStandalone) 'Terminal',
      if (current == 'Standalone' || !hasServerOrTerminal) 'Standalone',
    ];
  }

  static String tinLineOwnerFallback(String rawText) {
    final m = RegExp(
      r'\b\d{3}[-\s]?\d{3}[-\s]?\d{3}[-\s]?\d{3,5}\b[.,]?\s+(.+?)\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}',
      caseSensitive: false,
    ).firstMatch(rawText);
    return m?.group(1) ?? '';
  }
}

class LicenseSerialSuggestion {
  const LicenseSerialSuggestion({
    required this.serial,
    this.storeName = '',
    this.licenseKey = '',
    this.machineType = '',
    this.storeAddress = '',
    this.assignedTo = '',
    this.isUsed = false,
    this.trial = false,
    this.expired = false,
    this.dateExpired = '',
  });

  factory LicenseSerialSuggestion.fromJson(Map<String, dynamic> json) {
    return LicenseSerialSuggestion(
      serial: (json['serial'] ?? '').toString(),
      storeName: (json['store_name'] ?? '').toString(),
      licenseKey: (json['license_key'] ?? '').toString(),
      machineType: (json['machine_type'] ?? '').toString(),
      storeAddress: (json['store_address'] ?? '').toString(),
      assignedTo: (json['assigned_to'] ?? '').toString(),
      isUsed: json['is_used'] == true || json['is_used'] == 1,
      trial: json['trial'] == true || json['trial'] == 1,
      expired: json['expired'] == true || json['expired'] == 1,
      dateExpired: (json['date_expired'] ?? '').toString(),
    );
  }

  final String serial;
  final String storeName;
  final String licenseKey;
  final String machineType;
  final String storeAddress;
  final String assignedTo;
  final bool isUsed;
  final bool trial;
  final bool expired;
  final String dateExpired;

  bool get taken => assignedTo.isNotEmpty;

  bool get selectable => serial.isNotEmpty;

  String get title => serial.isEmpty ? 'No serial number on file' : serial;

  String get detail {
    final parts = <String>[];
    if (storeName.isNotEmpty) parts.add(storeName);
    if (licenseKey.isNotEmpty) parts.add(licenseKey);
    if (machineType.isNotEmpty) parts.add(machineType);
    if (trial) parts.add('Temporary');
    if (expired) parts.add('Expired');
    if (taken) {
      parts.add('In use by $assignedTo');
    } else if (isUsed) {
      parts.add('Activated');
    }
    return parts.join(' • ');
  }
}
