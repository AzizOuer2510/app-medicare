import 'package:flutter_test/flutter_test.dart';
import 'package:medicare/features/medications/medication.dart';

void main() {
  test('Medication date range rejects an end date before the start date', () {
    expect(
      medicationDateRangeError(
        DateTime(2026, 10, 29),
        DateTime(2026, 10, 28),
      ),
      isNotNull,
    );
    expect(
      medicationDateRangeError(
        DateTime(2026, 10, 28, 23),
        DateTime(2026, 10, 28),
      ),
      isNull,
    );
  });

  test('Medication accepts extended backend DTO and computes low stock', () {
    final medication = Medication.fromJson({
      'id': 42,
      'name': 'Vitamine',
      'pharmaceuticalForm': 'Gélule',
      'notes': 'Avec de l’eau',
      'unitsPerDose': 2,
      'weekdays': ['MONDAY', 'WEDNESDAY', 'SUNDAY'],
      'status': 'SUSPENDED',
      'remindersEnabled': false,
      'stockQuantity': '4',
      'stockUnit': 'gélules',
      'lowStockThreshold': 5,
      'packageQuantity': 30,
    });

    expect(medication.id, 42);
    expect(medication.pharmaceuticalForm, 'Gélule');
    expect(medication.unitsPerDose, 2);
    expect(medication.weekdays, [1, 3, 7]);
    expect(medication.remindersEnabled, isFalse);
    expect(medication.currentQuantity, 4);
    expect(medication.status, 'suspended');
    expect(medication.weekdays, [1, 3, 7]);
    expect(medication.isLowStock, isTrue);
  });

  test('Reminder normalizes legacy taken and new status DTOs', () {
    final taken = MedicationReminder.fromJson({
      'id': 1,
      'medicationId': 2,
      'date': '2026-10-27',
      'time': '08:00:00',
      'taken': true,
    });
    final missed = MedicationReminder.fromJson({
      'id': 2,
      'medicationId': 2,
      'date': '2026-10-27',
      'time': '12:00',
      'status': 'missed',
    });

    expect(taken.status, 'taken');
    expect(taken.taken, isTrue);
    expect(missed.status, 'missed');
    expect(missed.taken, isFalse);
  });

  test('Unconfigured zero stock threshold does not show a low-stock warning',
      () {
    final medication = Medication.fromJson({
      'id': 7,
      'name': 'Sans suivi de seuil',
      'stockQuantity': 0,
      'lowStockThreshold': 0,
    });

    expect(medication.isLowStock, isFalse);
  });
}
