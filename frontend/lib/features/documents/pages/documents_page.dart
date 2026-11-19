import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/care_workspace.dart';
import '../../notifications/pages/notifications_page.dart';
import '../providers/document_repository.dart';
import '../widgets/document_card.dart';
import '../widgets/document_upload_form.dart';
import '../../notifications/widgets/care_contacts.dart';
import '../../notifications/providers/notification_repository.dart';
import 'document_preview_page.dart';
import 'document_shares_page.dart';
import 'document_analysis_page.dart';

class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key});
  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _documents = [];
  Map<String, dynamic> _overview = {};
  bool _loading = true,
      _refreshing = false,
      _busy = false,
      _favorites = false,
      _grid = true;
  String? _category, _error;
  String _sort = 'recent';
  double? _uploadProgress;
  Timer? _debounce;
  int _requestId = 0;
  DocumentRepository get _repository => ref.read(documentRepositoryProvider);
  int _count(String key) => (_overview[key] as num?)?.toInt() ?? 0;
  bool get _filtered =>
      _search.text.trim().isNotEmpty || _category != null || _favorites;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _debounce?.cancel();
    final repository = _repository;
    final request = ++_requestId;
    setState(() => _refreshing = true);
    try {
      final result = await Future.wait<dynamic>([
        repository.documents(
          category: _category,
          query: _search.text,
          favorite: _favorites ? true : null,
          sort: _sort,
        ),
        repository.overview(),
      ]);
      if (!mounted || request != _requestId) return;
      setState(() {
        _documents = result[0] as List<Map<String, dynamic>>;
        _overview = result[1] as Map<String, dynamic>;
        _error = null;
      });
    } catch (error) {
      if (mounted && request == _requestId) {
        setState(() => _error = _errorMessage(error));
      }
    } finally {
      if (mounted && request == _requestId) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  String _errorMessage(Object error) =>
      error is DioException && error.response?.data is Map
      ? error.response?.data['message']?.toString() ?? 'Action impossible.'
      : 'Impossible de joindre le serveur.';

  Future<void> _perform(
    Future<void> Function() action, {
    String? message,
    bool refresh = true,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && refresh) await _load();
      if (mounted && message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _uploadProgress = null;
        });
      }
    }
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    ++_requestId;
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 300), () => _load());
  }

  void _reset() {
    _search.clear();
    setState(() {
      _category = null;
      _favorites = false;
      _sort = 'recent';
    });
    _load();
  }

  Future<void> _edit({
    Map<String, dynamic>? document,
    bool prescription = false,
  }) async {
    final repository = _repository;
    Map<String, dynamic>? patient;
    if (document == null &&
        (_overview['role'] == 'DOCTOR' || _overview['role'] == 'ADMIN')) {
      try {
        patient = await pickPatient(
          context,
          ref.read(notificationRepositoryProvider),
          canAdd: _overview['role'] == 'DOCTOR',
          allUsers: _overview['role'] == 'ADMIN',
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Patients indisponibles.')),
          );
        }
        return;
      }
      if (!mounted || patient == null) return;
    }
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => Theme(
        data: careTheme(context),
        child: DocumentUploadForm(
          initial: document,
          prescription: prescription,
          patientName: patient?['name'] as String?,
          loadDoctors: document == null && _overview['role'] == 'USER'
              ? ref.read(notificationRepositoryProvider).contacts
              : null,
        ),
      ),
    );
    if (data == null || !mounted) return;
    if (document != null) {
      await _perform(
        () => repository.update(document['id'] as int, data),
        message: 'Informations du document mises à jour.',
      );
      return;
    }
    await _perform(
      () => repository.upload(
        title: data['title'] as String,
        category: data['category'] as String,
        description: data['description'] as String,
        filename: data['filename'] as String,
        bytes: data['bytes'] as Uint8List,
        patientId: patient?['id'] as int?,
        doctorId: data['doctorId'] as int?,
        onSendProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      ),
      message: patient == null
          ? 'Document ajouté à votre bibliothèque.'
          : 'Document transmis au patient.',
    );
  }

  Future<void> _download(Map<String, dynamic> document) async {
    final repository = _repository;
    await _perform(() async {
      final bytes = await repository.content(document['id'] as int);
      await FilePicker.saveFile(
        dialogTitle: 'Enregistrer le document',
        fileName: document['filename'] as String,
        bytes: bytes,
      );
    }, refresh: false);
  }

  void _preview(Map<String, dynamic> document) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          DocumentPreviewPage(document: document, repository: _repository),
    ),
  );

  Future<void> _delete(Map<String, dynamic> document) async {
    final repository = _repository;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce document ?'),
        content: Text(
          '« ${document['title']} » sera supprimé de votre bibliothèque, ainsi que le fichier associé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Conserver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(
        () => repository.delete(document['id'] as int),
        message: 'Document supprimé.',
      );
    }
  }

  Future<void> _details(Map<String, dynamic> document) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(document['title'] as String),
        scrollable: true,
        content: SizedBox(
          width: 430,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CareBadge(
                documentCategory(document['category']),
                color: documentColor(document['category']),
              ),
              const SizedBox(height: 18),
              SelectableText(
                '${document['filename']}\n${careSize(document['size'] as num)}\nAjouté le ${careDate(document['uploadedAt'])}',
                style: const TextStyle(height: 1.8, fontSize: 13),
              ),
              if (_overview['role'] == 'USER')
                Text(
                  "Destinataire · ${document['sharedDoctorName'] ?? 'Personnel'}",
                ),
              if ((document['description'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 18),
                SelectableText(
                  document['description'] as String,
                  style: const TextStyle(height: 1.7),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'close'),
            child: const Text('Fermer'),
          ),
          if (_manage(document))
            TextButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Modifier'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'preview'),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Ouvrir'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result == 'edit') await _edit(document: document);
    if (result == 'preview') _preview(document);
  }

  bool _manage(Map<String, dynamic> doc) =>
      _overview['role'] == 'ADMIN' ||
      doc['ownerId'] == null ||
      doc['ownerId'] == _overview['viewerId'];

  void _action(Map<String, dynamic> document, String action) async {
    switch (action) {
      case 'doctor':
        int? doctorId;
        if (_overview['role'] == 'USER') {
          try {
            final people = await ref
                .read(notificationRepositoryProvider)
                .contacts();
            if (!mounted) return;
            doctorId = await showDialog<int>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('Destinataire du document'),
                children: [
                  for (final person in [
                    {'id': 0, 'name': 'Personnel'},
                    ...people,
                  ])
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, person['id']),
                      child: Text(person['name'] as String),
                    ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Annuler'),
                  ),
                ],
              ),
            );
            if (!mounted ||
                doctorId == null ||
                doctorId == (document['sharedDoctorId'] ?? 0)) {
              return;
            }
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Médecins indisponibles.')),
              );
            }
            return;
          }
        }
        final enabled = doctorId != null && doctorId != 0;
        await _perform(
          () => _repository.shareWithDoctor(
            document['id'] as int,
            enabled,
            doctorId: enabled ? doctorId : null,
          ),
          message: enabled
              ? 'Document partagé avec votre médecin.'
              : 'Accès du médecin retiré.',
        );
      case 'analysis':
        final saved = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => DocumentAnalysisPage(
              canConfirm: _manage(document),
              document: document,
              repository: _repository,
            ),
          ),
        );
        if (saved == true && mounted) await _load();
      case 'share':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                DocumentSharesPage(document: document, repository: _repository),
          ),
        );
      case 'preview':
        _preview(document);
      case 'details':
        _details(document);
      case 'edit':
        _edit(document: document);
      case 'download':
        _download(document);
      case 'delete':
        _delete(document);
    }
  }

  @override
  Widget build(BuildContext context) => CareWorkspace(
    index: 1,
    onRefresh: _load,
    onNavigate: (index) {
      if (index == 0) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const NotificationsPage()),
        );
      }
    },
    child: RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CareHero(
                  eyebrow: 'Votre bibliothèque personnelle',
                  title: 'Votre santé, bien classée.',
                  description:
                      'Ordonnances, analyses et comptes rendus. Gardez vos documents à portée de main, pour vous et vos prochains rendez-vous.',
                  icon: Icons.folder_open_rounded,
                  action: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD4E9DA),
                      foregroundColor: CareColors.ink,
                    ),
                    onPressed: _busy ? null : () => _edit(),
                    icon: const Icon(Icons.add_rounded, size: 19),
                    label: const Text('Ajouter un document'),
                  ),
                ),
                if (_overview['role'] == 'DOCTOR')
                  Wrap(
                    children: [
                      AddPatientButton(
                        repository: ref.read(notificationRepositoryProvider),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Déposer une ordonnance'),
                        onPressed: _busy
                            ? null
                            : () => _edit(prescription: true),
                      ),
                    ],
                  ),
                if (_overview['role'] == 'USER')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.medical_services_outlined),
                      label: const Text('Mes médecins'),
                      onPressed: () async {
                        final changed = await showDialog<bool>(
                          context: context,
                          builder: (_) => DoctorDialog(
                            repository: ref.read(
                              notificationRepositoryProvider,
                            ),
                          ),
                        );
                        if (changed == true && mounted) await _load();
                      },
                    ),
                  ),
                const SizedBox(height: 20),
                CareStats(
                  compactIndices: const [0, 3],
                  children: [
                    CareStat(
                      value: _loading ? '—' : '${_count('total')}',
                      label: 'Documents',
                      icon: Icons.folder_copy_outlined,
                    ),
                    CareStat(
                      value: _loading ? '—' : '${_count('prescriptions')}',
                      label: 'Ordonnances',
                      icon: Icons.medication_outlined,
                    ),
                    CareStat(
                      value: _loading ? '—' : '${_count('analyses')}',
                      label: 'Analyses',
                      icon: Icons.biotech_outlined,
                      color: CareColors.violet,
                    ),
                    CareStat(
                      value: _loading ? '—' : '${_count('favorites')}',
                      label: 'Favoris',
                      icon: Icons.star_outline_rounded,
                      color: CareColors.amber,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                if (_busy || _refreshing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(value: _uploadProgress),
                  ),
                if (_error != null) ...[
                  CareError(message: _error!, onRetry: _load),
                  const SizedBox(height: 16),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final main = _library();
                    if (constraints.maxWidth < 1000) return main;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: main),
                        const SizedBox(width: 24),
                        SizedBox(width: 250, child: _insights()),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _library() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Ma bibliothèque',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.7,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Vue grille',
            onPressed: () => setState(() => _grid = true),
            icon: Icon(
              Icons.grid_view_rounded,
              color: _grid ? CareColors.primary : CareColors.muted,
            ),
          ),
          IconButton(
            tooltip: 'Vue liste',
            onPressed: () => setState(() => _grid = false),
            icon: Icon(
              Icons.view_agenda_outlined,
              color: !_grid ? CareColors.primary : CareColors.muted,
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      TextField(
        key: const ValueKey('document-search'),
        controller: _search,
        onChanged: _searchChanged,
        decoration: InputDecoration(
          hintText: 'Rechercher un document…',
          prefixIcon: const Icon(Icons.search_rounded, color: CareColors.muted),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer la recherche',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _search.clear();
                    _load();
                  },
                ),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in <String?, String>{
            null: 'Tous',
            'PRESCRIPTION': 'Ordonnances',
            'ANALYSIS': 'Analyses',
            'OTHER': 'Autres',
          }.entries)
            ChoiceChip(
              key: ValueKey('document-category-${option.key ?? 'ALL'}'),
              label: Text(option.value),
              selected: _category == option.key,
              onSelected: (_) {
                setState(() => _category = option.key);
                _load();
              },
            ),
          FilterChip(
            key: const ValueKey('document-favorites-filter'),
            label: const Text('Favoris'),
            avatar: const Icon(Icons.star_outline_rounded, size: 16),
            selected: _favorites,
            onSelected: (value) {
              setState(() => _favorites = value);
              _load();
            },
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 16,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${_documents.length} document(s)',
            style: const TextStyle(color: CareColors.muted, fontSize: 12),
          ),
          DropdownButton<String>(
            key: const ValueKey('document-sort'),
            value: _sort,
            underline: const SizedBox.shrink(),
            style: const TextStyle(color: CareColors.muted, fontSize: 12),
            items: const [
              DropdownMenuItem(value: 'recent', child: Text('Plus récents')),
              DropdownMenuItem(value: 'oldest', child: Text('Plus anciens')),
              DropdownMenuItem(value: 'name', child: Text('Nom A → Z')),
              DropdownMenuItem(
                value: 'size',
                child: Text('Taille décroissante'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _sort = value);
                _load();
              }
            },
          ),
          if (_filtered || _sort != 'recent')
            TextButton(onPressed: _reset, child: const Text('Réinitialiser')),
        ],
      ),
      const SizedBox(height: 14),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(50),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_documents.isEmpty)
        CareEmpty(
          title: _filtered
              ? 'Aucun document trouvé'
              : 'Votre bibliothèque commence ici',
          message: _filtered
              ? 'Essayez une autre recherche ou modifiez vos filtres.'
              : 'Ajoutez votre première ordonnance, analyse ou compte rendu.',
          icon: _favorites
              ? Icons.star_border_rounded
              : Icons.create_new_folder_outlined,
          action: _filtered
              ? TextButton(
                  onPressed: _reset,
                  child: const Text('Effacer les filtres'),
                )
              : OutlinedButton(
                  onPressed: _busy ? null : () => _edit(),
                  child: const Text('Choisir un document'),
                ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = !_grid || constraints.maxWidth < 560
                ? 1
                : constraints.maxWidth < 900
                ? 2
                : 3;
            final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: _documents
                  .map(
                    (document) => SizedBox(
                      width: width,
                      height: _grid ? 304 : null,
                      child: DocumentCard(
                        document: document,
                        manage: _manage(document),
                        shareWithDoctor:
                            _overview['role'] == 'USER' ||
                            (_overview['role'] == 'ADMIN' &&
                                document['sharedDoctorId'] != null),
                        showOwner:
                            _overview['role'] == 'DOCTOR' ||
                            _overview['role'] == 'ADMIN',
                        busy: _busy,
                        compact: !_grid,
                        onOpen: () => _preview(document),
                        onFavorite: () => _perform(
                          () => _repository.favorite(
                            document['id'] as int,
                            document['favorite'] != true,
                          ),
                          message: document['favorite'] == true
                              ? 'Document retiré des favoris.'
                              : 'Document ajouté aux favoris.',
                        ),
                        onAction: (action) => _action(document, action),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
    ],
  );

  Widget _insights() {
    final total = _count('total');
    final others = total - _count('prescriptions') - _count('analyses');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CarePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.folder_open_outlined,
                size: 30,
                color: CareColors.primary,
              ),
              const SizedBox(height: 16),
              const Text(
                'Votre dossier, en un regard.',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              for (final entry in [
                ('Ordonnances', _count('prescriptions'), CareColors.primary),
                ('Analyses', _count('analyses'), CareColors.violet),
                ('Autres', others, CareColors.amber),
              ]) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.$1,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CareColors.muted,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.$2}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : entry.$2 / total,
                    minHeight: 5,
                    color: entry.$3,
                    backgroundColor: CareColors.canvas,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              const Divider(color: CareColors.line),
              const SizedBox(height: 10),
              Text(
                careSize(_count('totalBytes')),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Taille totale de vos documents',
                style: TextStyle(color: CareColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const CarePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.star_outline_rounded, color: CareColors.amber),
              SizedBox(height: 14),
              Text(
                'L’essentiel à portée de main.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Ajoutez vos documents importants aux favoris pour les retrouver en un instant, avant un rendez-vous.',
                style: TextStyle(
                  color: CareColors.muted,
                  height: 1.7,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
