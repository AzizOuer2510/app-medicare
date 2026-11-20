import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../home/patient_file_page.dart';
import 'health_api.dart';
import 'health_page.dart';
import 'health_theme.dart';

/// Espace médecin : patients suivis (traitement, rendez-vous ou « Mes médecins ») avec
/// leurs dernières constantes et les alertes, puis accès à leur suivi complet.
class DoctorHealthPatientsPage extends ConsumerStatefulWidget {
  const DoctorHealthPatientsPage({super.key});

  @override
  ConsumerState<DoctorHealthPatientsPage> createState() =>
      _DoctorHealthPatientsPageState();
}

class _DoctorHealthPatientsPageState
    extends ConsumerState<DoctorHealthPatientsPage> {
  List<Map<String, dynamic>> _patients = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final response = await ref.read(apiClientProvider).dio.get('/health/patients');
      if (!mounted) return;
      setState(() {
        _patients = asMapList(response.data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = healthErrorMessage(error,
            fallback: 'Impossible de charger vos patients.');
      });
    }
  }

  void _open(Map<String, dynamic> patient) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HealthPage(
          patient: HealthPatient(
            id: (patient['id'] as num).toInt(),
            name: patient['fullName']?.toString() ?? '',
          ),
        ),
      ),
    ).then((_) => _load());
  }

  /// Dossier patient : observance et médicaments (onglet 1) ou documents (onglet 2).
  void _openFile(Map<String, dynamic> patient, int tab) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientFilePage(
          patientId: (patient['id'] as num).toInt(),
          patientName: patient['fullName']?.toString() ?? '',
          summary: patient,
          initialTab: tab,
        ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final items = _patients
        .where((p) => (p['fullName'] ?? '').toString().toLowerCase().contains(query))
        .toList();
    final withAlerts =
        _patients.where((p) => (asDouble(p['alertCount']) ?? 0) > 0).length;

    return Scaffold(
      backgroundColor: HealthColors.background,
      appBar: healthAppBar('Suivi santé des patients', actions: [
        IconButton(
            tooltip: 'Actualiser',
            onPressed: _load,
            icon: const Icon(Icons.refresh)),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const HealthHero(
              label: 'ESPACE MÉDECIN',
              title: 'Vos patients,\nsuivis au quotidien.',
              subtitle:
                  'Constantes, nutrition et hydratation de vos patients en un coup d’œil.',
              icon: Icons.medical_services_rounded,
              badgeIcon: Icons.monitor_heart_rounded,
              height: 240,
            ),
            HealthBody(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: HealthSummaryTile(
                            label: 'Patients suivis',
                            value: _loading ? '—' : '${_patients.length}',
                            icon: Icons.people_outline,
                            color: HealthColors.brightTeal,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: HealthSummaryTile(
                            label: 'Avec alerte (30 j)',
                            value: _loading ? '—' : '$withAlerts',
                            icon: Icons.notification_important_outlined,
                            color: HealthColors.heart,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: healthInputDecoration('Rechercher un patient',
                          icon: Icons.search),
                    ),
                    const SizedBox(height: 4),
                    const HealthSectionTitle('Mes patients', icon: Icons.people_alt_outlined),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                            child: CircularProgressIndicator(
                                color: HealthColors.brightTeal)),
                      )
                    else if (_error != null)
                      HealthErrorState(message: _error!, onRetry: _load)
                    else if (items.isEmpty)
                      const HealthEmptyState(
                        icon: Icons.person_search_outlined,
                        title: 'Aucun patient suivi',
                        message:
                            'Un patient apparaît ici dès que vous lui prescrivez un traitement (Médicaments) ou qu’il prend rendez-vous avec vous (Rendez-vous).',
                      )
                    else
                      for (final patient in items)
                        _PatientCard(
                            patient: patient,
                            onTap: () => _open(patient),
                            onAdherence: () => _openFile(patient, 1),
                            onDocuments: () => _openFile(patient, 2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({
    required this.patient,
    required this.onTap,
    required this.onAdherence,
    required this.onDocuments,
  });

  final Map<String, dynamic> patient;
  final VoidCallback onTap, onAdherence, onDocuments;

  @override
  Widget build(BuildContext context) {
    final name = patient['fullName']?.toString() ?? '';
    final sources = (patient['sources'] as List? ?? const []).map((e) => e.toString());
    final alerts = (patient['alerts'] as List? ?? const []).map((e) => e.toString()).toList();
    final last = parseApiDateTime(patient['lastMeasureAt']);
    final values = <String>[
      if (patient['lastWeight'] != null) '${formatNumber(asDouble(patient['lastWeight']))} kg',
      if (patient['lastPressure'] != null) '${patient['lastPressure']} mmHg',
      if (patient['lastHeartRate'] != null) '${patient['lastHeartRate']} bpm',
      if (patient['lastGlycemia'] != null)
        '${formatNumber(asDouble(patient['lastGlycemia']), decimals: 2)} g/L',
    ];

    return HealthCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: HealthColors.brightTeal.withValues(alpha: .12),
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(
                      color: HealthColors.brightTeal, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: HealthColors.ink)),
                    Text(
                      last == null
                          ? 'Aucune mesure enregistrée'
                          : 'Dernière mesure : ${DateFormat('d MMM yyyy', 'fr_FR').format(last)}',
                      style: const TextStyle(fontSize: 12, color: HealthColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: HealthColors.brightTeal),
            ],
          ),
          if (values.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(values.join('  ·  '),
                style: const TextStyle(color: HealthColors.ink, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final source in sources)
                _chip(
                  switch (source) {
                    'MEDICATIONS' => 'Traitement prescrit',
                    'CARE_LINK' => 'Mes médecins',
                    _ => 'Rendez-vous',
                  },
                  switch (source) {
                    'MEDICATIONS' => Icons.medication_outlined,
                    'CARE_LINK' => Icons.link,
                    _ => Icons.calendar_month_outlined,
                  },
                  HealthColors.brightTeal,
                ),
              for (final alert in alerts)
                _chip(alert, Icons.warning_amber_rounded, HealthColors.heart),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onAdherence,
                icon: const Icon(Icons.medication_outlined, size: 18),
                label: const Text('Observance et médicaments'),
              ),
              TextButton.icon(
                onPressed: onDocuments,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Documents'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, IconData icon, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
