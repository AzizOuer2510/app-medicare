import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import 'ai_food_page.dart';
import 'health_ai_page.dart';
import 'health_api.dart';
import 'health_goals_page.dart';
import 'health_stats_page.dart';
import 'health_theme.dart';
import 'measure_form.dart';
import 'nutrition_chat_page.dart';

/// Tableau de bord : dernières mesures, IMC, nutrition et hydratation du jour,
/// évolution du poids et de la fréquence cardiaque, accès aux fonctions IA.
class HealthDashboardTab extends ConsumerStatefulWidget {
  const HealthDashboardTab({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  ConsumerState<HealthDashboardTab> createState() => _HealthDashboardTabState();
}

class _HealthDashboardTabState extends ConsumerState<HealthDashboardTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _records = [];
  Map<String, dynamic> _mealStats = {};
  int _waterMl = 0;
  int _waterGoal = 2000;
  Map<String, dynamic> _goal = {};
  bool _loading = true;
  String? _error;
  bool _addingWater = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _records.isEmpty;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final query = patientQuery(context);
      final results = await Future.wait([
        dio.get('/health-records', queryParameters: query),
        dio.get('/meals/stats/today', queryParameters: query),
        dio.get('/hydration/today', queryParameters: query),
        dio.get('/health-goals', queryParameters: query),
      ]);
      if (!mounted) return;
      final water = asMap(results[2].data);
      setState(() {
        _records = asMapList(results[0].data);
        _mealStats = asMap(results[1].data);
        _waterMl = (asDouble(water['totalMl']) ?? 0).round();
        _waterGoal = (asDouble(water['goalMl']) ?? 2000).round();
        _goal = asMap(results[3].data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = healthErrorMessage(error,
            fallback: 'Impossible de charger votre suivi de santé.');
      });
    }
  }

  /// Dernières valeurs (récente puis précédente) d'une constante donnée.
  (double?, double?) _latest(String field) {
    final values = _records
        .map((r) => asDouble(r[field]))
        .whereType<double>()
        .take(2)
        .toList();
    return (
      values.isNotEmpty ? values[0] : null,
      values.length > 1 ? values[1] : null,
    );
  }

  Map<String, dynamic>? get _latestPressure {
    for (final r in _records) {
      if (r['systolic'] != null && r['diastolic'] != null) return r;
    }
    return null;
  }

  Widget? _trend(String field, {bool lowerIsBetter = true}) {
    final (current, previous) = _latest(field);
    if (current == null || previous == null || current == previous) return null;
    final up = current > previous;
    final good = up != lowerIsBetter;
    return Icon(
      up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
      size: 20,
      color: good ? HealthColors.success : HealthColors.heart,
    );
  }

  Future<void> _quickWater(int ml) async {
    setState(() => _addingWater = true);
    try {
      final now = DateTime.now();
      await ref.read(apiClientProvider).dio.post('/hydration', data: {
        'quantityMl': ml,
        'recordedDate': apiDate(now),
        'recordedTime': apiTime(TimeOfDay.fromDateTime(now)),
      });
      notifyHealthDataChanged(ref);
      if (mounted) showHealthSnack(context, '$ml ml ajoutés à votre hydratation.');
    } catch (error) {
      if (mounted) showHealthSnack(context, healthErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _addingWater = false);
    }
  }

  Future<void> _addMeasure() async {
    final saved = await showMeasureForm(context, ref);
    if (saved) notifyHealthDataChanged(ref);
  }

  void _push(Widget page) => pushHealthPage(context, page).then((_) => _load());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen(healthRevisionProvider, (_, __) => _load());
    final patient = HealthScope.patientOf(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          patient == null
              ? const HealthHero(
                  label: 'SUIVI SANTÉ ET NUTRITION',
                  title: 'Votre santé,\nau quotidien.',
                  subtitle:
                      'Mesures, repas et hydratation réunis pour suivre votre évolution.',
                )
              : HealthHero(
                  label: 'ESPACE MÉDECIN · SUIVI DU PATIENT',
                  title: patient.name,
                  subtitle:
                      'Constantes, alimentation et hydratation de votre patient.',
                  icon: Icons.medical_services_rounded,
                  badgeIcon: Icons.monitor_heart_rounded,
                ),
          HealthBody(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: CircularProgressIndicator(
                            color: HealthColors.brightTeal),
                      ),
                    )
                  : _error != null
                      ? HealthErrorState(message: _error!, onRetry: _load)
                      : _content(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    final doctorView = HealthScope.isDoctorView(context);
    final (weight, _) = _latest('weight');
    final (heartRate, _) = _latest('heartRate');
    final (temperature, _) = _latest('temperature');
    final (glycemia, _) = _latest('glycemia');
    final pressure = _latestPressure;
    final targetWeight = asDouble(_goal['targetWeight']);
    final bmi = computeBmi(weight, asDouble(_goal['heightCm']));
    final lastDate = _records.isEmpty
        ? null
        : parseApiDateTime(_records.first['recordedAt']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthSectionTitle(
          doctorView ? 'Constantes du patient' : 'Mon suivi de santé',
          icon: Icons.favorite_rounded,
          trailing: TextButton.icon(
            onPressed: _addMeasure,
            icon: const Icon(Icons.add, size: 18),
            label: Text(doctorView ? 'Mesure de consultation' : 'Mesure'),
          ),
        ),
        if (lastDate != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'Dernière mesure : ${DateFormat("d MMMM yyyy 'à' HH:mm", 'fr_FR').format(lastDate)}',
              style: const TextStyle(color: HealthColors.muted, fontSize: 13),
            ),
          ),
        _ResponsiveGrid(children: [
          HealthSummaryTile(
            label: targetWeight == null
                ? 'Poids'
                : 'Poids · objectif ${formatNumber(targetWeight)} kg',
            value: weight == null ? '—' : '${formatNumber(weight)} kg',
            icon: Icons.monitor_weight_outlined,
            color: HealthColors.weight,
            trailing: _trend('weight'),
            onTap: () => widget.onOpenTab(1),
          ),
          HealthSummaryTile(
            label: 'Fréquence cardiaque',
            value: heartRate == null ? '—' : '${heartRate.round()} bpm',
            icon: Icons.favorite_outline,
            color: HealthColors.heart,
            trailing: _trend('heartRate'),
            onTap: () => widget.onOpenTab(1),
          ),
          HealthSummaryTile(
            label: 'Tension artérielle (mmHg)',
            value: pressure == null
                ? '—'
                : '${pressure['systolic']}/${pressure['diastolic']}',
            icon: Icons.speed_outlined,
            color: HealthColors.pressure,
            trailing: _trend('systolic'),
            onTap: () => widget.onOpenTab(1),
          ),
          HealthSummaryTile(
            label: 'Température',
            value: temperature == null ? '—' : '${formatNumber(temperature)} °C',
            icon: Icons.thermostat_outlined,
            color: HealthColors.temperature,
            onTap: () => widget.onOpenTab(1),
          ),
          HealthSummaryTile(
            label: 'Glycémie',
            value: glycemia == null
                ? '—'
                : '${formatNumber(glycemia, decimals: 2)} g/L',
            icon: Icons.bloodtype_outlined,
            color: HealthColors.glycemia,
            trailing: _trend('glycemia'),
            onTap: () => widget.onOpenTab(1),
          ),
          HealthSummaryTile(
            label: 'Hydratation aujourd’hui',
            value: '${formatLiters(_waterMl)} / ${formatLiters(_waterGoal)}',
            icon: Icons.water_drop_outlined,
            color: HealthColors.water,
            progress: _waterGoal == 0 ? 0 : _waterMl / _waterGoal,
            onTap: () => widget.onOpenTab(2),
          ),
        ]),
        const SizedBox(height: 12),
        _bmiCard(bmi),
        _nutritionCard(),
        _hydrationCard(),
        _evolutionCard(),
        const HealthSectionTitle('Assistance IA', icon: Icons.auto_awesome),
        _aiCard(
          icon: Icons.health_and_safety_outlined,
          color: HealthColors.glycemia,
          title: 'Analyse santé IA',
          subtitle: doctorView
              ? 'Alertes et tendances à partir des mesures du patient'
              : 'Alertes et recommandations à partir de vos mesures',
          page: const HealthAiPage(),
        ),
        if (!doctorView) ...[
        _aiCard(
          icon: Icons.photo_camera_outlined,
          color: HealthColors.brightTeal,
          title: 'Reconnaissance des aliments',
          subtitle: 'Photo ou description → estimation nutritionnelle',
          page: const AiFoodPage(),
        ),
        _aiCard(
          icon: Icons.chat_bubble_outline_rounded,
          color: HealthColors.success,
          title: 'NutriCoach',
          subtitle: 'Conseils nutritionnels personnalisés',
          page: const NutritionChatPage(),
        ),
        ],
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Text(
            'Les données et tendances présentées sont informatives et ne constituent pas un diagnostic médical.',
            style: TextStyle(
                fontSize: 12,
                color: HealthColors.muted,
                fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _bmiCard(double? bmi) {
    if (bmi == null) {
      return HealthCard(
        onTap: () => _push(const HealthGoalsPage()),
        child: const Row(
          children: [
            HealthIconBadge(Icons.calculate_outlined, HealthColors.brightTeal),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Calculer votre IMC',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: HealthColors.ink)),
                  Text('Renseignez la taille dans les objectifs et ajoutez un poids',
                      style: TextStyle(color: HealthColors.muted, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: HealthColors.muted),
          ],
        ),
      );
    }
    final color = bmiColor(bmi);
    return HealthCard(
      onTap: () => _push(const HealthGoalsPage()),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(formatNumber(bmi),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Indice de masse corporelle (IMC)',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: HealthColors.ink)),
                Text(bmiLabel(bmi),
                    style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: HealthColors.muted),
        ],
      ),
    );
  }

  Widget _nutritionCard() {
    final calories = asDouble(_mealStats['totalCalories']) ?? 0;
    final goal = asDouble(_mealStats['calorieGoal']) ??
        asDouble(_goal['dailyCalorieGoal']) ??
        2000;
    final meals = (asDouble(_mealStats['mealCount']) ?? 0).round();
    return HealthCard(
      onTap: () => widget.onOpenTab(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              HealthIconBadge(Icons.restaurant_rounded, HealthColors.calories),
              SizedBox(width: 12),
              Expanded(
                child: Text('Nutrition aujourd’hui',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: HealthColors.ink)),
              ),
              Icon(Icons.chevron_right, color: HealthColors.muted),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat('$meals', meals > 1 ? 'repas' : 'repas', HealthColors.brightTeal),
              _stat(formatNumber(calories, decimals: 0), 'kcal estimées',
                  HealthColors.calories),
              _stat(formatNumber(goal, decimals: 0), 'kcal objectif',
                  HealthColors.success),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: goal == 0 ? 0 : (calories / goal).clamp(0.0, 1.0),
              minHeight: 8,
              color: calories > goal ? HealthColors.heart : HealthColors.calories,
              backgroundColor: HealthColors.calories.withValues(alpha: .15),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _macro('Protéines', _mealStats['totalProtein'], HealthColors.protein),
              _macro('Glucides', _mealStats['totalCarbohydrates'], HealthColors.carbs),
              _macro('Lipides', _mealStats['totalFat'], HealthColors.fat),
              _macro('Fibres', _mealStats['totalFiber'], HealthColors.fiber),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 12, color: HealthColors.muted)),
          ],
        ),
      );

  Widget _macro(String label, dynamic value, Color color) => Expanded(
        child: Column(
          children: [
            Text('${formatNumber(asDouble(value) ?? 0)} g',
                style: TextStyle(fontWeight: FontWeight.w700, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: HealthColors.muted)),
          ],
        ),
      );

  Widget _hydrationCard() {
    final done = _waterMl >= _waterGoal;
    return HealthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HealthIconBadge(Icons.water_drop_rounded, HealthColors.water),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Hydratation aujourd’hui',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: HealthColors.ink)),
              ),
              Text('${formatLiters(_waterMl)} / ${formatLiters(_waterGoal)}',
                  style: const TextStyle(
                      color: HealthColors.water, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _waterGoal == 0 ? 0 : (_waterMl / _waterGoal).clamp(0.0, 1.0),
              minHeight: 12,
              color: done ? HealthColors.success : HealthColors.water,
              backgroundColor: HealthColors.water.withValues(alpha: .12),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            done
                ? 'Objectif atteint, bravo !'
                : 'Encore ${formatLiters(_waterGoal - _waterMl)} pour atteindre votre objectif',
            style: const TextStyle(fontSize: 13, color: HealthColors.muted),
          ),
          if (!HealthScope.isDoctorView(context)) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ml in const [150, 250, 500])
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16, color: HealthColors.water),
                  label: Text('$ml ml'),
                  onPressed: _addingWater ? null : () => _quickWater(ml),
                  backgroundColor: HealthColors.water.withValues(alpha: .08),
                  side: BorderSide.none,
                ),
            ],
          ),
          ],
        ],
      ),
    );
  }

  Widget _evolutionCard() {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final recent = _records.reversed.where((r) {
      final date = parseApiDateTime(r['recordedAt']);
      return date != null && date.isAfter(cutoff);
    }).toList();
    List<double> values(String field) =>
        recent.map((r) => asDouble(r[field])).whereType<double>().toList();
    final weights = values('weight');
    final rates = values('heartRate');

    return HealthCard(
      onTap: () => _push(const HealthStatsPage()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              HealthIconBadge(Icons.show_chart_rounded, HealthColors.brightTeal),
              SizedBox(width: 12),
              Expanded(
                child: Text('Évolution sur 30 jours',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: HealthColors.ink)),
              ),
              Text('Statistiques',
                  style: TextStyle(
                      color: HealthColors.brightTeal,
                      fontWeight: FontWeight.w600)),
              Icon(Icons.chevron_right, color: HealthColors.brightTeal),
            ],
          ),
          const SizedBox(height: 12),
          if (weights.length < 2 && rates.length < 2)
            const Text(
              'Ajoutez au moins deux mesures pour voir vos courbes d’évolution.',
              style: TextStyle(color: HealthColors.muted),
            ),
          if (weights.length >= 2) ...[
            const Text('Poids (kg)',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: HealthColors.weight)),
            const SizedBox(height: 6),
            HealthLineChart(
              series: [ChartSeries(weights, HealthColors.weight)],
              height: 110,
            ),
            const SizedBox(height: 14),
          ],
          if (rates.length >= 2) ...[
            const Text('Fréquence cardiaque (bpm)',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: HealthColors.heart)),
            const SizedBox(height: 6),
            HealthLineChart(
              series: [ChartSeries(rates, HealthColors.heart)],
              height: 110,
              decimals: 0,
            ),
          ],
        ],
      ),
    );
  }

  Widget _aiCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return HealthCard(
      onTap: () => _push(page),
      child: Row(
        children: [
          HealthIconBadge(icon, color, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: HealthColors.ink)),
                Text(subtitle,
                    style:
                        const TextStyle(color: HealthColors.muted, fontSize: 13)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: color),
        ],
      ),
    );
  }
}

/// Grille responsive : 2 colonnes sur téléphone, 3 sur écran large.
class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600 ? 3 : 2;
      const spacing = 10.0;
      final width =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    });
  }
}
