import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.read(apiClientProvider)),
);

class NotificationRepository {
  NotificationRepository(this.client);
  final ApiClient client;

  Future<List<Map<String, dynamic>>> adminNotifications({int? userId}) async =>
      _items(
        (await client.dio.get(
          '/notifications/admin',
          queryParameters: {if (userId != null) 'userId': userId},
        )).data,
      );

  Future<List<Map<String, dynamic>>> recipients() async =>
      _items((await client.dio.get('/notifications/admin/recipients')).data);

  Future<void> saveNotification(Map<String, dynamic> data, {int? id}) async {
    if (id == null) {
      await client.dio.post('/notifications/admin', data: data);
    } else {
      await client.dio.put('/notifications/admin/$id', data: data);
    }
  }

  Future<void> deleteNotification(int id) async =>
      client.dio.delete('/notifications/admin/$id');

  Future<List<Map<String, dynamic>>> notifications({
    bool? read,
    String? query,
    String? type,
    bool archived = false,
  }) async {
    final response = await client.dio.get(
      '/notifications',
      queryParameters: {
        if (read != null) 'read': read,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (type != null) 'type': type,
        'archived': archived,
      },
    );
    return _items(response.data);
  }

  Future<List<Map<String, dynamic>>> contacts() async =>
      _items((await client.dio.get('/notifications/care/contacts')).data);

  Future<Map<String, dynamic>> addPatient(String email) async {
    final response = await client.dio.put(
      '/notifications/care/patients',
      data: {'email': email.trim()},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> setDoctor(String? email, {int? doctorId}) async {
    if (email == null) {
      await client.dio.delete(
        '/notifications/care/doctor',
        queryParameters: {if (doctorId != null) 'doctorId': doctorId},
      );
    } else {
      await client.dio.put(
        '/notifications/care/doctor',
        data: {'email': email},
      );
    }
  }

  Future<List<Map<String, dynamic>>> history() async =>
      _items((await client.dio.get('/reminders/history')).data);

  Future<void> retry(int id) async => client.dio.post('/reminders/$id/retry');

  Future<void> setAlert(int id, DateTime at) async => client.dio.patch(
    '/reminders/$id/alert',
    data: {'at': at.toUtc().toIso8601String()},
  );

  Future<List<Map<String, dynamic>>> deliveries() async =>
      _items((await client.dio.get('/notifications/deliveries')).data);

  Future<int> unreadCount() async {
    final response = await client.dio.get('/notifications/unread-count');
    return response.data['count'] as int;
  }

  Future<void> markRead(int id) async {
    await client.dio.patch('/notifications/$id/read');
  }

  Future<Map<String, dynamic>> overview() async {
    final response = await client.dio.get('/notifications/overview');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> markUnread(int id) async {
    await client.dio.patch('/notifications/$id/unread');
  }

  Future<void> archive(int id, {required bool archived}) async {
    await client.dio.patch(
      '/notifications/$id/archive',
      data: {'archived': archived},
    );
  }

  Future<void> snooze(int id, int minutes) async {
    await client.dio.post('/reminders/$id/snooze', data: {'minutes': minutes});
  }

  Future<void> markAllRead() async {
    await client.dio.patch('/notifications/read-all');
  }

  Future<List<Map<String, dynamic>>> reminders({
    String? query,
    String? type,
    String? status,
  }) async {
    final response = await client.dio.get(
      '/reminders',
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (type != null) 'type': type,
        if (status != null) 'status': status,
      },
    );
    return _items(response.data);
  }

  Future<List<Map<String, dynamic>>> references(String type) async {
    if (type == 'GENERAL') return [];
    final response = await client.dio.get(
      type == 'APPOINTMENT' ? '/appointments' : '/medications',
    );
    return _items(response.data);
  }

  Future<void> saveReminder(Map<String, dynamic> data, {int? id}) async {
    if (id == null) {
      await client.dio.post('/reminders', data: data);
    } else {
      await client.dio.put('/reminders/$id', data: data);
    }
  }

  Future<void> cancelReminder(int id) async {
    await client.dio.patch('/reminders/$id/cancel');
  }

  Future<void> deleteReminder(int id) async {
    await client.dio.delete('/reminders/$id');
  }

  List<Map<String, dynamic>> _items(dynamic data) => (data as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
}
