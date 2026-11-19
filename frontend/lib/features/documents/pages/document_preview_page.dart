import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../core/widgets/care_workspace.dart';
import '../providers/document_repository.dart';

class DocumentPreviewPage extends StatefulWidget {
  const DocumentPreviewPage(
      {super.key, required this.document, required this.repository});
  final Map<String, dynamic> document;
  final DocumentRepository repository;
  @override
  State<DocumentPreviewPage> createState() => _DocumentPreviewPageState();
}

class _DocumentPreviewPageState extends State<DocumentPreviewPage> {
  final _pdf = PdfViewerController();
  late Future<Uint8List> _content;
  int _page = 1, _pages = 0;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _content = widget.repository.content(widget.document['id'] as int);
  }

  Future<void> _download() async {
    setState(() => _saving = true);
    try {
      final bytes = await _content;
      await FilePicker.saveFile(
          dialogTitle: 'Enregistrer le document',
          fileName: widget.document['filename'] as String,
          bytes: bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Téléchargement impossible. Réessayez.')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
      data: careTheme(context),
      child: Scaffold(
        appBar: AppBar(
            title: Text(widget.document['title'] as String,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                  tooltip: 'Télécharger',
                  onPressed: _saving ? null : _download,
                  icon: const Icon(Icons.file_download_outlined)),
              const SizedBox(width: 12)
            ]),
        body: Column(children: [
          if (_saving) const LinearProgressIndicator(),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    CareBadge(
                        widget.document['contentType'] == 'application/pdf'
                            ? 'PDF'
                            : 'IMAGE',
                        icon: Icons.visibility_outlined),
                    Text(careSize(widget.document['size'] as num),
                        style: const TextStyle(color: CareColors.muted)),
                    if (_pages > 0) ...[
                      IconButton(
                          tooltip: 'Page précédente',
                          onPressed: _page > 1
                              ? () => _pdf.goToPage(pageNumber: _page - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left)),
                      Text('$_page / $_pages'),
                      IconButton(
                          tooltip: 'Page suivante',
                          onPressed: _page < _pages
                              ? () => _pdf.goToPage(pageNumber: _page + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right)),
                      IconButton(
                          tooltip: 'Réduire',
                          onPressed: () => _pdf.zoomDown(),
                          icon: const Icon(Icons.zoom_out)),
                      IconButton(
                          tooltip: 'Agrandir',
                          onPressed: () => _pdf.zoomUp(),
                          icon: const Icon(Icons.zoom_in)),
                    ],
                  ])),
          Expanded(
              child: FutureBuilder<Uint8List>(
                  future: _content,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: CareEmpty(
                                  title: 'Le document ne peut pas être ouvert',
                                  message:
                                      'Vérifiez votre connexion puis réessayez.',
                                  icon: Icons.description_outlined,
                                  action: OutlinedButton(
                                      onPressed: () => setState(() => _content =
                                          widget.repository.content(
                                              widget.document['id'] as int)),
                                      child: const Text('Réessayer')))));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (widget.document['contentType'] != 'application/pdf') {
                      return InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 5,
                          child: Center(
                              child: Image.memory(snapshot.data!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Text(
                                      'Cette image est illisible.'))));
                    }
                    return PdfViewer.data(snapshot.data!,
                        sourceName:
                            'medicare-document-${widget.document['id']}',
                        controller: _pdf,
                        params: PdfViewerParams(
                            textSelectionParams: const PdfTextSelectionParams(),
                            onViewerReady: (document, controller) {
                              if (mounted) {
                                setState(() => _pages = document.pages.length);
                              }
                            },
                            onPageChanged: (page) {
                              if (mounted && page != null) {
                                setState(() => _page = page);
                              }
                            },
                            errorBannerBuilder: (context, error, stack,
                                    reference) =>
                                const Center(
                                    child: Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text(
                                            'Ce PDF ne peut pas être affiché. Vous pouvez le télécharger avec le bouton en haut.')))));
                  })),
        ]),
      ));
}
