import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/widgets/care_workspace.dart';
import '../documents/pages/document_preview_page.dart';
import '../documents/providers/document_repository.dart';
import '../documents/widgets/document_card.dart';
import '../documents/widgets/document_upload_form.dart';
import '../health/health_api.dart';
import '../health/health_page.dart';
import '../medications/medication_form_page.dart';
import '../medications/medication_statistics_page.dart';

/// Dossier d'un patient côté médecin : un seul écran synchronisé avec ce que le patient
/// voit dans l'application (santé et nutrition, médicaments pris / oubliés, documents
/// et ordonnances), et l'envoi d'une ordonnance qui arrive dans ses documents.
class PatientFilePage extends ConsumerStatefulWidget {
  const PatientFilePage({
    super.key,
    required this.patientId,
    required this.patientName,
    this.summary,
    this.initialTab = 0,
  });

  final int patientId;
  final String patientName;

  /// Ligne renvoyée par /health/patients (dernières constantes, alertes), si disponible.
  final Map<String, dynamic>? summary;
  final int initialTab;

  @override
  ConsumerState<PatientFilePage> createState() => _PatientFilePageState();
}

class _PatientFilePageState extends ConsumerState<PatientFilePage> {
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: careTheme(context),
      child: DefaultTabController(
        length: 3,
        initialIndex: widget.initialTab,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.patientName),
            bottom: const TabBar(
              isScrollable: false,
              tabs: [
                Tab(icon: Icon(Icons.monitor_heart_outlined), text: 'Santé'),
                Tab(icon: Icon(Icons.medication_outlined), text: 'Médicaments'),
                Tab(icon: Icon(Icons.folder_open_outlined), text: 'Documents'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _HealthTab(
                patientId: widget.patientId,
                patientName: widget.patientName,
                summary: widget.summary,
              ),
              _MedicationsTab(
                patientId: widget.patientId,
                patientName: widget.patientName,
              ),
              _DocumentsTab(
                patientId: widget.patientId,
                patientName: widget.patientName,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// Date en français sans dépendre des données de locale d'intl (« mar. 17 nov. 2026 »).
String _frDate(DateTime d, {bool weekday = false, bool year = false}) =>
    '${weekday ? '${_days[d.weekday - 1]} ' : ''}${d.day} ${_months[d.month - 1]}${year ? ' ${d.year}' : ''}';

String _apiError(Object error, String fallback) {
  if (error is DioException && error.response?.data is Map) {
    final message = (error.response!.data as Map)['message']?.toString();
    if (message != null && message.isNotEmpty) return message;
  }
  return fallback;
}

// ── Santé et nutrition ─────────────────────────────────────────────────────

class _HealthTab extends StatelessWidget {
  const _HealthTab({
    required this.patientId,
    required this.patientName,
    this.summary,
  });

  final int patientId;
  final String patientName;
  final Map<String, dynamic>? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary ?? const {};
    final alerts = (s['alerts'] as List?)?.map((e) => e.toString()).toList() ?? [];
    String value(String key, String unit) =>
        s[key] == null ? '—' : '${s[key]} $unit';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dernières constantes',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Chip(Icons.monitor_weight_outlined, 'Poids', value('lastWeight', 'kg')),
                    _Chip(Icons.speed_outlined, 'Tension', value('lastPressure', 'mmHg')),
                    _Chip(Icons.favorite_outline, 'Pouls', value('lastHeartRate', 'bpm')),
                    _Chip(Icons.bloodtype_outlined, 'Glycémie', value('lastGlycemia', 'g/L')),
                  ],
                ),
                const SizedBox(height: 12),
                if (alerts.isEmpty)
                  const Row(children: [
                    Icon(Icons.check_circle_outline, color: CareColors.primary, size: 18),
                    SizedBox(width: 6),
                    Text('Aucune alerte sur les 30 derniers jours'),
                  ])
                else
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFB3261E), size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Alertes : ${alerts.join(', ')}',
                        style: const TextStyle(color: Color(0xFFB3261E)))),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => HealthPage(
                patient: HealthPatient(id: patientId, name: patientName),
              ),
            ),
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Ouvrir le suivi santé et nutrition'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Mesures, courbes, objectifs, repas, hydratation et analyse IA : '
          'vous voyez les mêmes données que le patient, en temps réel.',
          style: TextStyle(color: CareColors.muted),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: CareColors.mint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: CareColors.primary),
          const SizedBox(width: 6),
          Text('$label : ', style: const TextStyle(color: CareColors.muted)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

// ── Médicaments : prises et oublis ─────────────────────────────────────────

const _statusLabels = {
  'TAKEN': 'Pris',
  'MISSED': 'Oublié',
  'SKIPPED': 'Sauté',
  'SNOOZED': 'Reporté',
  'PENDING': 'Non renseigné',
};

const _statusColors = {
  'TAKEN': Color(0xFF2E7D32),
  'MISSED': Color(0xFFB3261E),
  'SKIPPED': Color(0xFFC18A3A),
  'SNOOZED': Color(0xFF4F6BD8),
  'PENDING': Color(0xFF738584),
};

const _statusIcons = {
  'TAKEN': Icons.check_circle,
  'MISSED': Icons.cancel,
  'SKIPPED': Icons.remove_circle_outline,
  'SNOOZED': Icons.snooze,
  'PENDING': Icons.help_outline,
};

class _MedicationsTab extends ConsumerStatefulWidget {
  const _MedicationsTab({required this.patientId, required this.patientName});
  final int patientId;
  final String patientName;

  @override
  ConsumerState<_MedicationsTab> createState() => _MedicationsTabState();
}

class _MedicationsTabState extends ConsumerState<_MedicationsTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _medications = const [];
  List<Map<String, dynamic>> _intakes = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'ALL';

  @override
  bool get wantKeepAlive => true;

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
      final dio = ref.read(apiClientProvider).dio;
      final query = {'patientId': widget.patientId};
      final results = await Future.wait([
        dio.get('/medications', queryParameters: query),
        dio.get('/medications/intakes', queryParameters: query),
      ]);
      if (!mounted) return;
      setState(() {
        _medications = (results[0].data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _intakes = (results[1].data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _apiError(error, 'Impossible de charger les médicaments du patient.');
      });
    }
  }

  int _count(String status) => _intakes.where((i) => i['status'] == status).length;

  /// Le médecin ajoute un médicament et ses horaires : ils arrivent dans le planning du patient.
  Future<void> _addToPlanning() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationFormPage(
          patientId: widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    );
    if (added == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ajouté au planning de ${widget.patientName} : il est prévenu par une notification.')));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Réessayer')),
        ]),
      );
    }
    final active = _medications.where((m) => m['status'] == 'ACTIVE').toList();
    final shown = _filter == 'ALL'
        ? _intakes
        : _intakes.where((i) => i['status'] == _filter).toList();
    final taken = _count('TAKEN');
    final missed = _count('MISSED');
    final answered = taken + missed + _count('SKIPPED');
    final rate = answered == 0 ? null : (taken * 100 / answered).round();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('patient-medications-list'),
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: _Counter('Pris', taken, _statusColors['TAKEN']!)),
            const SizedBox(width: 8),
            Expanded(child: _Counter('Oubliés', missed, _statusColors['MISSED']!)),
            const SizedBox(width: 8),
            Expanded(
              child: _Counter('Observance', rate, CareColors.primary, suffix: rate == null ? '' : ' %'),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('30 derniers jours', style: TextStyle(color: CareColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _addToPlanning,
            icon: const Icon(Icons.add_alarm_outlined),
            label: const Text('Ajouter un médicament à son planning'),
          ),
          const SizedBox(height: 12),
          Text('Traitement en cours (${active.length})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          if (active.isEmpty)
            const Text('Aucun médicament actif.', style: TextStyle(color: CareColors.muted))
          else
            for (final m in active)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.medication_outlined, color: CareColors.primary),
                  title: Text('${m['name']}${m['dosage'] == null ? '' : ' · ${m['dosage']}'}'),
                  subtitle: Text([
                    if ((m['reminderTimes'] as List?)?.isNotEmpty == true)
                      'Prises : ${(m['reminderTimes'] as List).map((t) => t.toString().substring(0, 5)).join(', ')}',
                    if (m['prescriptionId'] == null) 'Ajouté par le patient',
                  ].join(' · ')),
                ),
              ),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(
              child: Text('Historique des prises',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => MedicationStatisticsPage(
                    patientId: widget.patientId,
                    patientName: widget.patientName,
                  ),
                ),
              ),
              icon: const Icon(Icons.insights_outlined, size: 18),
              label: const Text('Statistiques'),
            ),
          ]),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ALL', label: Text('Toutes')),
              ButtonSegment(value: 'TAKEN', label: Text('Prises')),
              ButtonSegment(value: 'MISSED', label: Text('Oubliées')),
            ],
            selected: {_filter},
            onSelectionChanged: (v) => setState(() => _filter = v.first),
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aucune prise pour ce filtre.',
                  textAlign: TextAlign.center, style: TextStyle(color: CareColors.muted)),
            )
          else
            for (final intake in shown) _IntakeTile(intake),
        ],
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter(this.label, this.value, this.color, {this.suffix = ''});
  final String label;
  final int? value;
  final Color color;
  final String suffix;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(value == null ? '—' : '$value$suffix',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(color: CareColors.muted)),
        ]),
      );
}

class _IntakeTile extends StatelessWidget {
  const _IntakeTile(this.intake);
  final Map<String, dynamic> intake;

  @override
  Widget build(BuildContext context) {
    final status = intake['status']?.toString() ?? 'PENDING';
    final date = DateTime.tryParse(intake['date']?.toString() ?? '');
    final time = intake['time']?.toString() ?? '';
    final takenAt = DateTime.tryParse(intake['takenAt']?.toString() ?? '');
    final color = _statusColors[status] ?? CareColors.muted;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(_statusIcons[status] ?? Icons.help_outline, color: color),
      title: Text(intake['medicationName']?.toString() ?? ''),
      subtitle: Text([
        if (date != null) _frDate(date, weekday: true),
        if (time.length >= 5) 'prévu à ${time.substring(0, 5)}',
        if (status == 'TAKEN' && takenAt != null) 'pris à ${DateFormat('HH:mm').format(takenAt)}',
        if ((intake['note']?.toString() ?? '').isNotEmpty) intake['note'].toString(),
      ].join(' · ')),
      trailing: Text(_statusLabels[status] ?? status,
          style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Documents et ordonnances ───────────────────────────────────────────────

class _DocumentsTab extends ConsumerStatefulWidget {
  const _DocumentsTab({required this.patientId, required this.patientName});
  final int patientId;
  final String patientName;

  @override
  ConsumerState<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<_DocumentsTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _documents = const [];
  bool _loading = true, _sending = false;
  String? _error;
  String? _category;

  DocumentRepository get _repository => ref.read(documentRepositoryProvider);

  @override
  bool get wantKeepAlive => true;

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
      final docs = await _repository.documents(
          patientId: widget.patientId, category: _category);
      if (!mounted) return;
      setState(() {
        _documents = docs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _apiError(error, 'Impossible de charger les documents du patient.');
      });
    }
  }

  Future<void> _send({required bool prescription}) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => Theme(
        data: careTheme(context),
        child: DocumentUploadForm(
          prescription: prescription,
          patientName: widget.patientName,
        ),
      ),
    );
    if (data == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await _repository.upload(
        title: data['title'] as String,
        category: data['category'] as String,
        description: data['description'] as String,
        filename: data['filename'] as String,
        bytes: data['bytes'] as Uint8List,
        patientId: widget.patientId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(prescription
            ? 'Ordonnance envoyée : ${widget.patientName} la retrouve dans ses documents.'
            : 'Document envoyé au patient.'),
      ));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_apiError(error, 'Envoi impossible.'))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _sending ? null : () => _send(prescription: true),
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Envoyer une ordonnance'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Envoyer un autre document',
              onPressed: _sending ? null : () => _send(prescription: false),
              icon: const Icon(Icons.upload_file_outlined),
            ),
          ]),
          if (_sending) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final c in const [
              (null, 'Tous'),
              ('PRESCRIPTION', 'Ordonnances'),
              ('ANALYSIS', 'Analyses'),
              ('OTHER', 'Autres'),
            ])
              ChoiceChip(
                label: Text(c.$2),
                selected: _category == c.$1,
                onSelected: (_) {
                  setState(() => _category = c.$1);
                  _load();
                },
              ),
          ]),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(_error!, textAlign: TextAlign.center),
                TextButton(onPressed: _load, child: const Text('Réessayer')),
              ]),
            )
          else if (_documents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucun document pour ce patient.',
                  textAlign: TextAlign.center, style: TextStyle(color: CareColors.muted)),
            )
          else
            for (final doc in _documents) _documentTile(doc),
        ],
      ),
    );
  }

  Widget _documentTile(Map<String, dynamic> doc) {
    final category = doc['category'];
    final date = DateTime.tryParse(doc['uploadedAt']?.toString() ?? '')?.toLocal();
    final sentBy = doc['sharedDoctorName']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: documentColor(category).withValues(alpha: 0.12),
          child: Icon(documentIcon(category), color: documentColor(category)),
        ),
        title: Text(doc['title']?.toString() ?? ''),
        subtitle: Text([
          documentCategory(category),
          if (date != null) _frDate(date, year: true),
          if (sentBy != null) 'médecin : $sentBy' else 'ajouté par le patient',
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentPreviewPage(document: doc, repository: _repository),
          ),
        ),
      ),
    );
  }
}
