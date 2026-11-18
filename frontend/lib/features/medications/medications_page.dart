import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../auth/authentication_state.dart';
import '../home/doctor_dashboard_page.dart';
import 'medication.dart';
import 'medication_assistant_page.dart';
import 'medication_card.dart';
import 'medication_form_page.dart';
import 'medication_history_page.dart';
import 'medication_notifications.dart';
import 'medication_statistics_page.dart';
import 'medication_stock_page.dart';
import 'prescriptions_page.dart';

class MedicationsPage extends ConsumerStatefulWidget {
  const MedicationsPage({super.key});

  @override
  ConsumerState<MedicationsPage> createState() => _MedicationsPageState();
}

class _MedicationsPageState extends ConsumerState<MedicationsPage> {
  List<Medication> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    if (ref.read(authenticationStateProvider).valueOrNull?.role != 'DOCTOR') {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => loading = true);
    try {
      final response =
          await ref.read(apiClientProvider).dio.get('/medications');
      if (!mounted) return;
      final loaded = _asList(response.data)
          .map(
            (value) => Medication.fromJson(value),
          )
          .toList();
      setState(() {
        items = loaded;
        loading = false;
      });
      for (final medication in loaded) {
        unawaited(_syncNotifications(medication));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de charger les médicaments.')),
      );
    }
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final value = data['items'] ?? data['medications'] ?? data['data'];
      if (value is List) {
        return value.whereType<Map<String, dynamic>>().toList();
      }
    }
    return [];
  }

  Future<void> _syncNotifications(Medication medication) async {
    try {
      if (!medication.remindersEnabled ||
          medication.status.toLowerCase() != 'active' ||
          medication.reminderTimes.isEmpty) {
        await MedicationNotifications.instance.cancel(medication.id);
        return;
      }
      final times = medication.reminderTimes.map((value) {
        final parts = value.split(':');
        return TimeOfDay(
          hour: int.tryParse(parts.first) ?? 8,
          minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
        );
      }).toList();
      await MedicationNotifications.instance.schedule(
        id: medication.id,
        name: medication.name,
        instructions: medication.instructions,
        times: times,
        weekdays: medication.weekdays.isEmpty
            ? {1, 2, 3, 4, 5, 6, 7}
            : medication.weekdays.toSet(),
        startDate: medication.startDate,
        endDate: medication.endDate,
      );
    } catch (_) {
      // Medication loading remains available if local notifications are blocked.
    }
  }

  Future<void> _add() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const MedicationFormPage()),
    );
    if (changed == true) await _load();
  }

  Future<void> _edit(Medication medication) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationFormPage(medication: medication),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(Medication medication) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer le médicament ?'),
        content: Text('Voulez-vous supprimer ${medication.name} ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .delete('/medications/${medication.id}');
      try {
        await MedicationNotifications.instance.cancel(medication.id);
      } catch (_) {
        // A notification plugin failure must not mask a successful API delete.
      }
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suppression impossible.')),
      );
    }
  }

  void _openHistory(Medication medication) {
    final readOnly =
        ref.read(authenticationStateProvider).valueOrNull?.role == 'USER';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationHistoryPage(
          medication: medication,
          readOnly: readOnly,
        ),
      ),
    );
  }

  Future<void> _openSchedule(
    Medication medication, {
    required bool readOnly,
  }) async {
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .get('/medications/${medication.id}/schedule');
      final reminders = medicationRemindersFromJson(response.data);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Text(
                medication.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (reminders.isEmpty)
                const Text('Aucune prise prévue aujourd’hui.'),
              ...reminders.map((reminder) => Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          reminder.status == 'taken'
                              ? Icons.check_circle
                              : reminder.status == 'missed'
                                  ? Icons.error_outline
                                  : Icons.schedule,
                          color: reminder.status == 'taken'
                              ? Colors.green
                              : reminder.status == 'missed'
                                  ? Colors.red
                                  : Colors.orange,
                        ),
                        title: Text(reminder.time.length >= 5
                            ? reminder.time.substring(0, 5)
                            : reminder.time),
                        subtitle: Text(_reminderStatus(reminder)),
                      ),
                      if (!readOnly)
                        Wrap(
                          spacing: 6,
                          children: [
                            _intakeAction(sheetContext, medication, reminder,
                                'taken', 'Effectuée'),
                            _intakeAction(sheetContext, medication, reminder,
                                'missed', 'Manquée'),
                            _intakeAction(sheetContext, medication, reminder,
                                'skipped', 'Ignorer'),
                            _intakeAction(sheetContext, medication, reminder,
                                'snooze', 'Reporter'),
                          ],
                        ),
                    ],
                  )),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de charger les prises.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authenticationStateProvider).valueOrNull;
    final patientReadOnly = user?.role == 'USER';
    if (user?.role == 'DOCTOR') {
      return DoctorDashboardPage(user: user!);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF075765),
      appBar: AppBar(
        title: const Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xFFB8F2EF),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
              child: SizedBox(
                width: 27,
                height: 27,
                child: Icon(Icons.add, color: Color(0xFF075765), size: 22),
              ),
            ),
            SizedBox(width: 6),
            Text(
              'MediCare',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: .1,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Observance',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const MedicationStatisticsPage()),
            ),
          ),
          IconButton(
            tooltip: 'Prescriptions',
            icon: const Icon(Icons.description_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PrescriptionsPage(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Assistant traitement',
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () => showMedicationAssistantPanel(context),
          ),
        ],
      ),
      floatingActionButton: patientReadOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _MedicationBackdrop(),
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                const _MedicationHero(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Mes traitements',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!loading)
                        Text(
                          '${items.length} ${items.length == 1 ? 'médicament' : 'médicaments'}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .78),
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  )
                else if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.medication_outlined,
                            size: 48,
                            color: Color(0xFF078B8D),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Aucun médicament pour le moment',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF17464D),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            patientReadOnly
                                ? 'Les médicaments et horaires seront ajoutés par votre médecin.'
                                : 'Ajoutez votre premier traitement pour organiser vos prises.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF557278)),
                          ),
                          if (!patientReadOnly) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _add,
                              icon: const Icon(Icons.add),
                              label: const Text('Ajouter un médicament'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else
                  ...items.map(
                    (medication) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: MedicationCard(
                        medication: medication,
                        onEdit: () => _edit(medication),
                        onDelete: () => _delete(medication),
                        onHistory: () => _openHistory(medication),
                        onSchedule: () => _openSchedule(
                          medication,
                          readOnly: patientReadOnly,
                        ),
                        readOnly: patientReadOnly,
                        onStock: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                MedicationStockPage(medication: medication),
                          ),
                        ).then((_) => _load()),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _intakeAction(
    BuildContext sheetContext,
    Medication medication,
    MedicationReminder reminder,
    String action,
    String label,
  ) =>
      TextButton(
        onPressed: () async {
          var minutes = 15;
          if (action == 'snooze') {
            final picked = await showDialog<int>(
              context: sheetContext,
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
          final endpoint = action == 'snooze'
              ? '/medications/reminders/${reminder.id}/snooze'
              : '/medications/reminders/${reminder.id}/$action';
          try {
            final response = await ref.read(apiClientProvider).dio.post(
                  endpoint,
                  data: action == 'snooze' ? {'minutes': minutes} : null,
                );
            if (action == 'snooze' && response.data is Map<String, dynamic>) {
              final until = DateTime.tryParse(
                  response.data['snoozedUntil']?.toString() ?? '');
              if (until != null) {
                await MedicationNotifications.instance.scheduleSnooze(
                  medicationId: medication.id,
                  reminderId: reminder.id,
                  name: medication.name,
                  instructions: medication.instructions,
                  snoozedUntil: until,
                );
              }
            } else {
              await MedicationNotifications.instance
                  .cancelSnooze(medication.id, reminder.id);
            }
            if (!mounted || !sheetContext.mounted) return;
            Navigator.pop(sheetContext);
            await _openSchedule(medication, readOnly: false);
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Impossible de modifier cette prise.')),
            );
          }
        },
        child: Text(label),
      );

  String _reminderStatus(MedicationReminder reminder) {
    final status = reminder.status;
    if (status == 'pending') {
      final scheduled = DateTime(
        reminder.date.year,
        reminder.date.month,
        reminder.date.day,
        int.tryParse(reminder.time.split(':').first) ?? 0,
        reminder.time.split(':').length > 1
            ? int.tryParse(reminder.time.split(':')[1]) ?? 0
            : 0,
      );
      if (scheduled.isBefore(DateTime.now())) {
        return 'Horaire dépassé — indiquez si la prise a été faite ou manquée';
      }
      return 'À venir';
    }
    return switch (status) {
      'taken' => 'Prise effectuée',
      'missed' => 'Prise manquée',
      'skipped' => 'Prise ignorée',
      'snoozed' => 'Prise reportée',
      _ => 'À confirmer',
    };
  }
}

class _MedicationBackdrop extends StatelessWidget {
  const _MedicationBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF064C59),
                  Color(0xFF087783),
                  Color(0xFF11A7A2),
                ],
              ),
            ),
          ),
          Positioned(
            top: 350,
            left: -150,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .035),
              ),
            ),
          ),
          Positioned(
            right: -180,
            bottom: -240,
            child: Container(
              width: 460,
              height: 460,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .07),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicationHero extends StatelessWidget {
  const _MedicationHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: width < 400 ? 480 : 470,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 20,
                right: 20,
                top: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Text(
                        'GESTION DES MÉDICAMENTS',
                        style: TextStyle(
                          color: Color(0xFFD8FFFF),
                          fontSize: 12,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      width < 400
                          ? 'Vos médicaments,\nbien organisés.\nVotre santé,\nmieux suivie.'
                          : 'Vos médicaments,\nbien organisés.\nVotre santé, mieux suivie.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: width < 400 ? 29 : 34,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Ajoutez, suivez et gérez facilement\nvos traitements au quotidien.',
                      style: TextStyle(
                        color: const Color(0xFFC5E9E9),
                        fontSize: width < 400 ? 15 : 17,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                left: 14,
                right: 14,
                bottom: -4,
                height: 192,
                child: _MedicationIllustration(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MedicationIllustration extends StatelessWidget {
  const _MedicationIllustration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomLeft,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 4,
          bottom: -100,
          child: Container(
            width: 290,
            height: 290,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: .09),
                width: 28,
              ),
            ),
          ),
        ),
        Positioned(
          right: -35,
          bottom: -155,
          child: Container(
            width: 300,
            height: 210,
            decoration: BoxDecoration(
              color: const Color(0xFF42C6BD).withValues(alpha: .26),
              borderRadius: BorderRadius.circular(150),
            ),
          ),
        ),
        Positioned(
          left: 24,
          bottom: 10,
          child: Transform.rotate(
            angle: -.16,
            child: const _MedicineBottle(),
          ),
        ),
        Positioned(
          left: 140,
          bottom: 24,
          child: Transform.rotate(
            angle: .48,
            child: const _PillBlister(),
          ),
        ),
        Positioned(
          left: 70,
          bottom: 0,
          child: Transform.rotate(
            angle: -.52,
            child: const _Capsule(),
          ),
        ),
        Positioned(
          left: 150,
          bottom: 0,
          child: Transform.rotate(
            angle: -.08,
            child: const _Tablet(),
          ),
        ),
      ],
    );
  }
}

class _MedicineBottle extends StatelessWidget {
  const _MedicineBottle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 176,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 82,
              height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFBDF5F2), Color(0xFF55C9C5)],
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(color: Color(0x33002D38), blurRadius: 10),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(
                  6,
                  (_) => Container(
                    width: 2,
                    height: 16,
                    color: Colors.white.withValues(alpha: .3),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 23,
            child: Container(
              width: 104,
              height: 148,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8AE4DF), Color(0xFF1EAAA9)],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: .45)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44002D38),
                    blurRadius: 18,
                    offset: Offset(8, 12),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 68,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF078B91).withValues(alpha: .72),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Color(0xFFB8F7F1),
                    size: 54,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillBlister extends StatelessWidget {
  const _PillBlister();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 118,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD7FFFC), Color(0xFF52C9C4)],
        ),
        borderRadius: BorderRadius.circular(21),
        border:
            Border.all(color: Colors.white.withValues(alpha: .65), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44002D38),
            blurRadius: 16,
            offset: Offset(8, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var row = 0; row < 2; row++)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                2,
                (_) => Container(
                  width: 27,
                  height: 27,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE7FFFD), Color(0xFF8CE0DB)],
                    ),
                    border: Border.all(color: const Color(0xFF6ACCC7)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x227BFFFF), blurRadius: 5),
                    ],
                  ),
                  child: const Icon(
                    Icons.remove,
                    size: 18,
                    color: Color(0xFF67C8C5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 22,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEBFFFE), Color(0xFF8EDFD9)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7BD3CE)),
      ),
      child: const Align(
        alignment: Alignment.centerRight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFF73D0CB),
            borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
          ),
          child: SizedBox(width: 21, height: 20),
        ),
      ),
    );
  }
}

class _Tablet extends StatelessWidget {
  const _Tablet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 28,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE6FFFD), Color(0xFF86DBD6)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF6BCBC6)),
      ),
      child: Center(
        child: Container(width: 1, height: 22, color: const Color(0xFF68C9C4)),
      ),
    );
  }
}
