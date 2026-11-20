import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/core/network/api_client.dart';
import 'package:medicare/core/providers.dart';
import 'package:medicare/features/auth/auth_user.dart';
import 'package:medicare/features/auth/authentication_state.dart';
import 'package:flutter/material.dart';
import 'package:medicare/features/medications/medication_form_page.dart';
import 'package:medicare/main.dart';

import 'widget_test.dart' as base;

/// Réponses réelles du serveur pour le patient Amine Trabelsi après que le Dr Ahmed
/// a ajouté un médicament à son planning et lui a envoyé une ordonnance.
const _medications = '''
[{"id":6,"name":"Amoxicilline","dosage":"500 mg","frequency":"1 fois / jour","frequencyPerDay":1,
"instructions":null,"startDate":null,"endDate":null,"reminderTimes":["08:00:00"],"prescriptionId":7,
"pharmaceuticalForm":"Comprimé","notes":null,"unitsPerDose":null,
"weekdays":["MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY","SUNDAY"],"status":"ACTIVE",
"remindersEnabled":true,"stockTracked":false,"stockQuantity":0.0,"stockUnit":null,"lowStockThreshold":0.0,
"packageQuantity":null,"lowStock":false,"patientId":7,"patientName":"Amine Trabelsi"}]
''';

const _today = '''
[{"id":31,"medicationId":6,"medicationName":"Amoxicilline","date":"2026-11-20","time":"08:00:00",
"status":"PENDING","taken":false}]
''';

const _overdue = '''
[{"id":29,"medicationId":6,"medicationName":"Amoxicilline","date":"2026-11-18","time":"08:00:00",
"status":"PENDING","taken":false}]
''';

const _documents = '''
[{"id":1,"title":"Ordonnance du 19/11/2026 – Dr Ahmed","category":"PRESCRIPTION",
"description":"Ordonnance envoyée par Dr Ahmed","filename":"ordonnance.pdf","contentType":"application/pdf",
"size":1200,"uploadedAt":"2026-11-19T22:33:51Z","favorite":false,"ownerId":7,"ownerName":"Amine Trabelsi",
"sharedDoctorId":1,"sharedDoctorName":"Dr Ahmed"}]
''';
const _overview = '''
{"total":1,"favorites":0,"prescriptions":1,"analyses":0,"totalBytes":1200,"role":"USER","viewerId":7}
''';

void main() {
  testWidgets('Le patient voit le médicament ajouté par son médecin', (tester) async {
    final storage = base.MemoryTokenStorage()..token = 'patient-token';
    final repository = base.FakeAuthRepository()
      ..currentUser = const AuthUser(
          id: 7, fullName: 'Amine Trabelsi', email: 'patient2@medicare.com', role: 'USER');
    final api = ApiClient(storage)
      ..dio.httpClientAdapter = base.StaticResponseAdapter('[]', responses: {
        '/medications': _medications,
        '/medications/today': _today,
        '/medications/reminders/31/taken': '{"id":31,"status":"TAKEN"}',
        '/medications/intakes': _overdue,
        '/medications/reminders/29/missed': '{"id":29,"status":"MISSED"}',
        '/documents': _documents,
        '/documents/overview': _overview,
      });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        tokenStorageProvider.overrideWithValue(storage),
        authRepositoryProvider.overrideWithValue(repository),
        apiClientProvider.overrideWithValue(api),
      ],
      child: const MediCareApp(),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Médicaments').first);
    await tester.tap(find.text('Médicaments').first);
    await tester.pumpAndSettle();
    expect(find.text('Impossible de charger les médicaments.'), findsNothing);

    // Le patient coche sa prise de 08:00 : elle est envoyée au serveur.
    expect(find.text('Mes prises'), findsOneWidget);
    // Une prise passée restée sans réponse peut encore être indiquée « Non pris ».
    expect(find.text('En attente de réponse (1)'), findsOneWidget);
    expect(find.text('Prévu le mer. 18/11 à 08:00'), findsOneWidget);
    await tester.ensureVisible(find.text('Non pris').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Non pris').first);
    await tester.pumpAndSettle();
    expect(find.text('Amoxicilline (08:00) : prise non faite enregistrée.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('À prendre à 08:00'), findsOneWidget);
    await tester.ensureVisible(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    expect(find.text('Amoxicilline (08:00) : prise enregistrée.'), findsOneWidget);

    // Le médicament ajouté par le médecin est dans « Mes traitements ».
    await tester.scrollUntilVisible(find.text('1 médicament'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('1 médicament'), findsOneWidget);
    expect(find.text('Amoxicilline'), findsWidgets);

    // Les ordonnances envoyées par le médecin sont accessibles depuis Médicaments.
    await tester.tap(find.byTooltip('Mes ordonnances'));
    await tester.pumpAndSettle();
    expect(find.text('Ordonnance du 19/11/2026 – Dr Ahmed'), findsWidgets);
  });

  testWidgets('Ajout manuel par le médecin : formulaire sans état, consignes, notes ni stock',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: MedicationFormPage(patientId: 7, patientName: 'Amine Trabelsi'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Planning de Amine Trabelsi'), findsOneWidget);
    for (final hidden in ['État du traitement', 'Instructions', 'Notes', 'Stock',
        'Quantité actuelle', 'Seuil de stock faible', 'Quantité par boîte']) {
      expect(find.text(hidden), findsNothing, reason: hidden);
    }
  });
}
