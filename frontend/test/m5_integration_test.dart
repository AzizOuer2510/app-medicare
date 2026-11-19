import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/core/network/api_client.dart';
import 'package:medicare/core/storage/token_storage.dart';
import 'package:medicare/features/auth/authentication_state.dart';
import 'package:medicare/features/auth/auth_user.dart';
import 'package:medicare/features/notifications/pages/notification_admin_page.dart';
import 'package:medicare/features/notifications/providers/notification_repository.dart';
import 'package:medicare/features/notifications/widgets/notification_badge.dart';

class _Authentication extends AuthenticationController {
  _Authentication(super.ref, this.user);
  final AuthUser user;
  @override
  Future<void> restoreSession() async => state = AsyncValue.data(user);
  void clear() => state = const AsyncValue.data(null);
}

AuthUser _user(String role) =>
    AuthUser(id: 1, fullName: 'Test', email: 'test@example.test', role: role);

class _Repository extends NotificationRepository {
  _Repository() : super(ApiClient(TokenStorage()));
  int adminRequests = 0, unread = 3;
  Map<String, dynamic>? saved;
  int? savedId, deletedId;
  @override
  Future<List<Map<String, dynamic>>> adminNotifications({int? userId}) async {
    adminRequests++;
    return [
      {
        'userId': 2,
        'recipientName': 'Médecin Test',
        'notification': {
          'id': 10,
          'title': 'Information',
          'message': 'Texte',
          'type': 'GENERAL',
          'read': false,
        },
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> recipients() async => [
    {'id': 1, 'name': 'Patient Test', 'role': 'USER'},
    {'id': 2, 'name': 'Médecin Test', 'role': 'DOCTOR'},
  ];
  @override
  Future<void> saveNotification(Map<String, dynamic> data, {int? id}) async {
    saved = data;
    savedId = id;
  }

  @override
  Future<void> deleteNotification(int id) async => deletedId = id;
  @override
  Future<int> unreadCount() async => unread;
}

Widget _app(String role, _Repository repository, Widget page) => ProviderScope(
  overrides: [
    authenticationStateProvider.overrideWith(
      (ref) => _Authentication(ref, _user(role)),
    ),
    notificationRepositoryProvider.overrideWithValue(repository),
  ],
  child: MaterialApp(home: page),
);

void main() {
  testWidgets(
    'patient et médecin ne chargent pas les données de l’administration',
    (tester) async {
      for (final role in ['USER', 'DOCTOR']) {
        final repository = _Repository();
        await tester.pumpWidget(
          _app(role, repository, const NotificationAdminPage()),
        );
        await tester.pumpAndSettle();
        expect(find.text('Accès réservé aux administrateurs.'), findsOneWidget);
        expect(repository.adminRequests, 0);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'admin crée pour un médecin, modifie la lecture et confirme la suppression',
    (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(
        _app('ADMIN', repository, const NotificationAdminPage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Créer une notification'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Médecin Test (DOCTOR)').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Message au médecin',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Votre document est disponible.',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(repository.saved?['userId'], 2);
      expect(repository.saved?['message'], 'Votre document est disponible.');
      expect(repository.savedId, isNull);
      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(repository.saved?['read'], true);
      expect(repository.savedId, 10);
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();
      expect(repository.deletedId, isNull);
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();
      expect(repository.deletedId, 10);
    },
  );

  testWidgets('le badge affiche les non lues et se vide à la déconnexion', (
    tester,
  ) async {
    final repository = _Repository();
    await tester.pumpWidget(
      _app('USER', repository, const Scaffold(body: NotificationBadgeButton())),
    );
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    final element = tester.element(find.byType(NotificationBadgeButton));
    final container = ProviderScope.containerOf(element);
    (container.read(authenticationStateProvider.notifier) as _Authentication)
        .clear();
    await tester.pumpAndSettle();
    expect(find.text('3'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
