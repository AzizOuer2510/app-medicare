import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'health_api.dart';
import 'health_dashboard_tab.dart';
import 'health_goals_page.dart';
import 'health_pdf_export.dart';
import 'health_stats_page.dart';
import 'health_theme.dart';
import 'measures_tab.dart';
import 'nutrition_tab.dart';

/// Module 4 — Suivi santé et nutrition.
/// Parcours : Tableau de bord → Mesures → Nutrition (journal + hydratation) → Analyse.
/// Avec [patient] : vue du médecin sur le suivi d'un patient qu'il suit.
class HealthPage extends ConsumerStatefulWidget {
  const HealthPage({super.key, this.initialTab = 0, this.patient});

  final int initialTab;
  final HealthPatient? patient;

  @override
  ConsumerState<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends ConsumerState<HealthPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 2),
  );
  bool _exporting = false;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await showHealthPdfExportDialog(context, ref, patient: widget.patient);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HealthScope(
      patient: widget.patient,
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final patient = widget.patient;
    return Scaffold(
      backgroundColor: HealthColors.background,
      appBar: healthAppBar(
        patient == null ? 'Suivi santé et nutrition' : 'Suivi de ${patient.name}',
        actions: [
          IconButton(
            tooltip: patient == null ? 'Mes objectifs' : 'Objectifs du patient',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () => pushHealthPage(context, const HealthGoalsPage()),
          ),
          IconButton(
            tooltip: 'Statistiques et évolution',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => pushHealthPage(context, const HealthStatsPage()),
          ),
          IconButton(
            tooltip: 'Exporter en PDF',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: HealthColors.accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Tableau de bord'),
            Tab(icon: Icon(Icons.monitor_heart_outlined), text: 'Mesures'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Nutrition'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          HealthDashboardTab(onOpenTab: (index) => _tabs.animateTo(index)),
          const MeasuresTab(),
          const NutritionTab(),
        ],
      ),
    );
  }
}
