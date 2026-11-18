package com.medicare.health;

import com.medicare.appointment.Appointment;
import com.medicare.appointment.AppointmentRepository;
import com.medicare.appointment.AppointmentStatus;
import com.medicare.medication.DoctorPatientAssignment;
import com.medicare.medication.DoctorPatientAssignmentRepository;
import com.medicare.nutrition.Hydration;
import com.medicare.nutrition.HydrationRepository;
import com.medicare.nutrition.Meal;
import com.medicare.nutrition.MealRepository;
import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import com.medicare.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.core.annotation.Order;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;

/**
 * Mode dev uniquement — comptes et données de démonstration du module Suivi santé et nutrition.
 *
 * <pre>
 * Patient                               Profil                         Médecin et lien
 * patient@medicare.com   Patient Test   constantes normales            Dr Ahmed  (Médicaments : suivi actif)
 * patient2@medicare.com  Amine Trabelsi hypertension, surpoids         Dr Ahmed  (Rendez-vous)
 * patient3@medicare.com  Sonia Mejri    glycémie élevée, fièvre        Dr Sarah  (Médicaments + Rendez-vous)
 * </pre>
 * Mot de passe des patients : Patient@2026 — médecins : Doctor@2026 (créés par DevSecretarySeeder).
 * Chaque étape est idempotente : rien n'est recréé si la donnée existe déjà.
 */
@Component
@Profile("dev")
@Order(100)
@RequiredArgsConstructor
public class DevHealthDataSeeder implements ApplicationRunner {
    static final String PASSWORD = "Patient@2026";

    private final UserRepository users;
    private final PasswordEncoder encoder;
    private final HealthRecordRepository records;
    private final HealthGoalRepository goals;
    private final MealRepository meals;
    private final HydrationRepository hydration;
    private final DoctorPatientAssignmentRepository assignments;
    private final AppointmentRepository appointments;

    /** Valeurs de départ (il y a 30 jours) et d'arrivée (aujourd'hui) des constantes. */
    private record Profile(double weightFrom, double weightTo, int hrFrom, int hrTo,
                           int sysFrom, int sysTo, int diaFrom, int diaTo,
                           double glyFrom, double glyTo, double lastTemperature,
                           double height, double targetWeight, int calorieGoal,
                           double mealFactor, int glassesPerDay) {}

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        User ahmed = users.findByEmailIgnoreCase("dr.ahmed@medicare.com").orElse(null);
        User sarah = users.findByEmailIgnoreCase("dr.sarah@medicare.com").orElse(null);

        User p1 = account("Patient Test", "patient@medicare.com");
        User p2 = account("Amine Trabelsi", "patient2@medicare.com");
        User p3 = account("Sonia Mejri", "patient3@medicare.com");

        // Liens médecin ↔ patient, partagés avec les modules Médicaments et Rendez-vous.
        if (ahmed != null) {
            follow(ahmed, p1);
            appointment(p2, ahmed, -6, AppointmentStatus.COMPLETED, "Contrôle de la tension");
            appointment(p2, ahmed, 5, AppointmentStatus.CONFIRMED, "Suivi hypertension");
        }
        if (sarah != null) {
            follow(sarah, p3);
            appointment(p3, sarah, 2, AppointmentStatus.PLANNED, "Bilan glycémique");
        }

        seed(p1, new Profile(77.2, 74.8, 76, 71, 128, 120, 83, 79, 0.98, 0.92, 36.7,
                175, 72, 2100, 1.0, 7));
        seed(p2, new Profile(92.4, 90.1, 84, 86, 146, 148, 92, 95, 1.04, 1.06, 36.8,
                178, 82, 2200, 1.35, 4));
        if (ahmed != null) consultation(p2, ahmed);
        seed(p3, new Profile(63.5, 62.8, 74, 98, 124, 126, 80, 81, 1.32, 1.58, 38.7,
                164, 60, 1800, 0.9, 6));
    }

    private User account(String fullName, String email) {
        return users.findByEmailIgnoreCase(email).orElseGet(() -> users.save(User.builder()
                .fullName(fullName).email(email).password(encoder.encode(PASSWORD))
                .emailVerified(true).role(Role.USER).build()));
    }

    private void follow(User doctor, User patient) {
        if (!assignments.existsByDoctorIdAndPatientId(doctor.getId(), patient.getId())
                && !assignments.existsByPatientId(patient.getId())) {
            assignments.save(DoctorPatientAssignment.builder().doctor(doctor).patient(patient).build());
        }
    }

    private void appointment(User patient, User doctor, int daysFromNow, AppointmentStatus status, String reason) {
        boolean exists = appointments.findByUserIdOrderByDateTimeDesc(patient.getId()).stream()
                .anyMatch(a -> a.getDoctor() != null && a.getDoctor().getId().equals(doctor.getId())
                        && reason.equals(a.getReason()));
        if (exists) return;
        appointments.save(Appointment.builder()
                .user(patient).doctor(doctor).doctorName(doctor.getFullName())
                .dateTime(LocalDate.now().plusDays(daysFromNow).atTime(10, 30))
                .reason(reason).appointmentType("Consultation").status(status).build());
    }

    /** Mesure prise par le médecin pendant le rendez-vous passé (lecture seule pour le patient). */
    private void consultation(User patient, User doctor) {
        if (records.existsByUserIdAndRecordedByIsNotNull(patient.getId())) return;
        records.save(HealthRecord.builder().user(patient).recordedBy(doctor)
                .recordedAt(LocalDate.now().minusDays(6).atTime(10, 45))
                .weight(90.6).heartRate(88).systolic(152).diastolic(97).temperature(36.8)
                .note("Mesure au cabinet - contrôle tension").build());
    }

    private void seed(User patient, Profile p) {
        if (records.existsByUserId(patient.getId())) return;
        LocalDate today = LocalDate.now();

        if (goals.findByUserId(patient.getId()).isEmpty()) {
            goals.save(HealthGoal.builder().user(patient).heightCm(p.height()).targetWeight(p.targetWeight())
                    .dailyCalorieGoal(p.calorieGoal()).dailyWaterGoalMl(2000).updatedBy(patient).build());
        }

        for (int i = 29; i >= 0; i -= 2) {
            double t = (29 - i) / 29.0;
            boolean latest = i <= 1;
            records.save(HealthRecord.builder().user(patient)
                    .recordedAt(LocalDateTime.of(today.minusDays(i), LocalTime.of(8, 15)))
                    .weight(round(lerp(p.weightFrom(), p.weightTo(), t) + (i % 3 == 0 ? 0.3 : -0.1), 1))
                    .heartRate((int) Math.round(lerp(p.hrFrom(), p.hrTo(), t)) + (i % 4 == 0 ? 2 : 0))
                    .systolic((int) Math.round(lerp(p.sysFrom(), p.sysTo(), t)))
                    .diastolic((int) Math.round(lerp(p.diaFrom(), p.diaTo(), t)))
                    .temperature(latest ? p.lastTemperature() : round(36.6 + (i % 5) * 0.1, 1))
                    .glycemia(round(lerp(p.glyFrom(), p.glyTo(), t) + (i % 3) * 0.02, 2))
                    .build());
        }

        String[][] menu = {
            {"BREAKFAST", "07:45", "Flocons d'avoine 60 g, Lait demi-écrémé 200 ml, Banane 120 g", "422", "17", "70", "8", "9"},
            {"LUNCH", "12:30", "Poulet grillé 150 g, Riz blanc cuit 150 g, Salade verte 80 g", "455", "51", "45", "6", "2"},
            {"SNACK", "16:30", "Yaourt nature 125 g, Amandes 20 g", "192", "8.6", "10", "14", "2.5"},
            {"DINNER", "19:45", "Saumon 120 g, Pomme de terre cuite 200 g, Brocoli 150 g", "475", "30", "51", "17", "7.5"},
        };
        for (int i = 13; i >= 0; i--) {
            LocalDate day = today.minusDays(i);
            for (int m = 0; m < menu.length; m++) {
                if (i == 0 && m >= 2) continue;          // aujourd'hui : petit-déjeuner et déjeuner seulement
                if (i % 4 == 1 && m == 2) continue;      // collation certains jours seulement
                String[] row = menu[m];
                double f = p.mealFactor();
                meals.save(Meal.builder().user(patient)
                        .mealType(Meal.MealType.valueOf(row[0])).mealDate(day).mealTime(LocalTime.parse(row[1]))
                        .description(row[2])
                        .calories(round(Double.parseDouble(row[3]) * f, 0))
                        .protein(round(Double.parseDouble(row[4]) * f, 1))
                        .carbohydrates(round(Double.parseDouble(row[5]) * f, 1))
                        .fat(round(Double.parseDouble(row[6]) * f, 1))
                        .fiber(round(Double.parseDouble(row[7]) * f, 1)).build());
            }
            int glasses = i == 0 ? Math.max(2, p.glassesPerDay() - 3) : p.glassesPerDay() + (i % 3) - 1;
            for (int g = 0; g < glasses; g++) {
                hydration.save(Hydration.builder().user(patient).recordedDate(day)
                        .recordedTime(LocalTime.of(8 + g * 2 % 14, 0)).quantityMl(250).build());
            }
        }
    }

    private static double lerp(double from, double to, double t) {
        return from + (to - from) * t;
    }

    private static double round(double value, int decimals) {
        double factor = Math.pow(10, decimals);
        return Math.round(value * factor) / factor;
    }
}
