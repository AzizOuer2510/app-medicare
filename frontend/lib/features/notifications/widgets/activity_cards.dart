import 'package:flutter/material.dart';
import '../../../core/widgets/care_workspace.dart';

String activityType(dynamic type) => switch (type) {
  'MEDICATION' => 'Médicament',
  'APPOINTMENT' => 'Rendez-vous',
  _ => 'Général',
};
IconData activityIcon(dynamic type) => switch (type) {
  'MEDICATION' => Icons.medication_outlined,
  'APPOINTMENT' => Icons.event_outlined,
  _ => Icons.notifications_none_rounded,
};
Color activityColor(dynamic type) => switch (type) {
  'MEDICATION' => CareColors.violet,
  'APPOINTMENT' => CareColors.primary,
  _ => CareColors.amber,
};

class NotificationCard extends StatelessWidget {
  const NotificationCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onRead,
    required this.onArchive,
  });
  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onRead, onArchive;

  @override
  Widget build(BuildContext context) {
    final read = item['read'] == true;
    final archived = item['archived'] == true;
    final color = activityColor(item['type']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: read ? Colors.white : const Color(0xFFFBFEFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: read ? CareColors.line : const Color(0xFFBCD9CC),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(activityIcon(item['type']), color: color, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      CareBadge(activityType(item['type']), color: color),
                      if (!read && !archived)
                        const CareBadge(
                          'Nouveau',
                          icon: Icons.circle,
                          color: CareColors.primary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item['title'] as String,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.4,
                      fontWeight: read ? FontWeight.w600 : FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['message'] as String,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.65,
                      color: CareColors.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        careDate(item['createdAt']),
                        style: const TextStyle(
                          fontSize: 11,
                          color: CareColors.muted,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : onRead,
                        icon: Icon(
                          read
                              ? Icons.mark_email_unread_outlined
                              : Icons.done_all_rounded,
                          size: 16,
                        ),
                        label: Text(
                          read ? 'Marquer non lue' : 'Marquer comme lue',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: archived
                  ? 'Restaurer la notification'
                  : 'Archiver la notification',
              onPressed: busy ? null : onArchive,
              icon: Icon(
                archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                size: 20,
                color: CareColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onAction,
    this.manage = true,
    this.recipient = true,
    this.admin = false,
  });
  final Map<String, dynamic> item;
  final bool busy;
  final bool manage, recipient, admin;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final pending = item['status'] == 'PENDING';
    final sent = item['status'] == 'SENT';
    final color = pending
        ? CareColors.primary
        : sent
        ? CareColors.violet
        : CareColors.muted;
    final date = DateTime.parse(item['scheduledFor'] as String).toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CarePanel(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}',
                    style: TextStyle(color: color, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      CareBadge(
                        pending
                            ? 'En attente'
                            : sent
                            ? 'Envoyé'
                            : 'Annulé',
                        color: color,
                        icon: pending
                            ? Icons.schedule
                            : sent
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                      ),
                      CareBadge(
                        item['authorId'] != null
                            ? 'Suivi'
                            : activityType(item['type']),
                        color: activityColor(item['type']),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item['title'] as String,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['message'] as String,
                    style: const TextStyle(
                      color: CareColors.muted,
                      height: 1.6,
                      fontSize: 13,
                    ),
                  ),
                  if (item['authorId'] != null)
                    Text(
                      "De ${item['authorName']} · Pour ${item['recipientName']}",
                    ),
                  if (item['instructionAt'] != null)
                    Text("Consigne du ${careDate(item['instructionAt'])}"),
                  if (item['deliveryFailedAt'] != null)
                    const Text('Échec de l’envoi'),
                  if (pending) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          careRelative(item['scheduledFor']),
                          style: const TextStyle(
                            color: CareColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (recipient)
                          TextButton.icon(
                            onPressed: busy ? null : () => onAction('snooze15'),
                            icon: const Icon(Icons.snooze_rounded, size: 16),
                            label: const Text(
                              'Reporter de 15 min',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if ((manage && (pending || admin || item['authorId'] == null)) ||
                (recipient && (pending || sent)))
              PopupMenuButton<String>(
                enabled: !busy,
                tooltip: 'Actions du rappel',
                onSelected: onAction,
                itemBuilder: (_) => [
                  if (pending && manage)
                    const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                  if (admin && pending && item['deliveryFailedAt'] != null)
                    const PopupMenuItem(
                      value: 'retry',
                      child: Text('Relancer l’envoi'),
                    ),
                  if (recipient && pending && item['authorId'] != null)
                    const PopupMenuItem(
                      value: 'alert',
                      child: Text('Choisir l’heure de mon alerte'),
                    ),
                  if (recipient && (pending || sent)) ...[
                    PopupMenuItem(
                      value: 'snooze60',
                      child: Text(
                        sent ? 'Reprogrammer dans 1 h' : 'Décaler de 1 h',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'snooze1440',
                      child: Text(
                        sent ? 'Reprogrammer demain' : 'Décaler d’un jour',
                      ),
                    ),
                  ],
                  if (pending && manage)
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Text('Annuler le rappel'),
                    ),
                  if (manage && (admin || item['authorId'] == null))
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Supprimer'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
