package com.medicare.health;

import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.*;

/**
 * Espace médecin du module Suivi santé et nutrition : liste des patients suivis
 * (via le module Médicaments ou le module Rendez-vous) avec un résumé de leurs constantes.
 */
@RestController
@RequestMapping("/api/health/patients")
@RequiredArgsConstructor
public class DoctorHealthController {
    private final HealthAccessService access;
    private final HealthRecordRepository records;

    @GetMapping
    @Transactional(readOnly = true)
    public List<Map<String, Object>> followed(Authentication auth) {
        var doctor = access.current(auth);
        List<Map<String, Object>> result = new ArrayList<>();
        access.followedPatients(doctor).forEach((patient, sources) -> {
            var all = records.findByUserIdOrderByRecordedAtDesc(patient.getId());
            var cutoff = LocalDateTime.now().minusDays(30);
            var recent = all.stream().filter(r -> r.getRecordedAt().isAfter(cutoff)).toList();
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("id", patient.getId());
            row.put("fullName", patient.getFullName());
            row.put("email", patient.getEmail());
            row.put("sources", sources);
            row.put("measureCount", all.size());
            row.put("lastMeasureAt", all.isEmpty() ? null : all.get(0).getRecordedAt());
            row.put("lastWeight", latest(all, HealthRecord::getWeight));
            row.put("lastHeartRate", latest(all, HealthRecord::getHeartRate));
            row.put("lastGlycemia", latest(all, HealthRecord::getGlycemia));
            var pressure = all.stream().filter(r -> r.getSystolic() != null).findFirst();
            row.put("lastPressure", pressure.map(r -> r.getSystolic() + "/" + r.getDiastolic()).orElse(null));
            var alerts = HealthAiController.buildInstantAlerts(recent);
            row.put("alertCount", alerts.size());
            row.put("alerts", alerts.stream().map(a -> a.get("metric")).toList());
            result.add(row);
        });
        return result;
    }

    private static <T> T latest(List<HealthRecord> newestFirst, java.util.function.Function<HealthRecord, T> field) {
        return newestFirst.stream().map(field).filter(Objects::nonNull).findFirst().orElse(null);
    }
}
