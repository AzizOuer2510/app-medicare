import 'package:flutter/material.dart';
import '../../../core/widgets/care_workspace.dart';

String documentCategory(dynamic value) => switch (value) {
  'PRESCRIPTION' => 'Ordonnance',
  'ANALYSIS' => 'Analyse',
  _ => 'Autre document',
};
Color documentColor(dynamic value) => switch (value) {
  'PRESCRIPTION' => CareColors.primary,
  'ANALYSIS' => CareColors.violet,
  _ => CareColors.amber,
};
IconData documentIcon(dynamic value) => switch (value) {
  'PRESCRIPTION' => Icons.medication_outlined,
  'ANALYSIS' => Icons.biotech_outlined,
  _ => Icons.description_outlined,
};

class DocumentCard extends StatelessWidget {
  const DocumentCard({
    super.key,
    required this.document,
    required this.busy,
    required this.onOpen,
    required this.onFavorite,
    required this.onAction,
    this.compact = false,
    this.manage = true,
    this.shareWithDoctor = false,
    this.showOwner = false,
  });
  final Map<String, dynamic> document;
  final bool busy, compact, manage, shareWithDoctor, showOwner;
  final VoidCallback onOpen, onFavorite;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final color = documentColor(document['category']);
    final favorite = document['favorite'] == true;
    final pdf = document['contentType'] == 'application/pdf';
    final title = document['title'] as String;
    final owner = showOwner ? document['ownerName'] as String? : null;
    final recipient = shareWithDoctor && !showOwner
        ? document['sharedDoctorName'] as String? ?? 'Personnel'
        : null;
    final preview = Container(
      width: compact ? 50 : double.infinity,
      height: compact ? 58 : 92,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.065),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Icon(
          pdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
          color: color,
          size: compact ? 25 : 37,
        ),
      ),
    );
    final actions = PopupMenuButton<String>(
      tooltip: 'Actions du document',
      enabled: !busy,
      onSelected: onAction,
      itemBuilder: (_) => [
        PopupMenuItem(value: 'analysis', child: Text('Analyser avec l’IA')),
        if (shareWithDoctor)
          PopupMenuItem(
            value: 'doctor',
            child: Text(
              showOwner
                  ? 'Retirer l’accès du médecin'
                  : 'Choisir le destinataire',
            ),
          ),
        if (manage)
          const PopupMenuItem(
            value: 'share',
            child: Text('Partager par QR code'),
          ),
        PopupMenuItem(value: 'preview', child: Text('Aperçu')),
        PopupMenuItem(value: 'details', child: Text('Informations')),
        if (manage)
          const PopupMenuItem(
            value: 'edit',
            child: Text('Modifier les informations'),
          ),
        PopupMenuItem(value: 'download', child: Text('Télécharger')),
        if (manage)
          const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
      ],
    );
    final star = IconButton(
      tooltip: favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
      onPressed: busy ? null : onFavorite,
      icon: Icon(
        favorite ? Icons.star_rounded : Icons.star_outline_rounded,
        color: favorite ? CareColors.amber : CareColors.muted,
        size: 22,
      ),
    );
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: CareColors.line),
      ),
      child: InkWell(
        onTap: busy ? null : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: compact
              ? Row(
                  children: [
                    preview,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            owner ??
                                recipient ??
                                "${documentCategory(document['category'])} · ${careSize(document['size'] as num)}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: CareColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (manage) star,
                    actions,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        preview,
                        if (manage) Positioned(top: 4, right: 4, child: star),
                        Positioned(
                          bottom: 8,
                          left: 10,
                          child: CareBadge(pdf ? 'PDF' : 'IMAGE', color: color),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      owner ??
                          (recipient == null
                              ? document['filename'] as String
                              : "$recipient · ${document['filename']}"),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CareColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: CareBadge(
                            documentCategory(document['category']),
                            color: color,
                          ),
                        ),
                        actions,
                      ],
                    ),
                    const Divider(color: CareColors.line, height: 17),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            careDate(document['uploadedAt'], time: false),
                            style: const TextStyle(
                              color: CareColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        Text(
                          careSize(document['size'] as num),
                          style: const TextStyle(
                            color: CareColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
