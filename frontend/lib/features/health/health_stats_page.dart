import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'health_api.dart';
import 'health_theme.dart';

/// Statistiques et graphiques : évolution des constantes, nutrition, hydratation
/// et mise en parallèle santé / nutrition sur la période choisie.
class HealthStatsPage extends ConsumerStatefulWidget {
  const HealthStatsPage({super.key});

  @override
  ConsumerState<HealthStatsPage> createState() => _HealthStatsPageState();
}

class _HealthStatsPageState extends ConsumerState<HealthStatsPage> {
  int _days = 30;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _nutrition = [];
  List<Map<String, dynamic>> _water = [];
  Map<String, dynamic> _goal = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final query = patientQuery(context, {'days': _days});
      final results = await Future.wait([
        dio.get('/health-records/history', queryParameters: query),
        dio.get('/meals/stats/daily', queryParameters: query),
        dio.get('/hydration/history', queryParameters: query),
        dio.get('/health-goals', queryParameters: patientQuery(context)),
      ]);
      if (!mounted) return;
      setState(() {
        _records = asMapList(results[0].data);
        _nutrition = asMapList(results[1].data);
        _water = asMapList(results[2].data);
        _goal = asMap(results[3].data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = healthErrorMessage(error,
            fallback: 'Impossible de charger les statistiques.');
      });
    }
  }

  List<double> _values(String field) =>
      _records.map((r) => asDouble(r[field])).whereType<double>().toList();

  List<DateTime> _dates(String field) => _records
      .where((r) => r[field] != null)
      .map((r) => parseApiDateTime(r['recordedAt']))
      .whereType<DateTime>()
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealthColors.background,
      appBar: healthAppBar(
          HealthScope.patientOf(context) == null
              ? 'Statistiques et évolution'
              : 'Statistiques · ${HealthScope.patientOf(context)!.name}',
          actions: [
        IconButton(
          tooltip: 'Actualiser',
          onPressed: _load,
          icon: const Icon(Icons.refresh),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 32),
          children: [
            HealthBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HealthChoiceChips<int>(
                    options: const [
                      (7, '7 jours'),
                      (30, '30 jours'),
                      (90, '3 mois'),
                      (180, '6 mois'),
                    ],
                    selected: _days,
                    onSelected: (value) {
                      setState(() => _days = value);
                      _load();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(48),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: HealthColors.brightTeal)),
                          )
                        : _error != null
                            ? HealthErrorState(message: _error!, onRetry: _load)
                            : _content(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final weights = _values('weight');
    final systolic = <double>[];
    final diastolic = <double>[];
    for (final r in _records) {
      final s = asDouble(r['systolic']);
      final d = asDouble(r['diastolic']);
      if (s != null && d != null) {
        systolic.add(s);
        diastolic.add(d);
      }
    }
    final heartRates = _values('heartRate');
    final temperatures = _values('temperature');
    final glycemias = _values('glycemia');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HealthSectionTitle('Santé', icon: Icons.favorite_rounded),
        if (_records.isEmpty)
          const HealthEmptyState(
            icon: Icons.show_chart,
            title: 'Pas encore de mesures sur cette période',
            message: 'Ajoutez des mesures pour voir leur évolution.',
          ),
        _MetricChart(
          title: 'Poids',
          unit: 'kg',
          icon: Icons.monitor_weight_outlined,
          color: HealthColors.weight,
          values: weights,
          dates: _dates('weight'),
          target: asDouble(_goal['targetWeight']),
        ),
        _MetricChart(
          title: 'Tension artérielle',
          unit: 'mmHg',
          icon: Icons.speed_outlined,
          color: HealthColors.pressure,
          values: systolic,
          secondary: diastolic,
          dates: _dates('systolic'),
          decimals: 0,
          legend: const ['Systolique', 'Diastolique'],
        ),
        _MetricChart(
          title: 'Fréquence cardiaque',
          unit: 'bpm',
          icon: Icons.favorite_outline,
          color: HealthColors.heart,
          values: heartRates,
          dates: _dates('heartRate'),
          decimals: 0,
        ),
        _MetricChart(
          title: 'Température',
          unit: '°C',
          icon: Icons.thermostat_outlined,
          color: HealthColors.temperature,
          values: temperatures,
          dates: _dates('temperature'),
        ),
        _MetricChart(
          title: 'Glycémie',
          unit: 'g/L',
          icon: Icons.bloodtype_outlined,
          color: HealthColors.glycemia,
          values: glycemias,
          dates: _dates('glycemia'),
          decimals: 2,
        ),
        const HealthSectionTitle('Nutrition', icon: Icons.restaurant_rounded),
        _nutritionCard(),
        const HealthSectionTitle('Hydratation', icon: Icons.water_drop_rounded),
        _waterCard(),
        const HealthSectionTitle('Santé et nutrition', icon: Icons.compare_arrows),
        _relationCard(weights),
      ],
    );
  }

  List<String> _dayLabels(List<Map<String, dynamic>> days) => days.map((d) {
        final date = DateTime.tryParse(d['date'].toString());
        return date == null ? '' : formatShortDate(date);
      }).toList();

  Widget _nutritionCard() {
    double total(String key) =>
        _nutrition.fold(0, (s, d) => s + (asDouble(d[key]) ?? 0));
    final meals = total('mealCount');
    final daysWithMeals =
        _nutrition.where((d) => (asDouble(d['mealCount']) ?? 0) > 0).length;
    final divisor = math.max(1, daysWithMeals);
    final calories = total('totalCalories');
    final protein = total('totalProtein');
    final carbs = total('totalCarbohydrates');
    final fat = total('totalFat');
    final fiber = total('totalFiber');
    final macroKcal = protein * 4 + carbs * 4 + fat * 9;
    final goal = asDouble(_goal['dailyCalorieGoal']) ?? 2000;

    return HealthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _kpi(formatNumber(meals, decimals: 0), 'repas enregistrés',
                  HealthColors.brightTeal),
              _kpi(formatNumber(meals / divisor, decimals: 1), 'repas / jour',
                  HealthColors.success),
              _kpi(formatNumber(calories / divisor, decimals: 0), 'kcal / jour',
                  HealthColors.calories),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            daysWithMeals == 0
                ? 'Aucun repas enregistré sur cette période.'
                : 'Moyennes calculées sur les $daysWithMeals jours avec au moins un repas.',
            style: const TextStyle(fontSize: 12, color: HealthColors.muted),
          ),
          const SizedBox(height: 14),
          const Text('Calories estimées par jour',
              style: TextStyle(fontWeight: FontWeight.w600, color: HealthColors.ink)),
          const SizedBox(height: 8),
          HealthBarChart(
            values: _nutrition.map((d) => asDouble(d['totalCalories']) ?? 0).toList(),
            labels: _dayLabels(_nutrition),
            color: HealthColors.calories,
            goal: goal,
          ),
          Text('Ligne verte : objectif de ${formatNumber(goal, decimals: 0)} kcal',
              style: const TextStyle(fontSize: 11, color: HealthColors.muted)),
          const SizedBox(height: 16),
          const Text('Macronutriments (moyenne par jour)',
              style: TextStyle(fontWeight: FontWeight.w600, color: HealthColors.ink)),
          const SizedBox(height: 10),
          _macroBar('Protéines', protein / divisor, protein * 4, macroKcal,
              HealthColors.protein),
          _macroBar('Glucides', carbs / divisor, carbs * 4, macroKcal,
              HealthColors.carbs),
          _macroBar('Lipides', fat / divisor, fat * 9, macroKcal, HealthColors.fat),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Fibres : ${formatNumber(fiber / divisor)} g / jour',
                style: const TextStyle(color: HealthColors.fiber,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _macroBar(String label, double grams, double kcal, double totalKcal,
      Color color) {
    final share = totalKcal <= 0 ? 0.0 : kcal / totalKcal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(color: HealthColors.ink)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 10,
                color: color,
                backgroundColor: color.withValues(alpha: .12),
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              '${formatNumber(grams)} g · ${formatNumber(share * 100, decimals: 0)} %',
              textAlign: TextAlign.right,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _waterCard() {
    final values = _water.map((d) => asDouble(d['totalMl']) ?? 0).toList();
    final goal = asDouble(_goal['dailyWaterGoalMl']) ?? 2000;
    final average = averageWaterPerDay(_water);
    final reached = values.where((v) => v >= goal).length;
    return HealthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _kpi(formatLiters(average), 'moyenne / jour renseigné', HealthColors.water),
              _kpi(formatLiters(goal), 'objectif', HealthColors.success),
              _kpi('$reached / ${values.length}', 'jours objectif atteint',
                  HealthColors.brightTeal),
            ],
          ),
          const SizedBox(height: 14),
          HealthBarChart(
            values: values,
            labels: _dayLabels(_water),
            color: HealthColors.water,
            goal: goal,
          ),
        ],
      ),
    );
  }

  /// Présente les tendances en parallèle, sans interprétation médicale.
  Widget _relationCard(List<double> weights) {
    final daysWithMeals =
        _nutrition.where((d) => (asDouble(d['mealCount']) ?? 0) > 0).toList();
    final avgCalories = daysWithMeals.isEmpty
        ? null
        : daysWithMeals.fold<double>(
                0, (s, d) => s + (asDouble(d['totalCalories']) ?? 0)) /
            daysWithMeals.length;
    final avgWater = averageWaterPerDay(_water) == 0 ? null : averageWaterPerDay(_water);
    final weightChange =
        weights.length >= 2 ? weights.last - weights.first : null;
    final calorieGoal = asDouble(_goal['dailyCalorieGoal']) ?? 2000;
    final waterGoal = asDouble(_goal['dailyWaterGoalMl']) ?? 2000;

    String trendText(double change) {
      if (change.abs() < 0.2) return 'stable';
      return change > 0
          ? 'en hausse de ${formatNumber(change)} kg'
          : 'en baisse de ${formatNumber(change.abs())} kg';
    }

    return HealthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _relationRow(
            Icons.monitor_weight_outlined,
            HealthColors.weight,
            'Poids',
            weightChange == null
                ? 'Pas assez de mesures de poids sur la période'
                : 'Poids ${trendText(weightChange)} (${formatNumber(weights.first)} → ${formatNumber(weights.last)} kg)',
          ),
          _relationRow(
            Icons.local_fire_department_outlined,
            HealthColors.calories,
            'Apports',
            avgCalories == null
                ? 'Aucun repas enregistré'
                : '${formatNumber(avgCalories, decimals: 0)} kcal / jour en moyenne '
                    '(${avgCalories > calorieGoal ? 'au-dessus' : 'en dessous'} de l’objectif de ${formatNumber(calorieGoal, decimals: 0)} kcal)',
          ),
          _relationRow(
            Icons.water_drop_outlined,
            HealthColors.water,
            'Hydratation',
            avgWater == null
                ? 'Aucune donnée'
                : '${formatLiters(avgWater)} / jour en moyenne '
                    '(${avgWater >= waterGoal ? 'objectif atteint' : 'sous l’objectif de ${formatLiters(waterGoal)}'})',
          ),
          const SizedBox(height: 6),
          const Text(
            'Ces tendances sont présentées côte à côte à titre indicatif ; elles ne constituent pas un diagnostic médical.',
            style: TextStyle(
                fontSize: 12, color: HealthColors.muted, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _relationRow(IconData icon, Color color, String title, String text) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HealthIconBadge(icon, color, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: HealthColors.ink)),
                  Text(text, style: const TextStyle(color: HealthColors.muted)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _kpi(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            FittedBox(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            ),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: HealthColors.muted)),
          ],
        ),
      );
}

class _MetricChart extends StatelessWidget {
  const _MetricChart({
    required this.title,
    required this.unit,
    required this.icon,
    required this.color,
    required this.values,
    required this.dates,
    this.secondary,
    this.decimals = 1,
    this.legend,
    this.target,
  });

  final String title;
  final String unit;
  final IconData icon;
  final Color color;
  final List<double> values;
  final List<double>? secondary;
  final List<DateTime> dates;
  final int decimals;
  final List<String>? legend;
  final double? target;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final change = values.last - values.first;
    String fmt(double v) => formatNumber(v, decimals: decimals);
    String pair(int i) =>
        secondary == null ? fmt(values[i]) : '${fmt(values[i])}/${fmt(secondary![i])}';

    return HealthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HealthIconBadge(icon, color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$title ($unit)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: HealthColors.ink)),
                    Text('${values.length} ${values.length > 1 ? 'mesures' : 'mesure'} · dernière : ${pair(values.length - 1)}',
                        style: const TextStyle(
                            fontSize: 12, color: HealthColors.muted)),
                  ],
                ),
              ),
              if (values.length >= 2)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${change > 0 ? '+' : ''}${fmt(change)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _mini('Min', fmt(minV)),
              _mini('Moyenne', fmt(avg)),
              _mini('Max', fmt(maxV)),
              if (target != null) _mini('Objectif', fmt(target!)),
            ],
          ),
          const SizedBox(height: 12),
          if (values.length >= 2)
            HealthLineChart(
              series: [
                ChartSeries(values, color),
                if (secondary != null)
                  ChartSeries(secondary!, color.withValues(alpha: .45)),
              ],
              decimals: decimals,
              startLabel: dates.isEmpty ? null : formatShortDate(dates.first),
              endLabel: dates.isEmpty ? null : formatShortDate(dates.last),
            )
          else
            const Text('Une seule mesure : ajoutez-en d’autres pour voir la courbe.',
                style: TextStyle(color: HealthColors.muted)),
          if (legend != null && values.length >= 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  _legendDot(color, legend![0]),
                  const SizedBox(width: 16),
                  _legendDot(color.withValues(alpha: .45), legend![1]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: HealthColors.muted)),
          ],
        ),
      );

  Widget _legendDot(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(fontSize: 12, color: HealthColors.muted)),
        ],
      );
}
