import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/features/medications/medication.dart';
import 'package:medicare/features/medications/medication_card.dart';

void main() {
  testWidgets('Medication card exposes status and low stock warning',
      (tester) async {
    final medication = Medication.fromJson({
      'id': 7,
      'name': 'Traitement quotidien',
      'status': 'active',
      'reminderTimes': ['08:30:00'],
      'currentQuantity': 2,
      'quantityUnit': 'comprimés',
      'lowStockThreshold': 3,
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MedicationCard(
          medication: medication,
          onEdit: () {},
          onDelete: () {},
          onHistory: () {},
          onSchedule: () {},
          onStock: () {},
        ),
      ),
    ));

    expect(find.text('Traitement quotidien'), findsOneWidget);
    expect(find.text('État : En cours'), findsOneWidget);
    expect(find.textContaining('Stock faible'), findsOneWidget);
    expect(find.textContaining('Prochaine prise'), findsOneWidget);
  });

  testWidgets('Patient medication card is read-only', (tester) async {
    final medication = Medication.fromJson({
      'id': 8,
      'name': 'Traitement patient',
      'status': 'active',
      'reminderTimes': ['08:30:00'],
      'currentQuantity': 2,
      'quantityUnit': 'comprimés',
      'lowStockThreshold': 3,
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MedicationCard(
          medication: medication,
          onEdit: () {},
          onDelete: () {},
          onHistory: () {},
          onSchedule: () {},
          onStock: () {},
          readOnly: true,
        ),
      ),
    ));

    expect(find.text('Agenda'), findsOneWidget);
    expect(find.text('Prises'), findsNothing);
    expect(find.text('Gérer'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });
}
