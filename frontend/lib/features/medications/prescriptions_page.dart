import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../auth/authentication_state.dart';
import 'medication.dart';
import 'medication_statistics_page.dart';
import 'prescription_upload_page.dart';

class PrescriptionsPage extends ConsumerStatefulWidget {
  const PrescriptionsPage({
    super.key,
    this.patientId,
    this.patientName,
  });

  final int? patientId;
  final String? patientName;

  @override
  ConsumerState<PrescriptionsPage> createState() => _PrescriptionsPageState();
}

class _PrescriptionsPageState extends ConsumerState<PrescriptionsPage> {
  List<Prescription> items = [];
  bool loading = true;
  String? error;
  int? _savingDocumentId;
  int? _editingPrescriptionId;
  int? _archivingPrescriptionId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final response =
          await ref.read(apiClientProvider).dio.get('/prescriptions');
      if (!mounted) return;
      final prescriptions = (response.data as List<dynamic>)
          .map(
            (value) => Prescription.fromJson(
              value as Map<String, dynamic>,
            ),
          )
          .toList();
      setState(() {
        items = widget.patientId == null
            ? prescriptions
            : prescriptions
                .where((item) => item.patientId == widget.patientId)
                .toList();
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Impossible de charger les prescriptions.';
      });
    }
  }

  Future<void> _downloadDocument(Prescription prescription) async {
    setState(() => _savingDocumentId = prescription.id);
    try {
      final response = await ref.read(apiClientProvider).dio.get<List<int>>(
            '/prescriptions/${prescription.id}/document',
            options: Options(responseType: ResponseType.bytes),
          );
      final data = response.data;
      if (data == null || data.isEmpty) {
        if (mounted) {
          _showMessage('Ce document est vide.', error: true);
        }
        return;
      }
      final extension =
          prescription.documentName?.split('.').last.toLowerCase() ?? 'pdf';
      await FilePicker.saveFile(
        dialogTitle: 'Enregistrer l’ordonnance',
        fileName: prescription.documentName ??
            'ordonnance-${prescription.id}.$extension',
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        bytes: Uint8List.fromList(data),
      );
    } on DioException catch (exception) {
      if (mounted) {
        _showMessage(
          exception.response?.statusCode == 404
              ? 'Ce document n’est plus disponible.'
              : 'Impossible de télécharger cette ordonnance.',
          error: true,
        );
      }
    } on PlatformException {
      if (mounted) {
        _showMessage('Impossible d’enregistrer le document.', error: true);
      }
    } finally {
      if (mounted) setState(() => _savingDocumentId = null);
    }
  }

  Future<void> _openPlanner(Prescription prescription) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PrescriptionUploadPage(existingPrescription: prescription),
      ),
    );
    if (updated == true && mounted) await _load();
  }

  Future<void> _openPatientAdherence() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationStatisticsPage(
          patientId: widget.patientId,
          patientName: widget.patientName,
        ),
      ),
    );
  }

  Future<void> _editPrescription(Prescription prescription) async {
    final changes = await showDialog<_PrescriptionChanges>(
      context: context,
      builder: (_) => _PrescriptionEditDialog(prescription: prescription),
    );
    if (changes == null) return;

    setState(() => _editingPrescriptionId = prescription.id);
    try {
      final form = FormData.fromMap({
        if (changes.file != null)
          'file': MultipartFile.fromBytes(
            changes.file!.bytes!,
            filename: changes.file!.name,
          ),
      });
      await ref.read(apiClientProvider).dio.put(
            '/prescriptions/${prescription.id}',
            queryParameters: {
              'diagnosis': changes.diagnosis,
              'prescriptionDate':
                  DateFormat('yyyy-MM-dd').format(changes.prescriptionDate),
              'notes': changes.notes,
            },
            data: form,
          );
      if (!mounted) return;
      _showMessage('Ordonnance mise à jour.');
      await _load();
    } on DioException catch (exception) {
      if (mounted) {
        _showMessage(
          _apiError(exception, 'Impossible de modifier cette ordonnance.'),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _editingPrescriptionId = null);
    }
  }

  Future<void> _archivePrescription(Prescription prescription) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archiver cette ordonnance ?'),
        content: const Text(
          'Elle sera retirée de la liste. Le document, les traitements liés et leur historique seront conservés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archiver'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _archivingPrescriptionId = prescription.id);
    try {
      await ref
          .read(apiClientProvider)
          .dio
          .delete('/prescriptions/${prescription.id}');
      if (!mounted) return;
      _showMessage('Ordonnance archivée.');
      await _load();
    } on DioException catch (exception) {
      if (mounted) {
        _showMessage(
          _apiError(exception, 'Impossible d’archiver cette ordonnance.'),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _archivingPrescriptionId = null);
    }
  }

  String _apiError(DioException exception, String fallback) {
    final data = exception.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
    return fallback;
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDoctor =
        ref.watch(authenticationStateProvider).valueOrNull?.role == 'DOCTOR';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patientName == null
            ? (isDoctor ? 'Prescriptions des patients' : 'Prescriptions')
            : 'Prescriptions de ${widget.patientName}'),
      ),
      body: Column(
        children: [
          if (isDoctor && widget.patientId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openPatientAdherence,
                  icon: const Icon(Icons.insights_outlined),
                  label: const Text('Consulter l’observance du traitement'),
                ),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(error!),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _load,
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      )
                    : items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.description_outlined,
                                      size: 56),
                                  const SizedBox(height: 12),
                                  Text(
                                    widget.patientName == null
                                        ? 'Aucune prescription ne vous a encore été attribuée.'
                                        : 'Aucune prescription active pour ce patient.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.patientName == null
                                        ? 'Les prescriptions apparaîtront ici lorsqu’un médecin les aura créées pour votre compte.'
                                        : 'Les prescriptions actives de ce patient apparaîtront ici.',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: items.length,
                              itemBuilder: (_, index) {
                                final prescription = items[index];
                                return Card(
                                  child: ListTile(
                                    leading: const CircleAvatar(
                                      child: Icon(Icons.description_outlined),
                                    ),
                                    title: Text(isDoctor
                                        ? prescription.patientName.isEmpty
                                            ? 'Patient #${prescription.patientId}'
                                            : prescription.patientName
                                        : prescription.doctorName.isEmpty
                                            ? 'Médecin'
                                            : 'Dr. ${prescription.doctorName}'),
                                    subtitle: Text(
                                      '${prescription.diagnosis ?? 'Prescription'}\n'
                                      '${DateFormat('dd/MM/yyyy').format(prescription.prescriptionDate)}\n'
                                      '${prescription.hasDocument ? prescription.documentName ?? 'Ordonnance jointe' : '${prescription.medicationIds.length} médicament(s)'}',
                                    ),
                                    isThreeLine: true,
                                    trailing: isDoctor
                                        ? PopupMenuButton<_PrescriptionAction>(
                                            tooltip: 'Actions ordonnance',
                                            enabled: _savingDocumentId !=
                                                    prescription.id &&
                                                _editingPrescriptionId !=
                                                    prescription.id &&
                                                _archivingPrescriptionId !=
                                                    prescription.id,
                                            onSelected: (action) {
                                              switch (action) {
                                                case _PrescriptionAction
                                                      .fillPlan:
                                                  _openPlanner(prescription);
                                                  break;
                                                case _PrescriptionAction
                                                      .download:
                                                  _downloadDocument(
                                                      prescription);
                                                  break;
                                                case _PrescriptionAction.edit:
                                                  _editPrescription(
                                                      prescription);
                                                  break;
                                                case _PrescriptionAction
                                                      .archive:
                                                  _archivePrescription(
                                                      prescription);
                                                  break;
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              if (prescription.hasDocument)
                                                const PopupMenuItem(
                                                  value: _PrescriptionAction
                                                      .fillPlan,
                                                  child: ListTile(
                                                    leading: Icon(Icons
                                                        .document_scanner_outlined),
                                                    title: Text(
                                                        'Préremplir le planning'),
                                                  ),
                                                ),
                                              if (prescription.hasDocument)
                                                const PopupMenuItem(
                                                  value: _PrescriptionAction
                                                      .download,
                                                  child: ListTile(
                                                    leading: Icon(Icons
                                                        .download_outlined),
                                                    title: Text(
                                                        'Télécharger le document'),
                                                  ),
                                                ),
                                              const PopupMenuItem(
                                                value: _PrescriptionAction.edit,
                                                child: ListTile(
                                                  leading:
                                                      Icon(Icons.edit_outlined),
                                                  title: Text(
                                                      'Modifier l’ordonnance'),
                                                ),
                                              ),
                                              const PopupMenuItem(
                                                value:
                                                    _PrescriptionAction.archive,
                                                child: ListTile(
                                                  leading: Icon(
                                                      Icons.archive_outlined),
                                                  title: Text(
                                                      'Archiver l’ordonnance'),
                                                ),
                                              ),
                                            ],
                                          )
                                        : prescription.hasDocument
                                            ? IconButton(
                                                tooltip:
                                                    'Télécharger l’ordonnance',
                                                onPressed: _savingDocumentId ==
                                                        prescription.id
                                                    ? null
                                                    : () => _downloadDocument(
                                                        prescription),
                                                icon: _savingDocumentId ==
                                                        prescription.id
                                                    ? const SizedBox(
                                                        width: 20,
                                                        height: 20,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth: 2),
                                                      )
                                                    : const Icon(Icons
                                                        .download_outlined),
                                              )
                                            : null,
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

enum _PrescriptionAction { fillPlan, download, edit, archive }

class _PrescriptionChanges {
  const _PrescriptionChanges({
    required this.diagnosis,
    required this.prescriptionDate,
    required this.notes,
    this.file,
  });

  final String diagnosis;
  final DateTime prescriptionDate;
  final String notes;
  final PlatformFile? file;
}

class _PrescriptionEditDialog extends StatefulWidget {
  const _PrescriptionEditDialog({required this.prescription});

  final Prescription prescription;

  @override
  State<_PrescriptionEditDialog> createState() =>
      _PrescriptionEditDialogState();
}

class _PrescriptionEditDialogState extends State<_PrescriptionEditDialog> {
  static const _maxFileBytes = 10 * 1024 * 1024;
  late final TextEditingController _diagnosis;
  late final TextEditingController _notes;
  late DateTime _prescriptionDate;
  PlatformFile? _file;
  String? _error;

  @override
  void initState() {
    super.initState();
    _diagnosis =
        TextEditingController(text: widget.prescription.diagnosis ?? '');
    _notes = TextEditingController(text: widget.prescription.notes ?? '');
    _prescriptionDate = widget.prescription.prescriptionDate;
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
        _error = null;
      });
    } on PlatformException catch (exception) {
      if (mounted) {
        setState(() {
          _error = exception.message ??
              'Impossible d’ouvrir le sélecteur de fichiers.';
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: _prescriptionDate,
    );
    if (date != null) setState(() => _prescriptionDate = date);
  }

  @override
  void dispose() {
    _diagnosis.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Modifier l’ordonnance'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _diagnosis,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Diagnostic'),
              ),
              TextFormField(
                controller: _notes,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: const Text('Date de l’ordonnance'),
                subtitle: Text(
                  DateFormat('dd/MM/yyyy').format(_prescriptionDate),
                ),
                onTap: _pickDate,
              ),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file),
                label: Text(
                  widget.prescription.hasDocument
                      ? 'Remplacer le document'
                      : 'Ajouter un document',
                ),
              ),
              if (_file != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(
                    _file!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Retirer le nouveau document',
                    onPressed: () => setState(() => _file = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: _error == null
                ? () => Navigator.pop(
                      context,
                      _PrescriptionChanges(
                        diagnosis: _diagnosis.text.trim(),
                        prescriptionDate: _prescriptionDate,
                        notes: _notes.text.trim(),
                        file: _file,
                      ),
                    )
                : null,
            child: const Text('Enregistrer'),
          ),
        ],
      );
}
