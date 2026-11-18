package com.medicare.health;

import com.medicare.nutrition.AiNutritionService;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.*;

/** Analyse IA des mesures des 30 derniers jours + alertes instantanées basées sur des règles. */
@RestController
@RequestMapping("/api/health/ai")
@RequiredArgsConstructor
public class HealthAiController {

    private final HealthRecordRepository healthRepo;
    private final HealthGoalRepository goalRepo;
    private final HealthAccessService access;
    private final AiNutritionService aiService;

    @GetMapping("/analyze")
    public Map<String, Object> analyze(@RequestParam(required = false) Long patientId, Authentication auth) {
        var user = access.resolve(auth, patientId).patient();
        var cutoff = LocalDateTime.now().minusDays(30);
        var recent = healthRepo.findByUserIdOrderByRecordedAtDesc(user.getId()).stream()
                .filter(r -> r.getRecordedAt().isAfter(cutoff))
                .limit(20)
                .toList();

        List<Map<String, Object>> recordMaps = new ArrayList<>();
        for (var r : recent) {
            Map<String, Object> m = new HashMap<>();
            m.put("recordedAt", r.getRecordedAt().toString());
            if (r.getWeight() != null)      m.put("weight", r.getWeight());
            if (r.getHeartRate() != null)   m.put("heartRate", r.getHeartRate());
            if (r.getSystolic() != null)    m.put("systolic", r.getSystolic());
            if (r.getDiastolic() != null)   m.put("diastolic", r.getDiastolic());
            if (r.getTemperature() != null) m.put("temperature", r.getTemperature());
            if (r.getGlycemia() != null)    m.put("glycemia", r.getGlycemia());
            recordMaps.add(m);
        }

        Map<String, Object> goalMap = null;
        var goal = goalRepo.findByUserId(user.getId());
        if (goal.isPresent()) {
            goalMap = new HashMap<>();
            goalMap.put("heightCm", goal.get().getHeightCm());
            goalMap.put("targetWeight", goal.get().getTargetWeight());
        }

        Map<String, Object> result = recent.isEmpty()
                ? aiService.emptyHealthResponse()
                : aiService.analyzeHealthRecords(recordMaps, goalMap);
        result.put("instantAlerts", buildInstantAlerts(recent));
        result.put("recordCount", recent.size());
        return result;
    }

    /** Contrôle la valeur la plus récente de chaque constante (pas forcément issue de la même mesure). */
    static List<Map<String, Object>> buildInstantAlerts(List<HealthRecord> newestFirst) {
        List<Map<String, Object>> alerts = new ArrayList<>();
        newestFirst.stream().map(HealthRecord::getTemperature).filter(Objects::nonNull).findFirst().ifPresent(t -> {
            if (t >= 38.5) alerts.add(alert("Hyperthermie", t + " °C", "36,1 - 37,2 °C", "red", "Fièvre élevée — consultez un médecin"));
            else if (t >= 37.5) alerts.add(alert("Fièvre légère", t + " °C", "36,1 - 37,2 °C", "orange", "Température élevée — repos recommandé"));
            else if (t < 36.0) alerts.add(alert("Hypothermie légère", t + " °C", "36,1 - 37,2 °C", "orange", "Température basse"));
        });
        newestFirst.stream().map(HealthRecord::getGlycemia).filter(Objects::nonNull).findFirst().ifPresent(g -> {
            if (g > 1.26) alerts.add(alert("Glycémie critique", g + " g/L", "0,70 - 1,00 g/L à jeun", "red", "Hyperglycémie — consultez un médecin"));
            else if (g > 1.00) alerts.add(alert("Glycémie élevée", g + " g/L", "0,70 - 1,00 g/L à jeun", "orange", "Glycémie au-dessus de la normale à jeun"));
            else if (g < 0.70) alerts.add(alert("Hypoglycémie", g + " g/L", "0,70 - 1,00 g/L à jeun", "red", "Glycémie trop basse — prenez du sucre rapidement"));
        });
        newestFirst.stream().filter(r -> r.getSystolic() != null).findFirst().ifPresent(r -> {
            int s = r.getSystolic();
            Integer d = r.getDiastolic();
            String value = s + "/" + (d == null ? "?" : d) + " mmHg";
            if (s >= 140 || (d != null && d >= 90)) alerts.add(alert("Hypertension", value, "< 120/80 mmHg", "red", "Tension artérielle élevée"));
            else if (s >= 130 || (d != null && d >= 85)) alerts.add(alert("Pré-hypertension", value, "< 120/80 mmHg", "orange", "Surveillez votre tension"));
            else if (s < 90) alerts.add(alert("Hypotension", value, "< 120/80 mmHg", "orange", "Tension artérielle basse"));
        });
        newestFirst.stream().map(HealthRecord::getHeartRate).filter(Objects::nonNull).findFirst().ifPresent(hr -> {
            if (hr > 100) alerts.add(alert("Tachycardie", hr + " bpm", "60 - 100 bpm", "orange", "Fréquence cardiaque élevée au repos"));
            else if (hr < 60) alerts.add(alert("Bradycardie", hr + " bpm", "60 - 100 bpm", "orange", "Fréquence cardiaque basse au repos"));
        });
        return alerts;
    }

    private static Map<String, Object> alert(String metric, String value, String normal, String color, String message) {
        Map<String, Object> a = new HashMap<>();
        a.put("metric", metric); a.put("value", value);
        a.put("normal", normal); a.put("color", color);
        a.put("message", message);
        return a;
    }
}
