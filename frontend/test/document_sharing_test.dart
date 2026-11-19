import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/features/documents/pages/document_shares_page.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'care_workspace_test.dart';
import 'm5_test_fixtures.dart' show tapVisible, enterVisible;

class ShareRepository extends LibraryRepository {
  final shared = <Map<String, dynamic>>[];
  final durations = <int>[];
  final revoked = <int>[];
  bool failCreate = false, failHistory = false;
  Completer<List<Map<String, dynamic>>>? delayedList;
  @override
  Future<List<Map<String, dynamic>>> shares(int documentId) async {
    if (delayedList != null) return delayedList!.future;
    return shared.map((share) => Map<String, dynamic>.from(share)).toList();
  }

  @override
  Future<Map<String, dynamic>> createShare(
    int documentId, {
    required int durationMinutes,
    required String label,
  }) async {
    if (failCreate) {
      throw DioException(
        requestOptions: RequestOptions(),
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 409,
          data: {'message': 'Révoquez un partage actif avant de continuer.'},
        ),
      );
    }
    durations.add(durationMinutes);
    final now = DateTime.now().toUtc();
    final share = <String, dynamic>{
      'id': shared.length + 1,
      'label': label.isEmpty ? 'Consultation' : label,
      'createdAt': now.toIso8601String(),
      'expiresAt': now
          .add(Duration(minutes: durationMinutes))
          .toIso8601String(),
      'status': 'ACTIVE',
      'accessCount': 0,
      'lastAccessAt': null,
    };
    shared.insert(0, share);
    return {
      'share': Map<String, dynamic>.from(share),
      'url': 'https://medicare.example/share/document#${'x' * 43}',
      'pin': '012345',
    };
  }

  @override
  Future<void> revokeShare(int documentId, int shareId) async {
    revoked.add(shareId);
    shared.firstWhere((share) => share['id'] == shareId)['status'] = 'REVOKED';
  }

  @override
  Future<List<Map<String, dynamic>>> shareAccesses(
    int documentId,
    int shareId,
  ) async {
    if (failHistory) throw StateError('Offline');
    return [
      {'id': 1, 'accessedAt': DateTime.now().toUtc().toIso8601String()},
    ];
  }
}

Future<void> showSharing(
  WidgetTester tester,
  ShareRepository repository,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DocumentSharesPage(
        document: repository.items.first,
        repository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Document menu opens sharing; QR contains only the link and preserves a leading zero in the PIN',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      final repository = ShareRepository();
      await showLibrary(tester, repository);
      await tapVisible(tester, find.byTooltip('Actions du document').first);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Partager par QR code'));
      await tester.pumpAndSettle();
      await enterVisible(
        tester,
        find.byKey(const ValueKey('share-label')),
        'Consultation démo',
      );
      await tapVisible(tester, find.text('1 heure'));
      await tapVisible(tester, find.byKey(const ValueKey('create-share')));
      await tester.pumpAndSettle();
      expect(repository.durations, [60]);
      expect(find.byType(QrImageView), findsOneWidget);
      final expectedUrl = 'https://medicare.example/share/document#${'x' * 43}';
      expect(find.text('012345'), findsOneWidget);
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tapVisible(tester, find.text('Copier le lien'));
      await tapVisible(tester, find.text('Copier le PIN'));
      expect(copied, [expectedUrl, '012345']);
      expect(copied.first, isNot(contains('012345')));
    },
  );

  testWidgets(
    'Revocation requires confirmation and removes the displayed QR and PIN',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      final repository = ShareRepository();
      await showSharing(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('create-share')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Révoquer cet accès'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conserver'));
      await tester.pumpAndSettle();
      expect(repository.revoked, isEmpty);
      expect(find.byType(QrImageView), findsOneWidget);
      await tapVisible(tester, find.text('Révoquer cet accès'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Révoquer'));
      await tester.pumpAndSettle();
      expect(repository.revoked, [1]);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('012345'), findsNothing);
      expect(find.text('Révoqué'), findsOneWidget);
    },
  );

  testWidgets('History supports retry and create errors remain visible', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final repository = ShareRepository();
    await repository.createShare(
      1,
      durationMinutes: 15,
      label: 'Historique démo',
    );
    await showSharing(tester, repository);
    repository.failCreate = true;
    await tapVisible(tester, find.byKey(const ValueKey('create-share')));
    await tester.pumpAndSettle();
    expect(
      find.text('Révoquez un partage actif avant de continuer.'),
      findsOneWidget,
    );
    expect(find.byType(QrImageView), findsNothing);
    repository.failHistory = true;
    await tapVisible(tester, find.text('Historique'));
    await tester.pumpAndSettle();
    expect(find.text('Impossible de charger l’historique.'), findsOneWidget);
    repository.failHistory = false;
    final retry = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        )
        .first;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('Document consulté'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Expired or revoked shares cannot display an active QR after refresh',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      final repository = ShareRepository();
      await showSharing(tester, repository);
      await tapVisible(tester, find.byKey(const ValueKey('create-share')));
      await tester.pumpAndSettle();
      repository.shared.first['expiresAt'] = DateTime.now()
          .subtract(const Duration(minutes: 1))
          .toIso8601String();
      await tester.tap(find.byTooltip('Actualiser les partages'));
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Expiré'), findsOneWidget);
      expect(find.byKey(const ValueKey('revoke-share-1')), findsNothing);
    },
  );

  testWidgets('A stale list response cannot discard a newly generated QR', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final repository = ShareRepository();
    await showSharing(tester, repository);
    repository.delayedList = Completer();
    await tester.tap(find.byTooltip('Actualiser les partages'));
    await tester.pump();
    await tapVisible(tester, find.byKey(const ValueKey('create-share')));
    await tester.pumpAndSettle();
    repository.delayedList!.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Actif'), findsOneWidget);
  });

  testWidgets('Sharing form and generated QR fit phone and desktop widths', (
    tester,
  ) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final size in [const Size(360, 800), const Size(1280, 1000)]) {
      tester.view.physicalSize = size;
      final repository = ShareRepository();
      await showSharing(tester, repository);
      await enterVisible(
        tester,
        find.byKey(const ValueKey('share-label')),
        'Une consultation avec un titre particulièrement long pour vérifier le partage',
      );
      await tapVisible(tester, find.text('24 heures'));
      await tapVisible(tester, find.byKey(const ValueKey('create-share')));
      await tester.pumpAndSettle();
      expect(repository.durations, [1440]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
