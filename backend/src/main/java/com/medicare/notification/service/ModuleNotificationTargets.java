package com.medicare.notification.service;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import java.util.regex.Pattern;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/** Reads recipient IDs only; never changes M1-M4 entities. */
@Component
@Transactional(readOnly = true)
public class ModuleNotificationTargets {
    @PersistenceContext private EntityManager em;
    private static final Pattern RESOURCE = Pattern.compile(
            "^/api/(appointments|secretary/appointments|medications|medications/reminders|health-records|prescriptions)/(\\d+)(?:/.*)?$");

    public Long medication(Long id) { return id("select m.user.id from Medication m where m.id=:id", id); }

    public Long existing(String path) {
        var match = RESOURCE.matcher(path);
        if (!match.matches()) return null;
        String query = switch (match.group(1)) {
            case "appointments", "secretary/appointments" -> "select a.user.id from Appointment a where a.id=:id";
            case "medications" -> "select m.user.id from Medication m where m.id=:id";
            case "medications/reminders" -> "select r.medication.user.id from MedicationReminder r where r.id=:id";
            case "health-records" -> "select h.user.id from HealthRecord h where h.id=:id";
            case "prescriptions" -> "select p.patient.id from Prescription p where p.id=:id";
            default -> throw new IllegalArgumentException("Unknown module");
        };
        return id(query, Long.valueOf(match.group(2)));
    }

    private Long id(String query, Long id) {
        return em.createQuery(query, Long.class).setParameter("id", id).getResultList().stream().findFirst().orElse(null);
    }
}
