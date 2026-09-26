import 'package:flutter/material.dart';

import '../models/employment_models.dart';
import '../services/employment_service.dart';
import '../theme.dart';
import '../widgets/premium.dart';
import 'employment_record_screen.dart';

const _kSpouseFields = ['spouse_name', 'spouse_employer', 'spouse_work_phone'];

const _kTextFields = [
  'full_name',
  'address',
  'birth_place',
  'cell_phone',
  'email',
  'government_id',
  'spouse_name',
  'spouse_employer',
  'spouse_work_phone',
  'job_title',
  'supervisor',
  'work_location',
  'work_email',
  'work_phone',
  'work_cell_phone',
  'salary',
];

class _ContactControllers {
  _ContactControllers(EmergencyContact c)
    : fullName = TextEditingController(text: c.fullName),
      address = TextEditingController(text: c.address),
      primaryPhone = TextEditingController(text: c.primaryPhone),
      cellPhone = TextEditingController(text: c.cellPhone),
      relationship = TextEditingController(text: c.relationship);

  final TextEditingController fullName;
  final TextEditingController address;
  final TextEditingController primaryPhone;
  final TextEditingController cellPhone;
  final TextEditingController relationship;

  Map<String, String> toJson() => {
    'full_name': fullName.text.trim(),
    'address': address.text.trim(),
    'primary_phone': primaryPhone.text.trim(),
    'cell_phone': cellPhone.text.trim(),
    'relationship': relationship.text.trim(),
  };

  void dispose() {
    fullName.dispose();
    address.dispose();
    primaryPhone.dispose();
    cellPhone.dispose();
    relationship.dispose();
  }
}

class _DependentControllers {
  _DependentControllers(EmploymentDependent d)
    : name = TextEditingController(text: d.name),
      relationship = TextEditingController(text: d.relationship);

  final TextEditingController name;
  final TextEditingController relationship;

  void dispose() {
    name.dispose();
    relationship.dispose();
  }
}

class EmploymentEditScreen extends StatefulWidget {
  const EmploymentEditScreen({
    super.key,
    required this.service,
    required this.record,
  });

  final EmploymentService service;
  final EmploymentRecord record;

  @override
  State<EmploymentEditScreen> createState() => _EmploymentEditScreenState();
}

class _EmploymentEditScreenState extends State<EmploymentEditScreen> {
  final Map<String, TextEditingController> _c = {};
  final List<_ContactControllers> _contacts = [];
  final List<_DependentControllers> _deps = [];
  String _marital = '';
  String _birthDate = '';
  String _startDate = '';
  bool _noDependents = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _spouseless => kSpouselessStatuses.contains(_marital);

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    for (final key in _kTextFields) {
      _c[key] = TextEditingController(text: r.field(key));
    }
    final m = r.maritalStatus;
    _marital = kMaritalStatuses.contains(m) ? m : '';
    _birthDate = _isoOrEmpty(r.field('birth_date'));
    _startDate = _isoOrEmpty(r.field('start_date'));
    _noDependents = r.hasNoDependents;
    final contacts = r.emergencyContacts;
    while (contacts.length < kMinEmergencyContacts) {
      contacts.add(EmergencyContact());
    }
    _contacts.addAll(contacts.map(_ContactControllers.new));
    final deps = r.dependents;
    if (deps.isEmpty) {
      _deps.add(_DependentControllers(EmploymentDependent()));
    } else {
      _deps.addAll(deps.map(_DependentControllers.new));
    }
    _syncSpouse();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final c in _contacts) {
      c.dispose();
    }
    for (final d in _deps) {
      d.dispose();
    }
    super.dispose();
  }

  static String _isoOrEmpty(String value) {
    final d = parseEmploymentDate(value);
    return d == null ? '' : employmentIsoDate(d);
  }

  void _syncSpouse() {
    if (!_spouseless) return;
    for (final key in _kSpouseFields) {
      _c[key]!.clear();
    }
  }

  Future<void> _pickDate({
    required String current,
    required ValueChanged<String> onPicked,
    required bool notFuture,
  }) async {
    final now = DateTime.now();
    final initial = parseEmploymentDate(current) ?? DateTime(now.year - 25);
    final last = notFuture ? now : DateTime(now.year + 10);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(last) ? last : initial,
      firstDate: DateTime(1900),
      lastDate: last,
    );
    if (picked != null) setState(() => onPicked(employmentIsoDate(picked)));
  }

  Future<void> _save() async {
    setState(() {
      _errors = const {};
      _saving = true;
    });
    final fields = <String, String>{};
    for (final key in _kTextFields) {
      final disabled = _spouseless && _kSpouseFields.contains(key);
      fields[key] = disabled ? '' : _c[key]!.text;
    }
    fields['marital_status'] = _marital;
    fields['birth_date'] = _birthDate;
    fields['start_date'] = _startDate;
    if (_noDependents) fields['has_no_dependents'] = '1';
    final deps = <Map<String, String>>[];
    for (final d in _deps) {
      final name = d.name.text.trim();
      if (name.isEmpty) continue;
      deps.add({
        'dependent_name': name,
        'relationship': d.relationship.text.trim(),
      });
    }
    fields['dependents'] = EmploymentService.encodeList(deps);
    fields['emergency_contacts'] = EmploymentService.encodeList(
      _contacts.map((c) => c.toJson()).toList(),
    );
    final res = await widget.service.updateRecord(widget.record.id, fields);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.ok) {
      employmentToast(context, res.message ?? 'Record updated.');
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _errors = res.errors);
    employmentToast(context, res.message ?? 'Could not save the changes');
  }

  Widget _field(
    String key,
    String label, {
    TextInputType? keyboard,
    bool enabled = true,
    TextCapitalization caps = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _c[key],
        enabled: enabled,
        keyboardType: keyboard,
        textCapitalization: caps,
        onChanged: (_) {
          if (_errors.containsKey(key)) {
            setState(() => _errors = {..._errors}..remove(key));
          }
        },
        decoration: InputDecoration(labelText: label, errorText: _errors[key]),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  Widget _dateField({
    required String errorKey,
    required String label,
    required String value,
    required ValueChanged<String> onPicked,
    required bool notFuture,
    bool clearable = false,
  }) {
    final b = context.brand;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(Brand.radiusSm + 2),
        onTap: () =>
            _pickDate(current: value, onPicked: onPicked, notFuture: notFuture),
        child: InputDecorator(
          isEmpty: value.isEmpty,
          decoration: InputDecoration(
            labelText: label,
            errorText: _errors[errorKey],
            suffixIcon: clearable && value.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear $label',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: () => setState(() => onPicked('')),
                  )
                : Icon(Icons.event_rounded, size: 20, color: b.paperDim),
          ),
          child: Text(
            value.isEmpty ? '' : employmentDate(value),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }

  Widget _contactField(
    TextEditingController c,
    int index,
    String key,
    String label, {
    TextInputType? keyboard,
  }) {
    final errKey = 'emergency_${index}_$key';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          errorText: _errors[errKey],
        ),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  Widget _errorLine(String key) {
    final msg = _errors[key];
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSize(
      duration: Duration(milliseconds: reduce ? 0 : 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: msg == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 15,
                    color: Brand.danger,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      msg,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Brand.danger),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = context.brand;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final rawName = widget.record.fullName.trim();
    final headerName = rawName.isEmpty ? 'Unnamed' : rawName;
    return StationScaffold(
      stationLabel: 'Edit record',
      title: 'Employment information',
      compact: true,
      showBottomBrand: false,
      onBack: () => Navigator.of(context).pop(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          GlassPanel(
            accent: employmentStatusColor(context, widget.record.status),
            child: Row(
              children: [
                AppAvatar(name: headerName, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        headerName,
                        style: text.titleSmall?.copyWith(color: b.paper),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Editing the information sheet',
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                EmploymentStatusPill(status: widget.record.status),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Employee information'),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  'full_name',
                  'Full name *',
                  caps: TextCapitalization.words,
                ),
                _field('address', 'Address *'),
                _field('birth_place', 'Birth place *'),
                _field(
                  'cell_phone',
                  'Cell phone *',
                  keyboard: TextInputType.phone,
                ),
                _field(
                  'email',
                  'Email address *',
                  keyboard: TextInputType.emailAddress,
                ),
                _field('government_id', 'SSS / Government ID *'),
                _dateField(
                  errorKey: 'birth_date',
                  label: 'Birth date *',
                  value: _birthDate,
                  notFuture: true,
                  onPicked: (v) => _birthDate = v,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<String>(
                    initialValue: _marital,
                    isExpanded: true,
                    dropdownColor: b.surface,
                    borderRadius: BorderRadius.circular(Brand.radius),
                    style: text.bodyLarge,
                    decoration: InputDecoration(
                      labelText: 'Marital status *',
                      errorText: _errors['marital_status'],
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Select…')),
                      for (final s in kMaritalStatuses)
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => setState(() {
                      _marital = v ?? '';
                      _syncSpouse();
                    }),
                  ),
                ),
                AnimatedSize(
                  duration: Duration(milliseconds: reduceMotion ? 0 : 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _spouseless
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 14),
                          child: EmploymentNotice(
                            'You do not have a legal spouse under the law — '
                            'the spouse fields are not required.',
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                _field(
                  'spouse_name',
                  "Spouse's name",
                  enabled: !_spouseless,
                  caps: TextCapitalization.words,
                ),
                _field(
                  'spouse_employer',
                  "Spouse's employer",
                  enabled: !_spouseless,
                ),
                _field(
                  'spouse_work_phone',
                  "Spouse's work phone",
                  enabled: !_spouseless,
                  keyboard: TextInputType.phone,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Job information'),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field('job_title', 'Title *'),
                _field('supervisor', 'Supervisor'),
                _field('work_location', 'Work location *'),
                _field(
                  'work_email',
                  'E-mail address *',
                  keyboard: TextInputType.emailAddress,
                ),
                _field(
                  'work_phone',
                  'Work phone',
                  keyboard: TextInputType.phone,
                ),
                _field(
                  'work_cell_phone',
                  'Cell phone',
                  keyboard: TextInputType.phone,
                ),
                _dateField(
                  errorKey: 'start_date',
                  label: 'Start date',
                  value: _startDate,
                  notFuture: false,
                  clearable: true,
                  onPicked: (v) => _startDate = v,
                ),
                _field('salary', 'Salary'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Emergency contacts'),
          for (var i = 0; i < _contacts.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            AppCard(
              radius: Brand.radiusLg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _contacts.length == 1
                              ? 'Emergency contact'
                              : 'Contact ${i + 1}'
                                    '${i == 0 ? ' — called first' : ''}',
                          style: text.labelLarge?.copyWith(
                            color: b.signalInk,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_contacts.length > kMinEmergencyContacts)
                        IconButton(
                          tooltip: 'Remove contact',
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Brand.danger,
                          ),
                          onPressed: () => setState(() {
                            _contacts.removeAt(i).dispose();
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _contactField(
                    _contacts[i].fullName,
                    i,
                    'full_name',
                    'Full name *',
                  ),
                  _contactField(
                    _contacts[i].address,
                    i,
                    'address',
                    'Address *',
                  ),
                  _contactField(
                    _contacts[i].primaryPhone,
                    i,
                    'primary_phone',
                    'Primary phone *',
                    keyboard: TextInputType.phone,
                  ),
                  _contactField(
                    _contacts[i].cellPhone,
                    i,
                    'cell_phone',
                    'Cell phone',
                    keyboard: TextInputType.phone,
                  ),
                  _contactField(
                    _contacts[i].relationship,
                    i,
                    'relationship',
                    'Relationship *',
                  ),
                ],
              ),
            ),
          ],
          _errorLine('emergency_contacts'),
          const SizedBox(height: 10),
          if (_contacts.length < kMaxEmergencyContacts)
            GhostButton(
              label: 'Add contact',
              icon: Icons.add_rounded,
              onPressed: () => setState(
                () => _contacts.add(_ContactControllers(EmergencyContact())),
              ),
            ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Dependents (insurance)'),
          AppCard(
            radius: Brand.radiusLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Opacity(
                  opacity: _noDependents ? 0.45 : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _deps.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    TextField(
                                      controller: _deps[i].name,
                                      enabled: !_noDependents,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      decoration: const InputDecoration(
                                        hintText: 'Name of dependent',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: _deps[i].relationship,
                                      enabled: !_noDependents,
                                      decoration: const InputDecoration(
                                        hintText: 'Relationship to employee',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove dependent',
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Brand.danger,
                                ),
                                onPressed: _noDependents
                                    ? null
                                    : () => setState(() {
                                        _deps.removeAt(i).dispose();
                                        if (_deps.isEmpty) {
                                          _deps.add(
                                            _DependentControllers(
                                              EmploymentDependent(),
                                            ),
                                          );
                                        }
                                      }),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (!_noDependents && _deps.length < kMaxDependents)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: () => setState(
                        () => _deps.add(
                          _DependentControllers(EmploymentDependent()),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add dependent'),
                    ),
                  ),
                CheckboxListTile(
                  value: _noDependents,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) => setState(() {
                    _noDependents = v ?? false;
                    _errors = {..._errors}..remove('dependents');
                  }),
                  title: Text(
                    'No dependents to declare',
                    style: text.bodyMedium,
                  ),
                ),
                _errorLine('dependents'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SignalButton(
            label: _saving ? 'Saving…' : 'Save changes',
            icon: Icons.save_rounded,
            busy: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 10),
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
