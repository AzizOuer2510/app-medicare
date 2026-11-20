import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/core/network/api_client.dart';
import 'package:medicare/core/storage/token_storage.dart';
import 'package:medicare/features/documents/pages/documents_page.dart';
import 'package:medicare/features/documents/providers/document_repository.dart';
import 'package:medicare/features/notifications/pages/notifications_page.dart';
import 'package:medicare/features/notifications/providers/notification_repository.dart';
import 'm5_test_fixtures.dart' as fixtures;

class ActivityRepository extends fixtures.DemoNotifications {
  final actions = <String>[];
  @override
  Future<void> markRead(int id) async {
    items.firstWhere((item) => item['id'] == id)['read'] = true;
  }

  @override
  Future<void> markUnread(int id) async {
    items.firstWhere((item) => item['id'] == id)['read'] = false;
  }

  @override
  Future<void> archive(int id, {required bool archived}) async {
    actions.add('archive:$id:$archived');
    items.firstWhere((item) => item['id'] == id)['archived'] = archived;
  }

  @override
  Future<void> snooze(int id, int minutes) async {
    actions.add('snooze:$id:$minutes');
    final item = scheduled.firstWhere((item) => item['id'] == id);
    item['scheduledFor'] = DateTime.parse(item['scheduledFor'] as String)
        .add(Duration(minutes: minutes))
        .toIso8601String();
  }
}

class LibraryRepository extends DocumentRepository {
  LibraryRepository() : super(ApiClient(TokenStorage()));
  final items = <Map<String, dynamic>>[
    {
      'id': 1,
      'title': 'Ordonnance Alpha',
      'category': 'PRESCRIPTION',
      'description': 'Données fictives',
      'filename': 'ordonnance.pdf',
      'contentType': 'application/pdf',
      'size': 1024,
      'uploadedAt': '2026-10-30T10:00:00Z',
      'favorite': false
    },
    {
      'id': 2,
      'title': 'Analyse Beta',
      'category': 'ANALYSIS',
      'description': 'Exemple fictif',
      'filename': 'analyse.png',
      'contentType': 'image/png',
      'size': 2048,
      'uploadedAt': '2026-10-29T10:00:00Z',
      'favorite': false
    },
    {
      'id': 3,
      'title': 'Compte rendu',
      'category': 'OTHER',
      'description': '',
      'filename': 'compte-rendu.pdf',
      'contentType': 'application/pdf',
      'size': 512,
      'uploadedAt': '2026-10-28T10:00:00Z',
      'favorite': true
    },
  ];
  final queries = <Map<String, dynamic>>[];
  int contentReads = 0;
  @override
  Future<List<Map<String, dynamic>>> documents(
      {String? category,
      String? query,
      bool? favorite,
      String sort = 'recent',
      int? patientId}) async {
    queries.add(
        {'category': category, 'q': query, 'favorite': favorite, 'sort': sort});
    final result = items
        .where((item) =>
            (category == null || item['category'] == category) &&
            (query == null ||
                '${item['title']} ${item['description']} ${item['filename']}'
                    .toLowerCase()
                    .contains(query.toLowerCase())) &&
            (favorite == null || item['favorite'] == favorite))
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    result.sort((a, b) => sort == 'name'
        ? (a['title'] as String).compareTo(b['title'] as String)
        : sort == 'size'
            ? (b['size'] as int).compareTo(a['size'] as int)
            : sort == 'oldest'
                ? (a['uploadedAt'] as String)
                    .compareTo(b['uploadedAt'] as String)
                : (b['uploadedAt'] as String)
                    .compareTo(a['uploadedAt'] as String));
    return result;
  }

  @override
  Future<Map<String, dynamic>> overview() async => {
        'total': items.length,
        'favorites': items.where((item) => item['favorite'] == true).length,
        'prescriptions':
            items.where((item) => item['category'] == 'PRESCRIPTION').length,
        'analyses':
            items.where((item) => item['category'] == 'ANALYSIS').length,
        'totalBytes':
            items.fold<int>(0, (sum, item) => sum + (item['size'] as int)),
      };
  @override
  Future<void> favorite(int id, bool favorite) async {
    items.firstWhere((item) => item['id'] == id)['favorite'] = favorite;
  }

  @override
  Future<void> update(int id, Map<String, dynamic> data) async {
    items.firstWhere((item) => item['id'] == id).addAll(data);
  }

  @override
  Future<Uint8List> content(int id) async {
    contentReads++;
    return base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=');
  }
}

Future<void> showLibrary(
    WidgetTester tester, LibraryRepository repository) async {
  await tester.pumpWidget(ProviderScope(
      key: const ValueKey('library-test'),
      overrides: [documentRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: DocumentsPage())));
  await tester.pumpAndSettle();
}

Future<void> showActivity(
    WidgetTester tester, ActivityRepository repository) async {
  await tester.pumpWidget(ProviderScope(
      key: const ValueKey('activity-test'),
      overrides: [notificationRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: NotificationsPage())));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Notifications can be marked unread, archived, and restored',
      (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final repository = ActivityRepository();
    await showActivity(tester, repository);
    expect(find.text('Créer'), findsNothing);
    await fixtures.tapVisible(tester, find.text('Marquer non lue'));
    await tester.pumpAndSettle();
    expect(repository.items[1]['read'], false);
    await fixtures.tapVisible(
        tester, find.byTooltip('Archiver la notification').first);
    await tester.pumpAndSettle();
    expect(repository.items.first['archived'], true);
    expect(find.text('Ordonnance disponible'), findsNothing);
    await fixtures.tapVisible(
        tester, find.byKey(const ValueKey('notification-archive-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Ordonnance disponible'), findsOneWidget);
    await fixtures.tapVisible(
        tester, find.byTooltip('Restaurer la notification'));
    await tester.pumpAndSettle();
    expect(repository.items.first['archived'], false);
    expect(repository.actions, ['archive:1:true', 'archive:1:false']);
  });

  testWidgets('A pending reminder can be postponed from its card',
      (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final repository = ActivityRepository();
    final original =
        DateTime.parse(repository.scheduled.first['scheduledFor'] as String);
    await showActivity(tester, repository);
    await fixtures.tapVisible(tester, find.text('Rappels'));
    await tester.pumpAndSettle();
    await fixtures.tapVisible(tester, find.text('Reporter de 15 min'));
    await tester.pumpAndSettle();
    expect(repository.actions, ['snooze:1:15']);
    expect(DateTime.parse(repository.scheduled.first['scheduledFor'] as String),
        original.add(const Duration(minutes: 15)));
  });

  testWidgets(
      'Document search/category/favorites combine and metadata can be edited',
      (tester) async {
    final repository = LibraryRepository();
    await showLibrary(tester, repository);
    await fixtures.tapVisible(
        tester, find.byTooltip('Ajouter aux favoris').first);
    await tester.pumpAndSettle();
    expect(repository.items.first['favorite'], true);
    await fixtures.tapVisible(
        tester, find.byKey(const ValueKey('document-favorites-filter')));
    await tester.pumpAndSettle();
    await fixtures.enterVisible(
        tester, find.byKey(const ValueKey('document-search')), 'Alpha');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Ordonnance Alpha'), findsOneWidget);
    expect(find.text('Analyse Beta'), findsNothing);
    expect(repository.queries.last['favorite'], true);
    await fixtures.tapVisible(tester, find.byTooltip('Actions du document'));
    await tester.pumpAndSettle();
    await fixtures.tapVisible(tester, find.text('Modifier les informations'));
    await tester.pumpAndSettle();
    await fixtures.enterVisible(
        tester,
        find.byKey(const ValueKey('document-title')),
        'Ordonnance Alpha modifiée');
    await fixtures.enterVisible(tester,
        find.byKey(const ValueKey('document-description')), 'Note modifiée');
    await fixtures.tapVisible(tester, find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(repository.items.first['title'], 'Ordonnance Alpha modifiée');
    expect(repository.items.first['description'], 'Note modifiée');
    expect(repository.items.first['filename'], 'ordonnance.pdf');
    await fixtures.tapVisible(tester, find.text('Réinitialiser'));
    await tester.pumpAndSettle();
    await fixtures.tapVisible(
        tester, find.byKey(const ValueKey('document-category-ANALYSIS')));
    await tester.pumpAndSettle();
    expect(find.text('Analyse Beta'), findsOneWidget);
    expect(find.text('Ordonnance Alpha modifiée'), findsNothing);
  });

  testWidgets('The document image preview loads protected content',
      (tester) async {
    final repository = LibraryRepository();
    await showLibrary(tester, repository);
    await fixtures.tapVisible(tester, find.text('Analyse Beta'));
    await tester.pumpAndSettle();
    expect(repository.contentReads, 1);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byTooltip('Télécharger'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'The redesigned module fits phone and wide screens including long titles',
      (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final size in [const Size(360, 800), const Size(1280, 900)]) {
      tester.view.physicalSize = size;
      final repository = LibraryRepository();
      repository.items.first['title'] =
          'Ordonnance médicale avec un titre très long pour vérifier la bibliothèque';
      await showLibrary(tester, repository);
      await fixtures.tapVisible(tester, find.byTooltip('Vue liste'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await showActivity(tester, ActivityRepository());
      await fixtures.tapVisible(tester, find.text('Rappels'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
