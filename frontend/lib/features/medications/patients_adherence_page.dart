import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../home/patient_file_page.dart';

/// Choix d'un patient suivi (médecin), par exemple avant d'ajouter un médicament à son planning.
/// Renvoie {'id': int, 'name': String} ou null.
Future<Map<String, dynamic>?> pickFollowedPatient(
    BuildContext context, WidgetRef ref,
    {String title = 'Pour quel patient ?'}) async {
  List<Map<String, dynamic>> patients;
  try {
    final response = await ref.read(apiClientProvider).dio.get('/health/patients');
    patients = (response.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } on DioException {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de charger vos patients.')));
    }
    return null;
  }
  if (!context.mounted) return null;
  if (patients.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Aucun patient suivi : un patient doit avoir un rendez-vous '
            'avec vous ou vous ajouter dans « Mes médecins ».')));
    return null;
  }
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(title),
      children: [
        for (final p in patients)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext,
                {'id': (p['id'] as num).toInt(), 'name': p['fullName']?.toString() ?? ''}),
            child: Row(children: [
              const Icon(Icons.person_outline, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(p['fullName']?.toString() ?? '')),
            ]),
          ),
      ],
    ),
  );
}

/// Observance des traitements de chaque patient suivi : prises effectuées, oubliées,
/// non renseignées et taux d'observance. Chaque patient ouvre son dossier (onglet Médicaments).
class PatientsAdherencePage extends ConsumerStatefulWidget {
  const PatientsAdherencePage({super.key});

  @override
  ConsumerState<PatientsAdherencePage> createState() => _PatientsAdherencePageState();
}

class _PatientsAdherencePageState extends ConsumerState<PatientsAdherencePage> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  String? _error;
  int _days = 7;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .get('/medications/adherence/patients', queryParameters: {'days': _days});
      if (!mounted) return;
      setState(() {
        _rows = (response.data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger l’observance des patients.';
      });
    }
  }

  Color _rateColor(num? rate) {
    if (rate == null) return Colors.grey;
    if (rate >= 80) return const Color(0xFF2E7D32);
    if (rate >= 50) return const Color(0xFFC18A3A);
    return const Color(0xFFB3261E);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Observance des patients')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 jours')),
                ButtonSegment(value: 30, label: Text('30 jours')),
              ],
              selected: {_days},
              onSelectionChanged: (v) {
                setState(() => _days = v.first);
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Column(children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Réessayer')),
              ])
            else if (_rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucun patient suivi.', textAlign: TextAlign.center),
              )
            else
              for (final row in _rows) _patientCard(row),
          ],
        ),
      ),
    );
  }

  Widget _patientCard(Map<String, dynamic> row) {
    final rate = row['adherencePercent'] as num?;
    final eligible = (row['eligibleDoses'] as num?)?.toInt() ?? 0;
    final active = (row['activeMedications'] as num?)?.toInt() ?? 0;
    final color = _rateColor(rate);
    final lastMissed = DateTime.tryParse(row['lastMissed']?.toString() ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => PatientFilePage(
              patientId: (row['patientId'] as num).toInt(),
              patientName: row['patientName']?.toString() ?? '',
              initialTab: 1,
            ),
          ),
        ).then((_) => _load()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Text(rate == null ? '—' : '${rate.round()} %',
                    style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row['patientName']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 4),
                    if (active == 0)
                      const Text('Aucun traitement en cours')
                    else if (eligible == 0)
                      Text('$active traitement(s) · aucune prise prévue sur la période')
                    else
                      Wrap(spacing: 10, children: [
                        Text('✔ ${row['taken']} prises', style: const TextStyle(color: Color(0xFF2E7D32))),
                        Text('✖ ${row['missed']} oubliées', style: const TextStyle(color: Color(0xFFB3261E))),
                        if (((row['pending'] as num?) ?? 0) > 0)
                          Text('? ${row['pending']} non renseignées',
                              style: const TextStyle(color: Colors.grey)),
                      ]),
                    if (lastMissed != null)
                      Text('Dernier oubli : ${lastMissed.day.toString().padLeft(2, '0')}/'
                          '${lastMissed.month.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
