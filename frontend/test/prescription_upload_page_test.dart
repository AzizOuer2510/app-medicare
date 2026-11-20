import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/features/medications/medication.dart';
import 'package:medicare/features/medications/prescription_upload_page.dart';

void main() {
  testWidgets('a new ordonnance needs a patient and a file before it can be sent',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PrescriptionUploadPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Avant l’envoi au patient'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Choisissez le patient et le fichier'), 200,
        scrollable: find.byType(Scrollable).first);
    final sendButton = find.ancestor(
      of: find.text('Choisissez le patient et le fichier'),
      matching: find.byType(FilledButton),
    );
    expect(sendButton, findsOneWidget);
    expect(tester.widget<FilledButton>(sendButton).onPressed, isNull);
  });

  testWidgets('existing ordonnance exposes the patient planning prefill action',
      (tester) async {
    final prescription = Prescription(
      id: 12,
      patientId: 7,
      patientName: 'Alice Martin',
      doctorId: 2,
      doctorName: 'Dr. Martin',
      prescriptionDate: DateTime(2026, 11, 15),
      medicationIds: const [],
      hasDocument: true,
      documentName: 'ordonnance.pdf',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PrescriptionUploadPage(existingPrescription: prescription),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Préremplir le planning de votre patient'), findsOneWidget);
    expect(find.text('Patient : Alice Martin'), findsOneWidget);
    expect(find.text('Nom complet du patient'), findsNothing);
    expect(find.text('Choisir un fichier'), findsNothing);
  });
}
