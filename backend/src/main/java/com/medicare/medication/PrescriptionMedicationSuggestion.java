package com.medicare.medication;

import java.math.BigDecimal;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;

public record PrescriptionMedicationSuggestion(
        String name,
        String dosage,
        String pharmaceuticalForm,
        BigDecimal unitsPerDose,
        Integer frequencyPerDay,
        String instructions,
        LocalDate startDate,
        LocalDate endDate,
        List<LocalTime> reminderTimes,
        List<DayOfWeek> weekdays,
        List<String> warnings) {}
