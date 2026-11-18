import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../auth/authentication_state.dart';
import 'health_api.dart';
import 'health_theme.dart';
import 'measure_form.dart';

/// Historique des mesures avec filtres par période et par type.
class MeasuresTab extends ConsumerStatefulWidget {
  const MeasuresTab({super.key});

  @override
  ConsumerState<MeasuresTab> createState() => _MeasuresTabState();
}

class _MeasuresTabState extends ConsumerState<MeasuresTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;
  int _days = 30; // 0 = tout l'historique
  String _type = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = _days == 0
          ? await dio.get('/health-records', queryParameters: patientQuery(context))
          : await dio.get('/health-records/history',
              queryParameters: patientQuery(context, {'days': _days}));
      if (!mounted) return;
      final list = asMapList(response.data);
      list.sort((a, b) => (b['recordedAt']?.toString() ?? '')
          .compareTo(a['recordedAt']?.toString() ?? ''));
      setState(() {
        _records = list;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = healthErrorMessage(error,
            fallback: 'Impossible de charger vos mesures.');
      });
    }
  }

  List<Map<String, dynamic>> get _filtered => _records.where((r) {
        switch (_type) {
          case 'weight':
            return r['weight'] != null;
          case 'heartRate':
            return r['heartRate'] != null;
          case 'pressure':
            return r['systolic'] != null;
          case 'temperature':
            return r['temperature'] != null;
          case 'glycemia':
            return r['glycemia'] != null;
          default:
            return true;
        }
      }).toList();

  Future<void> _edit([Map<String, dynamic>? record]) async {
    final saved = await showMeasureForm(context, ref, record: record);
    if (!saved || !mounted) return;
    showHealthSnack(context,
        record == null ? 'Mesure enregistrée.' : 'Mesure modifiée.');
    notifyHealthDataChanged(ref);
  }

  Future<void> _delete(Map<String, dynamic> record) async {
    if (!await confirmHealthDelete(context, 'cette mesure')) return;
    try {
      await ref.read(apiClientProvider).dio.delete('/health-records/${record['id']}');
      if (!mounted) return;
      showHealthSnack(context, 'Mesure supprimée.');
      notifyHealthDataChanged(ref);
    } catch (error) {
      if (mounted) showHealthSnack(context, healthErrorMessage(error), error: true);
    }
  }

  /// Le patient modifie ses propres saisies ; le médecin ne modifie que les mesures qu'il a saisies.
  bool _canEdit(Map<String, dynamic> record) {
    final me = ref.read(authenticationStateProvider).valueOrNull?.id;
    final author = (record['recordedById'] as num?)?.toInt();
    if (HealthScope.isDoctorView(context)) return author != null && author == me;
    return author == null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen(healthRevisionProvider, (_, __) => _load());
    final items = _filtered;
    final doctorView = HealthScope.isDoctorView(context);

    return Scaffold(
      backgroundColor: HealthColors.background,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-measure',
        onPressed: () => _edit(),
        backgroundColor: HealthColors.brightTeal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(doctorView ? 'Mesure de consultation' : 'Ajouter une mesure'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 96),
          children: [
            HealthBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text('Période',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: HealthColors.muted)),
                  ),
                  HealthChoiceChips<int>(
                    options: const [
                      (7, '7 jours'),
                      (30, '30 jours'),
                      (90, '3 mois'),
                      (180, '6 mois'),
                      (0, 'Tout'),
                    ],
                    selected: _days,
                    onSelected: (value) {
                      setState(() => _days = value);
                      _load();
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: Text('Type de mesure',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: HealthColors.muted)),
                  ),
                  HealthChoiceChips<String>(
                    options: const [
                      ('all', 'Toutes'),
                      ('weight', 'Poids'),
                      ('heartRate', 'Fréquence cardiaque'),
                      ('pressure', 'Tension'),
                      ('temperature', 'Température'),
                      ('glycemia', 'Glycémie'),
                    ],
                    selected: _type,
                    onSelected: (value) => setState(() => _type = value),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: HealthSectionTitle(
                      'Historique des mesures',
                      trailing: Text(
                        '${items.length} ${items.length > 1 ? 'mesures' : 'mesure'}',
                        style: const TextStyle(color: HealthColors.muted),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(40),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: HealthColors.brightTeal)),
                          )
                        : _error != null
                            ? HealthErrorState(message: _error!, onRetry: _load)
                            : items.isEmpty
                                ? HealthEmptyState(
                                    icon: Icons.monitor_heart_outlined,
                                    title: 'Aucune mesure sur cette période',
                                    message:
                                        'Enregistrez votre poids, votre tension, votre fréquence cardiaque, votre température ou votre glycémie.',
                                    action: FilledButton.icon(
                                      style: healthFilledButtonStyle(),
                                      onPressed: () => _edit(),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Ajouter une mesure'),
                                    ),
                                  )
                                : Column(
                                    children: [
                                      for (final record in items)
                                        _RecordCard(
                                          record: record,
                                          canEdit: _canEdit(record),
                                          onEdit: () => _edit(record),
                                          onDelete: () => _delete(record),
                                        ),
                                    ],
                                  ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> record;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = parseApiDateTime(record['recordedAt']);
    final values = <(IconData, String, Color)>[
      if (record['weight'] != null)
        (Icons.monitor_weight_outlined, '${formatNumber(asDouble(record['weight']))} kg',
            HealthColors.weight),
      if (record['heartRate'] != null)
        (Icons.favorite_outline, '${record['heartRate']} bpm', HealthColors.heart),
      if (record['systolic'] != null)
        (Icons.speed_outlined, '${record['systolic']}/${record['diastolic'] ?? '?'} mmHg',
            HealthColors.pressure),
      if (record['temperature'] != null)
        (Icons.thermostat_outlined,
            '${formatNumber(asDouble(record['temperature']))} °C',
            HealthColors.temperature),
      if (record['glycemia'] != null)
        (Icons.bloodtype_outlined,
            '${formatNumber(asDouble(record['glycemia']), decimals: 2)} g/L',
            HealthColors.glycemia),
    ];
    final note = record['note']?.toString();
    final author = record['recordedByName']?.toString();

    return HealthCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_outlined,
                  size: 18, color: HealthColors.brightTeal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  date == null
                      ? ''
                      : capitalize(DateFormat("EEEE d MMMM yyyy · HH:mm", 'fr_FR')
                          .format(date)),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: HealthColors.ink),
                ),
              ),
              if (!canEdit)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.lock_outline,
                      size: 18, color: HealthColors.muted),
                )
              else
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Modifier'),
                        contentPadding: EdgeInsets.zero),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                        leading: Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
                        title: Text('Supprimer'),
                        contentPadding: EdgeInsets.zero),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (icon, text, color) in values)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 6),
                      Text(text,
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
          if (author != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.medical_services_outlined,
                    size: 16, color: HealthColors.brightTeal),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Mesure prise en consultation par $author',
                      style: const TextStyle(
                          fontSize: 12,
                          color: HealthColors.brightTeal,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(note,
                style: const TextStyle(
                    color: HealthColors.muted, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}
