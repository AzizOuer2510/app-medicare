import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import 'medication.dart';
import 'medication_notifications.dart';

class MedicationHistoryPage extends ConsumerStatefulWidget {
  final Medication medication;
  final bool readOnly;

  const MedicationHistoryPage({
    super.key,
    required this.medication,
    this.readOnly = false,
  });

  @override
  ConsumerState<MedicationHistoryPage> createState() =>
      _MedicationHistoryPageState();
}

class _MedicationHistoryPageState extends ConsumerState<MedicationHistoryPage> {
  List<MedicationReminder> items = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .get('/medications/${widget.medication.id}/history');
      if (!mounted) return;
      setState(() {
        items = medicationRemindersFromJson(response.data);
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Impossible de charger l’historique des prises.';
      });
    }
  }

  Future<void> _action(MedicationReminder reminder, String action) async {
    var minutes = 15;
    if (action == 'snooze') {
      final picked = await showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Reporter la prise'),
          children: [
            for (final duration in const [5, 10, 15, 30, 60])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, duration),
                child: Text('$duration minutes'),
              ),
          ],
        ),
      );
      if (picked == null) return;
      minutes = picked;
    }
    try {
      final response = await ref.read(apiClientProvider).dio.post(
            action == 'snooze'
                ? '/medications/reminders/${reminder.id}/snooze'
                : '/medications/reminders/${reminder.id}/$action',
            data: action == 'snooze' ? {'minutes': minutes} : null,
          );
      if (action == 'snooze' && response.data is Map<String, dynamic>) {
        final until =
            DateTime.tryParse(response.data['snoozedUntil']?.toString() ?? '');
        if (until != null) {
          await MedicationNotifications.instance.scheduleSnooze(
            medicationId: widget.medication.id,
            reminderId: reminder.id,
            name: widget.medication.name,
            instructions: widget.medication.instructions,
            snoozedUntil: until,
          );
        }
      } else {
        await MedicationNotifications.instance
            .cancelSnooze(widget.medication.id, reminder.id);
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de modifier cette prise.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historique des prises')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : items.isEmpty
                  ? const Center(child: Text('Aucun historique disponible.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        itemBuilder: (_, index) {
                          final reminder = items[index];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                children: [
                                  ListTile(
                                    leading: Icon(
                                      reminder.status == 'taken'
                                          ? Icons.check_circle
                                          : reminder.status == 'missed'
                                              ? Icons.error_outline
                                              : reminder.status == 'skipped'
                                                  ? Icons
                                                      .do_not_disturb_on_outlined
                                                  : Icons.schedule,
                                      color: reminder.status == 'taken'
                                          ? Colors.green
                                          : reminder.status == 'missed'
                                              ? Colors.red
                                              : Colors.orange,
                                    ),
                                    title: Text(DateFormat('dd/MM/yyyy')
                                        .format(reminder.date)),
                                    subtitle: Text(
                                      '${reminder.time.length >= 5 ? reminder.time.substring(0, 5) : reminder.time} • ${_status(reminder)}',
                                    ),
                                  ),
                                  if (!widget.readOnly)
                                    Wrap(
                                      spacing: 4,
                                      children: [
                                        _actionButton(
                                            reminder, 'taken', 'Effectuée'),
                                        _actionButton(
                                            reminder, 'missed', 'Manquée'),
                                        _actionButton(
                                            reminder, 'skipped', 'Ignorer'),
                                        _actionButton(
                                            reminder, 'snooze', 'Reporter'),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _actionButton(
          MedicationReminder reminder, String action, String label) =>
      TextButton(
        onPressed: () => _action(reminder, action),
        child: Text(label),
      );

  String _status(MedicationReminder reminder) {
    final status = reminder.status;
    if (status == 'pending') {
      final parts = reminder.time.split(':');
      final scheduled = DateTime(
        reminder.date.year,
        reminder.date.month,
        reminder.date.day,
        int.tryParse(parts.first) ?? 0,
        parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      );
      if (scheduled.isBefore(DateTime.now())) {
        return 'À confirmer — horaire dépassé';
      }
    }
    return switch (status) {
      'taken' => 'Effectuée',
      'missed' => 'Manquée',
      'skipped' => 'Ignorée',
      'snoozed' => 'Reportée',
      _ => 'En attente',
    };
  }
}
