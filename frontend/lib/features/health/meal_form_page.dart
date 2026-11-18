import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import 'health_api.dart';
import 'health_theme.dart';

/// Ajout / modification d'un repas : type, date, heure, aliments (base d'aliments)
/// et quantités, commentaire, calories et macronutriments.
/// Renvoie `true` à la fermeture si le repas a été enregistré.
class MealFormPage extends ConsumerStatefulWidget {
  const MealFormPage({super.key, this.meal});

  final Map<String, dynamic>? meal;

  @override
  ConsumerState<MealFormPage> createState() => _MealFormPageState();
}

class _FoodLine {
  _FoodLine(this.food, this.quantity);
  final Map<String, dynamic> food;
  double quantity;

  double value(String key) => (asDouble(food[key]) ?? 0) * quantity / 100;
  String get unit => food['unit']?.toString() ?? 'g';
  String get label => '${food['name']} ${formatNumber(quantity, decimals: 0)} $unit';
}

class _MealFormPageState extends ConsumerState<MealFormPage> {
  final _formKey = GlobalKey<FormState>();
  late String _type = widget.meal?['mealType']?.toString() ?? _defaultType();
  late DateTime _date =
      DateTime.tryParse(widget.meal?['mealDate']?.toString() ?? '') ?? DateTime.now();
  late TimeOfDay _time =
      parseApiTime(widget.meal?['mealTime']) ?? TimeOfDay.now();
  late final _description =
      TextEditingController(text: widget.meal?['description']?.toString() ?? '');
  late final _comment =
      TextEditingController(text: widget.meal?['comment']?.toString() ?? '');
  late final Map<String, TextEditingController> _macros = {
    for (final key in const ['calories', 'protein', 'carbohydrates', 'fat', 'fiber'])
      key: TextEditingController(
        text: widget.meal?[key] == null
            ? ''
            : NumberFormat('0.#', 'fr_FR').format(asDouble(widget.meal![key])),
      ),
  };
  final List<_FoodLine> _lines = [];
  List<Map<String, dynamic>>? _foods;
  bool _saving = false;

  static String _defaultType() {
    final hour = TimeOfDay.now().hour;
    if (hour < 11) return 'BREAKFAST';
    if (hour < 15) return 'LUNCH';
    if (hour < 18) return 'SNACK';
    return 'DINNER';
  }

  @override
  void dispose() {
    _description.dispose();
    _comment.dispose();
    for (final c in _macros.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadFoods() async {
    if (_foods != null) return _foods!;
    final response = await ref.read(apiClientProvider).dio.get('/foods');
    _foods = asMapList(response.data);
    return _foods!;
  }

  void _recompute() {
    String fmt(double v) => NumberFormat('0.#', 'fr_FR').format(v);
    double sum(String key) => _lines.fold(0, (s, l) => s + l.value(key));
    setState(() {
      _macros['calories']!.text = fmt(sum('calories'));
      _macros['protein']!.text = fmt(sum('protein'));
      _macros['carbohydrates']!.text = fmt(sum('carbohydrates'));
      _macros['fat']!.text = fmt(sum('fat'));
      _macros['fiber']!.text = fmt(sum('fiber'));
      _description.text = _lines.map((l) => l.label).join(', ');
    });
  }

  Future<void> _addFood() async {
    List<Map<String, dynamic>> foods;
    try {
      foods = await _loadFoods();
    } catch (error) {
      if (mounted) showHealthSnack(context, healthErrorMessage(error), error: true);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<_FoodLine>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _FoodPicker(foods: foods),
    );
    if (picked == null) return;
    _lines.add(picked);
    _recompute();
  }

  Future<void> _pickDate() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (day != null) setState(() => _date = day);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _time);
    if (time != null) setState(() => _time = time);
  }

  String? _validateNumber(String? text, double max) {
    if (text == null || text.trim().isEmpty) return null;
    final value = parseUserNumber(text);
    if (value == null || value < 0) return 'Invalide';
    if (value > max) return 'Max ${formatNumber(max, decimals: 0)}';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_description.text.trim().isEmpty &&
        parseUserNumber(_macros['calories']!.text) == null) {
      showHealthSnack(context,
          'Ajoutez au moins un aliment, une description ou des calories.',
          error: true);
      return;
    }
    setState(() => _saving = true);
    final body = {
      'mealType': _type,
      'mealDate': apiDate(_date),
      'mealTime': apiTime(_time),
      'description': _description.text.trim(),
      'comment': _comment.text.trim(),
      for (final entry in _macros.entries)
        entry.key: parseUserNumber(entry.value.text),
    };
    try {
      final dio = ref.read(apiClientProvider).dio;
      if (widget.meal == null) {
        await dio.post('/meals', data: body);
      } else {
        await dio.put('/meals/${widget.meal!['id']}', data: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showHealthSnack(context, healthErrorMessage(error), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealthColors.background,
      appBar: healthAppBar(widget.meal == null ? 'Ajouter un repas' : 'Modifier le repas'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            HealthBody(
              maxWidth: 680,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HealthCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Type de repas',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: HealthColors.ink)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final entry in mealTypeLabels.entries)
                              ChoiceChip(
                                avatar: Icon(mealTypeIcons[entry.key],
                                    size: 18,
                                    color: _type == entry.key
                                        ? Colors.white
                                        : mealTypeColors[entry.key]),
                                label: Text(entry.value),
                                selected: _type == entry.key,
                                showCheckmark: false,
                                selectedColor: HealthColors.brightTeal,
                                labelStyle: TextStyle(
                                  color: _type == entry.key
                                      ? Colors.white
                                      : HealthColors.ink,
                                ),
                                onSelected: (_) => setState(() => _type = entry.key),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickDate,
                                icon: const Icon(Icons.event_outlined),
                                label: Text(DateFormat('dd/MM/yyyy').format(_date)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _pickTime,
                                icon: const Icon(Icons.schedule),
                                label: Text(shortTime(apiTime(_time))),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  HealthCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text('Aliments et quantités',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: HealthColors.ink)),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _addFood,
                              icon: const Icon(Icons.add),
                              label: const Text('Base d’aliments'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Choisissez des aliments : calories et macronutriments sont calculés automatiquement.',
                          style: TextStyle(fontSize: 12, color: HealthColors.muted),
                        ),
                        for (var i = 0; i < _lines.length; i++)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.restaurant,
                                color: HealthColors.brightTeal),
                            title: Text(_lines[i].label),
                            subtitle: Text(
                                '${formatNumber(_lines[i].value('calories'), decimals: 0)} kcal'),
                            trailing: IconButton(
                              tooltip: 'Retirer',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _lines.removeAt(i);
                                _recompute();
                              },
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _description,
                          maxLines: 3,
                          minLines: 2,
                          maxLength: 1000,
                          decoration: healthInputDecoration('Description',
                              icon: Icons.restaurant_menu_outlined,
                              hint: 'Poulet grillé 150 g, Riz 100 g, Salade 80 g'),
                        ),
                      ],
                    ),
                  ),
                  HealthCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Valeurs nutritionnelles (estimées)',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: HealthColors.ink)),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _macros['calories'],
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: healthInputDecoration('Calories',
                              icon: Icons.local_fire_department_outlined,
                              suffix: 'kcal'),
                          validator: (t) => _validateNumber(t, 10000),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(builder: (context, constraints) {
                          final width = (constraints.maxWidth - 12) / 2;
                          Widget field(String key, String label, double max) =>
                              SizedBox(
                                width: width,
                                child: TextFormField(
                                  controller: _macros[key],
                                  keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true),
                                  decoration:
                                      healthInputDecoration(label, suffix: 'g'),
                                  validator: (t) => _validateNumber(t, max),
                                ),
                              );
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              field('protein', 'Protéines', 1000),
                              field('carbohydrates', 'Glucides', 1000),
                              field('fat', 'Lipides', 1000),
                              field('fiber', 'Fibres', 500),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  HealthCard(
                    child: TextFormField(
                      controller: _comment,
                      maxLines: 2,
                      maxLength: 1000,
                      decoration: healthInputDecoration('Commentaire (optionnel)',
                          icon: Icons.notes_outlined,
                          hint: 'Ressenti, contexte, restaurant…'),
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
                        : const Icon(Icons.check),
                    label: const Text('Enregistrer le repas'),
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

/// Recherche dans la base d'aliments puis saisie de la quantité.
class _FoodPicker extends StatefulWidget {
  const _FoodPicker({required this.foods});

  final List<Map<String, dynamic>> foods;

  @override
  State<_FoodPicker> createState() => _FoodPickerState();
}

class _FoodPickerState extends State<_FoodPicker> {
  final _search = TextEditingController();
  final _quantity = TextEditingController(text: '100');
  Map<String, dynamic>? _selected;

  @override
  void dispose() {
    _search.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final results = widget.foods
        .where((f) => f['name'].toString().toLowerCase().contains(query) ||
            f['category'].toString().toLowerCase().contains(query))
        .toList();
    final height = MediaQuery.of(context).size.height * .75;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: height,
        child: HealthBody(
          maxWidth: 640,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _selected == null ? _list(results) : _quantityStep(),
          ),
        ),
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> results) => Column(
        children: [
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: healthInputDecoration('Rechercher un aliment',
                icon: Icons.search, hint: 'Poulet, riz, pomme…'),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: results.isEmpty
                ? const Center(child: Text('Aucun aliment trouvé'))
                : ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final food = results[i];
                      return ListTile(
                        title: Text(food['name'].toString()),
                        subtitle: Text(
                            '${food['category']} · ${formatNumber(asDouble(food['calories']), decimals: 0)} kcal / 100 ${food['unit']}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() => _selected = food),
                      );
                    },
                  ),
          ),
        ],
      );

  Widget _quantityStep() {
    final food = _selected!;
    final quantity = parseUserNumber(_quantity.text) ?? 0;
    double v(String key) => (asDouble(food[key]) ?? 0) * quantity / 100;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _selected = null),
            ),
            Expanded(
              child: Text(food['name'].toString(),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: HealthColors.ink)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _quantity,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: healthInputDecoration('Quantité',
              icon: Icons.scale_outlined, suffix: food['unit'].toString()),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final q in const [50, 80, 100, 150, 200, 250])
              ActionChip(
                label: Text('$q ${food['unit']}'),
                onPressed: () => setState(() => _quantity.text = '$q'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        HealthCard(
          color: HealthColors.background,
          child: Text(
            '${formatNumber(v('calories'), decimals: 0)} kcal · '
            'Protéines ${formatNumber(v('protein'))} g · '
            'Glucides ${formatNumber(v('carbohydrates'))} g · '
            'Lipides ${formatNumber(v('fat'))} g · '
            'Fibres ${formatNumber(v('fiber'))} g',
            style: const TextStyle(color: HealthColors.ink),
          ),
        ),
        const Spacer(),
        FilledButton.icon(
          style: healthFilledButtonStyle(),
          onPressed: quantity <= 0 || quantity > 5000
              ? null
              : () => Navigator.pop(context, _FoodLine(food, quantity)),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter au repas'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
