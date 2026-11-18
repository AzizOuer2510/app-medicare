import 'package:flutter/material.dart';

import 'medication.dart';

class MedicationCard extends StatelessWidget {
  final Medication medication;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onHistory;
  final VoidCallback onSchedule;
  final VoidCallback onStock;
  final bool readOnly;

  const MedicationCard({
    super.key,
    required this.medication,
    required this.onEdit,
    required this.onDelete,
    required this.onHistory,
    required this.onSchedule,
    required this.onStock,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final times = medication.reminderTimes.isEmpty
        ? 'Aucun horaire'
        : medication.reminderTimes.map(_shortTime).join('   ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.medication_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        medication.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if ((medication.dosage ?? '').isNotEmpty)
                        Text(medication.dosage!),
                    ],
                  ),
                ),
                if (!readOnly)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                      if (value == 'history') onHistory();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Modifier')),
                      PopupMenuItem(
                          value: 'history', child: Text('Historique')),
                      PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if ((medication.frequency ?? '').isNotEmpty)
              Text('Fréquence : ${medication.frequency}'),
            Text('État : ${_status(medication.status)}'),
            if (medication.reminderTimes.isNotEmpty)
              Text('Prochaine prise : ${_nextDose()}'),
            if (medication.stockTracked && medication.currentQuantity != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      medication.isLowStock
                          ? Icons.warning_amber_rounded
                          : Icons.inventory_2_outlined,
                      size: 18,
                      color: medication.isLowStock
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Stock : ${medication.currentQuantity} ${medication.quantityUnit ?? ''}'
                        '${medication.isLowStock ? ' — Stock faible' : ''}',
                        style: medication.isLowStock
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.error)
                            : null,
                      ),
                    ),
                    if (!readOnly)
                      TextButton(
                        onPressed: onStock,
                        child: const Text('Gérer'),
                      ),
                  ],
                ),
              ),
            if (medication.stockTracked && _estimatedDaysRemaining != null)
              Padding(
                padding: const EdgeInsets.only(left: 30, bottom: 4),
                child: Text('Environ $_estimatedDaysRemaining jours restants'),
              ),
            if (medication.startDate != null || medication.endDate != null)
              Text(
                'Période : ${_date(medication.startDate)} → ${_date(medication.endDate)}',
              ),
            if ((medication.instructions ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Instructions : ${medication.instructions}'),
              ),
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.access_time, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(times)),
                TextButton.icon(
                  onPressed: onSchedule,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(readOnly ? 'Agenda' : 'Prises'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortTime(String value) =>
      value.length >= 5 ? value.substring(0, 5) : value;

  String _date(DateTime? value) => value == null
      ? '...'
      : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _status(String status) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = medication.startDate;
    final end = medication.endDate;
    return switch (status.toLowerCase()) {
      'suspended' || 'paused' || 'pause' => 'En pause',
      'discontinued' => 'Arrêté',
      'completed' || 'finished' => 'Terminé',
      'inactive' => 'Inactif',
      _
          when start != null &&
              DateTime(start.year, start.month, start.day).isAfter(today) =>
        'À venir',
      _
          when end != null &&
              DateTime(end.year, end.month, end.day).isBefore(today) =>
        'Terminé',
      _ => 'En cours',
    };
  }

  String _nextDose() {
    if (!medication.remindersEnabled ||
        medication.status.toLowerCase() != 'active') {
      return 'Aucune prise active';
    }
    final now = DateTime.now();
    final weekdays = medication.weekdays.toSet();
    for (var offset = 0; offset < 8; offset++) {
      final date = DateTime(now.year, now.month, now.day + offset);
      if (weekdays.isNotEmpty && !weekdays.contains(date.weekday)) continue;
      if (medication.startDate != null &&
          date.isBefore(DateTime(
            medication.startDate!.year,
            medication.startDate!.month,
            medication.startDate!.day,
          ))) {
        continue;
      }
      if (medication.endDate != null &&
          date.isAfter(DateTime(
            medication.endDate!.year,
            medication.endDate!.month,
            medication.endDate!.day,
          ))) {
        continue;
      }
      final doses = medication.reminderTimes.map((value) {
        final parts = value.split(':');
        return DateTime(
          date.year,
          date.month,
          date.day,
          int.tryParse(parts.first) ?? 0,
          parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
        );
      }).toList()
        ..sort();
      for (final dose in doses) {
        if (dose.isAfter(now)) {
          final time =
              '${dose.hour.toString().padLeft(2, '0')}:${dose.minute.toString().padLeft(2, '0')}';
          return offset == 0
              ? time
              : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} $time';
        }
      }
    }
    return 'Aucune prise à venir';
  }

  int? get _estimatedDaysRemaining {
    final quantity = medication.currentQuantity;
    final dosesPerDay =
        medication.frequencyPerDay ?? medication.reminderTimes.length;
    if (quantity == null || dosesPerDay <= 0) return null;
    final daysPerWeek =
        medication.weekdays.isEmpty ? 7 : medication.weekdays.length;
    final weeklyUse =
        (medication.unitsPerDose ?? 1) * dosesPerDay * daysPerWeek;
    if (weeklyUse <= 0) return null;
    final remaining = (quantity / (weeklyUse / 7)).floor();
    final endDate = medication.endDate;
    final depletionDate = DateTime.now().add(Duration(days: remaining));
    if (endDate != null &&
        DateTime(depletionDate.year, depletionDate.month, depletionDate.day)
            .isAfter(DateTime(endDate.year, endDate.month, endDate.day))) {
      return null;
    }
    return remaining;
  }
}
