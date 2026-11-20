import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'medication.dart';
import 'medication_notifications.dart';

class MedicationFormPage extends ConsumerStatefulWidget {
  final Medication? medication;
  final int? prescriptionId;
  final PrescriptionMedicationSuggestion? suggestion;
  final bool draftOnly;

  /// Médecin : patient pour qui le planning est créé (sans passer par une ordonnance déposée).
  final int? patientId;
  final String? patientName;

  const MedicationFormPage({
    super.key,
    this.medication,
    this.prescriptionId,
    this.suggestion,
    this.draftOnly = false,
    this.patientId,
    this.patientName,
  });

  @override
  ConsumerState<MedicationFormPage> createState() => _MedicationFormPageState();
}

class _MedicationFormPageState extends ConsumerState<MedicationFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _dosage;
  late final TextEditingController _instructions;
  late final TextEditingController _notes;
  late final TextEditingController _unitsPerDose;
  late final TextEditingController _quantity;
  late final TextEditingController _unit;
  late final TextEditingController _threshold;
  late final TextEditingController _package;
  int _frequency = 1;
  DateTime? _startDate;
  DateTime? _endDate;
  List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  String _form = 'Comprimé';
  String _status = 'active';
  bool _remindersEnabled = true;
  bool _loading = false;
  bool _frequencyConfirmed = true;
  bool _formConfirmed = true;
  bool _ocrReviewed = false;
  bool _allowNoEndDate = false;

  bool get _fromPrescription =>
      widget.prescriptionId != null || widget.draftOnly;
  bool get _prescriptionLinked =>
      widget.prescriptionId != null ||
      widget.patientId != null ||
      widget.draftOnly ||
      widget.medication?.prescriptionId != null;
  bool get _ocrReview => widget.suggestion != null;

  String? get _dateRangeError => medicationDateRangeError(_startDate, _endDate);

  @override
  void initState() {
    super.initState();
    final m = widget.medication;
    final suggestion = widget.suggestion;
    _name = TextEditingController(text: suggestion?.name ?? m?.name ?? '');
    _dosage =
        TextEditingController(text: suggestion?.dosage ?? m?.dosage ?? '');
    _instructions = TextEditingController(
      text: suggestion?.instructions ?? m?.instructions ?? '',
    );
    _notes = TextEditingController(text: m?.notes ?? '');
    _unitsPerDose = TextEditingController(
      text: suggestion?.unitsPerDose?.toString() ??
          m?.unitsPerDose?.toString() ??
          '',
    );
    _quantity =
        TextEditingController(text: m?.currentQuantity?.toString() ?? '');
    _unit = TextEditingController(text: m?.quantityUnit ?? '');
    _threshold = TextEditingController(
      text: m?.lowStockThreshold?.toString() ?? '',
    );
    _package =
        TextEditingController(text: m?.packageQuantity?.toString() ?? '');
    _frequency = suggestion?.frequencyPerDay ?? m?.frequencyPerDay ?? 1;
    _frequencyConfirmed =
        suggestion?.frequencyPerDay != null || suggestion == null;
    _form = suggestion?.pharmaceuticalForm ??
        m?.pharmaceuticalForm ??
        (suggestion == null ? 'Comprimé' : 'Autre');
    _formConfirmed =
        suggestion?.pharmaceuticalForm != null || suggestion == null;
    _startDate = suggestion?.startDate ??
        m?.startDate ??
        (_fromPrescription && suggestion == null
            ? DateTime(
                DateTime.now().year, DateTime.now().month, DateTime.now().day)
            : null);
    _endDate = suggestion?.endDate ?? m?.endDate;
    _status = m?.status ?? 'active';
    _remindersEnabled = m?.remindersEnabled ?? true;
    if (suggestion != null) {
      _weekdays = suggestion.weekdays.toSet();
      _times = suggestion.reminderTimes.map(_parseTime).toList();
    } else if (m != null) {
      if (m.weekdays.isNotEmpty) _weekdays = m.weekdays.toSet();
      if (m.reminderTimes.isNotEmpty) {
        _times = m.reminderTimes.map(_parseTime).toList();
        _frequency = _times.length;
      }
    }
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 8,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
  }

  String _apiTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _pickDate(bool start) async {
    final firstDate = start
        ? DateTime(2020)
        : (_startDate == null
            ? DateTime(2020)
            : DateTime(
                _startDate!.year,
                _startDate!.month,
                _startDate!.day,
              ));
    final initial = start
        ? (_startDate ?? DateTime.now())
        : (_endDate != null && !_endDate!.isBefore(firstDate)
            ? _endDate!
            : _startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked != null) {
      setState(() {
        if (start) {
          _startDate = picked;
          if (_endDate != null && _dateRangeError != null) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
          _allowNoEndDate = false;
        }
      });
    }
  }

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times[index],
    );
    if (picked != null) setState(() => _times[index] = picked);
  }

  void _setFrequency(int value) {
    setState(() {
      _frequency = value;
      _frequencyConfirmed = true;
      if (!_ocrReview) {
        while (_times.length < value) {
          _times.add(TimeOfDay(hour: 8 + _times.length * 2, minute: 0));
        }
        if (_times.length > value) _times = _times.sublist(0, value);
      }
    });
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _times.add(picked));
  }

  num? _number(TextEditingController c) => num.tryParse(c.text.trim());

  String? _validateOptionalNumber(
    String? value, {
    required bool mustBePositive,
    required String label,
  }) {
    if (value == null || value.trim().isEmpty) return null;
    final number = num.tryParse(value.trim());
    if (number == null ||
        !number.isFinite ||
        (mustBePositive ? number <= 0 : number < 0)) {
      return mustBePositive
          ? '$label doit être supérieur à zéro.'
          : '$label ne peut pas être négatif.';
    }
    return null;
  }

  String _weekdayName(int weekday) => const [
        'MONDAY',
        'TUESDAY',
        'WEDNESDAY',
        'THURSDAY',
        'FRIDAY',
        'SATURDAY',
        'SUNDAY',
      ][weekday - 1];

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_ocrReview && !_ocrReviewed) {
      _message(
          'Vérifiez les informations avec l’ordonnance avant de continuer.');
      return;
    }
    if (_ocrReview && !_formConfirmed) {
      _message('Sélectionnez la forme pharmaceutique après vérification.');
      return;
    }
    if (_ocrReview && !_frequencyConfirmed) {
      _message('Sélectionnez la fréquence quotidienne après vérification.');
      return;
    }
    if (_ocrReview && _startDate == null) {
      _message('Indiquez la date de début du traitement.');
      return;
    }
    if (_ocrReview && _endDate == null && !_allowNoEndDate) {
      _message(
          'Indiquez une date de fin ou confirmez un traitement sans échéance.');
      return;
    }
    if (_fromPrescription && _times.isEmpty) {
      _message('Ajoutez au moins un horaire de prise.');
      return;
    }
    if (_fromPrescription && _times.length != _frequency) {
      _message(
          'Le nombre d’horaires doit correspondre à la fréquence quotidienne.');
      return;
    }
    if (_fromPrescription && _weekdays.isEmpty) {
      _message('Sélectionnez au moins un jour de prise.');
      return;
    }
    if (_dateRangeError != null) {
      _message(_dateRangeError!);
      return;
    }
    if (_times.toSet().length != _times.length) {
      _message('Les horaires de prise doivent être différents.');
      return;
    }
    setState(() => _loading = true);
    try {
      final m = widget.medication;
      final data = <String, dynamic>{
        'name': _name.text.trim(),
        'dosage': _dosage.text.trim().isEmpty ? null : _dosage.text.trim(),
        'frequency': '$_frequency fois / jour',
        'frequencyPerDay': _frequency,
        'instructions': _instructions.text.trim().isEmpty
            ? null
            : _instructions.text.trim(),
        'startDate': _startDate?.toIso8601String().split('T').first,
        'endDate': _endDate?.toIso8601String().split('T').first,
        'reminderTimes': _times.map(_apiTime).toList(),
        'prescriptionId': m?.prescriptionId ?? widget.prescriptionId,
        if (m == null && widget.prescriptionId == null && widget.patientId != null)
          'patientId': widget.patientId,
        'pharmaceuticalForm': _form,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'unitsPerDose': _number(_unitsPerDose),
        'weekdays': _weekdays.map(_weekdayName).toList(),
        'status': _status.toUpperCase(),
        'remindersEnabled':
            _status == 'discontinued' ? false : _remindersEnabled,
        'stockQuantity': _number(_quantity),
        'stockUnit': _unit.text.trim().isEmpty ? null : _unit.text.trim(),
        'lowStockThreshold': _number(_threshold),
        'packageQuantity': _number(_package),
      };
      if (widget.draftOnly) {
        if (mounted) {
          Navigator.pop(context, MedicationDraft.fromRequest(data));
        }
        return;
      }
      final dio = ref.read(apiClientProvider).dio;
      var savedId = m?.id ?? 0;
      if (m == null) {
        final response = await dio.post('/medications', data: data);
        final payload = response.data;
        if (payload is Map<String, dynamic>) {
          savedId = (payload['id'] as num?)?.toInt() ?? 0;
        }
      } else {
        await dio.put('/medications/${m.id}', data: data);
      }
      try {
        if (!_prescriptionLinked && _remindersEnabled && _status == 'active') {
          await MedicationNotifications.instance.schedule(
            id: savedId,
            name: _name.text.trim(),
            instructions: _instructions.text.trim(),
            times: _times,
            weekdays: _weekdays,
            startDate: _startDate,
            endDate: _endDate,
          );
        } else if (!_prescriptionLinked && m != null) {
          await MedicationNotifications.instance.cancel(m.id);
        }
      } catch (_) {
        // A platform notification failure must not undo the saved medication.
      }
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (error) {
      final data = error.response?.data;
      final detail = data is Map ? data['message']?.toString() : null;
      _message(detail == null || detail.isEmpty
          ? 'Impossible d’enregistrer le médicament. Vérifiez la connexion au serveur.'
          : 'Impossible d’enregistrer le médicament : $detail');
    } catch (_) {
      _message('Impossible d’enregistrer le médicament.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  void dispose() {
    for (final c in [
      _name,
      _dosage,
      _instructions,
      _notes,
      _unitsPerDose,
      _quantity,
      _unit,
      _threshold,
      _package,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.medication != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.draftOnly
              ? 'Préparer le planning'
              : _fromPrescription
                  ? 'Médicament de l’ordonnance'
                  : editing
                      ? 'Modifier le médicament'
                      : widget.patientName != null
                          ? 'Planning de ${widget.patientName}'
                          : 'Ajouter un médicament',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.patientName != null && !editing) ...[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text('Patient : ${widget.patientName}'),
                  subtitle: const Text(
                      'Le médicament et ses horaires de prise seront ajoutés au planning du patient.'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_fromPrescription) ...[
              const Text(
                'Saisissez les informations exactement comme elles figurent sur l’ordonnance déposée.',
              ),
              const SizedBox(height: 12),
            ],
            if (_ocrReview) ...[
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Planning prérempli depuis l’ordonnance — vérification obligatoire',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Les informations non détectées restent vides. Comparez chaque champ au document original.',
                      ),
                      if (widget.suggestion!.warnings.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final warning in widget.suggestion!.warnings)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text('• $warning'),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Médicament'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nom obligatoire' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _formConfirmed ? _form : null,
              hint: const Text('À vérifier'),
              decoration:
                  const InputDecoration(labelText: 'Forme pharmaceutique'),
              items: const [
                'Comprimé',
                'Gélule',
                'Solution buvable',
                'Sirop',
                'Gouttes',
                'Injection',
                'Crème',
                'Inhalateur',
                'Autre',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() {
                if (v != null) {
                  _form = v;
                  _formConfirmed = true;
                }
              }),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dosage,
              decoration: const InputDecoration(
                labelText: 'Dosage',
                hintText: 'Ex. 500 mg',
              ),
              validator: (value) =>
                  _ocrReview && (value == null || value.trim().isEmpty)
                      ? 'Vérifiez et saisissez le dosage.'
                      : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _unitsPerDose,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Unités par prise'),
              validator: (value) => _validateOptionalNumber(
                value,
                mustBePositive: true,
                label: 'Les unités par prise',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _frequencyConfirmed ? _frequency : null,
              hint: const Text('À vérifier'),
              decoration:
                  const InputDecoration(labelText: 'Fréquence quotidienne'),
              items: List.generate(6, (i) => i + 1)
                  .map((v) =>
                      DropdownMenuItem(value: v, child: Text('$v fois / jour')))
                  .toList(),
              onChanged: (v) {
                if (v != null) _setFrequency(v);
              },
            ),
            const SizedBox(height: 10),
            const Text('Jours de prise',
                style: TextStyle(fontWeight: FontWeight.w600)),
            Wrap(
              spacing: 4,
              children: List.generate(7, (i) {
                final day = i + 1;
                const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
                return FilterChip(
                  label: Text(labels[i],
                      semanticsLabel: const [
                        'Lundi',
                        'Mardi',
                        'Mercredi',
                        'Jeudi',
                        'Vendredi',
                        'Samedi',
                        'Dimanche'
                      ][i]),
                  selected: _weekdays.contains(day),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _weekdays.add(day);
                    } else {
                      _weekdays.remove(day);
                    }
                  }),
                );
              }),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rappels locaux'),
              subtitle: const Text(
                  'Notifications sur cet appareil, sans marquer la prise automatiquement'),
              value: _status == 'discontinued' ? false : _remindersEnabled,
              onChanged: _status == 'discontinued'
                  ? null
                  : (v) => setState(() => _remindersEnabled = v),
            ),
            ...List.generate(
              _times.length,
              (i) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(_times[i].format(context)),
                trailing: _ocrReview
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Modifier l’horaire',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _pickTime(i),
                          ),
                          IconButton(
                            tooltip: 'Supprimer l’horaire',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _times.removeAt(i)),
                          ),
                        ],
                      )
                    : IconButton(
                        tooltip: 'Modifier l’horaire',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _pickTime(i),
                      ),
              ),
            ),
            if (_ocrReview)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addTime,
                  icon: const Icon(Icons.add_alarm),
                  label: const Text('Ajouter un horaire vérifié'),
                ),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                onPressed: () => _pickDate(true),
                icon: const Icon(Icons.calendar_today),
                label: Text(_startDate == null
                    ? 'Date de début'
                    : MaterialLocalizations.of(context)
                        .formatShortDate(_startDate!)),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: OutlinedButton.icon(
                onPressed: () => _pickDate(false),
                icon: const Icon(Icons.event),
                label: Text(_endDate == null
                    ? 'Date de fin'
                    : MaterialLocalizations.of(context)
                        .formatShortDate(_endDate!)),
              )),
            ]),
            if (_dateRangeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _dateRangeError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_ocrReview)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _allowNoEndDate,
                title: const Text(
                    'Confirmer qu’aucune date de fin n’est prescrite'),
                onChanged: _endDate == null
                    ? (value) =>
                        setState(() => _allowNoEndDate = value ?? false)
                    : null,
              ),
            if (!_fromPrescription) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration:
                    const InputDecoration(labelText: 'État du traitement'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('En cours')),
                  DropdownMenuItem(value: 'suspended', child: Text('En pause')),
                  DropdownMenuItem(
                      value: 'discontinued', child: Text('Arrêté')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'active'),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _instructions,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Instructions', hintText: 'Ex. Après le repas'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            if (_ocrReview) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _ocrReviewed,
                title: const Text(
                  'J’ai vérifié les informations sur l’ordonnance originale',
                ),
                onChanged: (value) =>
                    setState(() => _ocrReviewed = value ?? false),
              ),
            ],
            if (!_fromPrescription) ...[
              const Divider(height: 32),
              Text('Stock', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextFormField(
                  controller: _quantity,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Quantité actuelle'),
                  validator: (value) => _validateOptionalNumber(
                    value,
                    mustBePositive: false,
                    label: 'La quantité',
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  controller: _unit,
                  decoration: const InputDecoration(
                      labelText: 'Unité', hintText: 'comprimés'),
                )),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextFormField(
                  controller: _threshold,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Seuil de stock faible'),
                  validator: (value) => _validateOptionalNumber(
                    value,
                    mustBePositive: false,
                    label: 'Le seuil de stock',
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  controller: _package,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Quantité par boîte'),
                  validator: (value) => _validateOptionalNumber(
                    value,
                    mustBePositive: true,
                    label: 'La quantité par boîte',
                  ),
                )),
              ]),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(
                _loading
                    ? 'Enregistrement...'
                    : widget.draftOnly
                        ? 'Confirmer ce médicament'
                        : _fromPrescription
                            ? 'Ajouter au planning'
                            : 'Enregistrer',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
