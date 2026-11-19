import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
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

_Field _field(String key) => _fields.firstWhere((f) => f.key == key);

/// Un appareil de mesure = une photo = un groupe de champs du formulaire.
class _Device {
  const _Device(this.code, this.label, this.icon, this.color, this.keys);
  final String code; // valeur envoyée à /health/ai/read-device
  final String label;
  final IconData icon;
  final Color color;
  final List<String> keys;
}

const _devices = [
  _Device('BLOOD_PRESSURE', 'Tensiomètre', Icons.speed_outlined,
      HealthColors.pressure, ['systolic', 'diastolic', 'heartRate']),
  _Device('TEMPERATURE', 'Thermomètre', Icons.thermostat_outlined,
      HealthColors.temperature, ['temperature']),
  _Device('WEIGHT', 'Pèse-personne', Icons.monitor_weight_outlined,
      HealthColors.weight, ['weight']),
  _Device('GLYCEMIA', 'Lecteur de glycémie', Icons.bloodtype_outlined,
      HealthColors.glycemia, ['glycemia']),
];

/// État de la lecture IA d'une photo pour un appareil.
class _Reading {
  Uint8List? photo;
  bool reading = false;
  bool? success;
  String? message;
}

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

  /// Lecture IA par appareil (photo + résultat).
  final Map<String, _Reading> _readings = {
    for (final d in _devices) d.code: _Reading(),
  };

  /// Champs pré-remplis par l'IA : à vérifier par le patient avant validation.
  final Set<String> _aiFilled = {};
  bool _aiChecked = false;

  bool get _canUseCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _readDevice(_Device device) async {
    ImageSource? source = ImageSource.gallery;
    if (_canUseCamera) {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text('Photographier l’écran (${device.label.toLowerCase()})'),
                onTap: () => Navigator.pop(sheet, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choisir une photo dans la galerie'),
                onTap: () => Navigator.pop(sheet, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
    }
    if (source == null || !mounted) return;
    final Uint8List bytes;
    try {
      final file = await ImagePicker().pickImage(
          source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 90);
      if (file == null) return;
      bytes = await file.readAsBytes();
    } catch (_) {
      if (mounted) {
        showHealthSnack(context, 'Impossible d’ouvrir la photo.', error: true);
      }
      return;
    }
    if (!mounted) return;
    final reading = _readings[device.code]!;
    setState(() {
      reading
        ..photo = bytes
        ..reading = true
        ..success = null
        ..message = null;
    });
    try {
      final response = await aiDio(ref).post('/health/ai/read-device',
          data: {'device': device.code, 'image': base64Encode(bytes)});
      final data = asMap(response.data);
      final values = asMap(data['values']);
      if (!mounted) return;
      setState(() {
        reading
          ..reading = false
          ..success = data['success'] == true
          ..message = data['message']?.toString();
        if (reading.success == true) {
          // Pré-remplissage uniquement : rien n'est enregistré avant la validation du patient.
          for (final entry in values.entries) {
            final f = _field(entry.key);
            final v = asDouble(entry.value);
            if (v == null) continue;
            _controllers[f.key]!.text = formatNumber(v,
                    decimals: f.integer ? 0 : (f.key == 'glycemia' ? 2 : 1))
                .replaceAll(' ', '')
                .replaceAll(' ', '');
            _aiFilled.add(f.key);
          }
          _aiChecked = false;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        reading
          ..reading = false
          ..success = false
          ..message = healthErrorMessage(error,
              fallback: 'La lecture a échoué. Reprenez la photo.');
      });
    }
  }

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
    if (_aiFilled.isNotEmpty && !_aiChecked) {
      setState(() =>
          _error = 'Confirmez que vous avez vérifié les valeurs lues par l’IA.');
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
                const Text(
                  'Saisissez les valeurs, ou utilisez « Lire par photo » : '
                  'l’IA lit l’écran de l’appareil et pré-remplit les champs.',
                  style: TextStyle(fontSize: 13, color: HealthColors.muted),
                ),
                const SizedBox(height: 10),
                for (final device in _devices) ...[
                  _deviceGroup(device),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 2),
                TextFormField(
                  controller: _note,
                  maxLength: 500,
                  decoration: healthInputDecoration('Note (optionnel)',
                      icon: Icons.notes_outlined, hint: 'À jeun, après le sport…'),
                ),
                if (_aiFilled.isNotEmpty)
                  CheckboxListTile(
                    value: _aiChecked,
                    onChanged: (v) => setState(() {
                      _aiChecked = v ?? false;
                      _error = null;
                    }),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: HealthColors.brightTeal,
                    title: const Text(
                        'J’ai vérifié (et corrigé si besoin) les valeurs lues par l’IA',
                        style: TextStyle(fontSize: 14, color: HealthColors.ink)),
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

  Widget _fieldInput(_Field f) {
    final ai = _aiFilled.contains(f.key);
    return TextFormField(
      controller: _controllers[f.key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: healthInputDecoration(f.label,
              icon: f.icon, hint: f.hint, suffix: f.suffix)
          .copyWith(
        helperText: ai ? 'Lu par l’IA — vérifiez' : null,
        helperStyle: const TextStyle(color: HealthColors.brightTeal),
        filled: ai ? true : null,
        fillColor: ai ? const Color(0xFFE6F5F3) : null,
      ),
      validator: (text) => _validate(f, text),
    );
  }

  /// Groupe d'un appareil : bouton « Lire par photo », photo et champs côte à côte.
  Widget _deviceGroup(_Device device) {
    final reading = _readings[device.code]!;
    final fields = device.keys.map(_field).toList();
    const errorColor = Color(0xFFB3261E);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: device.color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(device.icon, color: device.color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(device.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: HealthColors.ink)),
              ),
              TextButton.icon(
                onPressed: reading.reading ? null : () => _readDevice(device),
                icon: const Icon(Icons.document_scanner_outlined, size: 18),
                label: Text(reading.photo == null ? 'Lire par photo' : 'Reprendre'),
                style: TextButton.styleFrom(foregroundColor: device.color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reading.photo != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.memory(reading.photo!,
                          width: 96, height: 96, fit: BoxFit.cover),
                      if (reading.reading)
                        Container(
                          width: 96,
                          height: 96,
                          color: Colors.black38,
                          child: const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  children: [
                    for (final f in fields) ...[
                      _fieldInput(f),
                      if (f != fields.last) const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (reading.reading || reading.message != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  reading.reading
                      ? Icons.hourglass_top
                      : reading.success == true
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                  size: 18,
                  color: reading.reading
                      ? HealthColors.muted
                      : reading.success == true
                          ? HealthColors.success
                          : errorColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    reading.reading
                        ? 'Lecture de l’écran par l’IA… (quelques secondes)'
                        : reading.message!,
                    style: TextStyle(
                      fontSize: 13,
                      color: reading.reading || reading.success == true
                          ? HealthColors.muted
                          : errorColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
