import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/authentication_state.dart';
import '../pages/notifications_page.dart';
import '../providers/notification_repository.dart';

final unreadNotificationsProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final user = ref.watch(authenticationStateProvider).valueOrNull;
  if (user == null) return 0;
  final refresh = Timer(const Duration(seconds: 15), ref.invalidateSelf);
  ref.onDispose(refresh.cancel);
  return ref.watch(notificationRepositoryProvider).unreadCount();
});

class NotificationBadgeButton extends ConsumerWidget {
  const NotificationBadgeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadNotificationsProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: 'Notifications et rappels',
      icon: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NotificationsPage()),
        );
        if (context.mounted) ref.invalidate(unreadNotificationsProvider);
      },
    );
  }
}
