package com.medicare.health;

import com.medicare.common.ApiException;
import com.medicare.nutrition.AiNutritionService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
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
    private final DeviceReadingService deviceReader;

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

        var instantAlerts = buildInstantAlerts(recent);
        // Les alertes calculées sont transmises au modèle pour que son résumé ne les contredise pas.
        List<String> alertLabels = instantAlerts.stream()
                .map(a -> a.get("metric") + " (" + a.get("value") + ")")
                .toList();
        Map<String, Object> result = recent.isEmpty()
                ? aiService.emptyHealthResponse()
                : aiService.analyzeHealthRecords(recordMaps, goalMap, alertLabels);
        result.put("instantAlerts", instantAlerts);
        // Statut et urgence découlent des seuils médicaux fixes, pas du modèle de langage,
        // pour que l'écran ne signale jamais une valeur normale comme anormale.
        boolean red = instantAlerts.stream().anyMatch(a -> "red".equals(a.get("color")));
        boolean orange = instantAlerts.stream().anyMatch(a -> "orange".equals(a.get("color")));
        result.put("status", red ? "alerte" : orange ? "attention" : "bon");
        result.put("statusColor", red ? "red" : orange ? "orange" : "green");
        result.put("urgency", red ? "urgent" : orange ? "attention" : "normal");
        result.put("alerts", List.of());
        result.put("recordCount", recent.size());
        return result;
    }

    public record DeviceReadingRequest(String device, String image) {}

    /**
     * Lecture IA d'une photo d'écran d'appareil (tensiomètre, thermomètre, balance, glucomètre).
     * Ne fait que lire et vérifier : rien n'est enregistré sans la validation du patient.
     */
    @PostMapping("/read-device")
    public Map<String, Object> readDevice(@RequestBody DeviceReadingRequest req) {
        if (req.image() == null || req.image().isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Ajoutez une photo de l'écran de l'appareil.");
        }
        if (req.image().length() > 8_000_000) {
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "Image trop volumineuse (6 Mo maximum).");
        }
        DeviceReadingService.Device device;
        try {
            device = DeviceReadingService.Device.valueOf(String.valueOf(req.device()).toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw new ApiException(HttpStatus.BAD_REQUEST,
                    "Appareil inconnu : BLOOD_PRESSURE, TEMPERATURE, WEIGHT ou GLYCEMIA attendu.");
        }
        return deviceReader.read(device, req.image());
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
