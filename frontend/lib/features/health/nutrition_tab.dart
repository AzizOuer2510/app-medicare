import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'ai_food_page.dart';
import 'health_api.dart';
import 'health_theme.dart';
import 'meal_form_page.dart';
import 'nutrition_chat_page.dart';

/// Section Nutrition : journal alimentaire et hydratation.
class NutritionTab extends StatefulWidget {
  const NutritionTab({super.key});

  @override
  State<NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends State<NutritionTab>
    with AutomaticKeepAliveClientMixin {
  int _section = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Container(
          color: HealthColors.background,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: HealthBody(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.menu_book_outlined),
                    label: Text('Journal alimentaire')),
                ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.water_drop_outlined),
                    label: Text('Hydratation')),
              ],
              selected: {_section},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _section = value.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: Colors.white,
                selectedBackgroundColor: HealthColors.brightTeal,
                selectedForegroundColor: Colors.white,
                foregroundColor: HealthColors.brightTeal,
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _section,
            children: const [_MealJournal(), _HydrationSection()],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Journal alimentaire
// ─────────────────────────────────────────────────────────────────────────────
class _MealJournal extends ConsumerStatefulWidget {
  const _MealJournal();

  @override
  ConsumerState<_MealJournal> createState() => _MealJournalState();
}

class _MealJournalState extends ConsumerState<_MealJournal> {
  List<Map<String, dynamic>> _meals = [];
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  String? _error;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final dio = ref.read(apiClientProvider).dio;
      final results = await Future.wait([
        _days == 0
            ? dio.get('/meals', queryParameters: patientQuery(context))
            : dio.get('/meals/history',
                queryParameters: patientQuery(context, {'days': _days})),
        dio.get('/meals/stats/today', queryParameters: patientQuery(context)),
      ]);
      if (!mounted) return;
      setState(() {
        _meals = asMapList(results[0].data);
        _stats = asMap(results[1].data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = healthErrorMessage(error,
            fallback: 'Impossible de charger votre journal alimentaire.');
      });
    }
  }

  Map<String, List<Map<String, dynamic>>> get _byDay {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final meal in _meals) {
      grouped.putIfAbsent(meal['mealDate']?.toString() ?? '', () => []).add(meal);
    }
    return grouped;
  }

  Future<void> _openForm([Map<String, dynamic>? meal]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MealFormPage(meal: meal)),
    );
    if (saved == true && mounted) {
      showHealthSnack(context, meal == null ? 'Repas enregistré.' : 'Repas modifié.');
      notifyHealthDataChanged(ref);
    }
  }

  Future<void> _delete(Map<String, dynamic> meal) async {
    if (!await confirmHealthDelete(context, 'ce repas')) return;
    try {
      await ref.read(apiClientProvider).dio.delete('/meals/${meal['id']}');
      if (!mounted) return;
      showHealthSnack(context, 'Repas supprimé.');
      notifyHealthDataChanged(ref);
    } catch (error) {
      if (mounted) showHealthSnack(context, healthErrorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(healthRevisionProvider, (_, __) => _load());
    final grouped = _byDay;
    final doctorView = HealthScope.isDoctorView(context);

    return Scaffold(
      backgroundColor: HealthColors.background,
      floatingActionButton: doctorView ? null : FloatingActionButton.extended(
        heroTag: 'add-meal',
        onPressed: () => _openForm(),
        backgroundColor: HealthColors.brightTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter un repas'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            HealthBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TodaySummary(stats: _stats),
                  if (doctorView)
                    const HealthCard(
                      color: Color(0xFFE8F5F4),
                      child: Row(
                        children: [
                          Icon(Icons.visibility_outlined, color: HealthColors.brightTeal),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Journal tenu par le patient : consultation seule.',
                              style: TextStyle(color: HealthColors.ink),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                  Row(
                    children: [
                      Expanded(
                        child: _ShortcutCard(
                          icon: Icons.photo_camera_outlined,
                          title: 'Analyse IA',
                          subtitle: 'Photo ou texte',
                          color: HealthColors.brightTeal,
                          onTap: () => Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (_) => const AiFoodPage()),
                          ).then((saved) {
                            if (saved == true) notifyHealthDataChanged(ref);
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ShortcutCard(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'NutriCoach',
                          subtitle: 'Conseils IA',
                          color: HealthColors.success,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NutritionChatPage()),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  HealthSectionTitle('Historique des repas',
                      icon: Icons.history_rounded,
                      trailing: Text(
                          '${_meals.length} ${_meals.length > 1 ? 'repas' : 'repas'}',
                          style: const TextStyle(color: HealthColors.muted))),
                  HealthChoiceChips<int>(
                    padding: EdgeInsets.zero,
                    options: const [
                      (1, 'Aujourd’hui'),
                      (7, '7 jours'),
                      (30, '30 jours'),
                      (0, 'Tout'),
                    ],
                    selected: _days,
                    onSelected: (value) {
                      setState(() => _days = value);
                      _load();
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                          child: CircularProgressIndicator(
                              color: HealthColors.brightTeal)),
                    )
                  else if (_error != null)
                    HealthErrorState(message: _error!, onRetry: _load)
                  else if (grouped.isEmpty)
                    HealthEmptyState(
                      icon: Icons.restaurant_outlined,
                      title: 'Aucun repas enregistré',
                      message: doctorView
                          ? 'Le patient n’a enregistré aucun repas sur cette période.'
                          : 'Ajoutez vos petits-déjeuners, déjeuners, dîners et collations pour suivre vos apports.',
                      action: doctorView ? null : FilledButton.icon(
                        style: healthFilledButtonStyle(),
                        onPressed: () => _openForm(),
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter un repas'),
                      ),
                    )
                  else
                    for (final entry in grouped.entries)
                      _DayGroup(
                        date: entry.key,
                        meals: entry.value,
                        readOnly: doctorView,
                        onEdit: _openForm,
                        onDelete: _delete,
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final calories = asDouble(stats['totalCalories']) ?? 0;
    final goal = asDouble(stats['calorieGoal']) ?? 2000;
    final count = (asDouble(stats['mealCount']) ?? 0).round();
    return HealthCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HealthIconBadge(
                  Icons.local_fire_department_outlined, HealthColors.calories),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Aujourd’hui',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: HealthColors.ink)),
              ),
              Text('$count repas',
                  style: const TextStyle(color: HealthColors.muted)),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: formatNumber(calories, decimals: 0),
                style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: HealthColors.calories),
              ),
              TextSpan(
                text: '  / ${formatNumber(goal, decimals: 0)} kcal estimées',
                style: const TextStyle(color: HealthColors.muted),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: goal == 0 ? 0 : (calories / goal).clamp(0.0, 1.0),
              minHeight: 8,
              color: calories > goal ? HealthColors.heart : HealthColors.calories,
              backgroundColor: HealthColors.calories.withValues(alpha: .15),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _macro('Protéines', stats['totalProtein'], HealthColors.protein),
              _macro('Glucides', stats['totalCarbohydrates'], HealthColors.carbs),
              _macro('Lipides', stats['totalFat'], HealthColors.fat),
              _macro('Fibres', stats['totalFiber'], HealthColors.fiber),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macro(String label, dynamic value, Color color) => Expanded(
        child: Column(
          children: [
            Text('${formatNumber(asDouble(value) ?? 0)} g',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: HealthColors.muted)),
          ],
        ),
      );
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HealthCard(
        onTap: onTap,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            HealthIconBadge(icon, color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: HealthColors.ink)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: HealthColors.muted)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.date,
    required this.meals,
    required this.readOnly,
    required this.onEdit,
    required this.onDelete,
  });

  final bool readOnly;
  final String date;
  final List<Map<String, dynamic>> meals;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onDelete;

  @override
  Widget build(BuildContext context) {
    final day = DateTime.tryParse(date);
    final total = meals.fold<double>(
        0, (sum, m) => sum + (asDouble(m['calories']) ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(day == null ? date : formatLongDate(day),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: HealthColors.ink)),
              ),
              Text('${formatNumber(total, decimals: 0)} kcal',
                  style: const TextStyle(
                      color: HealthColors.calories, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        for (final meal in meals)
          _MealCard(
            meal: meal,
            readOnly: readOnly,
            onEdit: () => onEdit(meal),
            onDelete: () => onDelete(meal),
          ),
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.meal,
    required this.readOnly,
    required this.onEdit,
    required this.onDelete,
  });

  final bool readOnly;
  final Map<String, dynamic> meal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final type = meal['mealType']?.toString() ?? '';
    final color = mealTypeColors[type] ?? HealthColors.brightTeal;
    final description = meal['description']?.toString() ?? '';
    final comment = meal['comment']?.toString() ?? '';
    final macros = <String>[
      if (meal['protein'] != null) 'P ${formatNumber(asDouble(meal['protein']))} g',
      if (meal['carbohydrates'] != null)
        'G ${formatNumber(asDouble(meal['carbohydrates']))} g',
      if (meal['fat'] != null) 'L ${formatNumber(asDouble(meal['fat']))} g',
      if (meal['fiber'] != null) 'F ${formatNumber(asDouble(meal['fiber']))} g',
    ];
    return HealthCard(
      onTap: readOnly ? null : onEdit,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HealthIconBadge(mealTypeIcons[type] ?? Icons.restaurant, color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(mealTypeLabels[type] ?? type,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: HealthColors.ink)),
                    const SizedBox(width: 8),
                    Text(shortTime(meal['mealTime']),
                        style: const TextStyle(
                            color: HealthColors.muted, fontSize: 12)),
                    const Spacer(),
                    if (meal['calories'] != null)
                      Text('${formatNumber(asDouble(meal['calories']), decimals: 0)} kcal',
                          style: const TextStyle(
                              color: HealthColors.calories,
                              fontWeight: FontWeight.w700)),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(description, style: const TextStyle(color: HealthColors.ink)),
                ],
                if (macros.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(macros.join('  ·  '),
                      style: const TextStyle(
                          fontSize: 12, color: HealthColors.muted)),
                ],
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(comment,
                      style: const TextStyle(
                          fontSize: 12,
                          color: HealthColors.muted,
                          fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
          if (readOnly)
            const SizedBox(width: 12)
          else
          PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Modifier')),
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hydratation
// ─────────────────────────────────────────────────────────────────────────────
class _HydrationSection extends ConsumerStatefulWidget {
  const _HydrationSection();

  @override
  ConsumerState<_HydrationSection> createState() => _HydrationSectionState();
}

class _HydrationSectionState extends ConsumerState<_HydrationSection> {
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _history = [];
  int _total = 0;
  int _goal = 2000;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final dio = ref.read(apiClientProvider).dio;
      final results = await Future.wait([
        dio.get('/hydration/today', queryParameters: patientQuery(context)),
        dio.get('/hydration/history',
            queryParameters: patientQuery(context, {'days': 7})),
      ]);
      if (!mounted) return;
      final today = asMap(results[0].data);
      setState(() {
        _entries = asMapList(today['entries']);
        _total = (asDouble(today['totalMl']) ?? 0).round();
        _goal = (asDouble(today['goalMl']) ?? 2000).round();
        _history = asMapList(results[1].data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = healthErrorMessage(error,
            fallback: 'Impossible de charger votre hydratation.');
      });
    }
  }

  Future<void> _add(int ml, {String? note}) async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await ref.read(apiClientProvider).dio.post('/hydration', data: {
        'quantityMl': ml,
        'recordedDate': apiDate(now),
        'recordedTime': apiTime(TimeOfDay.fromDateTime(now)),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });
      if (!mounted) return;
      showHealthSnack(context, '$ml ml ajoutés.');
      notifyHealthDataChanged(ref);
    } catch (error) {
      if (mounted) showHealthSnack(context, healthErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _customAmount() async {
    final quantity = TextEditingController();
    final note = TextEditingController();
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajouter de l’eau'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantity,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: healthInputDecoration('Quantité',
                  icon: Icons.water_drop_outlined, suffix: 'ml', hint: '330'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: healthInputDecoration('Note (optionnel)',
                  icon: Icons.notes_outlined, hint: 'Thé, infusion…'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final ml = parseUserNumber(quantity.text)?.round();
              if (ml == null || ml < 10 || ml > 5000) return;
              Navigator.pop(dialogContext, (ml, note.text));
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    quantity.dispose();
    note.dispose();
    if (result != null) await _add(result.$1, note: result.$2);
  }

  Future<void> _delete(Map<String, dynamic> entry) async {
    if (!await confirmHealthDelete(context, 'cette entrée')) return;
    try {
      await ref.read(apiClientProvider).dio.delete('/hydration/${entry['id']}');
      if (!mounted) return;
      notifyHealthDataChanged(ref);
    } catch (error) {
      if (mounted) showHealthSnack(context, healthErrorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(healthRevisionProvider, (_, __) => _load());
    final doctorView = HealthScope.isDoctorView(context);
    final progress = _goal == 0 ? 0.0 : _total / _goal;
    final average = averageWaterPerDay(_history);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          HealthBody(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: HealthColors.brightTeal)),
                  )
                : _error != null
                    ? HealthErrorState(message: _error!, onRetry: _load)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HealthCard(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                HealthRing(
                                  progress: progress,
                                  color: progress >= 1
                                      ? HealthColors.success
                                      : HealthColors.water,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.water_drop,
                                          color: HealthColors.water, size: 28),
                                      Text(formatLiters(_total),
                                          style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.w800,
                                              color: HealthColors.ink)),
                                      Text('sur ${formatLiters(_goal)}',
                                          style: const TextStyle(
                                              color: HealthColors.muted)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  progress >= 1
                                      ? 'Objectif d’hydratation atteint !'
                                      : 'Encore ${formatLiters(_goal - _total)} aujourd’hui',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: progress >= 1
                                        ? HealthColors.success
                                        : HealthColors.muted,
                                  ),
                                ),
                                if (!doctorView) ...[
                                const SizedBox(height: 16),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final ml in const [150, 250, 330, 500, 750])
                                      ActionChip(
                                        avatar: const Icon(Icons.add,
                                            size: 16, color: HealthColors.water),
                                        label: Text('$ml ml'),
                                        onPressed: _saving ? null : () => _add(ml),
                                        backgroundColor:
                                            HealthColors.water.withValues(alpha: .08),
                                        side: BorderSide.none,
                                      ),
                                    ActionChip(
                                      avatar: const Icon(Icons.edit_outlined,
                                          size: 16, color: HealthColors.brightTeal),
                                      label: const Text('Autre'),
                                      onPressed: _saving ? null : _customAmount,
                                      side: BorderSide.none,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Objectif modifiable dans « Mes objectifs ».',
                                  style: TextStyle(
                                      fontSize: 12, color: HealthColors.muted),
                                ),
                                ],
                              ],
                            ),
                          ),
                          HealthSectionTitle('Historique sur 7 jours',
                              icon: Icons.bar_chart_rounded,
                              trailing: Text(
                                  'Moyenne ${formatLiters(average)}/jour',
                                  style: const TextStyle(
                                      color: HealthColors.muted))),
                          HealthCard(
                            child: HealthBarChart(
                              values: _history
                                  .map((d) => asDouble(d['totalMl']) ?? 0)
                                  .toList(),
                              labels: _history.map((d) {
                                final date = DateTime.tryParse(d['date'].toString());
                                return date == null ? '' : formatShortDate(date);
                              }).toList(),
                              color: HealthColors.water,
                              goal: _goal.toDouble(),
                            ),
                          ),
                          HealthSectionTitle('Entrées du jour',
                              icon: Icons.schedule,
                              trailing: Text(
                                  '${_entries.length} ${_entries.length > 1 ? 'entrées' : 'entrée'}',
                                  style: const TextStyle(
                                      color: HealthColors.muted))),
                          if (_entries.isEmpty)
                            HealthEmptyState(
                              icon: Icons.local_drink_outlined,
                              title: 'Rien pour l’instant',
                              message: doctorView
                                  ? 'Aucune consommation d’eau enregistrée aujourd’hui.'
                                  : 'Touchez une quantité ci-dessus pour enregistrer un verre d’eau.',
                            )
                          else
                            for (final entry in _entries)
                              HealthCard(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                                child: Row(
                                  children: [
                                    const HealthIconBadge(
                                        Icons.water_drop, HealthColors.water),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('${entry['quantityMl']} ml',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: HealthColors.ink)),
                                          Text(
                                            [
                                              shortTime(entry['recordedTime']),
                                              if ((entry['note'] ?? '')
                                                  .toString()
                                                  .isNotEmpty)
                                                entry['note'].toString(),
                                            ].join(' · '),
                                            style: const TextStyle(
                                                color: HealthColors.muted,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!doctorView)
                                    IconButton(
                                      tooltip: 'Supprimer',
                                      icon: const Icon(Icons.delete_outline),
                                      color: const Color(0xFFB3261E),
                                      onPressed: () => _delete(entry),
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
