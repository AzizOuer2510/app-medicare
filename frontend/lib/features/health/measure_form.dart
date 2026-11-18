import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import 'health_api.dart';
import 'health_theme.dart';

/// Ouvre le formulaire d'ajout (ou de modification si [record] est fourni).
/// Renvoie `true` si la mesure a été enregistrée.
Future<bool> showMeasureForm(BuildContext context, WidgetRef ref,
    {Map<String, dynamic>? record}) async {
  final patient = HealthScope.patientOf(context);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (_) => HealthScope(patient: patient, child: _MeasureForm(record: record)),
  );
  return saved == true;
}

class _MeasureForm extends ConsumerStatefulWidget {
  const _MeasureForm({this.record});

  final Map<String, dynamic>? record;

  @override
  ConsumerState<_MeasureForm> createState() => _MeasureFormState();
}

class _Field {
  const _Field(this.key, this.label, this.icon, this.suffix, this.min, this.max,
      {this.integer = false, this.hint});
  final String key;
  final String label;
  final IconData icon;
  final String suffix;
  final double min;
  final double max;
  final bool integer;
  final String? hint;
}

const _fields = [
  _Field('weight', 'Poids', Icons.monitor_weight_outlined, 'kg', 1, 500, hint: '74,5'),
  _Field('heartRate', 'Fréquence cardiaque', Icons.favorite_outline, 'bpm', 20, 250,
      integer: true, hint: '72'),
  _Field('systolic', 'Tension systolique', Icons.speed_outlined, 'mmHg', 50, 260,
      integer: true, hint: '120'),
  _Field('diastolic', 'Tension diastolique', Icons.speed_outlined, 'mmHg', 30, 160,
      integer: true, hint: '80'),
  _Field('temperature', 'Température', Icons.thermostat_outlined, '°C', 30, 45,
      hint: '36,7'),
  _Field('glycemia', 'Glycémie', Icons.bloodtype_outlined, 'g/L', 0.1, 10,
      hint: '0,95'),
];

class _MeasureFormState extends ConsumerState<_MeasureForm> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final f in _fields)
      f.key: TextEditingController(
        text: widget.record?[f.key] == null
            ? ''
            : formatNumber(asDouble(widget.record![f.key]),
                    decimals: f.integer ? 0 : 2)
                .replaceAll(' ', '')
                .replaceAll(' ', ''),
      ),
  };
  late final _note =
      TextEditingController(text: widget.record?['note']?.toString() ?? '');
  late DateTime _date =
      parseApiDateTime(widget.record?['recordedAt']) ?? DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(_date);
    setState(() => _date = DateTime(day.year, day.month, day.day, t.hour, t.minute));
  }

  String? _validate(_Field f, String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final value = parseUserNumber(text);
    if (value == null) return 'Nombre invalide';
    if (f.integer && value != value.roundToDouble()) return 'Nombre entier attendu';
    if (value < f.min || value > f.max) {
      return 'Entre ${formatNumber(f.min, decimals: 1)} et ${formatNumber(f.max, decimals: 0)} ${f.suffix}';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final values = <String, num>{};
    for (final f in _fields) {
      final value = parseUserNumber(_controllers[f.key]!.text);
      if (value != null) values[f.key] = f.integer ? value.round() : value;
    }
    if (values.isEmpty) {
      setState(() => _error = 'Renseignez au moins une mesure.');
      return;
    }
    if (values.containsKey('systolic') != values.containsKey('diastolic')) {
      setState(() => _error = 'Renseignez la tension systolique et diastolique.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'recordedAt': DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(_date),
      ...values,
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    };
    try {
      final dio = ref.read(apiClientProvider).dio;
      if (widget.record == null) {
        await dio.post('/health-records',
            data: body, queryParameters: patientQuery(context));
      } else {
        await dio.put('/health-records/${widget.record!['id']}', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = healthErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: HealthBody(
        maxWidth: 640,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const HealthIconBadge(
                        Icons.monitor_heart_outlined, HealthColors.brightTeal),
                    const SizedBox(width: 12),
                    Text(
                      widget.record != null
                          ? 'Modifier la mesure'
                          : HealthScope.isDoctorView(context)
                              ? 'Mesure de consultation'
                              : 'Nouvelle mesure',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: HealthColors.ink),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  HealthScope.isDoctorView(context)
                      ? 'Patient : ${HealthScope.patientOf(context)!.name}. La mesure apparaîtra dans son suivi avec votre nom.'
                      : 'Remplissez uniquement les mesures prises.',
                  style: const TextStyle(color: HealthColors.muted),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _pickDateTime,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(DateFormat("EEEE d MMMM yyyy 'à' HH:mm", 'fr_FR')
                      .format(_date)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(14),
                    foregroundColor: HealthColors.brightTeal,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth > 440;
                  final width = twoColumns
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final f in _fields)
                        SizedBox(
                          width: width,
                          child: TextFormField(
                            controller: _controllers[f.key],
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: healthInputDecoration(f.label,
                                icon: f.icon, hint: f.hint, suffix: f.suffix),
                            validator: (text) => _validate(f, text),
                          ),
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  maxLength: 500,
                  decoration: healthInputDecoration('Note (optionnel)',
                      icon: Icons.notes_outlined, hint: 'À jeun, après le sport…'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(_error!,
                      style: const TextStyle(color: Color(0xFFB3261E))),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: healthFilledButtonStyle(),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: const Text('Enregistrer la mesure'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
