import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/features/medications/medication.dart';
import 'package:medicare/features/medications/medication_assistant.dart';

void main() {
  const assistant = MedicationAssistant();

  final medication = Medication.fromJson({
    'id': 8,
    'name': 'Vitamine C',
    'dosage': '500 mg',
    'frequency': '1 fois / jour',
    'reminderTimes': ['08:30:00'],
    'startDate': '2026-10-28',
    'stockTracked': true,
    'stockQuantity': 4,
    'stockUnit': 'comprimés',
    'lowStockThreshold': 5,
  });

  test('finds registered medication schedule locally', () {
    final response = assistant.answer(
      'Quels sont les horaires de Vitamine C ?',
      medications: [medication],
      prescriptions: const [],
    );

    expect(response, contains('08:30'));
    expect(response, contains('Vitamine C'));
  });

  test('explains prescription fields without interpreting medical advice', () {
    final response = assistant.answer(
      'Que signifie le champ posologie ?',
      medications: const [],
      prescriptions: const [],
    );

    expect(response, contains('reprend les indications'));
    expect(response, contains('ne peux pas déterminer'));
  });

  test('refuses requests to change a dose', () {
    final response = assistant.answer(
      'Dois-je augmenter la dose de Vitamine C ?',
      medications: [medication],
      prescriptions: const [],
    );

    expect(response, contains('Je ne peux pas recommander une dose'));
    expect(response, contains('médecin ou à votre pharmacien'));
  });

  test('reports missing prescription data clearly', () {
    final response = assistant.answer(
      'Quelles prescriptions sont enregistrées ?',
      medications: const [],
      prescriptions: const [],
    );

    expect(response, contains('Aucune prescription'));
  });

  test('reports saved stock and configured low-stock threshold', () {
    final response = assistant.answer(
      'Quel est le stock de Vitamine C ?',
      medications: [medication],
      prescriptions: const [],
    );

    expect(response, contains('4 comprimés'));
    expect(response, contains('seuil configuré est atteint'));
  });
}
