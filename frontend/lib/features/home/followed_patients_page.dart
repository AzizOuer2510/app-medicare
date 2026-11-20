import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'patient_file_page.dart';

class FollowedPatient {
  const FollowedPatient({required this.id, required this.fullName, this.summary});

  final int id;
  final String fullName;

  /// Dernières constantes, alertes et origine du lien (traitement, rendez-vous, « Mes médecins »).
  final Map<String, dynamic>? summary;

  factory FollowedPatient.fromJson(Map<String, dynamic> json) {
    return FollowedPatient(
      id: (json['id'] as num).toInt(),
      fullName: json['fullName'] as String? ?? '',
      summary: json,
    );
  }
}

const _sourceLabels = {
  'MEDICATIONS': 'Traitement',
  'APPOINTMENTS': 'Rendez-vous',
  'CARE_LINK': 'Mes médecins',
};

/// Patients suivis par le médecin. La liste est la même dans tous les modules : un patient est
/// suivi s'il a un traitement prescrit par le médecin, un rendez-vous avec lui, ou s'il l'a
/// ajouté dans « Mes médecins ». Chaque patient ouvre son dossier (santé, médicaments, documents).
class FollowedPatientsPage extends ConsumerStatefulWidget {
  const FollowedPatientsPage({super.key});

  @override
  ConsumerState<FollowedPatientsPage> createState() =>
      _FollowedPatientsPageState();
}

class _FollowedPatientsPageState extends ConsumerState<FollowedPatientsPage> {
  List<FollowedPatient> _patients = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await ref.read(apiClientProvider).dio.get('/health/patients');
      if (!mounted) return;
      setState(() {
        _patients = (response.data as List<dynamic>)
            .map((item) => FollowedPatient.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList();
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les patients suivis.';
      });
    }
  }

  void _open(FollowedPatient patient, {int tab = 0}) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PatientFilePage(
          patientId: patient.id,
          patientName: patient.fullName,
          summary: patient.summary,
          initialTab: tab,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patients suivis')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _loadPatients,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : _patients.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aucun patient suivi pour le moment.\n'
                          'Un patient apparaît ici dès qu’il a un traitement prescrit par vous, '
                          'un rendez-vous avec vous, ou qu’il vous ajoute dans « Mes médecins ».',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPatients,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _patients.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final patient = _patients[index];
                          final s = patient.summary ?? const {};
                          final alerts = (s['alertCount'] as num?)?.toInt() ?? 0;
                          final sources = ((s['sources'] as List?) ?? const [])
                              .map((e) => _sourceLabels[e] ?? e.toString())
                              .join(' · ');
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: alerts > 0
                                  ? const Color(0xFFFDE8E7)
                                  : null,
                              child: Icon(
                                alerts > 0
                                    ? Icons.warning_amber_rounded
                                    : Icons.person_outline,
                                color: alerts > 0
                                    ? const Color(0xFFB3261E)
                                    : null,
                              ),
                            ),
                            title: Text(patient.fullName),
                            subtitle: Text([
                              if (sources.isNotEmpty) 'Suivi : $sources',
                              if (alerts > 0) '$alerts alerte(s) santé',
                            ].join('\n')),
                            isThreeLine: sources.isNotEmpty && alerts > 0,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Médicaments pris et oubliés',
                                  onPressed: () => _open(patient, tab: 1),
                                  icon: const Icon(Icons.medication_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Documents et ordonnances',
                                  onPressed: () => _open(patient, tab: 2),
                                  icon: const Icon(Icons.folder_open_outlined),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: () => _open(patient),
                          );
                        },
                      ),
                    ),
    );
  }
}
