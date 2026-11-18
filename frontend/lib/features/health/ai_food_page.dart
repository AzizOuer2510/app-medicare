import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import 'health_api.dart';
import 'health_theme.dart';

/// Option IA : photo (ou description) du repas → aliments détectés →
/// estimation nutritionnelle → confirmation / correction → journal alimentaire.
/// Renvoie `true` si un repas a été enregistré.
class AiFoodPage extends ConsumerStatefulWidget {
  const AiFoodPage({super.key});

  @override
  ConsumerState<AiFoodPage> createState() => _AiFoodPageState();
}

class _FoodControllers {
  _FoodControllers(Map<String, dynamic> food)
      : name = TextEditingController(text: food['name']?.toString() ?? ''),
        quantity = TextEditingController(text: food['quantity']?.toString() ?? ''),
        calories = _num(food['calories']),
        protein = _num(food['protein']),
        carbs = _num(food['carbs']),
        fat = _num(food['fat']);

  static TextEditingController _num(dynamic v) => TextEditingController(
      text: NumberFormat('0.#', 'fr_FR').format(asDouble(v) ?? 0));

  final TextEditingController name, quantity, calories, protein, carbs, fat;

  List<TextEditingController> get all => [name, quantity, calories, protein, carbs, fat];

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}

class _AiFoodPageState extends ConsumerState<AiFoodPage> {
  final _description = TextEditingController();
  final List<_FoodControllers> _foods = [];
  Uint8List? _image;
  String _imageType = 'image/jpeg';
  bool _analyzing = false;
  bool _analyzed = false;
  bool _demo = false;
  bool _saving = false;
  String _summary = '';
  String? _error;
  String _mealType = 'LUNCH';

  static const _suggestions = [
    'Poulet grillé avec riz et salade',
    'Couscous aux légumes et merguez',
    'Omelette aux légumes et pain complet',
    'Salade César avec croûtons',
    'Pâtes bolognaise',
    'Yaourt avec fruits et granola',
  ];

  @override
  void dispose() {
    _description.dispose();
    for (final f in _foods) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _canUseCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _image = bytes;
        _imageType = file.mimeType ?? 'image/jpeg';
        _analyzed = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        showHealthSnack(context, 'Impossible d’ouvrir la photo.', error: true);
      }
    }
  }

  Future<void> _analyze() async {
    final description = _description.text.trim();
    if (_image == null && description.isEmpty) {
      showHealthSnack(context, 'Ajoutez une photo ou décrivez votre repas.',
          error: true);
      return;
    }
    setState(() {
      _analyzing = true;
      _analyzed = false;
      _error = null;
    });
    try {
      final response = await aiDio(ref).post(
            '/nutrition/ai/analyze',
            data: _image != null
                ? {'image': base64Encode(_image!), 'mediaType': _imageType}
                : {'description': description},
          );
      final data = asMap(response.data);
      for (final f in _foods) {
        f.dispose();
      }
      _foods
        ..clear()
        ..addAll(asMapList(data['foods']).map(_FoodControllers.new));
      if (!mounted) return;
      setState(() {
        _summary = data['description']?.toString() ?? '';
        _demo = data['demo_mode'] == true;
        _analyzing = false;
        _analyzed = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _error = healthErrorMessage(error, fallback: 'L’analyse a échoué.');
      });
    }
  }

  double _total(TextEditingController Function(_FoodControllers) field) =>
      _foods.fold(0, (s, f) => s + (parseUserNumber(field(f).text) ?? 0));

  Future<void> _save() async {
    if (_foods.isEmpty) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    try {
      await ref.read(apiClientProvider).dio.post('/meals', data: {
        'mealType': _mealType,
        'mealDate': apiDate(now),
        'mealTime': apiTime(TimeOfDay.fromDateTime(now)),
        'description': _foods
            .where((f) => f.name.text.trim().isNotEmpty)
            .map((f) => '${f.name.text.trim()} ${f.quantity.text.trim()}'.trim())
            .join(', '),
        'comment': 'Estimation par analyse IA',
        'calories': _total((f) => f.calories),
        'protein': _total((f) => f.protein),
        'carbohydrates': _total((f) => f.carbs),
        'fat': _total((f) => f.fat),
      });
      notifyHealthDataChanged(ref);
      if (!mounted) return;
      showHealthSnack(context, 'Repas enregistré dans votre journal.');
      Navigator.pop(context, true);
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
      appBar: healthAppBar('Reconnaissance des aliments'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          HealthBody(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HealthCard(
                  child: Row(
                    children: [
                      HealthIconBadge(Icons.auto_awesome, HealthColors.brightTeal,
                          size: 48),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Analyse IA de votre repas',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: HealthColors.ink)),
                            Text(
                              'Photographiez votre assiette ou décrivez-la : l’IA identifie les aliments et estime les valeurs nutritionnelles. Vous pouvez tout corriger avant l’enregistrement.',
                              style: TextStyle(color: HealthColors.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                HealthCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('1. Photo du repas',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: HealthColors.ink)),
                      const SizedBox(height: 10),
                      if (_image != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(_image!,
                              height: 200, fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                _analyzing ? null : () => _pick(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(_image == null ? 'Choisir une photo' : 'Changer'),
                          ),
                          if (_canUseCamera)
                            OutlinedButton.icon(
                              onPressed:
                                  _analyzing ? null : () => _pick(ImageSource.camera),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Prendre une photo'),
                            ),
                          if (_image != null)
                            TextButton.icon(
                              onPressed: _analyzing
                                  ? null
                                  : () => setState(() {
                                        _image = null;
                                        _analyzed = false;
                                      }),
                              icon: const Icon(Icons.close),
                              label: const Text('Retirer la photo'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _image == null
                            ? '… ou décrivez votre repas'
                            : 'Description (ignorée tant qu’une photo est sélectionnée)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: HealthColors.ink),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _description,
                        enabled: _image == null,
                        maxLines: 3,
                        minLines: 2,
                        decoration: healthInputDecoration('Votre repas',
                            icon: Icons.restaurant_menu_outlined,
                            hint: 'Poulet grillé avec riz blanc et salade verte…'),
                      ),
                      if (_image == null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in _suggestions)
                              ActionChip(
                                label: Text(s, style: const TextStyle(fontSize: 12)),
                                onPressed: () =>
                                    setState(() => _description.text = s),
                                backgroundColor:
                                    HealthColors.brightTeal.withValues(alpha: .08),
                                side: BorderSide.none,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: healthFilledButtonStyle(),
                        onPressed: _analyzing ? null : _analyze,
                        icon: _analyzing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.psychology_outlined),
                        label: Text(_analyzing
                            ? 'Analyse en cours…'
                            : _image != null
                                ? 'Analyser la photo'
                                : 'Analyser la description'),
                      ),
                      if (_analyzing)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            _image != null
                                ? 'Analyse visuelle : 30 à 90 secondes au premier chargement du modèle.'
                                : 'Estimation nutritionnelle : 15 à 30 secondes.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: HealthColors.muted),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(_error!,
                              style: const TextStyle(color: Color(0xFFB3261E))),
                        ),
                    ],
                  ),
                ),
                if (_analyzed) ..._results(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _results() {
    final calories = _total((f) => f.calories);
    return [
      HealthCard(
        color: _demo ? const Color(0xFFFFF6E5) : Colors.white,
        child: Row(
          children: [
            Icon(_demo ? Icons.science_outlined : Icons.auto_awesome,
                color: _demo ? HealthColors.temperature : HealthColors.brightTeal),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_demo)
                    const Text('Mode démonstration',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: HealthColors.temperature)),
                  Text(_summary,
                      style: const TextStyle(
                          color: HealthColors.ink, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          ],
        ),
      ),
      HealthCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('2. Estimation nutritionnelle',
                style: TextStyle(fontWeight: FontWeight.w700, color: HealthColors.ink)),
            const SizedBox(height: 12),
            Row(
              children: [
                _total2(formatNumber(calories, decimals: 0), 'kcal', HealthColors.calories),
                _total2('${formatNumber(_total((f) => f.protein))} g', 'Protéines',
                    HealthColors.protein),
                _total2('${formatNumber(_total((f) => f.carbs))} g', 'Glucides',
                    HealthColors.carbs),
                _total2('${formatNumber(_total((f) => f.fat))} g', 'Lipides',
                    HealthColors.fat),
              ],
            ),
          ],
        ),
      ),
      HealthSectionTitle('3. Aliments détectés — vérifiez et corrigez',
          icon: Icons.edit_note,
          trailing: IconButton(
            tooltip: 'Ajouter un aliment',
            icon: const Icon(Icons.add_circle_outline, color: HealthColors.brightTeal),
            onPressed: () => setState(() => _foods.add(_FoodControllers(const {}))),
          )),
      if (_foods.isEmpty)
        const HealthEmptyState(
          icon: Icons.no_food_outlined,
          title: 'Aucun aliment détecté',
          message: 'Ajoutez les aliments manuellement avec le bouton +.',
        ),
      for (var i = 0; i < _foods.length; i++) _foodCard(i),
      HealthCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('4. Enregistrer dans le journal',
                style: TextStyle(fontWeight: FontWeight.w700, color: HealthColors.ink)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in mealTypeLabels.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _mealType == entry.key,
                    showCheckmark: false,
                    selectedColor: HealthColors.brightTeal,
                    labelStyle: TextStyle(
                        color: _mealType == entry.key
                            ? Colors.white
                            : HealthColors.ink),
                    onSelected: (_) => setState(() => _mealType = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: healthFilledButtonStyle(HealthColors.success),
              onPressed: _saving || _foods.isEmpty ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: const Text('Confirmer et enregistrer le repas'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Estimation indicative : les quantités et la composition réelles peuvent différer.',
              style: TextStyle(fontSize: 12, color: HealthColors.muted),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _total2(String value, String label, Color color) => Expanded(
        child: Column(
          children: [
            FittedBox(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            ),
            Text(label,
                style: const TextStyle(fontSize: 11, color: HealthColors.muted)),
          ],
        ),
      );

  Widget _foodCard(int index) {
    final food = _foods[index];
    Widget numField(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: healthInputDecoration(label).copyWith(isDense: true),
          ),
        );
    return HealthCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 14),
      child: Column(
        children: [
          Row(
            children: [
              Text('Aliment ${index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: HealthColors.ink)),
              const Spacer(),
              IconButton(
                tooltip: 'Retirer',
                icon: const Icon(Icons.delete_outline),
                color: const Color(0xFFB3261E),
                onPressed: () => setState(() => _foods.removeAt(index).dispose()),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: food.name,
                        decoration:
                            healthInputDecoration('Nom').copyWith(isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: food.quantity,
                        decoration:
                            healthInputDecoration('Quantité').copyWith(isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    numField(food.calories, 'kcal'),
                    const SizedBox(width: 6),
                    numField(food.protein, 'Prot. g'),
                    const SizedBox(width: 6),
                    numField(food.carbs, 'Gluc. g'),
                    const SizedBox(width: 6),
                    numField(food.fat, 'Lip. g'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
