package com.medicare.medication;

import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.text.Normalizer;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.EnumSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Component
public class PrescriptionMedicationParser {
    private static final Pattern DOSAGE = Pattern.compile(
            "(?iu)\\b\\d+(?:[.,]\\d+)?\\s*(?:mg|g|mcg|μg|µg|ml|ui|iu|%)"
                    + "(?:\\s*/\\s*(?:\\d+(?:[.,]\\d+)?\\s*)?(?:ml|mg|g))?\\b");
    private static final Pattern UNITS_PER_DOSE = Pattern.compile(
            "(?iu)\\b(\\d+(?:[.,]\\d+)?)\\s*(?:comprim[eé]s?|cp\\b|tablets?|tabs?|"
                    + "g[eé]lules?|capsules?|"
                    + "cuill[eè]res?|gouttes?|doses?)");
    private static final Pattern NUMERIC_FREQUENCY = Pattern.compile(
            "\\b(\\d{1,2})\\s*(?:fois|times)\\s*(?:/|par|a|per)\\s*(?:j|jour|day)\\b");
    private static final Pattern SHORT_FREQUENCY = Pattern.compile(
            "\\b(\\d{1,2})\\s*(?:x|×)\\s*(?:/|par|per)?\\s*(?:j|jour|day)\\b");
    private static final Pattern ENGLISH_FREQUENCY = Pattern.compile(
            "\\b(once|twice|thrice|one|two|three)\\s+(?:a|per)\\s+day\\b");
    private static final Pattern HOURS_FREQUENCY = Pattern.compile(
            "\\b(?:every|toutes? les?)\\s+(\\d{1,2})\\s*(?:hours?|heures?|h)\\b");
    private static final Pattern WEEKDAY_PATTERN = Pattern.compile(
            "\\b(lundi|monday|mardi|tuesday|mercredi|wednesday|jeudi|thursday|"
                    + "vendredi|friday|samedi|saturday|dimanche|sunday)\\b");
    private static final Pattern CLOCK_TIME = Pattern.compile(
            "\\b([01]?\\d|2[0-3])[:h]([0-5]\\d)\\b");
    private static final Pattern REGIMEN_SEQUENCE = Pattern.compile(
            "\\b([0-9])\\s*[-–]\\s*([0-9])\\s*[-–]\\s*([0-9])\\b");
    private static final Pattern FRENCH_DATE_RANGE = Pattern.compile(
            "\\bdu\\s+(\\d{1,2})/(\\d{1,2})/(\\d{4})\\s+au\\s+"
                    + "(\\d{1,2})/(\\d{1,2})/(\\d{4})\\b");
    private static final Pattern ISO_DATE_RANGE = Pattern.compile(
            "\\bfrom\\s+(\\d{4})-(\\d{1,2})-(\\d{1,2})\\s+to\\s+"
                    + "(\\d{4})-(\\d{1,2})-(\\d{1,2})\\b");
    private static final Pattern INSTRUCTION_PREFIX = Pattern.compile(
            "(?iu)^(?:maximum|minimum|dose|posologie|dur[eé]e|exemple|indication|"
                    + "prendre|take|give|during)\\b.*");
    private static final Pattern ORAL_REHYDRATION_ROW = Pattern.compile(
            "(?iu)^\\s*[\\d\\p{P}\\p{S}]*\\s*(?:sels?\\s+de\\s+r[eé]hydratation\\s+orale"
                    + "(?:\\s*\\(?sro\\)?)?|\\(?sro\\)?\\b)");
    private static final Pattern ALGINATE_ROW = Pattern.compile(
            "(?iu)^\\s*[\\d\\p{P}\\p{S}]*\\s*(?:alginate(?:\\s*/\\s*antiacide)?"
                    + "(?:\\s*\\(\\s*ex\\.?(?:\\s*gaviscon)?\\s*\\)?)?|"
                    + "antiacide(?:\\s*\\(\\s*ex\\.?(?:\\s*gaviscon)?\\s*\\)?)?|gaviscon)");
    private static final int MAX_DETAIL_LINES = 5;

    public record ExtractionResult(List<PrescriptionMedicationSuggestion> medications, String notice) {}
    private record TableMedication(String name, int endIndex) {}

    public ExtractionResult parse(String text) {
        List<String> lines = Arrays.stream(text.split("\\R"))
                .map(String::trim)
                .filter(line -> !line.isEmpty())
                .toList();
        List<PrescriptionMedicationSuggestion> medications = new ArrayList<>();

        for (int i = 0; i < lines.size(); i++) {
            String line = lines.get(i);
            Matcher dosageMatcher = DOSAGE.matcher(line);
            boolean hasDosage = dosageMatcher.find();
            TableMedication tableMedication = tableMedication(line);
            if (!hasDosage && tableMedication == null) {
                continue;
            }

            String name;
            String dosage;
            StringBuilder details;
            if (hasDosage) {
                name = cleanMedicationName(line.substring(0, dosageMatcher.start()));
                if (!isMedicationName(name)) {
                    continue;
                }
                dosage = dosageMatcher.group().replaceAll("\\s+", " ").trim();
                details = new StringBuilder(line.substring(dosageMatcher.end()).trim());
            } else {
                name = tableMedication.name();
                dosage = null;
                details = new StringBuilder(line.substring(tableMedication.endIndex()).trim());
            }

            int lastDetailLine = i;
            for (int next = i + 1; next < Math.min(lines.size(), i + MAX_DETAIL_LINES + 1); next++) {
                String nextLine = lines.get(next);
                TableMedication nextTableMedication = tableMedication(nextLine);
                if (nextTableMedication != null && !nextTableMedication.name().equals(name)) {
                    break;
                }
                if (nextTableMedication == null && medicationNameBeforeDosage(nextLine) != null) break;
                if (!details.isEmpty()) {
                    details.append(' ');
                }
                String nextDetails = nextTableMedication == null
                        ? nextLine
                        : nextLine.substring(nextTableMedication.endIndex()).trim();
                if (!nextDetails.replaceAll("[\\p{P}\\p{S}]+", "").isBlank()) {
                    details.append(nextDetails);
                }
                lastDetailLine = next;
            }
            medications.add(suggestion(name, dosage, details.toString()));
            i = lastDetailLine;
        }

        if (medications.isEmpty()) {
            return new ExtractionResult(List.of(),
                    "Aucun médicament n’a été détecté avec certitude. Saisissez-le manuellement.");
        }
        return new ExtractionResult(List.copyOf(medications),
                "Vérifiez chaque champ avec l’ordonnance originale avant l’enregistrement.");
    }

    private PrescriptionMedicationSuggestion suggestion(String name, String dosage, String details) {
        String normalized = normalize(details);
        List<LocalTime> times = reminderTimes(normalized);
        Integer explicitFrequency = frequency(normalized);
        Integer frequency = explicitFrequency;
        boolean scheduleMismatch = explicitFrequency != null
                && !times.isEmpty()
                && explicitFrequency != times.size();
        if (scheduleMismatch) {
            frequency = null;
        } else if (explicitFrequency == null && !times.isEmpty()) {
            frequency = times.size();
        }
        if (frequency != null && frequency > 6) {
            frequency = null;
        }

        EnumSet<DayOfWeek> weekdays = weekdays(normalized);
        String form = pharmaceuticalForm(normalized);
        BigDecimal units = unitsPerDose(normalized);
        LocalDate[] dateRange = dateRange(normalized);
        List<String> warnings = new ArrayList<>();
        if (dosage == null) warnings.add("Dosage à renseigner selon la présentation exacte.");
        if (form == null) warnings.add("Forme pharmaceutique à vérifier.");
        if (units == null) warnings.add("Unités par prise non détectées.");
        if (frequency == null) warnings.add("Fréquence quotidienne à renseigner.");
        if (times.isEmpty()) warnings.add("Horaires de prise à renseigner.");
        if (scheduleMismatch) warnings.add("Fréquence et horaires détectés non concordants.");
        if (weekdays.isEmpty()) warnings.add("Jours de prise à sélectionner.");
        if (dateRange == null) {
            warnings.add("Dates du traitement à confirmer.");
        }

        return new PrescriptionMedicationSuggestion(
                name,
                dosage,
                form,
                units,
                frequency,
                details.isBlank() ? null : details.trim(),
                dateRange == null ? null : dateRange[0],
                dateRange == null ? null : dateRange[1],
                List.copyOf(times),
                List.copyOf(weekdays),
                List.copyOf(warnings));
    }

    private boolean isMedicationName(String name) {
        return !name.isEmpty()
                && name.length() <= 160
                && !INSTRUCTION_PREFIX.matcher(name).matches();
    }

    private String medicationNameBeforeDosage(String line) {
        Matcher matcher = DOSAGE.matcher(line);
        if (!matcher.find()) return null;
        String name = cleanMedicationName(line.substring(0, matcher.start()));
        return isMedicationName(name) ? name : null;
    }

    private String cleanMedicationName(String name) {
        return name.replaceFirst("^[\\s\\d\\p{P}\\p{S}]+", "")
                .replaceFirst("[\\s:;,\\-]+$", "")
                .trim();
    }

    private TableMedication tableMedication(String line) {
        Matcher matcher = ORAL_REHYDRATION_ROW.matcher(line);
        if (matcher.find()) {
            return new TableMedication("Sels de réhydratation orale (SRO)", matcher.end());
        }
        matcher = ALGINATE_ROW.matcher(line);
        if (matcher.find()) {
            return new TableMedication("Alginate / antiacide (ex. Gaviscon)", matcher.end());
        }
        return null;
    }

    private List<LocalTime> reminderTimes(String text) {
        LinkedHashSet<LocalTime> times = new LinkedHashSet<>();
        Matcher matcher = CLOCK_TIME.matcher(text);
        while (matcher.find()) {
            times.add(LocalTime.of(
                    Integer.parseInt(matcher.group(1)),
                    Integer.parseInt(matcher.group(2))));
        }
        return List.copyOf(times);
    }

    private Integer dayPartFrequency(String text) {
        int count = 0;
        for (String part : List.of(
                "matin", "morning", "midi", "noon", "soir", "evening", "coucher", "bedtime")) {
            if (text.matches(".*\\b" + part + "\\b.*")) count++;
        }
        return count == 0 ? null : count;
    }

    private Integer frequency(String text) {
        Matcher matcher = NUMERIC_FREQUENCY.matcher(text);
        if (matcher.find()) return boundedFrequency(matcher.group(1));
        matcher = SHORT_FREQUENCY.matcher(text);
        if (matcher.find()) return boundedFrequency(matcher.group(1));
        matcher = ENGLISH_FREQUENCY.matcher(text);
        if (matcher.find()) {
            return switch (matcher.group(1)) {
                case "once", "one" -> 1;
                case "twice", "two" -> 2;
                case "thrice", "three" -> 3;
                default -> null;
            };
        }
        matcher = HOURS_FREQUENCY.matcher(text);
        if (matcher.find()) {
            int hours = Integer.parseInt(matcher.group(1));
            if (hours > 0 && 24 % hours == 0) return 24 / hours;
        }
        matcher = REGIMEN_SEQUENCE.matcher(text);
        if (matcher.find()) {
            return Integer.parseInt(matcher.group(1))
                    + Integer.parseInt(matcher.group(2))
                    + Integer.parseInt(matcher.group(3));
        }
        return dayPartFrequency(text);
    }

    private Integer boundedFrequency(String value) {
        int frequency = Integer.parseInt(value);
        return frequency >= 1 && frequency <= 24 ? frequency : null;
    }

    private EnumSet<DayOfWeek> weekdays(String text) {
        if (text.matches(".*\\b(tous les jours|chaque jour|daily|every day)\\b.*")) {
            return EnumSet.allOf(DayOfWeek.class);
        }
        EnumSet<DayOfWeek> result = EnumSet.noneOf(DayOfWeek.class);
        Matcher matcher = WEEKDAY_PATTERN.matcher(text);
        while (matcher.find()) {
            result.add(switch (matcher.group(1)) {
                case "lundi", "monday" -> DayOfWeek.MONDAY;
                case "mardi", "tuesday" -> DayOfWeek.TUESDAY;
                case "mercredi", "wednesday" -> DayOfWeek.WEDNESDAY;
                case "jeudi", "thursday" -> DayOfWeek.THURSDAY;
                case "vendredi", "friday" -> DayOfWeek.FRIDAY;
                case "samedi", "saturday" -> DayOfWeek.SATURDAY;
                case "dimanche", "sunday" -> DayOfWeek.SUNDAY;
                default -> throw new IllegalStateException("Unexpected weekday");
            });
        }
        return result;
    }

    private String pharmaceuticalForm(String text) {
        if (text.matches(".*\\b(solution buvable|oral solution)\\b.*")) return "Solution buvable";
        if (text.matches(".*\\b(sirop|syrup)\\b.*")) return "Sirop";
        if (text.matches(".*\\b(g[eé]lule|capsules?)\\b.*")) return "Gélule";
        if (text.matches(".*\\b(comprim[eé]s?|cp|tablets?)\\b.*")) return "Comprimé";
        if (text.matches(".*\\b(goutte|drops?)\\b.*")) return "Gouttes";
        if (text.matches(".*\\b(injection|injectable)\\b.*")) return "Injection";
        if (text.matches(".*\\b(cr[eè]me|cream|ointment)\\b.*")) return "Crème";
        if (text.matches(".*\\b(inhalateur|inhaler)\\b.*")) return "Inhalateur";
        return null;
    }

    private BigDecimal unitsPerDose(String text) {
        Matcher matcher = UNITS_PER_DOSE.matcher(text);
        if (!matcher.find()) return null;
        try {
            return new BigDecimal(matcher.group(1).replace(',', '.'));
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private LocalDate[] dateRange(String text) {
        Matcher matcher = FRENCH_DATE_RANGE.matcher(text);
        if (matcher.find()) {
            return parseDateRange(
                    matcher.group(3), matcher.group(2), matcher.group(1),
                    matcher.group(6), matcher.group(5), matcher.group(4));
        }
        matcher = ISO_DATE_RANGE.matcher(text);
        if (matcher.find()) {
            return parseDateRange(
                    matcher.group(1), matcher.group(2), matcher.group(3),
                    matcher.group(4), matcher.group(5), matcher.group(6));
        }
        return null;
    }

    private LocalDate[] parseDateRange(
            String startYear, String startMonth, String startDay,
            String endYear, String endMonth, String endDay) {
        try {
            return new LocalDate[] {
                    LocalDate.of(Integer.parseInt(startYear), Integer.parseInt(startMonth),
                            Integer.parseInt(startDay)),
                    LocalDate.of(Integer.parseInt(endYear), Integer.parseInt(endMonth),
                            Integer.parseInt(endDay))
            };
        } catch (java.time.DateTimeException | NumberFormatException ignored) {
            return null;
        }
    }

    private String normalize(String text) {
        return Normalizer.normalize(text, Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "")
                .toLowerCase(Locale.ROOT);
    }
}
