package com.medicare.medication;

import org.junit.jupiter.api.Test;

import java.time.DayOfWeek;
import java.time.LocalTime;

import static org.assertj.core.api.Assertions.assertThat;

class PrescriptionMedicationParserTest {
    private final PrescriptionMedicationParser parser = new PrescriptionMedicationParser();

    @Test
    void extractsFrenchMedicationAndOnlyFillsRecognizedScheduleFields() {
        var result = parser.parse("""
                Amoxicilline 500 mg, 1 gélule matin et soir, tous les jours
                pendant 7 jours
                """);

        assertThat(result.medications()).hasSize(1);
        var medication = result.medications().getFirst();
        assertThat(medication.name()).isEqualTo("Amoxicilline");
        assertThat(medication.dosage()).isEqualTo("500 mg");
        assertThat(medication.pharmaceuticalForm()).isEqualTo("Gélule");
        assertThat(medication.unitsPerDose()).isEqualByComparingTo("1");
        assertThat(medication.frequencyPerDay()).isEqualTo(2);
        assertThat(medication.reminderTimes()).isEmpty();
        assertThat(medication.weekdays()).containsExactly(
                DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY,
                DayOfWeek.THURSDAY, DayOfWeek.FRIDAY, DayOfWeek.SATURDAY, DayOfWeek.SUNDAY);
        assertThat(medication.warnings()).contains("Horaires de prise à renseigner.");
        assertThat(medication.startDate()).isNull();
        assertThat(medication.endDate()).isNull();
        assertThat(medication.warnings()).contains("Dates du traitement à confirmer.");
    }

    @Test
    void extractsEnglishFrequencyButDoesNotInventTimesOrWeekdays() {
        var result = parser.parse("Ibuprofen 200 mg, take 1 tablet twice a day");

        assertThat(result.medications()).hasSize(1);
        var medication = result.medications().getFirst();
        assertThat(medication.frequencyPerDay()).isEqualTo(2);
        assertThat(medication.unitsPerDose()).isEqualByComparingTo("1");
        assertThat(medication.reminderTimes()).isEmpty();
        assertThat(medication.weekdays()).isEmpty();
        assertThat(medication.warnings()).contains(
                "Horaires de prise à renseigner.",
                "Jours de prise à sélectionner.");
    }

    @Test
    void extractsClockTimesOnlyWhenTheyAreExplicit() {
        var result = parser.parse(
                "Paracetamol 500 mg, take 1 tablet at 08:00 and 20:00 every day");

        assertThat(result.medications()).hasSize(1);
        var medication = result.medications().getFirst();
        assertThat(medication.frequencyPerDay()).isEqualTo(2);
        assertThat(medication.reminderTimes())
                .containsExactly(LocalTime.of(8, 0), LocalTime.of(20, 0));
    }

    @Test
    void extractsOnlyExplicitPrescriptionDateRanges() {
        var result = parser.parse(
                "Paracetamol 500 mg, 1 comprimé matin, du 12/03/2026 au 19/03/2026");

        assertThat(result.medications()).hasSize(1);
        assertThat(result.medications().getFirst().startDate())
                .isEqualTo(java.time.LocalDate.of(2026, 3, 12));
        assertThat(result.medications().getFirst().endDate())
                .isEqualTo(java.time.LocalDate.of(2026, 3, 19));
    }

    @Test
    void preservesMedicationConcentrationInDosage() {
        var result = parser.parse("Amoxicillin 500 mg/5 ml, 1 dose twice a day");

        assertThat(result.medications()).hasSize(1);
        assertThat(result.medications().getFirst().dosage()).isEqualTo("500 mg/5 ml");
    }

    @Test
    void extractsAllRowsFromFrenchMedicationTableWithoutInventingMissingDoses() {
        var result = parser.parse("""
                Médicament
                Exemple de prise
                Indication et précautions
                Paracétamol 500 mg
                1 comprimé si besoin, espacer d’au moins 6 h.
                Maximum 3 g (6 comprimés de 500 mg) en 24 h.
                Douleur ou fièvre. Exemple uniquement pour adulte d’au moins 50 kg.
                Sels de réhydratation orale (SRO)
                Dissoudre le sachet exactement dans le volume d’eau indiqué sur l’emballage.
                En cas de diarrhée ou pertes hydriques.
                ‘Alginate / antiacide (ex.
                Gaviscon)
                Dose et fréquence selon la présentation exacte et sa notice.
                Brûlures d’estomac / reflux.
                """);

        assertThat(result.medications()).hasSize(3);
        assertThat(result.medications())
                .extracting(PrescriptionMedicationSuggestion::name)
                .containsExactly(
                        "Paracétamol",
                        "Sels de réhydratation orale (SRO)",
                        "Alginate / antiacide (ex. Gaviscon)");
        assertThat(result.medications().get(0).dosage()).isEqualTo("500 mg");
        assertThat(result.medications().get(1).dosage()).isNull();
        assertThat(result.medications().get(1).frequencyPerDay()).isNull();
        assertThat(result.medications().get(1).instructions())
                .contains("Dissoudre le sachet");
        assertThat(result.medications().get(1).warnings())
                .contains("Dosage à renseigner selon la présentation exacte.");
        assertThat(result.medications().get(2).dosage()).isNull();
        assertThat(result.medications().get(2).frequencyPerDay()).isNull();
        assertThat(result.medications().get(2).instructions())
                .contains("Dose et fréquence selon la présentation exacte");
    }

    @Test
    void returnsManualEntryNoticeWhenNoMedicationCanBeIdentified() {
        var result = parser.parse("Ordonnance médicale - renouvellement");

        assertThat(result.medications()).isEmpty();
        assertThat(result.notice()).contains("Saisissez-le manuellement");
    }
}
