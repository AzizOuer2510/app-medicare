import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import 'health_api.dart';
import 'health_theme.dart';

/// Objectifs personnels : taille (calcul de l'IMC), poids cible,
/// calories et eau quotidiennes, notes.
class HealthGoalsPage extends ConsumerStatefulWidget {
  const HealthGoalsPage({super.key});

  @override
  ConsumerState<HealthGoalsPage> createState() => _HealthGoalsPageState();
}

class _HealthGoalsPageState extends ConsumerState<HealthGoalsPage> {
  final _formKey = GlobalKey<FormState>();
  final _height = TextEditingController();
  final _targetWeight = TextEditingController();
  final _calories = TextEditingController();
  final _water = TextEditingController();
  final _notes = TextEditingController();
  double? _currentWeight;
  String? _updatedBy;
  bool _updatedByDoctor = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_height, _targetWeight, _calories, _water, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _text(dynamic value) => value == null
      ? ''
      : NumberFormat('0.#', 'fr_FR').format(asDouble(value));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final query = patientQuery(context);
      final results = await Future.wait([
        dio.get('/health-goals', queryParameters: query),
        dio.get('/health-records', queryParameters: query),
      ]);
      if (!mounted) return;
      final goal = asMap(results[0].data);
      final records = asMapList(results[1].data);
      setState(() {
        _height.text = _text(goal['heightCm']);
        _targetWeight.text = _text(goal['targetWeight']);
        _calories.text = _text(goal['dailyCalorieGoal'] ?? 2000);
        _water.text = _text(goal['dailyWaterGoalMl'] ?? 2000);
        _notes.text = goal['notes']?.toString() ?? '';
        _updatedBy = goal['updatedByName']?.toString();
        _updatedByDoctor = goal['updatedByDoctor'] == true;
        _currentWeight = records
            .map((r) => asDouble(r['weight']))
            .whereType<double>()
            .firstOrNull;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = healthErrorMessage(error,
            fallback: 'Impossible de charger vos objectifs.');
      });
    }
  }

  String? _range(String? text, double min, double max, String unit) {
    if (text == null || text.trim().isEmpty) return null;
    final value = parseUserNumber(text);
    if (value == null) return 'Nombre invalide';
    if (value < min || value > max) {
      return 'Entre ${formatNumber(min, decimals: 0)} et ${formatNumber(max, decimals: 0)} $unit';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).dio.post('/health-goals',
          queryParameters: patientQuery(context), data: {
        'heightCm': parseUserNumber(_height.text),
        'targetWeight': parseUserNumber(_targetWeight.text),
        'dailyCalorieGoal': parseUserNumber(_calories.text)?.round(),
        'dailyWaterGoalMl': parseUserNumber(_water.text)?.round(),
        'notes': _notes.text.trim(),
      });
      if (!mounted) return;
      notifyHealthDataChanged(ref);
      showHealthSnack(context, 'Objectifs enregistrés.');
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showHealthSnack(context, healthErrorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weight = _currentWeight ?? parseUserNumber(_targetWeight.text);
    final bmi = computeBmi(weight, parseUserNumber(_height.text));

    return Scaffold(
      backgroundColor: HealthColors.background,
      appBar: healthAppBar(HealthScope.patientOf(context) == null
          ? 'Mes objectifs de santé'
          : 'Objectifs de ${HealthScope.patientOf(context)!.name}'),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: HealthColors.brightTeal))
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: HealthErrorState(message: _error!, onRetry: _load),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      HealthBody(
                        maxWidth: 680,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _bmiCard(bmi),
                            if (_updatedByDoctor && _updatedBy != null)
                              HealthCard(
                                color: const Color(0xFFE8F5F4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.medical_services_outlined,
                                        color: HealthColors.brightTeal),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Objectifs ajustés par $_updatedBy.',
                                        style: const TextStyle(color: HealthColors.ink),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            HealthCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('Paramètres personnels',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: HealthColors.ink)),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _height,
                                    keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true),
                                    onChanged: (_) => setState(() {}),
                                    decoration: healthInputDecoration('Taille',
                                        icon: Icons.height, suffix: 'cm', hint: '175'),
                                    validator: (t) => _range(t, 50, 260, 'cm'),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _targetWeight,
                                    keyboardType: const TextInputType.numberWithOptions(
                                        decimal: true),
                                    onChanged: (_) => setState(() {}),
                                    decoration: healthInputDecoration('Poids cible',
                                        icon: Icons.flag_outlined,
                                        suffix: 'kg',
                                        hint: '70'),
                                    validator: (t) => _range(t, 1, 500, 'kg'),
                                  ),
                                ],
                              ),
                            ),
                            HealthCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('Objectifs quotidiens',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: HealthColors.ink)),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _calories,
                                    keyboardType: TextInputType.number,
                                    decoration: healthInputDecoration('Calories',
                                        icon: Icons.local_fire_department_outlined,
                                        suffix: 'kcal / jour'),
                                    validator: (t) => _range(t, 500, 10000, 'kcal'),
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _water,
                                    keyboardType: TextInputType.number,
                                    decoration: healthInputDecoration('Eau',
                                        icon: Icons.water_drop_outlined,
                                        suffix: 'ml / jour'),
                                    validator: (t) => _range(t, 250, 10000, 'ml'),
                                  ),
                                ],
                              ),
                            ),
                            HealthCard(
                              child: TextFormField(
                                controller: _notes,
                                maxLines: 3,
                                maxLength: 1000,
                                decoration: healthInputDecoration(
                                    'Notes personnelles',
                                    icon: Icons.notes_outlined,
                                    hint: 'Régime sans gluten, sportif, allergies…'),
                              ),
                            ),
                            FilledButton.icon(
                              style: healthFilledButtonStyle(),
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save_outlined),
                              label: const Text('Enregistrer mes objectifs'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _bmiCard(double? bmi) {
    return HealthCard(
      child: Column(
        children: [
          const Row(
            children: [
              HealthIconBadge(Icons.calculate_outlined, HealthColors.brightTeal),
              SizedBox(width: 12),
              Expanded(
                child: Text('Indice de masse corporelle (IMC)',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: HealthColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (bmi == null)
            const Text(
              'Renseignez votre taille et enregistrez un poids dans vos mesures pour calculer votre IMC.',
              textAlign: TextAlign.center,
              style: TextStyle(color: HealthColors.muted),
            )
          else ...[
            Text(formatNumber(bmi),
                style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: bmiColor(bmi))),
            Text(bmiLabel(bmi),
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: bmiColor(bmi))),
            if (_currentWeight != null)
              Text('Calculé avec votre dernier poids : ${formatNumber(_currentWeight)} kg',
                  style: const TextStyle(fontSize: 12, color: HealthColors.muted)),
            const SizedBox(height: 12),
            _BmiScale(bmi: bmi),
          ],
        ],
      ),
    );
  }
}

class _BmiScale extends StatelessWidget {
  const _BmiScale({required this.bmi});

  final double bmi;

  @override
  Widget build(BuildContext context) {
    final position = ((bmi - 15) / 25).clamp(0.0, 1.0);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: 24,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 10,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(colors: [
                        HealthColors.pressure,
                        HealthColors.success,
                        HealthColors.temperature,
                        HealthColors.heart,
                      ]),
                    ),
                  ),
                ),
                Positioned(
                  left: (constraints.maxWidth * position - 10)
                      .clamp(0.0, constraints.maxWidth - 20),
                  top: -4,
                  child: const Icon(Icons.arrow_drop_down,
                      size: 22, color: HealthColors.ink),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('< 18,5', style: TextStyle(fontSize: 11, color: HealthColors.pressure)),
            Text('18,5 – 25', style: TextStyle(fontSize: 11, color: HealthColors.success)),
            Text('25 – 30', style: TextStyle(fontSize: 11, color: HealthColors.temperature)),
            Text('> 30', style: TextStyle(fontSize: 11, color: HealthColors.heart)),
          ],
        ),
      ],
    );
  }
}
