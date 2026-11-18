import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'medication.dart';

class MedicationStockPage extends ConsumerStatefulWidget {
  const MedicationStockPage({super.key, required this.medication});
  final Medication medication;

  @override
  ConsumerState<MedicationStockPage> createState() =>
      _MedicationStockPageState();
}

class _MedicationStockPageState extends ConsumerState<MedicationStockPage> {
  final _quantity = TextEditingController();
  final _unit = TextEditingController();
  final _threshold = TextEditingController();
  final _package = TextEditingController();
  final _note = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quantity.text = widget.medication.currentQuantity?.toString() ?? '';
    _unit.text = widget.medication.quantityUnit ?? 'unités';
    _threshold.text = widget.medication.lowStockThreshold?.toString() ?? '';
    _package.text = widget.medication.packageQuantity?.toString() ?? '';
    _load();
  }

  num? _num(TextEditingController c) => num.tryParse(c.text.trim());

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref.read(apiClientProvider).dio.get(
            '/medications/${widget.medication.id}/stock',
          );
      final payload = response.data;
      if (payload is Map<String, dynamic>) {
        final stock = payload['stock'] is Map<String, dynamic>
            ? payload['stock'] as Map<String, dynamic>
            : payload;
        _quantity.text = (stock['currentQuantity'] ??
                stock['quantity'] ??
                _quantity.text)
            .toString();
        _unit.text = (stock['quantityUnit'] ?? stock['unit'] ?? _unit.text)
            .toString();
        _threshold.text =
            (stock['lowStockThreshold'] ?? _threshold.text).toString();
        _package.text = (stock['packageQuantity'] ?? _package.text).toString();
      }
    } catch (_) {
      _error = 'Stock non disponible. Vous pouvez tout de même le mettre à jour.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_num(_quantity) == null || _num(_quantity)! < 0) {
      _message('Saisissez une quantité valide.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).dio.put(
        '/medications/${widget.medication.id}/stock',
        data: {
          'quantity': _num(_quantity),
          'unit': _unit.text.trim(),
          'lowStockThreshold': _num(_threshold),
          'packageQuantity': _num(_package),
        },
      );
      if (mounted) _message('Stock mis à jour.');
    } catch (_) {
      _message('Impossible de mettre à jour le stock.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refill() async {
    final quantity = _num(_package);
    if (quantity == null || quantity <= 0) {
      _message('Saisissez d’abord la quantité par boîte dans les paramètres de stock.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(apiClientProvider).dio.post(
        '/medications/${widget.medication.id}/stock/refill',
        data: {'quantity': quantity, 'note': _note.text.trim()},
      );
      _note.clear();
      await _load();
      if (mounted) _message('Réapprovisionnement enregistré.');
    } catch (_) {
      _message('Impossible d’enregistrer le réapprovisionnement.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  @override
  void dispose() {
    _quantity.dispose();
    _unit.dispose();
    _threshold.dispose();
    _package.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Stock — ${widget.medication.name}')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  TextFormField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: 'Quantité actuelle (${_unit.text})'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _unit,
                    decoration: const InputDecoration(labelText: 'Unité de stock'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _threshold,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Seuil de stock faible'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _package,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantité par boîte'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Enregistrer la quantité'),
                  ),
                  const Divider(height: 36),
                  Text('Ajouter un réapprovisionnement', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _note,
                    decoration: const InputDecoration(labelText: 'Note (facultative)'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _refill,
                    icon: const Icon(Icons.add_shopping_cart),
                    label: const Text('Ajouter une boîte au stock'),
                  ),
                ],
              ),
      );
}
