import 'dart:async';
import 'package:flutter/material.dart';
import '../providers/document_repository.dart';
import '../widgets/document_card.dart';
import '../../../core/widgets/care_workspace.dart';

class DocumentAnalysisPage extends StatefulWidget {
  const DocumentAnalysisPage({
    super.key,
    required this.document,
    this.canConfirm = true,
    required this.repository,
  });
  final Map<String, dynamic> document;
  final DocumentRepository repository;
  final bool canConfirm;
  @override
  State<DocumentAnalysisPage> createState() => _DocumentAnalysisPageState();
}

class _DocumentAnalysisPageState extends State<DocumentAnalysisPage> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in [
      'title',
      'documentDate',
      'doctor',
      'facility',
      'summary',
    ])
      key: TextEditingController(),
  };
  Map<String, dynamic> result = {};
  String category = 'OTHER';
  String? error;
  bool busy = true;
  TimeOfDay? time;
  Timer? poll;
  int get id => widget.document['id'] as int;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    poll?.cancel();
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> load({bool start = false}) async {
    poll?.cancel();
    try {
      final next = await widget.repository.analysis(id, start: start);
      if (!mounted) return;
      final proposal = next['draft']?['fields'];
      if (proposal != null && result['status'] != next['status']) {
        for (final entry in fields.entries) {
          entry.value.text = proposal[entry.key]?.toString() ?? '';
        }
        category = proposal['category'] as String;
      }
      setState(() {
        result = next;
        error = null;
        busy = false;
      });
      if (['QUEUED', 'PROCESSING'].contains(next['status'])) {
        poll = Timer(const Duration(seconds: 3), load);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Connexion au serveur impossible.';
          busy = false;
        });
      }
    }
  }

  DateTime? get followUp =>
      DateTime.tryParse(result['draft']?['followUpDate']?.toString() ?? '');
  Future<void> confirm() async {
    if (!form.currentState!.validate() || busy) return;
    final date = followUp;
    final at = time != null && date != null
        ? DateTime(date.year, date.month, date.day, time!.hour, time!.minute)
        : null;
    if (at != null && !at.isAfter(DateTime.now())) {
      setState(() => error = 'Choisissez une heure future.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.confirmAnalysis(id, {
        'fields': {
          for (final e in fields.entries)
            e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
          'category': category,
        },
        if (at != null) 'reminderAt': at.toUtc().toIso8601String(),
        if (at != null) 'offsetMinutes': at.timeZoneOffset.inMinutes,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Validation impossible. Vérifiez les valeurs puis réessayez.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = result['status'];
    final editable = status == 'READY' && widget.canConfirm;
    return Theme(
      data: careTheme(context),
      child: Scaffold(
        appBar: AppBar(title: const Text('Analyse du document')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: CarePanel(
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.document['title'] as String,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),
                        if (error != null) ...[
                          Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          TextButton(
                            onPressed: busy ? null : load,
                            child: const Text('Actualiser'),
                          ),
                        ],
                        if (busy) const LinearProgressIndicator(),
                        if (status == null || status == 'FAILED') ...[
                          Text(
                            result['error']?.toString() ??
                                'Le document sera lu sur ce PC. Vous pourrez corriger les informations proposées avant de les enregistrer.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () {
                                    setState(() => busy = true);
                                    load(start: true);
                                  },
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: Text(
                              status == 'FAILED'
                                  ? 'Relancer l’analyse'
                                  : 'Lancer l’analyse',
                            ),
                          ),
                        ],
                        if (status == 'QUEUED' || status == 'PROCESSING') ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            status == 'QUEUED'
                                ? 'En attente de traitement'
                                : 'Lecture et classement en cours…',
                          ),
                          const Text(
                            'Vous pouvez quitter cet écran. Une notification vous préviendra quand les propositions seront prêtes.',
                          ),
                        ],
                        if (status == 'READY' || status == 'CONFIRMED') ...[
                          Text(
                            editable
                                ? 'Vérifiez les informations proposées avec le texte source.'
                                : status == 'CONFIRMED'
                                ? 'Informations validées'
                                : 'Propositions en attente de validation par le patient.',
                          ),
                          Material(
                            color: Colors.transparent,
                            child: ExpansionTile(
                              title: const Text('Texte lu sur le document'),
                              children: [
                                SelectableText(
                                  result['draft']['sourceText'] as String,
                                ),
                              ],
                            ),
                          ),
                          for (final entry in {
                            'title': 'Titre',
                            'documentDate': 'Date du document (AAAA-MM-JJ)',
                            'doctor': 'Médecin',
                            'facility': 'Établissement',
                            'summary': 'Résumé descriptif',
                          }.entries)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: TextFormField(
                                controller: fields[entry.key],
                                readOnly: !editable || busy,
                                maxLines: entry.key == 'summary' ? 3 : 1,
                                maxLength: switch (entry.key) {
                                  'title' => 120,
                                  'summary' => 1000,
                                  'documentDate' => 10,
                                  _ => 160,
                                },
                                decoration: InputDecoration(
                                  labelText: entry.value,
                                ),
                                validator: (v) {
                                  final text = v?.trim() ?? '';
                                  if (entry.key == 'title' && text.isEmpty) {
                                    return 'Saisissez un titre.';
                                  }
                                  if (entry.key == 'documentDate' &&
                                      text.isNotEmpty) {
                                    final date = DateTime.tryParse(text);
                                    if (date == null ||
                                        date
                                                .toIso8601String()
                                                .split('T')
                                                .first !=
                                            text) {
                                      return 'Utilisez une date valide au format AAAA-MM-JJ.';
                                    }
                                  }
                                  return null;
                                },
                              ),
                            ),
                          DropdownButtonFormField<String>(
                            initialValue: category,
                            decoration: const InputDecoration(
                              labelText: 'Catégorie',
                            ),
                            items: [
                              for (final c in [
                                'PRESCRIPTION',
                                'ANALYSIS',
                                'OTHER',
                              ])
                                DropdownMenuItem(
                                  value: c,
                                  child: Text(documentCategory(c)),
                                ),
                            ],
                            onChanged: editable && !busy
                                ? (value) => setState(() => category = value!)
                                : null,
                          ),
                          if (editable && followUp != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Suivi mentionné : « ${result['draft']['evidence']} »',
                            ),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      final chosen = await showTimePicker(
                                        context: context,
                                        initialTime:
                                            time ??
                                            const TimeOfDay(hour: 9, minute: 0),
                                      );
                                      if (chosen != null && mounted) {
                                        setState(() => time = chosen);
                                      }
                                    },
                              child: Text(
                                time == null
                                    ? 'Ajouter un rappel pour cette date'
                                    : 'Heure du rappel : ${time!.format(context)}',
                              ),
                            ),
                            if (time != null)
                              TextButton(
                                onPressed: () => setState(() => time = null),
                                child: const Text('Retirer le rappel'),
                              ),
                          ],
                          if (editable)
                            Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: FilledButton(
                                onPressed: busy ? null : confirm,
                                child: const Text('Valider et enregistrer'),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
