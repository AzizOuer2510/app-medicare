import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/core/network/api_client.dart';
import 'package:medicare/core/storage/token_storage.dart';
import 'package:medicare/features/notifications/providers/notification_repository.dart';
import 'package:medicare/features/notifications/pages/notifications_page.dart';
class DemoNotifications extends NotificationRepository {
  DemoNotifications() : super(ApiClient(TokenStorage()));
  final notificationQueries = <Map<String, dynamic>>[];
  final reminderQueries = <Map<String, dynamic>>[];
  final items = <Map<String, dynamic>>[
    {
      'id': 1,
      'title': 'Ordonnance disponible',
      'message': 'PDF démo',
      'type': 'GENERAL',
      'read': false,
      'createdAt': '2026-10-09T10:00:00Z'
    },
    {
      'id': 2,
      'title': 'Rappel de prise',
      'message': 'Exemple fictif',
      'type': 'MEDICATION',
      'read': true,
      'createdAt': '2026-10-09T10:00:00Z'
    },
    {
      'id': 3,
      'title': 'Consultation demain',
      'message': 'Exemple fictif',
      'type': 'APPOINTMENT',
      'read': false,
      'createdAt': '2026-10-09T10:00:00Z'
    },
  ];
  final scheduled = <Map<String, dynamic>>[
    {
      'id': 1,
      'title': 'Préparer les documents',
      'message': 'PDF démo',
      'type': 'GENERAL',
      'status': 'PENDING',
      'scheduledFor': '2027-01-01T10:00:00Z'
    },
    {
      'id': 2,
      'title': 'Ancien rappel de prise',
      'message': 'Exemple fictif',
      'type': 'MEDICATION',
      'status': 'CANCELLED',
      'scheduledFor': '2027-01-01T10:00:00Z'
    },
  ];

  bool matches(Map<String, dynamic> item, String? query, String? type) {
    final text = '${item['title']} ${item['message']}'.toLowerCase();
    return (query == null || text.contains(query.trim().toLowerCase())) &&
        (type == null || item['type'] == type);
  }

  @override
  Future<List<Map<String, dynamic>>> notifications(
      {bool? read, String? query, String? type, bool archived = false}) async {
    notificationQueries
        .add({'read': read, 'q': query, 'type': type, 'archived': archived});
    return items
        .where((item) =>
            matches(item, query, type) &&
            (item['archived'] == true) == archived &&
            (read == null || item['read'] == read))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> reminders(
      {String? query, String? type, String? status}) async {
    reminderQueries.add({'q': query, 'type': type, 'status': status});
    return scheduled
        .where((item) =>
            matches(item, query, type) &&
            (status == null || item['status'] == status))
        .toList();
  }

  @override
  Future<int> unreadCount() async =>
      items.where((item) => item['read'] == false).length;

  @override
  Future<Map<String, dynamic>> overview() async => {
        'unread': items
            .where((item) => item['read'] == false && item['archived'] != true)
            .length,
        'inbox': items.where((item) => item['archived'] != true).length,
        'archived': items.where((item) => item['archived'] == true).length,
        'pendingReminders':
            scheduled.where((item) => item['status'] == 'PENDING').length,
        'sentReminders':
            scheduled.where((item) => item['status'] == 'SENT').length,
        'nextReminder': null,
      };
}

Future<void> showNotifications(
    WidgetTester tester, DemoNotifications repository) async {
  await tester.pumpWidget(ProviderScope(
    key: const ValueKey('notifications-test-scope'),
    overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: NotificationsPage()),
  ));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Future<void> enterVisible(
    WidgetTester tester, Finder finder, String text) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, text);
}
