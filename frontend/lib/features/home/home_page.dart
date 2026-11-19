import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../appointments/appointments_page.dart';
import '../auth/authentication_state.dart';
import '../health/health_page.dart';
import '../medications/medications_page.dart';
import 'doctor_dashboard_page.dart';
import '../notifications/pages/notifications_page.dart';
import '../notifications/widgets/notification_badge.dart';
import '../documents/pages/documents_page.dart';

const _deepTeal = Color(0xFF07575E);
const _brightTeal = Color(0xFF0C7778);
const _ink = Color(0xFF17464D);
const _muted = Color(0xFF557278);

/// Menu principal patient : même design que les modules (sarcelle profond,
/// bandeau illustré, cartes blanches arrondies) avec le logo MediCare.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authenticationStateProvider).valueOrNull;
    if (user?.role == 'DOCTOR') {
      return DoctorDashboardPage(user: user!);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F7F6),
      appBar: AppBar(
        backgroundColor: _deepTeal,
        foregroundColor: Colors.white,
        titleSpacing: 12,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Image.asset('assets/images/medicare_logo_mark.png',
                  semanticLabel: 'Logo MediCare'),
            ),
            const SizedBox(width: 10),
            const Text('MediCare',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ],
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
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _HomeHero(name: user?.fullName),
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(
                        'Mes services',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ),
                    _ModuleCard(
                      icon: Icons.calendar_month_rounded,
                      color: _brightTeal,
                      badgeColor: const Color(0xFFF0B66A),
                      title: 'Rendez-vous',
                      description:
                          'Planifiez et suivez vos consultations médicales.',
                      page: const AppointmentsPage(),
                    ),
                    _ModuleCard(
                      icon: Icons.medication_rounded,
                      color: const Color(0xFF078B8D),
                      badgeColor: const Color(0xFF65D3CA),
                      title: 'Médicaments',
                      description:
                          'Traitements, rappels de prise, stock et ordonnances.',
                      page: const MedicationsPage(),
                    ),
                    _ModuleCard(
                      icon: Icons.monitor_heart_rounded,
                      color: const Color(0xFF398A67),
                      badgeColor: const Color(0xFF2B8FD6),
                      title: 'Suivi santé et nutrition',
                      description:
                          'Mesures, repas, hydratation, statistiques et analyses IA.',
                      page: const HealthPage(),
                    ),
                    _ModuleCard(
                      icon: Icons.notifications_active_outlined,
                      color: _brightTeal,
                      badgeColor: const Color(0xFFF0B66A),
                      title: 'Notifications et rappels',
                      description: 'Vos informations et rappels de suivi.',
                      page: const NotificationsPage(),
                    ),
                    _ModuleCard(
                      icon: Icons.folder_shared_outlined,
                      color: const Color(0xFF398A67),
                      badgeColor: const Color(0xFF65D3CA),
                      title: 'Documents médicaux',
                      description: 'Consultez et partagez vos documents médicaux.',
                      page: const DocumentsPage(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_deepTeal, _brightTeal],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -60,
            bottom: -110,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 26,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
            child: LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth > 560;
              final logo = Container(
                width: wide ? 170 : 130,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/medicare_logo.png',
                  semanticLabel: 'MediCare - Protect Your Health',
                ),
              );
              final text = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ESPACE PATIENT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name == null || name!.isEmpty
                        ? 'Bienvenue dans MediCare'
                        : 'Bonjour $name',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Votre santé, bien accompagnée au quotidien.',
                    style: TextStyle(
                      color: Color(0xFFC6E8E6),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
              );
              return wide
                  ? Row(
                      children: [
                        Expanded(child: text),
                        const SizedBox(width: 20),
                        logo,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        logo,
                        const SizedBox(height: 18),
                        text,
                      ],
                    );
            }),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.icon,
    required this.color,
    required this.badgeColor,
    required this.title,
    required this.description,
    required this.page,
  });

  final IconData icon;
  final Color color;
  final Color badgeColor;
  final String title;
  final String description;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(icon, color: color, size: 32),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(color: _muted, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_forward_rounded, color: color, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
