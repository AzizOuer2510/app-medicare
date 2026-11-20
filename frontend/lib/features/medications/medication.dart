String? medicationDateRangeError(DateTime? start, DateTime? end) {
  if (start == null || end == null) return null;
  final startDay = DateTime(start.year, start.month, start.day);
  final endDay = DateTime(end.year, end.month, end.day);
  return endDay.isBefore(startDay)
      ? 'La date de fin doit être le même jour ou après la date de début.'
      : null;
}

class Medication {
  final int id;
  final String name;
  final String? dosage;
  final String? frequency;
  final int? frequencyPerDay;
  final String? instructions;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> reminderTimes;
  final int? prescriptionId;
  final String? pharmaceuticalForm;
  final String? notes;
  final num? unitsPerDose;
  final List<int> weekdays;
  final String status;
  final bool remindersEnabled;
  final bool stockTracked;
  final num? currentQuantity;
  final String? quantityUnit;
  final num? lowStockThreshold;
  final num? packageQuantity;

  /// Patient concerné (utile côté médecin, qui voit les plannings de plusieurs patients).
  final int? patientId;
  final String? patientName;

  const Medication({
    required this.id,
    required this.name,
    this.dosage,
    this.frequency,
    this.frequencyPerDay,
    this.instructions,
    this.startDate,
    this.endDate,
    this.reminderTimes = const [],
    this.prescriptionId,
    this.pharmaceuticalForm,
    this.notes,
    this.unitsPerDose,
    this.weekdays = const [],
    this.status = 'active',
    this.remindersEnabled = true,
    this.stockTracked = false,
    this.currentQuantity,
    this.quantityUnit,
    this.lowStockThreshold,
    this.packageQuantity,
    this.patientId,
    this.patientName,
  });

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: _number(json['id'])?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      dosage: json['dosage'] as String?,
      frequency: json['frequency'] as String?,
      frequencyPerDay: _number(json['frequencyPerDay'])?.toInt(),
      instructions: json['instructions'] as String?,
      startDate: _date(json['startDate']),
      endDate: _date(json['endDate']),
      reminderTimes: (json['reminderTimes'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList(),
      prescriptionId: _number(json['prescriptionId'])?.toInt(),
      pharmaceuticalForm:
          (json['pharmaceuticalForm'] ?? json['form'])?.toString(),
      notes: json['notes']?.toString(),
      unitsPerDose: _number(json['unitsPerDose']),
      weekdays:
          _list(json['weekdays']).map(_weekdayNumber).whereType<int>().toList(),
      status: json['status']?.toString().toLowerCase() ?? 'active',
      remindersEnabled: json['remindersEnabled'] != false,
      stockTracked: json['stockTracked'] as bool? ??
          (json['stockUnit'] != null ||
              json['quantityUnit'] != null ||
              (_number(json['stockQuantity'] ?? json['currentQuantity']) ?? 0) >
                  0 ||
              (_number(json['lowStockThreshold']) ?? 0) > 0),
      currentQuantity:
          _number(json['stockQuantity'] ?? json['currentQuantity']),
      quantityUnit: (json['stockUnit'] ?? json['quantityUnit'])?.toString(),
      lowStockThreshold: _number(json['lowStockThreshold']),
      packageQuantity: _number(json['packageQuantity']),
      patientId: _number(json['patientId'])?.toInt(),
      patientName: json['patientName']?.toString(),
    );
  }

  bool get isLowStock =>
      stockTracked &&
      currentQuantity != null &&
      lowStockThreshold != null &&
      lowStockThreshold! > 0 &&
      currentQuantity! <= lowStockThreshold!;

  static num? _number(dynamic value) {
    if (value is num) return value;
    return value == null ? null : num.tryParse(value.toString());
  }

  static int? _weekdayNumber(dynamic value) {
    final numeric = _number(value)?.toInt();
    if (numeric != null && numeric >= 1 && numeric <= 7) return numeric;
    const weekdays = {
      'MONDAY': 1,
      'TUESDAY': 2,
      'WEDNESDAY': 3,
      'THURSDAY': 4,
      'FRIDAY': 5,
      'SATURDAY': 6,
      'SUNDAY': 7,
    };
    return weekdays[value?.toString().toUpperCase()];
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  static List<dynamic> _list(dynamic value) =>
      value is List<dynamic> ? value : const [];
}

class MedicationReminder {
  final int id;
  final int medicationId;
  final String medicationName;
  final DateTime date;
  final String time;
  final bool taken;
  final DateTime? takenAt;
  final String status;
  final DateTime? snoozedUntil;

  const MedicationReminder({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.date,
    required this.time,
    required this.taken,
    this.takenAt,
    this.status = '',
    this.snoozedUntil,
  });

  factory MedicationReminder.fromJson(Map<String, dynamic> json) {
    final nestedMedication = json['medication'];
    final medication = nestedMedication is Map<String, dynamic>
        ? nestedMedication
        : const <String, dynamic>{};
    final rawStatus =
        (json['status'] ?? json['intakeStatus'])?.toString().toLowerCase();
    return MedicationReminder(
      id: Medication._number(
                  json['id'] ?? json['reminderId'] ?? json['intakeId'])
              ?.toInt() ??
          0,
      medicationId: Medication._number(
            json['medicationId'] ?? json['medicationID'] ?? medication['id'],
          )?.toInt() ??
          0,
      medicationName:
          (json['medicationName'] ?? medication['name'] ?? '').toString(),
      date: Medication._date(
            json['date'] ?? json['scheduledDate'] ?? json['dueDate'],
          ) ??
          DateTime.now(),
      time: (json['time'] ?? json['scheduledTime'] ?? '').toString(),
      taken: json['taken'] == true || rawStatus == 'taken',
      takenAt: Medication._date(json['takenAt']),
      status: rawStatus ?? (json['taken'] == true ? 'taken' : 'pending'),
      snoozedUntil: Medication._date(json['snoozedUntil']),
    );
  }
}

class Prescription {
  final int id;
  final int patientId;
  final String patientName;
  final int doctorId;
  final String doctorName;
  final String? diagnosis;
  final DateTime prescriptionDate;
  final String? notes;
  final List<int> medicationIds;
  final bool hasDocument;
  final String? documentName;

  const Prescription({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.doctorName,
    this.diagnosis,
    required this.prescriptionDate,
    this.notes,
    required this.medicationIds,
    this.hasDocument = false,
    this.documentName,
  });

  factory Prescription.fromJson(Map<String, dynamic> json) {
    return Prescription(
      id: (json['id'] as num).toInt(),
      patientId: (json['patientId'] as num).toInt(),
      patientName: json['patientName'] as String? ?? '',
      doctorId: (json['doctorId'] as num).toInt(),
      doctorName: json['doctorName'] as String? ?? '',
      diagnosis: json['diagnosis'] as String?,
      prescriptionDate: DateTime.parse(json['prescriptionDate'].toString()),
      notes: json['notes'] as String?,
      medicationIds: (json['medicationIds'] as List<dynamic>? ?? [])
          .map((value) => (value as num).toInt())
          .toList(),
      hasDocument: json['hasDocument'] as bool? ?? false,
      documentName: json['documentName'] as String?,
    );
  }
}

class PrescriptionMedicationSuggestion {
  final String? name;
  final String? dosage;
  final String? pharmaceuticalForm;
  final num? unitsPerDose;
  final int? frequencyPerDay;
  final String? instructions;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> reminderTimes;
  final List<int> weekdays;
  final List<String> warnings;

  const PrescriptionMedicationSuggestion({
    this.name,
    this.dosage,
    this.pharmaceuticalForm,
    this.unitsPerDose,
    this.frequencyPerDay,
    this.instructions,
    this.startDate,
    this.endDate,
    this.reminderTimes = const [],
    this.weekdays = const [],
    this.warnings = const [],
  });

  factory PrescriptionMedicationSuggestion.fromJson(
    Map<String, dynamic> json,
  ) {
    return PrescriptionMedicationSuggestion(
      name: json['name'] as String?,
      dosage: json['dosage'] as String?,
      pharmaceuticalForm: json['pharmaceuticalForm'] as String?,
      unitsPerDose: Medication._number(json['unitsPerDose']),
      frequencyPerDay: Medication._number(json['frequencyPerDay'])?.toInt(),
      instructions: json['instructions'] as String?,
      startDate: Medication._date(json['startDate']),
      endDate: Medication._date(json['endDate']),
      reminderTimes: (json['reminderTimes'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList(),
      weekdays: Medication._list(json['weekdays'])
          .map(Medication._weekdayNumber)
          .whereType<int>()
          .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList(),
    );
  }
}

class MedicationDraft {
  final String name;
  final String? dosage;
  final String? frequency;
  final int? frequencyPerDay;
  final String? instructions;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> reminderTimes;
  final String pharmaceuticalForm;
  final String? notes;
  final num? unitsPerDose;
  final List<String> weekdays;
  final String status;
  final bool remindersEnabled;
  final num? stockQuantity;
  final String? stockUnit;
  final num? lowStockThreshold;
  final num? packageQuantity;

  const MedicationDraft({
    required this.name,
    this.dosage,
    this.frequency,
    this.frequencyPerDay,
    this.instructions,
    this.startDate,
    this.endDate,
    required this.reminderTimes,
    required this.pharmaceuticalForm,
    this.notes,
    this.unitsPerDose,
    required this.weekdays,
    required this.status,
    required this.remindersEnabled,
    this.stockQuantity,
    this.stockUnit,
    this.lowStockThreshold,
    this.packageQuantity,
  });

  factory MedicationDraft.fromRequest(Map<String, dynamic> json) =>
      MedicationDraft(
        name: json['name'] as String,
        dosage: json['dosage'] as String?,
        frequency: json['frequency'] as String?,
        frequencyPerDay: Medication._number(json['frequencyPerDay'])?.toInt(),
        instructions: json['instructions'] as String?,
        startDate: Medication._date(json['startDate']),
        endDate: Medication._date(json['endDate']),
        reminderTimes: (json['reminderTimes'] as List<dynamic>? ?? [])
            .map((value) => value.toString())
            .toList(),
        pharmaceuticalForm: json['pharmaceuticalForm'] as String,
        notes: json['notes'] as String?,
        unitsPerDose: Medication._number(json['unitsPerDose']),
        weekdays: (json['weekdays'] as List<dynamic>? ?? [])
            .map((value) => value.toString())
            .toList(),
        status: json['status'] as String,
        remindersEnabled: json['remindersEnabled'] as bool? ?? true,
        stockQuantity: Medication._number(json['stockQuantity']),
        stockUnit: json['stockUnit'] as String?,
        lowStockThreshold: Medication._number(json['lowStockThreshold']),
        packageQuantity: Medication._number(json['packageQuantity']),
      );

  Map<String, dynamic> toRequest(int prescriptionId) => {
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        'frequencyPerDay': frequencyPerDay,
        'instructions': instructions,
        'startDate': startDate?.toIso8601String().split('T').first,
        'endDate': endDate?.toIso8601String().split('T').first,
        'reminderTimes': reminderTimes,
        'prescriptionId': prescriptionId,
        'pharmaceuticalForm': pharmaceuticalForm,
        'notes': notes,
        'unitsPerDose': unitsPerDose,
        'weekdays': weekdays,
        'status': status.toUpperCase(),
        'remindersEnabled': remindersEnabled,
        'stockQuantity': stockQuantity,
        'stockUnit': stockUnit,
        'lowStockThreshold': lowStockThreshold,
        'packageQuantity': packageQuantity,
      };
}

List<MedicationReminder> medicationRemindersFromJson(dynamic response) {
  dynamic data = response;
  if (data is Map<String, dynamic>) {
    data = data['items'] ??
        data['reminders'] ??
        data['intakes'] ??
        data['history'] ??
        data['data'] ??
        const [];
  }
  if (data is! List) return [];
  return data
      .whereType<Map<String, dynamic>>()
      .map(MedicationReminder.fromJson)
      .toList();
}
