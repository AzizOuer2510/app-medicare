import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/care_workspace.dart';

class DocumentUploadForm extends StatefulWidget {
  const DocumentUploadForm({
    super.key,
    this.initial,
    this.patientName,
    this.loadDoctors,
    this.prescription = false,
  });
  final bool prescription;
  final Map<String, dynamic>? initial;
  final String? patientName;
  final Future<List<Map<String, dynamic>>> Function()? loadDoctors;

  @override
  State<DocumentUploadForm> createState() => _DocumentUploadFormState();
}

class _DocumentUploadFormState extends State<DocumentUploadForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _category = 'PRESCRIPTION';
  PlatformFile? _file;
  bool _picking = false;
  String? _fileError;
  Future<List<Map<String, dynamic>>>? _doctors;
  int _doctorId = 0;

  @override
  void initState() {
    super.initState();
    _doctors = widget.loadDoctors?.call();
    _title.text = widget.initial?['title'] as String? ?? '';
    _description.text = widget.initial?['description'] as String? ?? '';
    _category = widget.initial?['category'] as String? ?? 'PRESCRIPTION';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _picking = true;
      _fileError = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > 10 * 1024 * 1024 || file.size == 0) {
        setState(
          () => _fileError = 'Choisissez un fichier non vide de 10 Mo maximum.',
        );
        return;
      }
      if (file.bytes == null) {
        setState(() => _fileError = 'Impossible de lire ce fichier.');
        return;
      }
      setState(() {
        _file = file;
        if (_title.text.isEmpty) {
          _title.text = file.name.length > 120
              ? file.name.substring(0, 120)
              : file.name;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _fileError = 'Impossible de selectionner le fichier.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (widget.initial == null && _file?.bytes == null) {
      setState(() => _fileError = 'Selectionnez un fichier.');
      return;
    }
    Navigator.pop(context, <String, dynamic>{
      'title': _title.text.trim(),
      'category': _category,
      if (_doctorId != 0) 'doctorId': _doctorId,
      'description': _description.text.trim(),
      if (widget.initial == null) 'filename': _file!.name,
      if (widget.initial == null) 'bytes': _file!.bytes!,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null
          ? (widget.prescription
                ? 'Déposer une ordonnance'
                : 'Ajouter un document médical')
          : 'Modifier les informations',
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_doctors != null)
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _doctors,
                  builder: (context, snapshot) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        key: const ValueKey('document-recipient'),
                        initialValue: _doctorId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Destinataire',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('Personnel'),
                          ),
                          for (final doctor
                              in snapshot.data ?? <Map<String, dynamic>>[])
                            DropdownMenuItem(
                              value: doctor['id'] as int,
                              child: Text(doctor['name'] as String),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _doctorId = value ?? 0),
                      ),
                      if (snapshot.hasError)
                        TextButton(
                          onPressed: () =>
                              setState(() => _doctors = widget.loadDoctors!()),
                          child: const Text('Recharger mes médecins'),
                        ),
                      if (snapshot.hasData && snapshot.data!.isEmpty)
                        const Text(
                          'Ajoutez un médecin dans « Mes médecins » pour lui partager ce document.',
                        ),
                    ],
                  ),
                ),
              if (widget.patientName != null)
                Text("Destinataire · ${widget.patientName}"),
              TextFormField(
                key: const ValueKey('document-title'),
                controller: _title,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Titre du document',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Titre requis'
                    : null,
              ),
              if (!widget.prescription)
                DropdownButtonFormField<String>(
                  key: const ValueKey('document-category'),
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: const [
                    DropdownMenuItem(
                      value: 'PRESCRIPTION',
                      child: Text('Ordonnance'),
                    ),
                    DropdownMenuItem(value: 'ANALYSIS', child: Text('Analyse')),
                    DropdownMenuItem(value: 'OTHER', child: Text('Autre')),
                  ],
                  onChanged: (value) => setState(() => _category = value!),
                ),
              TextFormField(
                key: const ValueKey('document-description'),
                controller: _description,
                maxLength: 2000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (facultative)',
                ),
              ),
              if (widget.initial == null) ...[
                InkWell(
                  onTap: _picking ? null : _pickFile,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: CareColors.canvas,
                      border: Border.all(color: CareColors.line),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.cloud_upload_outlined,
                          color: CareColors.primary,
                          size: 34,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _file?.name ?? 'Parcourir vos fichiers',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _file == null
                              ? 'PDF, PNG ou JPEG · 10 Mo maximum'
                              : careSize(_file!.size),
                          style: const TextStyle(
                            color: CareColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else
                Text(
                  'Fichier : ${widget.initial!['filename']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: CareColors.muted, fontSize: 12),
                ),
              if (_picking) const LinearProgressIndicator(),
              if (_fileError != null)
                Text(
                  _fileError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: _picking ? null : _submit,
        child: Text(
          widget.initial == null ? 'Importer le document' : 'Enregistrer',
        ),
      ),
    ],
  );
}
