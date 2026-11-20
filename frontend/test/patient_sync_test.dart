import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/core/network/api_client.dart';
import 'package:medicare/core/providers.dart';
import 'package:medicare/features/auth/auth_user.dart';
import 'package:medicare/features/auth/authentication_state.dart';
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
    expect(find.text('Amoxicilline'), findsOneWidget);
    expect(find.text('1 médicament'), findsOneWidget);

    // Les ordonnances envoyées par le médecin sont accessibles depuis Médicaments.
    await tester.tap(find.byTooltip('Mes ordonnances'));
    await tester.pumpAndSettle();
    expect(find.text('Ordonnance du 19/11/2026 – Dr Ahmed'), findsWidgets);
  });
}
