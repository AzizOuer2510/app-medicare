import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../auth/auth_user.dart';
import '../auth/authentication_state.dart';
import '../health/doctor_health_patients_page.dart';
import 'followed_patients_page.dart';
import '../medications/medication.dart';
import '../medications/prescriptions_page.dart';
import '../medications/prescription_upload_page.dart';

class DoctorDashboardPage extends ConsumerStatefulWidget {
  const DoctorDashboardPage({required this.user, super.key});

  final AuthUser user;

  @override
  ConsumerState<DoctorDashboardPage> createState() =>
      _DoctorDashboardPageState();
}

class _DoctorDashboardPageState extends ConsumerState<DoctorDashboardPage> {
  List<Prescription> _prescriptions = const [];
  List<FollowedPatient> _patients = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        ref.read(apiClientProvider).dio.get('/prescriptions'),
        ref.read(apiClientProvider).dio.get('/prescriptions/patients/followed'),
      ]);
      if (!mounted) return;
      setState(() {
        _prescriptions = (responses[0].data as List<dynamic>)
            .map((item) => Prescription.fromJson(item as Map<String, dynamic>))
            .toList();
        _patients = (responses[1].data as List<dynamic>)
            .map((item) =>
                FollowedPatient.fromJson(item as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les données du tableau de bord.';
      });
    }
  }

  Future<void> _uploadPrescription() async {
    final uploaded = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PrescriptionUploadPage()),
    );
    if (uploaded == true && mounted) await _loadDashboardData();
  }

  Future<void> _browsePrescriptions() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrescriptionsPage()),
    );
    if (mounted) await _loadDashboardData();
  }

  Future<void> _browseFollowedPatients() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FollowedPatientsPage()),
    );
    if (mounted) await _loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/doctor_dashboard_background.png'),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Color.fromARGB(100, 255, 255, 255),
            BlendMode.srcOver,
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Image.asset(
            'assets/images/medicare_logo_transparent.png',
            width: 156,
            height: 42,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            semanticLabel: 'MediCare',
          ),
          actions: [
            IconButton(
              tooltip: 'Profil',
              onPressed: () => Navigator.pushNamed(context, '/profile'),
              icon: const Icon(Icons.account_circle_outlined),
            ),
            IconButton(
              tooltip: 'Déconnexion',
              onPressed: () async {
                await ref.read(authenticationStateProvider.notifier).logout();
                if (context.mounted) {
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/login', (_) => false);
                }
              },
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadDashboardData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Bonjour Dr. ${widget.user.fullName}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Au cœur du suivi de vos patients',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.upload_file_outlined),
                  ),
                  title: const Text('Déposer une ordonnance'),
                  subtitle: const Text(
                    'Choisissez un patient par son nom complet et ajoutez son ordonnance.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _uploadPrescription,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.document_scanner_outlined),
                  ),
                  title: const Text('Préremplir un planning existant'),
                  subtitle: const Text(
                    'Analysez une ordonnance déjà déposée pour proposer les médicaments.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _browsePrescriptions,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.monitor_heart_outlined),
                  ),
                  title: const Text('Suivi santé et nutrition des patients'),
                  subtitle: const Text(
                    'Constantes, repas, hydratation, alertes et mesures de consultation.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DoctorHealthPatientsPage()),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatisticCard(
                      label: 'Patients suivis',
                      value: _loading ? '—' : '${_patients.length}',
                      icon: Icons.people_outline,
                      onTap: _browseFollowedPatients,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatisticCard(
                      label: 'Prescriptions',
                      value: _loading ? '—' : '${_prescriptions.length}',
                      icon: Icons.description_outlined,
                      onTap: _browsePrescriptions,
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    title: Text(_error!),
                    trailing: TextButton(
                      onPressed: _loadDashboardData,
                      child: const Text('Réessayer'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatisticCard extends StatelessWidget {
  const _StatisticCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
