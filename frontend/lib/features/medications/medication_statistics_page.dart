import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import 'medication.dart';

class MedicationStatisticsPage extends ConsumerStatefulWidget {
  const MedicationStatisticsPage({
    super.key,
    this.patientId,
    this.patientName,
  });

  final int? patientId;
  final String? patientName;

  @override
  ConsumerState<MedicationStatisticsPage> createState() =>
      _MedicationStatisticsPageState();
}

class _MedicationStatisticsPageState
    extends ConsumerState<MedicationStatisticsPage> {
  String _period = 'week';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _statistics = {};
  List<MedicationReminder> _today = [];
  List<Map<String, dynamic>> _days = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  num? _number(Iterable<String> keys) {
    for (final key in keys) {
      final value = _statistics[key];
      if (value is num) return value;
      if (value != null && num.tryParse(value.toString()) != null) {
        return num.parse(value.toString());
      }
    }
    return null;
  }

  num _asNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final results = await Future.wait([
        dio.get('/medications/statistics', queryParameters: {
          if (widget.patientId != null) 'patientId': widget.patientId,
          'period': switch (_period) {
            'day' => 'DAILY',
            'month' => 'MONTHLY',
            _ => 'WEEKLY',
          },
        }),
        dio.get('/medications/today', queryParameters: {
          if (widget.patientId != null) 'patientId': widget.patientId,
        }),
      ]);
      final stats = results[0].data;
      final today = results[1].data;
      if (!mounted) return;
      setState(() {
        _statistics = stats is Map<String, dynamic>
            ? (stats['statistics'] is Map<String, dynamic>
                ? stats['statistics'] as Map<String, dynamic>
                : stats)
            : {};
        final records = today is List
            ? today
            : today is Map<String, dynamic>
                ? today['items'] ?? today['intakes'] ?? today['data'] ?? []
                : [];
        _today = records is List
            ? records
                .whereType<Map<String, dynamic>>()
                .map(MedicationReminder.fromJson)
                .toList()
            : [];
        final daily = _statistics['days'] ?? _statistics['daily'];
        _days = daily is List
            ? daily.whereType<Map<String, dynamic>>().toList()
            : [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les statistiques de prise.';
      });
    }
  }

  String _text(Iterable<String> names, {String fallback = '—'}) {
    for (final name in names) {
      final value = _statistics[name];
      if (value != null) return value.toString();
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final taken = _number(['taken', 'takenCount', 'completedCount']) ?? 0;
    final missed = _number(['missed', 'missedCount', 'overdueCount']) ?? 0;
    final planned = _number([
          'eligibleDoses',
          'scheduled',
          'scheduledCount',
          'total',
        ]) ??
        (taken + missed);
    final rate = _number([
          'adherencePercent',
          'adherenceRate',
          'adherence',
          'percentage',
        ]) ??
        (planned == 0 ? 0 : taken * 100 / planned);
    final rateText = rate;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patientName == null
            ? 'Observance du traitement'
            : 'Observance · ${widget.patientName}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    const SizedBox(height: 12),
                    FilledButton(
                        onPressed: _load, child: const Text('Réessayer')),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _period,
                        decoration: const InputDecoration(labelText: 'Période'),
                        items: const [
                          DropdownMenuItem(
                              value: 'day', child: Text('Aujourd’hui')),
                          DropdownMenuItem(
                              value: 'week', child: Text('Cette semaine')),
                          DropdownMenuItem(
                              value: 'month', child: Text('Ce mois-ci')),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _period = value);
                          _load();
                        },
                      ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Observance',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 12),
                              Semantics(
                                label:
                                    'Taux d’observance ${rateText.toStringAsFixed(0)} pour cent',
                                child: LinearProgressIndicator(
                                  value:
                                      (rateText / 100).clamp(0, 1).toDouble(),
                                  minHeight: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text('${rateText.toStringAsFixed(0)} %'),
                              const SizedBox(height: 16),
                              Wrap(spacing: 20, runSpacing: 8, children: [
                                _Metric(
                                    label: 'Prises effectuées',
                                    value: taken.toString()),
                                _Metric(
                                    label: 'Manquées',
                                    value: missed.toString()),
                                _Metric(
                                    label: 'Prévues',
                                    value: planned.toString()),
                                _Metric(
                                    label: 'Ignorées',
                                    value: (_number([
                                              'skipped',
                                              'skippedCount',
                                            ]) ??
                                            0)
                                        .toString()),
                                _Metric(
                                    label: 'Reportées',
                                    value:
                                        (_number(['snoozed']) ?? 0).toString()),
                              ]),
                            ],
                          ),
                        ),
                      ),
                      Text('Historique quotidien',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (_days.isEmpty)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.bar_chart_outlined),
                            title: Text(
                                'Aucune prise éligible sur cette période.'),
                          ),
                        )
                      else
                        Card(
                          child: SizedBox(
                            height: 154,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.all(12),
                              itemCount: _days.length,
                              itemBuilder: (context, index) {
                                final day = _days[index];
                                final eligible = _asNum(day['eligibleDoses']);
                                final completed = _asNum(day['taken']);
                                final ratio = eligible == 0
                                    ? 0.0
                                    : (completed / eligible)
                                        .clamp(0.0, 1.0)
                                        .toDouble();
                                final date = DateTime.tryParse(
                                  day['date']?.toString() ?? '',
                                );
                                final label = date == null
                                    ? ''
                                    : DateFormat('dd/MM').format(date);
                                return Semantics(
                                  label:
                                      '$label : ${completed.toInt()} prises sur ${eligible.toInt()}',
                                  child: Tooltip(
                                    message:
                                        '${completed.toInt()} / ${eligible.toInt()} prises',
                                    child: SizedBox(
                                      width: 42,
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.bottomCenter,
                                              child: Container(
                                                height: 92 * ratio + 3,
                                                width: 20,
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(label,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      for (final metric in const [
                        (['skipped', 'skippedCount'], 'Ignorées'),
                        (['streak', 'currentStreak'], 'Série actuelle'),
                      ])
                        if (_number(metric.$1) != null)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.insights_outlined),
                              title: Text(metric.$2),
                              trailing: Text(_text(metric.$1)),
                            ),
                          ),
                      const SizedBox(height: 16),
                      Text('Résumé du jour',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      if (_today.isEmpty)
                        const Card(
                            child: ListTile(
                          leading: Icon(Icons.event_available_outlined),
                          title: Text('Aucune prise planifiée aujourd’hui.'),
                        ))
                      else
                        ..._today.map((intake) => Card(
                              child: ListTile(
                                leading: Icon(
                                  intake.status == 'taken'
                                      ? Icons.check_circle_outline
                                      : intake.status == 'missed'
                                          ? Icons.error_outline
                                          : Icons.schedule,
                                ),
                                title: Text(intake.medicationName.isEmpty
                                    ? 'Médicament'
                                    : intake.medicationName),
                                subtitle: Text(DateFormat('HH:mm').format(
                                  DateTime.tryParse(
                                          '2000-01-01 ${intake.time}') ??
                                      DateTime(2000),
                                )),
                                trailing: Text(_status(intake.status)),
                              ),
                            )),
                      if (_statistics.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                              'Les agrégats détaillés seront affichés lorsque le serveur les fournira.'),
                        ),
                    ],
                  ),
                ),
    );
  }

  String _status(String status) => switch (status) {
        'taken' => 'Effectuée',
        'missed' => 'Manquée',
        'skipped' => 'Ignorée',
        'snoozed' => 'Reportée',
        _ => 'En attente',
      };
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 125,
        child: Semantics(
          label: '$label : $value',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              Text(label),
            ],
          ),
        ),
      );
}
