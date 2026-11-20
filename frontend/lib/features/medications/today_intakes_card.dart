import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'medication.dart';
import 'medication_notifications.dart';

/// Patient : liste des prises du jour, horaire par horaire. Le patient coche « Pris »
/// ou indique « Non pris » ; le médecin qui le suit voit ces réponses dans
/// l'observance (dossier patient). Rechargée quand [refreshKey] change.
class TodayIntakesCard extends ConsumerStatefulWidget {
  const TodayIntakesCard({super.key, this.refreshKey = 0});

  final int refreshKey;

  @override
  ConsumerState<TodayIntakesCard> createState() => _TodayIntakesCardState();
}

class _TodayIntakesCardState extends ConsumerState<TodayIntakesCard> {
  List<MedicationReminder> _intakes = const [];
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TodayIntakesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await ref.read(apiClientProvider).dio.get('/medications/today');
      if (!mounted) return;
      setState(() {
        _intakes = medicationRemindersFromJson(response.data);
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les prises du jour.';
      });
    }
  }

  /// action : 'taken' (pris), 'missed' (non pris) ou 'pending' (annuler la réponse).
  Future<void> _answer(MedicationReminder intake, String action) async {
    setState(() => _busy.add(intake.id));
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .post('/medications/reminders/${intake.id}/$action');
      // Le rappel local reporté est annulé en arrière-plan : il ne doit jamais
      // retarder ni bloquer la confirmation de la prise.
      unawaited(MedicationNotifications.instance
          .cancelSnooze(intake.medicationId, intake.id)
          .catchError((Object _) {}));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (action) {
          'taken' => '${intake.medicationName} (${_hour(intake)}) : prise enregistrée.',
          'missed' => '${intake.medicationName} (${_hour(intake)}) : prise non faite enregistrée.',
          _ => 'Réponse annulée.',
        }),
      ));
      await _load();
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Impossible d’enregistrer cette prise.'),
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(intake.id));
    }
  }

  static String _hour(MedicationReminder r) =>
      r.time.length >= 5 ? r.time.substring(0, 5) : r.time;

  @override
  Widget build(BuildContext context) {
    final answered = _intakes.where((i) => i.status == 'taken').length;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_rounded, color: Color(0xFF078B8D)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Mes prises d’aujourd’hui',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF17464D))),
                ),
                if (!_loading && _intakes.isNotEmpty)
                  Text('$answered / ${_intakes.length} prises',
                      style: const TextStyle(color: Color(0xFF557278))),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Cochez chaque prise faite. Votre médecin suit vos réponses.',
              style: TextStyle(fontSize: 13, color: Color(0xFF557278)),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Row(children: [
                Expanded(child: Text(_error!)),
                TextButton(onPressed: _load, child: const Text('Réessayer')),
              ])
            else if (_intakes.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Aucune prise prévue aujourd’hui.'),
              )
            else
              for (final intake in _intakes) _intakeRow(intake),
          ],
        ),
      ),
    );
  }

  Widget _intakeRow(MedicationReminder intake) {
    final busy = _busy.contains(intake.id);
    final taken = intake.status == 'taken';
    final missed = intake.status == 'missed';
    final takenAt = intake.takenAt;
    final subtitle = taken
        ? 'Pris${takenAt == null ? '' : ' à ${takenAt.hour.toString().padLeft(2, '0')}:${takenAt.minute.toString().padLeft(2, '0')}'}'
        : missed
            ? 'Non pris'
            : intake.status == 'skipped'
                ? 'Ignorée'
                : 'À prendre à ${_hour(intake)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: taken
            ? const Color(0xFFE8F5E9)
            : missed
                ? const Color(0xFFFDECEA)
                : const Color(0xFFF4F7F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          busy
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : Checkbox(
                  value: taken,
                  activeColor: const Color(0xFF2E7D32),
                  onChanged: (value) =>
                      _answer(intake, value == true ? 'taken' : 'pending'),
                ),
          Text(_hour(intake),
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: Color(0xFF17464D))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(intake.medicationName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: taken
                            ? const Color(0xFF2E7D32)
                            : missed
                                ? const Color(0xFFB3261E)
                                : const Color(0xFF557278))),
              ],
            ),
          ),
          if (!taken)
            TextButton(
              onPressed: busy || missed ? null : () => _answer(intake, 'missed'),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB3261E)),
              child: const Text('Non pris'),
            ),
        ],
      ),
    );
  }
}
