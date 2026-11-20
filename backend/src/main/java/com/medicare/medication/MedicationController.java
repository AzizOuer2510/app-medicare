package com.medicare.medication;

import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import com.medicare.user.repository.UserRepository;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.*;
import java.time.temporal.ChronoUnit;
import java.util.*;

@RestController
@RequestMapping("/api/medications")
@RequiredArgsConstructor
public class MedicationController {
    private static final BigDecimal ZERO = BigDecimal.ZERO;
    private static final int MAX_SCHEDULE_DAYS = 366;
    private static final String PLANNING_DIAGNOSIS = "Planning de traitement";

    private final MedicationRepository repo;
    private final UserRepository users;
    private final PrescriptionRepository prescriptions;
    private final MedicationReminderRepository reminders;
    private final MedicationStockEntryRepository stockEntries;
    private final DoctorPatientAssignmentRepository assignments;
    private final com.medicare.health.HealthAccessService healthAccess;
    private final com.medicare.notification.service.CareRelationships care;

    public record MedicationRequest(
            @NotBlank @Size(max = 160) String name,
            @Size(max = 80) String dosage,
            @Size(max = 80) String frequency,
            @Min(1) @Max(24) Integer frequencyPerDay,
            @Size(max = 1000) String instructions,
            LocalDate startDate,
            LocalDate endDate,
            List<LocalTime> reminderTimes,
            Long prescriptionId,
            @Size(max = 80) String pharmaceuticalForm,
            @Size(max = 2000) String notes,
            @DecimalMin(value = "0.001") @Digits(integer = 9, fraction = 3) BigDecimal unitsPerDose,
            List<DayOfWeek> weekdays,
            MedicationStatus status,
            Boolean remindersEnabled,
            @DecimalMin("0") @Digits(integer = 9, fraction = 3) BigDecimal stockQuantity,
            @Size(max = 40) String stockUnit,
            @DecimalMin("0") @Digits(integer = 9, fraction = 3) BigDecimal lowStockThreshold,
            @DecimalMin(value = "0.001") @Digits(integer = 9, fraction = 3) BigDecimal packageQuantity,
            /** Médecin sans ordonnance : patient suivi pour qui le planning est créé. */
            Long patientId) {}

    public record MedicationResponse(
            Long id, String name, String dosage, String frequency, Integer frequencyPerDay,
            String instructions, LocalDate startDate, LocalDate endDate, List<LocalTime> reminderTimes,
            Long prescriptionId, String pharmaceuticalForm, String notes, BigDecimal unitsPerDose,
            List<DayOfWeek> weekdays, MedicationStatus status, boolean remindersEnabled,
            boolean stockTracked, BigDecimal stockQuantity, String stockUnit, BigDecimal lowStockThreshold,
            BigDecimal packageQuantity, boolean lowStock, Long patientId, String patientName,
            /** Médecin qui a prescrit le médicament : lui seul peut le modifier ou le supprimer. */
            Long prescriberId, String prescriberName) {
        static MedicationResponse from(Medication m) {
            BigDecimal quantity = nvl(m.getStockQuantity());
            BigDecimal threshold = nvl(m.getLowStockThreshold());
            boolean tracked = isStockTracked(m);
            return new MedicationResponse(m.getId(), m.getName(), m.getDosage(), m.getFrequency(),
                    m.getFrequencyPerDay(), m.getInstructions(), m.getStartDate(), m.getEndDate(),
                    List.copyOf(m.getReminderTimes()), m.getPrescription() == null ? null : m.getPrescription().getId(),
                    m.getPharmaceuticalForm(), m.getNotes(), m.getUnitsPerDose(), List.copyOf(m.getWeekdays()),
                    m.getStatus(), m.isRemindersEnabled(), tracked, quantity, m.getStockUnit(),
                    threshold, m.getPackageQuantity(),
                    tracked && threshold.signum() > 0
                            && quantity.compareTo(threshold) <= 0,
                    m.getUser() == null ? null : m.getUser().getId(),
                    m.getUser() == null ? null : m.getUser().getFullName(),
                    m.getPrescription() == null ? null : m.getPrescription().getDoctor().getId(),
                    m.getPrescription() == null ? null : m.getPrescription().getDoctor().getFullName());
        }
    }

    public record IntakeResponse(
            Long id, Long medicationId, String medicationName, LocalDate date, LocalTime time,
            IntakeStatus status, boolean taken, LocalDateTime confirmedAt, LocalDateTime takenAt,
            LocalDateTime snoozedUntil, String note) {
        static IntakeResponse from(MedicationReminder r) {
            return new IntakeResponse(r.getId(), r.getMedication().getId(), r.getMedication().getName(),
                    r.getDate(), r.getTime(), r.getStatus(), r.isTaken(), r.getTakenAt(), r.getTakenAt(),
                    r.getSnoozedUntil(), r.getIntakeNote());
        }
    }

    public record StockEntryResponse(Long id, String type, BigDecimal quantityChange,
                                     BigDecimal quantityAfter, String note, LocalDateTime createdAt) {
        static StockEntryResponse from(MedicationStockEntry entry) {
            return new StockEntryResponse(entry.getId(), entry.getType().name(), entry.getQuantityChange(),
                    entry.getQuantityAfter(), entry.getNote(), entry.getCreatedAt());
        }
    }

    public record StockResponse(Long medicationId, BigDecimal quantity, String unit,
                                BigDecimal lowStockThreshold, BigDecimal packageQuantity,
                                boolean lowStock, List<StockEntryResponse> entries) {}

    public record StockChangeRequest(
            @NotNull @DecimalMin("0") @Digits(integer = 9, fraction = 3) BigDecimal quantity,
            @Size(max = 500) String note,
            @Size(max = 40) String unit,
            @DecimalMin("0") @Digits(integer = 9, fraction = 3) BigDecimal lowStockThreshold,
            @DecimalMin(value = "0.001") @Digits(integer = 9, fraction = 3) BigDecimal packageQuantity) {}

    public record IntakeUpdateRequest(@NotNull IntakeStatus status, @Size(max = 1000) String note) {}
    public record SnoozeRequest(@Min(1) @Max(1440) int minutes) {}

    public record DailyAdherence(LocalDate date, long eligibleDoses, long taken, long missed,
                                 long skipped, long snoozed, long pending) {}
    public record AdherenceResponse(String period, LocalDate from, LocalDate to, long eligibleDoses,
                                    long taken, long missed, long skipped, long snoozed,
                                    long pending, double adherencePercent, List<DailyAdherence> days) {}

    @GetMapping
    @Transactional(readOnly = true)
    public List<MedicationResponse> all(@RequestParam(required = false) Long patientId, Authentication auth) {
        User current = currentUser(auth);
        return visibleMedications(current, patientId).stream().map(MedicationResponse::from).toList();
    }

    @GetMapping("/{id}")
    @Transactional(readOnly = true)
    public MedicationResponse one(@PathVariable Long id, Authentication auth) {
        return MedicationResponse.from(ownedMedication(id, currentUser(auth)));
    }

    @PostMapping
    @Transactional
    public MedicationResponse create(@Valid @RequestBody MedicationRequest request, Authentication auth) {
        User user = currentUser(auth);
        requireScheduleManager(user);
        validateRequest(request);
        Prescription prescription = findPrescription(request.prescriptionId(), user);
        if (user.getRole() == Role.DOCTOR && prescription == null && request.patientId() != null) {
            // Planning ajouté directement depuis le dossier du patient : rattaché à une ordonnance
            // « Planning de traitement » du médecin, pour que le patient le reçoive dans son planning.
            prescription = planningPrescription(user, request.patientId());
        }
        if (user.getRole() == Role.DOCTOR && prescription == null) {
            badRequest("Choisissez le patient pour qui ce planning est créé.");
        }
        if (user.getRole() == Role.DOCTOR
                && (request.reminderTimes() == null || request.reminderTimes().isEmpty())) {
            badRequest("A doctor must add at least one medication time");
        }

        Medication medication = new Medication();
        medication.setUser(prescription == null ? user : prescription.getPatient());
        applyRequest(medication, request, user, true);
        // applyRequest relit prescriptionId (absent pour un planning créé par patientId) :
        // on rattache explicitement l'ordonnance retenue, sinon le médecin perd le médicament.
        medication.setPrescription(prescription);
        Medication saved = repo.save(medication);
        if (nvl(saved.getStockQuantity()).signum() > 0) {
            saveStockEntry(saved, null, MedicationStockEntry.Type.INITIAL_STOCK,
                    saved.getStockQuantity(), "Initial stock");
        }
        if (user.getRole() == Role.DOCTOR) {
            // Le patient est prévenu que son planning de prises a changé.
            String times = saved.getReminderTimes().stream().sorted()
                    .map(t -> t.toString().substring(0, 5)).reduce((a, b) -> a + ", " + b).orElse("");
            care.notify(saved.getUser(), "Nouveau traitement",
                    user.getFullName() + " a ajouté " + saved.getName()
                            + (times.isEmpty() ? "" : " (" + times + ")")
                            + " à votre planning de prises. Retrouvez-le dans Médicaments.");
        }
        return MedicationResponse.from(saved);
    }

    @PutMapping("/{id}")
    @Transactional
    public MedicationResponse update(@PathVariable Long id, @Valid @RequestBody MedicationRequest request,
                                     Authentication auth) {
        User user = currentUser(auth);
        requireScheduleManager(user);
        validateRequest(request);
        Medication medication = ownedMedicationForUpdate(id, user);
        Prescription prescription = findPrescription(request.prescriptionId(), user);
        if (user.getRole() == Role.DOCTOR
                && (medication.getPrescription() == null || prescription == null
                || !medication.getPrescription().getId().equals(prescription.getId()))) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Doctors can only edit medications from their own prescription");
        }
        if (user.getRole() == Role.DOCTOR
                && (request.reminderTimes() == null || request.reminderTimes().isEmpty())) {
            badRequest("A doctor must add at least one medication time");
        }
        BigDecimal oldStock = nvl(medication.getStockQuantity());
        reminders.deleteFuturePending(id, LocalDate.now(), LocalTime.now());
        applyRequest(medication, request, user, false);
        Medication saved = repo.save(medication);
        BigDecimal newStock = nvl(saved.getStockQuantity());
        if (newStock.compareTo(oldStock) != 0) {
            saveStockEntry(saved, null, MedicationStockEntry.Type.CORRECTION,
                    newStock.subtract(oldStock), "Medication details updated");
        }
        return MedicationResponse.from(saved);
    }

    @DeleteMapping("/{id}")
    @Transactional
    public void delete(@PathVariable Long id, Authentication auth) {
        User user = currentUser(auth);
        requireScheduleManager(user);
        Medication medication = ownedMedicationForUpdate(id, user);
        medication.setStatus(MedicationStatus.DISCONTINUED);
        medication.setRemindersEnabled(false);
        reminders.deleteFuturePending(id, LocalDate.now(), LocalTime.now());
        repo.save(medication);
    }

    @GetMapping("/today")
    @Transactional
    public List<IntakeResponse> today(
            @RequestParam(required = false) Long patientId,
            Authentication auth) {
        User user = currentUser(auth);
        LocalDate today = LocalDate.now();
        List<IntakeResponse> result = new ArrayList<>();
        List<Medication> medications = visibleMedications(user, patientId);
        for (Medication owned : medications) {
            if (owned.getStatus() != MedicationStatus.ACTIVE || !owned.isRemindersEnabled()) continue;
            Medication medication = visibleMedicationForUpdate(owned.getId(), user, patientId);
            generate(medication, today, today);
            result.addAll(reminders.findByMedicationIdAndDateOrderByTime(medication.getId(), today).stream()
                    .map(IntakeResponse::from).toList());
        }
        return result.stream().sorted(Comparator.comparing(IntakeResponse::time)
                .thenComparing(IntakeResponse::medicationName)).toList();
    }

    @GetMapping("/{id}/schedule")
    @Transactional
    public List<IntakeResponse> schedule(@PathVariable Long id,
            @RequestParam(required = false) LocalDate date,
            @RequestParam(required = false) LocalDate from,
            @RequestParam(required = false) LocalDate to,
            Authentication auth) {
        Medication medication = ownedMedicationForUpdate(id, currentUser(auth));
        LocalDate start = date != null ? date : from != null ? from : LocalDate.now();
        LocalDate end = date != null ? date : to != null ? to : start;
        validateRange(start, end);
        generate(medication, start, end);
        return reminders.findSchedule(id, start, end).stream().map(IntakeResponse::from).toList();
    }

    @GetMapping({"/{id}/history", "/{id}/intakes"})
    @Transactional(readOnly = true)
    public List<IntakeResponse> history(@PathVariable Long id,
            @RequestParam(required = false) LocalDate from,
            @RequestParam(required = false) LocalDate to,
            Authentication auth) {
        Medication medication = ownedMedication(id, currentUser(auth));
        LocalDate start = from == null
                ? (medication.getStartDate() == null ? LocalDate.now().minusDays(30) : medication.getStartDate())
                : from;
        LocalDate end = to == null
                ? (medication.getEndDate() == null ? LocalDate.now() : medication.getEndDate())
                : to;
        validateRange(start, end);
        return reminders.findSchedule(id, start, end).stream().map(IntakeResponse::from).toList();
    }

    @PostMapping("/reminders/{reminderId}/taken")
    @Transactional
    public IntakeResponse markTaken(@PathVariable Long reminderId, Authentication auth) {
        return updateIntake(reminderId, IntakeStatus.TAKEN, null, currentUser(auth));
    }

    @PostMapping("/reminders/{reminderId}/pending")
    @Transactional
    public IntakeResponse markPending(@PathVariable Long reminderId, Authentication auth) {
        return updateIntake(reminderId, IntakeStatus.PENDING, null, currentUser(auth));
    }

    @PostMapping("/reminders/{reminderId}/missed")
    @Transactional
    public IntakeResponse markMissed(@PathVariable Long reminderId, Authentication auth) {
        return updateIntake(reminderId, IntakeStatus.MISSED, null, currentUser(auth));
    }

    @PostMapping("/reminders/{reminderId}/skipped")
    @Transactional
    public IntakeResponse markSkipped(@PathVariable Long reminderId, Authentication auth) {
        return updateIntake(reminderId, IntakeStatus.SKIPPED, null, currentUser(auth));
    }

    @PostMapping("/reminders/{reminderId}/snooze")
    @Transactional
    public IntakeResponse snooze(@PathVariable Long reminderId,
            @Valid @RequestBody SnoozeRequest request, Authentication auth) {
        User user = currentUser(auth);
        requireIntakeRecorder(user);
        MedicationReminder visible = findReminder(reminderId, user, false);
        ownedMedicationForUpdate(visible.getMedication().getId(), user);
        MedicationReminder reminder = findReminder(reminderId, user, true);
        if (reminder.getStatus() == IntakeStatus.TAKEN
                || reminder.getStatus() == IntakeStatus.MISSED
                || reminder.getStatus() == IntakeStatus.SKIPPED) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "This dose can no longer be snoozed");
        }
        reminder.setStatus(IntakeStatus.SNOOZED);
        reminder.setTaken(false);
        reminder.setTakenAt(null);
        reminder.setSnoozedUntil(LocalDateTime.now().plusMinutes(request.minutes()));
        return IntakeResponse.from(reminders.save(reminder));
    }

    @PatchMapping("/reminders/{reminderId}")
    @Transactional
    public IntakeResponse updateIntake(@PathVariable Long reminderId,
            @Valid @RequestBody IntakeUpdateRequest request, Authentication auth) {
        return updateIntake(reminderId, request.status(), request.note(), currentUser(auth));
    }

    @GetMapping("/{id}/stock")
    @Transactional(readOnly = true)
    public StockResponse stock(@PathVariable Long id, Authentication auth) {
        Medication medication = ownedMedication(id, currentUser(auth));
        return stockResponse(medication);
    }

    @PutMapping("/{id}/stock")
    @Transactional
    public StockResponse correctStock(@PathVariable Long id,
            @Valid @RequestBody StockChangeRequest request, Authentication auth) {
        User user = currentUser(auth);
        requireScheduleManager(user);
        Medication medication = ownedMedicationForUpdate(id, user);
        BigDecimal before = nvl(medication.getStockQuantity());
        medication.setStockQuantity(request.quantity());
        if (request.unit() != null) medication.setStockUnit(trimOrNull(request.unit()));
        if (request.lowStockThreshold() != null) {
            medication.setLowStockThreshold(request.lowStockThreshold());
        }
        if (request.packageQuantity() != null) {
            medication.setPackageQuantity(request.packageQuantity());
        }
        repo.save(medication);
        saveStockEntry(medication, null, MedicationStockEntry.Type.CORRECTION,
                request.quantity().subtract(before), request.note());
        return stockResponse(medication);
    }

    @PostMapping({"/{id}/stock/refill", "/{id}/stock/refills"})
    @Transactional
    public StockResponse refill(@PathVariable Long id,
            @Valid @RequestBody StockChangeRequest request, Authentication auth) {
        User user = currentUser(auth);
        requireScheduleManager(user);
        if (request.quantity().compareTo(ZERO) <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Refill quantity must be positive");
        }
        Medication medication = ownedMedicationForUpdate(id, user);
        BigDecimal after = nvl(medication.getStockQuantity()).add(request.quantity());
        medication.setStockQuantity(after);
        repo.save(medication);
        saveStockEntry(medication, null, MedicationStockEntry.Type.REFILL, request.quantity(), request.note());
        return stockResponse(medication);
    }

    /**
     * Historique des prises (prises, oubliées, sautées…) de tous les médicaments, du plus récent au plus ancien.
     * Avec patientId : réservé au médecin qui suit le patient (synchronisation médecin ↔ patient).
     */
    @GetMapping("/intakes")
    @Transactional
    public List<IntakeResponse> intakes(@RequestParam(required = false) Long patientId,
            @RequestParam(required = false) LocalDate from,
            @RequestParam(required = false) LocalDate to,
            @RequestParam(required = false) IntakeStatus status,
            Authentication auth) {
        User user = currentUser(auth);
        LocalDate end = to == null ? LocalDate.now() : to;
        LocalDate start = from == null ? end.minusDays(29) : from;
        validateRange(start, end);
        LocalDateTime now = LocalDateTime.now();
        List<IntakeResponse> result = new ArrayList<>();
        for (Medication owned : visibleMedications(user, patientId)) {
            Medication medication = visibleMedicationForUpdate(owned.getId(), user, patientId);
            generate(medication, start, end);
            reminders.findSchedule(medication.getId(), start, end).stream()
                    .filter(r -> !LocalDateTime.of(r.getDate(), r.getTime()).isAfter(now))
                    .filter(r -> status == null || r.getStatus() == status)
                    .map(IntakeResponse::from)
                    .forEach(result::add);
        }
        result.sort(Comparator.comparing(IntakeResponse::date).thenComparing(IntakeResponse::time).reversed());
        return result;
    }

    public record PatientAdherence(Long patientId, String patientName, int activeMedications,
                                   long eligibleDoses, long taken, long missed, long skipped, long pending,
                                   Double adherencePercent, LocalDate lastMissed) {}

    /**
     * Observance de chaque patient suivi par le médecin sur les derniers jours (7 par défaut) :
     * prises effectuées, oubliées, ignorées, non renseignées et taux d'observance.
     */
    @GetMapping("/adherence/patients")
    @Transactional
    public List<PatientAdherence> patientsAdherence(@RequestParam(defaultValue = "7") int days, Authentication auth) {
        User doctor = currentUser(auth);
        if (doctor.getRole() != Role.DOCTOR) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Réservé aux médecins.");
        }
        if (days < 1 || days > 90) badRequest("days must be between 1 and 90");
        LocalDate to = LocalDate.now();
        LocalDate from = to.minusDays(days - 1L);
        LocalDateTime now = LocalDateTime.now();
        List<PatientAdherence> result = new ArrayList<>();
        for (User patient : healthAccess.followedPatients(doctor).keySet()) {
            List<MedicationReminder> eligible = new ArrayList<>();
            int active = 0;
            for (Medication owned : repo.findByUserIdOrderByName(patient.getId())) {
                if (owned.getStatus() != MedicationStatus.ACTIVE) continue;
                active++;
                Medication medication = visibleMedicationForUpdate(owned.getId(), doctor, patient.getId());
                generate(medication, from, to);
                if (!medication.isRemindersEnabled()) continue;
                reminders.findSchedule(medication.getId(), from, to).stream()
                        .filter(r -> !LocalDateTime.of(r.getDate(), r.getTime()).isAfter(now))
                        .forEach(eligible::add);
            }
            long taken = count(eligible, IntakeStatus.TAKEN);
            long missed = count(eligible, IntakeStatus.MISSED);
            long skipped = count(eligible, IntakeStatus.SKIPPED);
            long pending = eligible.size() - taken - missed - skipped;
            LocalDate lastMissed = eligible.stream().filter(r -> r.getStatus() == IntakeStatus.MISSED)
                    .map(MedicationReminder::getDate).max(Comparator.naturalOrder()).orElse(null);
            Double percent = eligible.isEmpty() ? null : Math.round((taken * 1000.0) / eligible.size()) / 10.0;
            result.add(new PatientAdherence(patient.getId(), patient.getFullName(), active, eligible.size(),
                    taken, missed, skipped, pending, percent, lastMissed));
        }
        return result;
    }

    @GetMapping({"/adherence", "/statistics"})
    @Transactional
    public AdherenceResponse adherence(@RequestParam(defaultValue = "DAILY") String period,
            @RequestParam(required = false) LocalDate date,
            @RequestParam(required = false) Long patientId,
            Authentication auth) {
        LocalDate anchor = date == null ? LocalDate.now() : date;
        String normalized = period.toUpperCase(Locale.ROOT);
        LocalDate from;
        LocalDate to;
        switch (normalized) {
            case "DAY", "DAILY" -> { from = anchor; to = anchor; normalized = "DAILY"; }
            case "WEEK", "WEEKLY" -> {
                from = anchor.with(DayOfWeek.MONDAY);
                to = from.plusDays(6);
                normalized = "WEEKLY";
            }
            case "MONTH", "MONTHLY" -> {
                from = anchor.withDayOfMonth(1);
                to = anchor.withDayOfMonth(anchor.lengthOfMonth());
                normalized = "MONTHLY";
            }
            default -> throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Period must be DAILY, WEEKLY, or MONTHLY");
        }
        validateRange(from, to);
        User user = currentUser(auth);
        List<Medication> medications = visibleMedications(user, patientId);
        for (Medication owned : medications) {
            Medication medication = visibleMedicationForUpdate(owned.getId(), user, patientId);
            generate(medication, from, to);
        }

        LocalDateTime now = LocalDateTime.now();
        List<MedicationReminder> scheduled = new ArrayList<>();
        for (Medication medication : medications) {
            if (medication.getStatus() == MedicationStatus.ACTIVE && medication.isRemindersEnabled()) {
                scheduled.addAll(reminders.findSchedule(medication.getId(), from, to));
            }
        }
        List<MedicationReminder> eligible = scheduled.stream().filter(r -> {
            LocalDateTime doseTime = LocalDateTime.of(r.getDate(), r.getTime());
            return !doseTime.isAfter(now);
        }).toList();
        long taken = count(eligible, IntakeStatus.TAKEN);
        long missed = count(eligible, IntakeStatus.MISSED);
        long skipped = count(eligible, IntakeStatus.SKIPPED);
        long snoozed = count(eligible, IntakeStatus.SNOOZED);
        long pending = count(eligible, IntakeStatus.PENDING);
        long total = eligible.size();
        LocalDate lastDay = to.isAfter(now.toLocalDate()) ? now.toLocalDate() : to;
        List<DailyAdherence> days = new ArrayList<>();
        for (LocalDate day = from; !day.isAfter(lastDay); day = day.plusDays(1)) {
            LocalDate currentDay = day;
            List<MedicationReminder> daily = eligible.stream()
                    .filter(reminder -> reminder.getDate().equals(currentDay)).toList();
            days.add(new DailyAdherence(currentDay, daily.size(), count(daily, IntakeStatus.TAKEN),
                    count(daily, IntakeStatus.MISSED), count(daily, IntakeStatus.SKIPPED),
                    count(daily, IntakeStatus.SNOOZED), count(daily, IntakeStatus.PENDING)));
        }
        return new AdherenceResponse(normalized, from, to, total, taken, missed, skipped, snoozed,
                pending, total == 0 ? 0.0 : Math.round((taken * 10000.0) / total) / 100.0,
                days);
    }

    private void applyRequest(Medication m, MedicationRequest r, User user, boolean creating) {
        List<LocalTime> times = normalizeTimes(r.reminderTimes());
        m.setName(r.name().trim());
        m.setDosage(r.dosage());
        m.setFrequency(r.frequency());
        m.setFrequencyPerDay(r.frequencyPerDay());
        m.setInstructions(r.instructions());
        m.setStartDate(r.startDate());
        m.setEndDate(r.endDate());
        m.setReminderTimes(new ArrayList<>(times));
        m.setPrescription(findPrescription(r.prescriptionId(), user));
        if (r.pharmaceuticalForm() != null || creating) m.setPharmaceuticalForm(trimOrNull(r.pharmaceuticalForm()));
        if (r.notes() != null || creating) m.setNotes(trimOrNull(r.notes()));
        if (r.unitsPerDose() != null || creating) m.setUnitsPerDose(r.unitsPerDose());
        if (r.weekdays() != null || creating) m.setWeekdays(r.weekdays() == null
                ? new ArrayList<>() : new ArrayList<>(r.weekdays().stream().distinct().sorted().toList()));
        if (r.status() != null) m.setStatus(r.status());
        else if (creating) m.setStatus(MedicationStatus.ACTIVE);
        if (r.remindersEnabled() != null) m.setRemindersEnabled(r.remindersEnabled());
        else if (creating) m.setRemindersEnabled(true);
        if (m.getStatus() == MedicationStatus.DISCONTINUED) m.setRemindersEnabled(false);
        if (r.stockQuantity() != null) m.setStockQuantity(r.stockQuantity());
        else if (creating) m.setStockQuantity(ZERO);
        if (r.stockUnit() != null || creating) m.setStockUnit(trimOrNull(r.stockUnit()));
        if (r.lowStockThreshold() != null) m.setLowStockThreshold(r.lowStockThreshold());
        else if (creating) m.setLowStockThreshold(ZERO);
        if (r.packageQuantity() != null || creating) m.setPackageQuantity(r.packageQuantity());
    }

    private void validateRequest(MedicationRequest request) {
        validateDates(request.startDate(), request.endDate());
        List<LocalTime> times = normalizeTimes(request.reminderTimes());
        if (times.size() > 24) badRequest("At most 24 reminder times are allowed");
        if (request.frequencyPerDay() != null && !times.isEmpty() && request.frequencyPerDay() != times.size()) {
            badRequest("Frequency and reminder times do not match");
        }
        if (request.weekdays() != null && request.weekdays().stream().anyMatch(Objects::isNull))
            badRequest("Weekdays must contain valid days");
        if (request.status() == MedicationStatus.DISCONTINUED && Boolean.TRUE.equals(request.remindersEnabled())) {
            badRequest("Discontinued medications cannot have reminders enabled");
        }
        if (request.unitsPerDose() != null && request.stockUnit() != null && request.stockUnit().isBlank()) {
            badRequest("Stock unit cannot be blank");
        }
        if (request.stockQuantity() != null && request.stockQuantity().compareTo(ZERO) < 0) {
            badRequest("Stock quantity cannot be negative");
        }
    }

    private IntakeResponse updateIntake(Long reminderId, IntakeStatus target, String note, User user) {
        // Le patient confirme ses propres prises (findReminder le limite à ses médicaments) :
        // le médecin qui le suit voit ainsi les prises effectuées et oubliées.
        requireIntakeRecorder(user);
        MedicationReminder visibleReminder = findReminder(reminderId, user, false);
        Medication medication = ownedMedicationForUpdate(visibleReminder.getMedication().getId(), user);
        MedicationReminder reminder = findReminder(reminderId, user, true);
        IntakeStatus before = reminder.getStatus() == null
                ? (reminder.isTaken() ? IntakeStatus.TAKEN : IntakeStatus.PENDING) : reminder.getStatus();
        if (before == target) {
            if (note != null) reminder.setIntakeNote(note);
            return IntakeResponse.from(reminder);
        }
        if (before == IntakeStatus.TAKEN && target != IntakeStatus.PENDING) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "A taken dose must be reversed to pending first");
        }
        if (target == IntakeStatus.TAKEN) deductStockOnce(medication, reminder);
        else if (before == IntakeStatus.TAKEN && target == IntakeStatus.PENDING) refundStockOnce(medication, reminder);
        reminder.setStatus(target);
        reminder.setTaken(target == IntakeStatus.TAKEN);
        reminder.setTakenAt(target == IntakeStatus.TAKEN ? LocalDateTime.now() : null);
        if (target != IntakeStatus.SNOOZED) reminder.setSnoozedUntil(null);
        if (note != null) reminder.setIntakeNote(note);
        return IntakeResponse.from(reminders.save(reminder));
    }

    private void deductStockOnce(Medication medication, MedicationReminder reminder) {
        if (!isStockTracked(medication)) return;
        BigDecimal amount = doseQuantity(medication);
        BigDecimal available = nvl(medication.getStockQuantity());
        if (available.compareTo(amount) < 0) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Insufficient medication stock");
        }
        BigDecimal after = available.subtract(amount);
        medication.setStockQuantity(after);
        repo.save(medication);
        saveStockEntry(medication, reminder, MedicationStockEntry.Type.INTAKE_DEDUCTION,
                amount.negate(), "Confirmed intake");
    }

    private void refundStockOnce(Medication medication, MedicationReminder reminder) {
        if (!isStockTracked(medication)) return;
        MedicationStockEntry lastDoseEntry = stockEntries
                .findFirstByReminderIdOrderByCreatedAtDescIdDesc(reminder.getId()).orElse(null);
        if (lastDoseEntry == null || lastDoseEntry.getType() != MedicationStockEntry.Type.INTAKE_DEDUCTION) return;
        BigDecimal amount = lastDoseEntry.getQuantityChange().abs();
        BigDecimal after = nvl(medication.getStockQuantity()).add(amount);
        medication.setStockQuantity(after);
        repo.save(medication);
        saveStockEntry(medication, reminder, MedicationStockEntry.Type.INTAKE_REFUND,
                amount, "Taken intake reversed");
    }

    private void saveStockEntry(Medication medication, MedicationReminder reminder,
                                MedicationStockEntry.Type type, BigDecimal change, String note) {
        stockEntries.save(MedicationStockEntry.builder().medication(medication).reminder(reminder)
                .type(type).quantityChange(change).quantityAfter(nvl(medication.getStockQuantity()))
                .note(note).createdAt(LocalDateTime.now()).build());
    }

    private static boolean isStockTracked(Medication m) {
        return m.getStockUnit() != null || m.getPackageQuantity() != null
                || nvl(m.getLowStockThreshold()).signum() > 0
                || nvl(m.getStockQuantity()).signum() > 0;
    }

    private BigDecimal doseQuantity(Medication m) {
        return m.getUnitsPerDose() == null ? BigDecimal.ONE : m.getUnitsPerDose();
    }

    private StockResponse stockResponse(Medication medication) {
        BigDecimal quantity = nvl(medication.getStockQuantity());
        BigDecimal threshold = nvl(medication.getLowStockThreshold());
        return new StockResponse(medication.getId(), quantity, medication.getStockUnit(), threshold,
                medication.getPackageQuantity(), isStockTracked(medication)
                        && threshold.signum() > 0 && quantity.compareTo(threshold) <= 0,
                stockEntries.findByMedicationIdOrderByCreatedAtDescIdDesc(medication.getId()).stream()
                        .map(StockEntryResponse::from).toList());
    }

    private void generate(Medication medication, LocalDate from, LocalDate to) {
        if (medication.getStatus() != MedicationStatus.ACTIVE || !medication.isRemindersEnabled()
                || medication.getReminderTimes() == null || medication.getReminderTimes().isEmpty()) return;
        LocalDate start = from;
        LocalDate end = to;
        if (medication.getStartDate() != null && start.isBefore(medication.getStartDate())) start = medication.getStartDate();
        if (medication.getEndDate() != null && end.isAfter(medication.getEndDate())) end = medication.getEndDate();
        if (end.isBefore(start)) return;
        Set<DayOfWeek> weekdays = medication.getWeekdays() == null
                ? Set.of() : new HashSet<>(medication.getWeekdays());
        for (LocalDate day = start; !day.isAfter(end); day = day.plusDays(1)) {
            if (!weekdays.isEmpty() && !weekdays.contains(day.getDayOfWeek())) continue;
            for (LocalTime time : medication.getReminderTimes()) {
                if (!reminders.existsByMedicationIdAndDateAndTime(medication.getId(), day, time)) {
                    reminders.save(MedicationReminder.builder().medication(medication).date(day).time(time).build());
                }
            }
        }
    }

    private void validateRange(LocalDate from, LocalDate to) {
        validateDates(from, to);
        if (ChronoUnit.DAYS.between(from, to) >= MAX_SCHEDULE_DAYS) {
            badRequest("Date range cannot exceed 366 days");
        }
    }

    private void validateDates(LocalDate start, LocalDate end) {
        if (start != null && end != null && end.isBefore(start)) badRequest("End date must be after start date");
    }

    private List<LocalTime> normalizeTimes(List<LocalTime> times) {
        if (times == null) return List.of();
        if (times.stream().anyMatch(Objects::isNull)) badRequest("Reminder times must be valid");
        if (new HashSet<>(times).size() != times.size()) badRequest("Reminder times must be unique");
        return times.stream().sorted().toList();
    }

    private Medication ownedMedication(Long id, User user) {
        if (user.getRole() == Role.ADMIN) {
            return repo.findById(id)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Medication not found"));
        }
        if (user.getRole() == Role.DOCTOR) {
            return repo.findByIdAndPrescriptionDoctorId(id, user.getId())
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Medication not found"));
        }
        return repo.findByIdAndUserId(id, user.getId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Medication not found"));
    }

    private Medication ownedMedicationForUpdate(Long id, User user) {
        if (user.getRole() == Role.ADMIN) {
            return repo.findById(id)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Medication not found"));
        }
        if (user.getRole() == Role.DOCTOR) {
            return repo.findByIdAndPrescriptionDoctorIdForUpdate(id, user.getId())
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Medication not found"));
        }
        return repo.findByIdAndUserIdForUpdate(id, user.getId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Medication not found"));
    }

    private MedicationReminder findReminder(Long id, User user, boolean forUpdate) {
        Optional<MedicationReminder> result;
        if (user.getRole() == Role.ADMIN) {
            result = forUpdate ? reminders.findByIdForUpdate(id) : reminders.findById(id);
        } else if (user.getRole() == Role.DOCTOR) {
            result = forUpdate
                    ? reminders.findByIdAndMedicationPrescriptionDoctorIdForUpdate(id, user.getId())
                    : reminders.findByIdAndMedicationPrescriptionDoctorId(id, user.getId());
        } else {
            result = forUpdate
                    ? reminders.findByIdAndMedicationUserIdForUpdate(id, user.getId())
                    : reminders.findByIdAndMedicationUserId(id, user.getId());
        }
        return result.orElseThrow(
                () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Reminder not found"));
    }

    /** Ordonnance « Planning de traitement » du médecin pour ce patient (réutilisée, ou créée une fois). */
    private Prescription planningPrescription(User doctor, Long patientId) {
        requireFollowedPatient(doctor, patientId);
        User patient = users.findById(patientId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Patient not found"));
        return prescriptions.findByDoctorIdAndArchivedFalseOrderByPrescriptionDateDesc(doctor.getId()).stream()
                .filter(p -> p.getPatient().getId().equals(patientId) && PLANNING_DIAGNOSIS.equals(p.getDiagnosis()))
                .findFirst()
                .orElseGet(() -> {
                    Prescription created = prescriptions.save(Prescription.builder()
                            .doctor(doctor).patient(patient).diagnosis(PLANNING_DIAGNOSIS)
                            .prescriptionDate(LocalDate.now()).build());
                    if (!assignments.existsByDoctorIdAndPatientId(doctor.getId(), patientId)) {
                        assignments.save(DoctorPatientAssignment.builder()
                                .doctor(doctor).patient(patient).active(true).build());
                    }
                    return created;
                });
    }

    private Prescription findPrescription(Long id, User user) {
        if (id == null) return null;
        if (user.getRole() == Role.ADMIN) {
            return prescriptions.findById(id)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Prescription not found"));
        }
        if (user.getRole() == Role.DOCTOR) {
            return prescriptions.findByIdAndDoctorId(id, user.getId())
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Prescription not found"));
        }
        return prescriptions.findByIdAndPatientId(id, user.getId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Prescription not found"));
    }

    private List<Medication> visibleMedications(User user) {
        return switch (user.getRole()) {
            case ADMIN -> repo.findAll();
            case DOCTOR -> repo.findByPrescriptionDoctorIdOrderByName(user.getId());
            case USER -> repo.findByUserIdOrderByName(user.getId());
        };
    }

    private List<Medication> visibleMedications(User user, Long patientId) {
        if (patientId == null) return visibleMedications(user);
        requireFollowedPatient(user, patientId);
        // Le médecin qui suit le patient voit tout son traitement (pas seulement ses propres prescriptions).
        return repo.findByUserIdOrderByName(patientId);
    }

    private void requireFollowedPatient(User user, Long patientId) {
        boolean follows = user.getRole() == Role.DOCTOR && users.findById(patientId)
                .map(patient -> healthAccess.follows(user, patient)).orElse(false);
        if (!follows) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Patient not found");
    }

    /** Verrouille un médicament visible : celui de l'utilisateur, ou celui d'un patient suivi par le médecin. */
    private Medication visibleMedicationForUpdate(Long id, User user, Long patientId) {
        if (patientId == null) return ownedMedicationForUpdate(id, user);
        requireFollowedPatient(user, patientId);
        return repo.findByIdAndUserIdForUpdate(id, patientId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Medication not found"));
    }

    /** Médecin, administrateur, ou patient pour ses propres prises (pas pour modifier le traitement). */
    private void requireIntakeRecorder(User user) {
        if (user.getRole() != Role.USER) requireScheduleManager(user);
    }

    private void requireScheduleManager(User user) {
        if (user.getRole() != Role.DOCTOR && user.getRole() != Role.ADMIN) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Patients can only consult their medication agenda");
        }
    }

    private User currentUser(Authentication auth) {
        return users.findByEmail(auth.getName())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "User not found"));
    }

    private long count(List<MedicationReminder> entries, IntakeStatus status) {
        return entries.stream().filter(r -> r.getStatus() == status).count();
    }

    private String trimOrNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private static BigDecimal nvl(BigDecimal value) {
        return value == null ? ZERO : value;
    }

    private void badRequest(String message) {
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, message);
    }
}
