import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'medication.dart';
import 'medication_form_page.dart';

class PrescriptionUploadPage extends ConsumerStatefulWidget {
  const PrescriptionUploadPage({
    super.key,
    this.existingPrescription,
  });

  final Prescription? existingPrescription;

  @override
  ConsumerState<PrescriptionUploadPage> createState() =>
      _PrescriptionUploadPageState();
}

class _PrescriptionUploadPageState
    extends ConsumerState<PrescriptionUploadPage> {
  static const _maxFileBytes = 10 * 1024 * 1024;
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  List<_PatientOption> _patients = const [];
  _PatientOption? _selectedPatient;
  PlatformFile? _file;
  bool _searching = false;
  bool _uploading = false;
  bool _extracting = false;
  bool _ocrCompleted = false;
  bool _sendCompleted = false;
  String? _error;
  String? _ocrNotice;
  int? _uploadedPrescriptionId;
  String? _uploadedPatientName;
  int _medicationsAdded = 0;
  List<PrescriptionMedicationSuggestion> _suggestions = const [];
  List<MedicationDraft?> _suggestionDrafts = const [];
  final List<MedicationDraft> _manualDrafts = [];
  final Set<int> _savedSuggestionIndexes = {};
  final Set<int> _savedDraftIndexes = {};

  List<MedicationDraft> get _draftMedications => [
        ..._suggestionDrafts.whereType<MedicationDraft>(),
        ..._manualDrafts,
      ];

  bool get _allSuggestionsReviewed =>
      _suggestionDrafts.every((draft) => draft != null);

  bool get _canSendPrescription =>
      _selectedPatient != null &&
      _file != null &&
      _ocrCompleted &&
      _allSuggestionsReviewed &&
      !_uploading &&
      _uploadedPrescriptionId == null;

  @override
  void initState() {
    super.initState();
    final prescription = widget.existingPrescription;
    _uploadedPrescriptionId = prescription?.id;
    _uploadedPatientName = prescription?.patientName;
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    _searchTimer?.cancel();
    final query = value.trim();
    setState(() {
      _selectedPatient = null;
      _patients = const [];
      _searching = query.length >= 2;
      _error = null;
    });
    if (query.length < 2) return;
    _searchTimer = Timer(
      const Duration(milliseconds: 300),
      () => _searchPatients(query),
    );
  }

  Future<void> _searchPatients(String query) async {
    setState(() => _searching = true);
    try {
      final response = await ref
          .read(apiClientProvider)
          .dio
          .get('/prescriptions/patients', queryParameters: {'search': query});
      if (!mounted || _searchController.text.trim() != query) return;
      final data = response.data as List<dynamic>;
      setState(() {
        _patients = data
            .map(
                (item) => _PatientOption.fromJson(item as Map<String, dynamic>))
            .toList();
        _searching = false;
      });
    } on DioException catch (error) {
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _searching = false;
        _error = _apiError(error, 'Impossible de rechercher les patients.');
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      if (file.size > _maxFileBytes) {
        setState(() => _error = 'Le fichier ne doit pas dépasser 10 Mo.');
        return;
      }
      if (file.bytes == null || file.bytes!.isEmpty) {
        setState(() => _error = 'Impossible de lire ce fichier. Réessayez.');
        return;
      }
      setState(() {
        _file = file;
        _ocrCompleted = false;
        _ocrNotice = null;
        _suggestions = const [];
        _suggestionDrafts = const [];
        _manualDrafts.clear();
        _error = null;
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _error =
            error.message ?? 'Impossible d’ouvrir le sélecteur de fichiers.';
      });
    }
  }

  Future<void> _upload() async {
    final patient = _selectedPatient;
    final file = _file;
    if (!_canSendPrescription || patient == null || file?.bytes == null) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final form = FormData.fromMap({
        'patientId': patient.id.toString(),
        'file': MultipartFile.fromBytes(file!.bytes!, filename: file.name),
      });
      final response = await ref.read(apiClientProvider).dio.post(
            '/prescriptions/upload',
            data: form,
          );
      final payload = response.data;
      if (payload is! Map<String, dynamic> || payload['id'] is! num) {
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _error =
              'L’ordonnance a été envoyée, mais son identifiant est introuvable. Ne la téléversez pas à nouveau.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _uploadedPrescriptionId = (payload['id'] as num).toInt();
        _uploadedPatientName = patient.fullName;
      });
      await _saveDraftMedications((payload['id'] as num).toInt());
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = _apiError(error, 'L’envoi de l’ordonnance a échoué.');
      });
    }
  }

  Future<void> _addMedication() async {
    final prescriptionId = _uploadedPrescriptionId;
    if (prescriptionId == null) {
      final draft = await Navigator.push<MedicationDraft>(
        context,
        MaterialPageRoute(
          builder: (_) => const MedicationFormPage(draftOnly: true),
        ),
      );
      if (draft != null && mounted) {
        setState(() => _manualDrafts.add(draft));
      }
      return;
    }
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationFormPage(prescriptionId: prescriptionId),
      ),
    );
    if (added == true && mounted) {
      setState(() => _medicationsAdded++);
    }
  }

  Future<void> _extractMedications() async {
    final prescriptionId = widget.existingPrescription?.id;
    final file = _file;
    if (prescriptionId == null && file?.bytes == null) {
      return;
    }
    setState(() {
      _extracting = true;
      _error = null;
      _ocrNotice = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = prescriptionId == null
          ? await dio.post(
              '/prescriptions/extract-medications',
              data: FormData.fromMap({
                'file': MultipartFile.fromBytes(
                  file!.bytes!,
                  filename: file.name,
                ),
              }),
            )
          : await dio.post(
              '/prescriptions/$prescriptionId/extract-medications',
            );
      final payload = response.data;
      if (payload is! Map) {
        throw const FormatException('Réponse OCR invalide.');
      }
      final medications = payload['medications'];
      if (medications is! List) {
        throw const FormatException('Liste des médicaments invalide.');
      }
      final suggestions = medications
          .whereType<Map>()
          .map(
            (item) => PrescriptionMedicationSuggestion.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _suggestions = suggestions;
        _suggestionDrafts = List<MedicationDraft?>.filled(
          suggestions.length,
          null,
        );
        _ocrCompleted = true;
        _ocrNotice = payload['notice'] as String?;
        _extracting = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = _apiError(error, 'L’analyse locale de l’ordonnance a échoué.');
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = error.message.toString();
      });
    }
  }

  Future<void> _reviewSuggestion(int index) async {
    if (widget.existingPrescription == null) {
      final draft = await Navigator.push<MedicationDraft>(
        context,
        MaterialPageRoute(
          builder: (_) => MedicationFormPage(
            draftOnly: true,
            suggestion: _suggestions[index],
          ),
        ),
      );
      if (draft != null && mounted) {
        setState(() => _suggestionDrafts[index] = draft);
      }
      return;
    }
    final prescriptionId = _uploadedPrescriptionId;
    if (prescriptionId == null || _savedSuggestionIndexes.contains(index)) {
      return;
    }
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationFormPage(
          prescriptionId: prescriptionId,
          suggestion: _suggestions[index],
        ),
      ),
    );
    if (added == true && mounted) {
      setState(() {
        _savedSuggestionIndexes.add(index);
        _medicationsAdded++;
      });
    }
  }

  Future<void> _saveDraftMedications(int prescriptionId) async {
    final dio = ref.read(apiClientProvider).dio;
    final drafts = _draftMedications;
    for (var index = 0; index < drafts.length; index++) {
      if (_savedDraftIndexes.contains(index)) continue;
      try {
        await dio.post(
          '/medications',
          data: drafts[index].toRequest(prescriptionId),
        );
        if (!mounted) return;
        setState(() {
          _savedDraftIndexes.add(index);
          _medicationsAdded = _savedDraftIndexes.length;
        });
      } on DioException catch (error) {
        if (!mounted) return;
        setState(() {
          _uploading = false;
          _error = 'Ordonnance envoyée au patient, mais le planning est '
              'incomplet. Réessayez l’enregistrement du planning. '
              '${_apiError(error, 'Échec de l’enregistrement du médicament.')}';
        });
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _uploading = false;
      _sendCompleted = true;
      _error = null;
    });
  }

  Future<void> _retryDraftMedications() async {
    final prescriptionId = _uploadedPrescriptionId;
    if (prescriptionId == null || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    await _saveDraftMedications(prescriptionId);
  }

  void _finish() => Navigator.pop(context, true);

  String _apiError(DioException error, String fallback) {
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return error.message ?? fallback;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingMedicationCount =
        widget.existingPrescription?.medicationIds.length ?? 0;
    final totalMedications = existingMedicationCount + _medicationsAdded;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingPrescription == null
            ? 'Nouvelle ordonnance'
            : 'Planning de l’ordonnance'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.existingPrescription == null) ...[
            Text(
              'Choisir un patient',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Recherchez son nom complet. Seuls les patients disponibles pour votre suivi apparaissent.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged:
                  _uploadedPrescriptionId == null ? _searchChanged : null,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Nom complet du patient',
                hintText: 'Ex. Amel Ben Salem',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_selectedPatient != null) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(_selectedPatient!.fullName),
                  subtitle: const Text('Patient sélectionné'),
                  trailing: IconButton(
                    tooltip: 'Changer de patient',
                    onPressed: _uploadedPrescriptionId != null
                        ? null
                        : () => setState(() {
                              _selectedPatient = null;
                              _patients = const [];
                              _searchController.clear();
                            }),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ] else if (_patients.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final patient in _patients)
                      ListTile(
                        leading: const Icon(Icons.person_outline,
                            color: Colors.teal),
                        title: Text(patient.fullName),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() {
                          _selectedPatient = patient;
                          _patients = const [];
                          _searchController.text = patient.fullName;
                        }),
                      ),
                  ],
                ),
              ),
            ] else if (_searchController.text.trim().length >= 2 &&
                !_searching &&
                _error == null &&
                _selectedPatient == null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Aucun patient disponible avec ce nom.'),
              ),
            ],
            const SizedBox(height: 28),
          ],
          if (widget.existingPrescription == null) ...[
            Text(
              'Document de l’ordonnance',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'PDF, JPG ou PNG — 10 Mo maximum.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _uploading || _uploadedPrescriptionId != null
                  ? null
                  : _pickFile,
              icon: const Icon(Icons.attach_file),
              label: Text(
                  _file == null ? 'Choisir un fichier' : 'Changer le fichier'),
            ),
            if (_file != null) ...[
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(_file!.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${(_file!.size / 1024).ceil()} Ko'),
                  trailing: IconButton(
                    tooltip: 'Supprimer le fichier',
                    onPressed:
                        _uploading ? null : () => setState(() => _file = null),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            ],
          ],
          if (widget.existingPrescription == null &&
              _uploadedPrescriptionId == null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Avant l’envoi au patient',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Analysez l’ordonnance, vérifiez les médicaments détectés '
                      'et complétez leur planning. Le document ne sera envoyé '
                      'qu’après cette étape.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _file == null || _extracting || _ocrCompleted
                          ? null
                          : _extractMedications,
                      icon: _extracting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.document_scanner_outlined),
                      label: Text(
                        _extracting
                            ? 'Analyse locale en cours…'
                            : _ocrCompleted
                                ? 'Analyse terminée'
                                : 'Préremplir les champs avec l’OCR local',
                      ),
                    ),
                    if (_ocrNotice != null) ...[
                      const SizedBox(height: 8),
                      Text(_ocrNotice!),
                    ],
                    if (_suggestions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Médicaments détectés — vérifiez chaque proposition',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      for (var index = 0; index < _suggestions.length; index++)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.medication_outlined),
                            title: Text(
                              _suggestions[index].name?.isNotEmpty == true
                                  ? _suggestions[index].name!
                                  : 'Médicament détecté',
                            ),
                            subtitle: Text(
                              _suggestionDrafts[index] != null
                                  ? 'Vérifié : ${_suggestionDrafts[index]!.dosage ?? 'dosage non renseigné'}'
                                  : [
                                      if (_suggestions[index]
                                              .dosage
                                              ?.isNotEmpty ==
                                          true)
                                        _suggestions[index].dosage!,
                                      if (_suggestions[index]
                                          .warnings
                                          .isNotEmpty)
                                        '${_suggestions[index].warnings.length} champ(s) à vérifier',
                                      'Touchez pour vérifier et compléter',
                                    ].join(' · '),
                            ),
                            trailing: Icon(
                              _suggestionDrafts[index] == null
                                  ? Icons.edit_outlined
                                  : Icons.check_circle,
                              color: _suggestionDrafts[index] == null
                                  ? null
                                  : Colors.teal,
                            ),
                            onTap: () => _reviewSuggestion(index),
                          ),
                        ),
                    ],
                    if (_ocrCompleted) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _addMedication,
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'Ajouter manuellement un médicament au planning',
                        ),
                      ),
                      for (var index = 0; index < _manualDrafts.length; index++)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.medication_outlined),
                            title: Text(_manualDrafts[index].name),
                            subtitle: Text(
                              _manualDrafts[index].dosage ??
                                  'Dosage non renseigné',
                            ),
                            trailing: IconButton(
                              tooltip: 'Supprimer du planning',
                              onPressed: () =>
                                  setState(() => _manualDrafts.removeAt(index)),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                      if (!_allSuggestionsReviewed) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Vérifiez chaque médicament détecté avant de pouvoir envoyer l’ordonnance.',
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (widget.existingPrescription != null &&
              _uploadedPrescriptionId != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_outlined, color: Colors.teal),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ordonnance déposée',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Patient : ${_uploadedPatientName ?? 'Patient'}',
                    ),
                    if (widget.existingPrescription?.documentName != null)
                      Text(
                        'Document : ${widget.existingPrescription!.documentName}',
                      ),
                    Text(
                      totalMedications == 0
                          ? 'Aucun médicament ajouté au planning.'
                          : '$totalMedications médicament(s) lié(s) au planning.',
                    ),
                    if (existingMedicationCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '$existingMedicationCount médicament(s) sont déjà liés. Vérifiez le planning pour éviter les doublons.',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'L’OCR fonctionne localement. Aucun médicament n’est enregistré avant votre vérification et confirmation.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _extracting ? null : _extractMedications,
              icon: _extracting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(
                _extracting
                    ? 'Analyse locale en cours…'
                    : 'Préremplir les champs avec l’OCR local',
              ),
            ),
            if (_ocrNotice != null) ...[
              const SizedBox(height: 8),
              Text(_ocrNotice!),
            ],
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Médicaments détectés — vérifiez chaque proposition',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < _suggestions.length; index++)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.medication_outlined),
                    title: Text(
                      _suggestions[index].name?.isNotEmpty == true
                          ? _suggestions[index].name!
                          : 'Médicament détecté',
                    ),
                    subtitle: Text([
                      if (_suggestions[index].dosage?.isNotEmpty == true)
                        _suggestions[index].dosage!,
                      if (_suggestions[index].warnings.isNotEmpty)
                        '${_suggestions[index].warnings.length} champ(s) à vérifier',
                    ].join(' · ')),
                    trailing: _savedSuggestionIndexes.contains(index)
                        ? const Icon(Icons.check_circle, color: Colors.teal)
                        : const Icon(Icons.chevron_right),
                    onTap: _savedSuggestionIndexes.contains(index)
                        ? null
                        : () => _reviewSuggestion(index),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _addMedication,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un médicament au planning'),
            ),
            OutlinedButton(
              onPressed: _finish,
              child: const Text('Terminer'),
            ),
          ],
          if (widget.existingPrescription == null &&
              _uploadedPrescriptionId != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_outlined, color: Colors.teal),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ordonnance envoyée au patient',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Patient : ${_uploadedPatientName ?? 'Patient'}'),
                    Text(
                      _sendCompleted
                          ? '${_draftMedications.length} médicament(s) confirmé(s) dans le planning.'
                          : '${_savedDraftIndexes.length}/${_draftMedications.length} médicament(s) enregistré(s) dans le planning.',
                    ),
                    if (_uploading) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ] else if (_sendCompleted) ...[
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _finish,
                        child: const Text('Terminer'),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _retryDraftMedications,
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                          'Réessayer l’enregistrement du planning',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          if (_uploadedPrescriptionId == null)
            FilledButton.icon(
              onPressed: _canSendPrescription ? _upload : null,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(
                _uploading
                    ? 'Envoi de l’ordonnance et du planning…'
                    : _ocrCompleted && _allSuggestionsReviewed
                        ? 'Envoyer l’ordonnance au patient'
                        : 'Analyser et vérifier avant l’envoi',
              ),
            ),
        ],
      ),
    );
  }
}

class _PatientOption {
  const _PatientOption({required this.id, required this.fullName});

  final int id;
  final String fullName;

  factory _PatientOption.fromJson(Map<String, dynamic> json) => _PatientOption(
        id: (json['id'] as num).toInt(),
        fullName: json['fullName'] as String? ?? '',
      );
}
