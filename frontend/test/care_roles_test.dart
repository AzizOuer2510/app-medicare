import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/features/documents/widgets/document_card.dart';
import 'package:medicare/features/documents/widgets/document_upload_form.dart';
import 'package:medicare/features/notifications/widgets/activity_cards.dart';
import 'package:medicare/features/notifications/widgets/care_contacts.dart';
import 'm5_test_fixtures.dart' show DemoNotifications;

class PatientContacts extends DemoNotifications {
  @override
  Future<List<Map<String, dynamic>>> contacts() async => [];
  @override
  Future<Map<String, dynamic>> addPatient(String email) async {
    expect(email, 'sara@example.test');
    return {'id': 7, 'name': 'Sara'};
  }
}

void main() {
  testWidgets('le dépôt personnel propose aussi les deux médecins rattachés', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentUploadForm(
            loadDoctors: () async => [
              {'id': 5, 'name': 'Dr Martin'},
              {'id': 9, 'name': 'Dr Leroy'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('document-recipient'));
    expect(tester.state<FormFieldState<int>>(field).value, 0);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('Dr Martin').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Dr Leroy').hitTestable());
    await tester.pumpAndSettle();
    expect(tester.state<FormFieldState<int>>(field).value, 9);
  });
  testWidgets('ajouter un patient le sélectionne pour le dépôt en cours', (
    tester,
  ) async {
    final repository = PatientContacts();
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await pickPatient(context, repository, canAdd: true);
              },
              child: const Text('Déposer une ordonnance'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Déposer une ordonnance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un patient'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sara@example.test');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(selected?['id'], 7);
  });
  const followUp = {
    'title': 'Suivi',
    'message': 'Apporter le bilan',
    'scheduledFor': '2030-12-14T18:00:00Z',
    'instructionAt': '2030-12-15T10:00:00Z',
    'status': 'PENDING',
    'type': 'GENERAL',
    'authorId': 2,
    'authorName': 'Dr Martin',
    'recipientName': 'Sara',
  };
  testWidgets('le patient règle son alerte et le médecin modifie la consigne', (
    tester,
  ) async {
    for (final patient in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderCard(
              item: followUp,
              busy: false,
              onAction: (_) {},
              recipient: patient,
              manage: !patient,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Actions du rappel'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choisir l’heure de mon alerte'),
        patient ? findsOneWidget : findsNothing,
      );
      expect(find.text('Modifier'), patient ? findsNothing : findsOneWidget);
      expect(find.text('Supprimer'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }
  });
  testWidgets('le médecin peut analyser le fichier partagé et le lire', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentCard(
            document: const {
              'title': 'Analyse',
              'category': 'ANALYSIS',
              'contentType': 'application/pdf',
              'size': 123,
              'ownerName': 'Sara',
              'uploadedAt': '2030-12-15T10:00:00Z',
              'filename': 'analyse.pdf',
            },
            compact: true,
            manage: false,
            showOwner: true,
            busy: false,
            onOpen: () {},
            onFavorite: () {},
            onAction: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Actions du document'));
    await tester.pumpAndSettle();
    expect(find.text('Analyser avec l’IA'), findsOneWidget);
    expect(find.text('Télécharger'), findsOneWidget);
    expect(find.text('Partager par QR code'), findsNothing);
    expect(find.text('Supprimer'), findsNothing);
  });
}
