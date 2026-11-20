import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../auth/auth_user.dart';
import '../auth/authentication_state.dart';
import '../health/doctor_health_patients_page.dart';
import 'followed_patients_page.dart';
import '../medications/medication_form_page.dart';
import '../medications/patients_adherence_page.dart';
import '../medications/prescription_upload_page.dart';
import '../notifications/pages/notifications_page.dart';
import '../notifications/widgets/notification_badge.dart';
import '../documents/pages/documents_page.dart';

class DoctorDashboardPage extends ConsumerStatefulWidget {
  const DoctorDashboardPage({required this.user, super.key});

  final AuthUser user;

  @override
  ConsumerState<DoctorDashboardPage> createState() =>
      _DoctorDashboardPageState();
}

class _DoctorDashboardPageState extends ConsumerState<DoctorDashboardPage> {
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
      // Même liste de patients suivis que dans tous les modules.
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

  /// Ajoute un médicament et ses horaires au planning d'un patient choisi (sans ordonnance à déposer).
  Future<void> _addToPatientPlanning() async {
    final patient = await pickFollowedPatient(context, ref,
        title: 'Planning de quel patient ?');
    if (patient == null || !mounted) return;
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationFormPage(
          patientId: patient['id'] as int,
          patientName: patient['name'] as String,
        ),
      ),
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ajouté au planning de ${patient['name']} : il est prévenu par une notification.')));
      await _loadDashboardData();
    }
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
            const NotificationBadgeButton(),
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
                  title: const Text('Envoyer une ordonnance et préparer le planning'),
                  subtitle: const Text(
                    'L’ordonnance arrive dans les documents du patient ; les médicaments peuvent être extraits pour créer son planning de prises.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _uploadPrescription,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.add_alarm_outlined),
                  ),
                  title: const Text('Ajouter un médicament au planning d’un patient'),
                  subtitle: const Text(
                    'Choisissez le patient, le médicament et ses horaires : ils arrivent dans son planning de prises.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _addToPatientPlanning,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.fact_check_outlined),
                  ),
                  title: const Text('Observance des traitements'),
                  subtitle: const Text(
                    'Prises effectuées et oubliées de chaque patient, avec son taux d’observance.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PatientsAdherencePage()),
                  ),
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
                      label: 'Patients en alerte',
                      value: _loading
                          ? '—'
                          : '${_patients.where((p) => ((p.summary?['alertCount'] as num?) ?? 0) > 0).length}',
                      icon: Icons.warning_amber_rounded,
                      onTap: _browseFollowedPatients,
                    ),
                  ),
                ],
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Notifications et rappels'),
                  subtitle: const Text('Vos notifications et rappels pour vos patients.'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const NotificationsPage(),
                  )),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_shared_outlined),
                  title: const Text('Documents médicaux'),
                  subtitle: const Text('Tous les documents et ordonnances de vos patients, synchronisés avec leur application.'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const DocumentsPage(),
                  )),
                ),
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
