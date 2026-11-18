import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'health_api.dart';
import 'health_theme.dart';

/// Analyse IA des mesures des 30 derniers jours : état général, alertes
/// automatiques, analyse détaillée, tendances et recommandations.
class HealthAiPage extends ConsumerStatefulWidget {
  const HealthAiPage({super.key});

  @override
  ConsumerState<HealthAiPage> createState() => _HealthAiPageState();
}

class _HealthAiPageState extends ConsumerState<HealthAiPage> {
  bool _loading = true;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await aiDio(ref)
          .get('/health/ai/analyze', queryParameters: patientQuery(context));
      if (!mounted) return;
      setState(() {
        _result = asMap(response.data);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = healthErrorMessage(error, fallback: 'L’analyse a échoué.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HealthColors.background,
      appBar: healthAppBar(
          HealthScope.patientOf(context) == null
              ? 'Analyse santé IA'
              : 'Analyse IA · ${HealthScope.patientOf(context)!.name}',
          actions: [
        IconButton(
          tooltip: 'Relancer l’analyse',
          onPressed: _loading ? null : _analyze,
          icon: const Icon(Icons.refresh),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: _analyze,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            HealthBody(
              maxWidth: 720,
              child: _loading
                  ? const HealthCard(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: HealthColors.brightTeal),
                          SizedBox(height: 18),
                          Text('Analyse IA en cours…',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: HealthColors.ink)),
                          SizedBox(height: 6),
                          Text(
                            'Examen de vos mesures des 30 derniers jours. Le premier lancement du modèle peut prendre une minute.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: HealthColors.muted),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? HealthErrorState(message: _error!, onRetry: _analyze)
                      : _content(_result ?? {}),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'alerte' => HealthColors.heart,
        'attention' => HealthColors.temperature,
        _ => HealthColors.success,
      };

  IconData _statusIcon(String status) => switch (status) {
        'alerte' => Icons.warning_amber_rounded,
        'attention' => Icons.info_outline_rounded,
        _ => Icons.check_circle_outline_rounded,
      };

  Color _severityColor(String value) => switch (value) {
        'red' || 'high' => HealthColors.heart,
        'orange' || 'medium' => HealthColors.temperature,
        _ => HealthColors.pressure,
      };

  Widget _content(Map<String, dynamic> result) {
    final status = result['status']?.toString() ?? 'bon';
    final color = _statusColor(status);
    final instant = asMapList(result['instantAlerts']);
    final aiAlerts = asMapList(result['alerts']);
    final conditions = (result['possibleConditions'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final recommendations = (result['recommendations'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final count = (asDouble(result['recordCount']) ?? 0).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HealthCard(
          borderColor: color.withValues(alpha: .5),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(_statusIcon(status), size: 56, color: color),
              const SizedBox(height: 10),
              Text('État général : ${capitalize(status)}',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 8),
              Text(result['summary']?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: HealthColors.ink, height: 1.4)),
              const SizedBox(height: 8),
              Text('Basé sur $count ${count > 1 ? 'mesures' : 'mesure'} (30 derniers jours)',
                  style: const TextStyle(fontSize: 12, color: HealthColors.muted)),
            ],
          ),
        ),
        if (result['demo_mode'] == true)
          const HealthCard(
            color: Color(0xFFFFF6E5),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: HealthColors.temperature),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Service IA (Ollama) indisponible : seules les alertes automatiques sont calculées. Lancez « ollama serve » puis relancez l’analyse.',
                    style: TextStyle(color: HealthColors.ink),
                  ),
                ),
              ],
            ),
          ),
        if (result['urgency'] == 'urgent')
          const HealthCard(
            color: Color(0xFFFDECEE),
            borderColor: HealthColors.heart,
            child: Row(
              children: [
                Icon(Icons.emergency_outlined, color: HealthColors.heart),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Consultez rapidement un médecin.',
                      style: TextStyle(
                          color: HealthColors.heart, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        if (instant.isNotEmpty) ...[
          const HealthSectionTitle('Alertes détectées',
              icon: Icons.notification_important_outlined),
          for (final alert in instant) _alertCard(alert),
        ],
        if (aiAlerts.isNotEmpty) ...[
          const HealthSectionTitle('Analyse détaillée', icon: Icons.manage_search),
          for (final alert in aiAlerts) _alertCard(alert),
        ],
        if (conditions.isNotEmpty) ...[
          const HealthSectionTitle('Tendances à surveiller',
              icon: Icons.medical_information_outlined),
          HealthCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in conditions)
                  Chip(
                    label: Text(c),
                    backgroundColor: HealthColors.glycemia.withValues(alpha: .08),
                    side: BorderSide.none,
                  ),
              ],
            ),
          ),
        ],
        if (recommendations.isNotEmpty) ...[
          const HealthSectionTitle('Recommandations', icon: Icons.lightbulb_outline),
          HealthCard(
            child: Column(
              children: [
                for (var i = 0; i < recommendations.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: HealthColors.brightTeal,
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(recommendations[i],
                              style: const TextStyle(color: HealthColors.ink)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const Padding(
          padding: EdgeInsets.all(4),
          child: Text(
            'Cette analyse est indicative et ne remplace pas l’avis d’un professionnel de santé.',
            style: TextStyle(
                fontSize: 12, color: HealthColors.muted, fontStyle: FontStyle.italic),
          ),
        ),
      ],
    );
  }

  Widget _alertCard(Map<String, dynamic> alert) {
    final color = _severityColor(
        (alert['color'] ?? alert['severity'] ?? 'low').toString());
    return HealthCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 52,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(alert['metric']?.toString() ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: HealthColors.ink)),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(alert['value']?.toString() ?? '',
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(alert['message']?.toString() ?? '',
                    style: const TextStyle(color: HealthColors.ink)),
                if (alert['normal'] != null)
                  Text('Valeurs usuelles : ${alert['normal']}',
                      style: const TextStyle(
                          fontSize: 12, color: HealthColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
