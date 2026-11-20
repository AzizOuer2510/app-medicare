import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(ref.read(apiClientProvider)),
);

class DocumentRepository {
  DocumentRepository(this.client);
  final ApiClient client;

  Future<Map<String, dynamic>> analysis(int id, {bool start = false}) async {
    final path = '/documents/$id/analysis';
    final response = start
        ? await client.dio.post(path)
        : await client.dio.get(path);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> confirmAnalysis(int id, Map<String, dynamic> review) async {
    await client.dio.post('/documents/$id/analysis/confirm', data: review);
  }

  Future<List<Map<String, dynamic>>> documents({
    String? category,
    String? query,
    bool? favorite,
    String sort = 'recent',
    int? patientId,
  }) async {
    final response = await client.dio.get(
      '/documents',
      queryParameters: {
        if (patientId != null) 'patientId': patientId,
        if (category != null) 'category': category,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (favorite != null) 'favorite': favorite,
        'sort': sort,
      },
    );
    return (response.data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> overview() async {
    final response = await client.dio.get('/documents/overview');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> shareWithDoctor(int id, bool enabled, {int? doctorId}) async {
    await client.dio.put(
      '/documents/$id/doctor',
      queryParameters: {
        'enabled': enabled,
        if (doctorId != null) 'doctorId': doctorId,
      },
    );
  }

  Future<void> favorite(int id, bool favorite) async {
    await client.dio.patch(
      '/documents/$id/favorite',
      data: {'favorite': favorite},
    );
  }

  Future<void> update(int id, Map<String, dynamic> data) async {
    await client.dio.put('/documents/$id', data: data);
  }

  Future<void> upload({
    required String title,
    required String category,
    required String description,
    required String filename,
    required Uint8List bytes,
    int? patientId,
    int? doctorId,
    ProgressCallback? onSendProgress,
  }) async {
    await client.dio.post(
      '/documents',
      data: FormData.fromMap({
        'title': title,
        'category': category,
        'description': description,
        if (doctorId != null) 'doctorId': doctorId,
        if (patientId != null) 'patientId': patientId,
        'file': MultipartFile.fromBytes(bytes, filename: filename),
      }),
      options: Options(contentType: 'multipart/form-data'),
      onSendProgress: onSendProgress,
    );
  }

  Future<Uint8List> content(int id) async {
    final response = await client.dio.get<List<int>>(
      '/documents/$id/content',
      queryParameters: {'download': true},
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<void> delete(int id) async {
    await client.dio.delete('/documents/$id');
  }

  Future<List<Map<String, dynamic>>> shares(int documentId) async {
    final response = await client.dio.get('/documents/$documentId/shares');
    return (response.data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createShare(
    int documentId, {
    required int durationMinutes,
    required String label,
  }) async {
    final response = await client.dio.post(
      '/documents/$documentId/shares',
      data: {'durationMinutes': durationMinutes, 'label': label},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> revokeShare(int documentId, int shareId) async {
    await client.dio.patch('/documents/$documentId/shares/$shareId/revoke');
  }

  Future<List<Map<String, dynamic>>> shareAccesses(
    int documentId,
    int shareId,
  ) async {
    final response = await client.dio.get(
      '/documents/$documentId/shares/$shareId/accesses',
    );
    return (response.data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }
}
