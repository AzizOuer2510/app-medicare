import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../health/health_api.dart';
import '../health/health_page.dart';
import '../medications/medication_statistics_page.dart';
import '../medications/prescriptions_page.dart';

class FollowedPatient {
  const FollowedPatient({required this.id, required this.fullName});

  final int id;
  final String fullName;

  factory FollowedPatient.fromJson(Map<String, dynamic> json) {
    return FollowedPatient(
      id: (json['id'] as num).toInt(),
      fullName: json['fullName'] as String? ?? '',
    );
  }
}

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
      final response = await ref
          .read(apiClientProvider)
          .dio
          .get('/prescriptions/patients/followed');
      if (!mounted) return;
      setState(() {
        _patients = (response.data as List<dynamic>)
            .map((item) =>
                FollowedPatient.fromJson(item as Map<String, dynamic>))
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

  Future<void> _openPatientPrescriptions(FollowedPatient patient) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PrescriptionsPage(
          patientId: patient.id,
          patientName: patient.fullName,
        ),
      ),
    );
  }

  Future<void> _openPatientAdherence(FollowedPatient patient) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationStatisticsPage(
          patientId: patient.id,
          patientName: patient.fullName,
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
                          'Aucun patient suivi pour le moment.',
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
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            ),
                            title: Text(patient.fullName),
                            subtitle: const Text(
                                'Consulter ses prescriptions et son observance'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Suivi santé et nutrition',
                                  onPressed: () => Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => HealthPage(
                                        patient: HealthPatient(
                                          id: patient.id,
                                          name: patient.fullName,
                                        ),
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.monitor_heart_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Observance du traitement',
                                  onPressed: () =>
                                      _openPatientAdherence(patient),
                                  icon: const Icon(Icons.insights_outlined),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: () => _openPatientPrescriptions(patient),
                          );
                        },
                      ),
                    ),
    );
  }
}
