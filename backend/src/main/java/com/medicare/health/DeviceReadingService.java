package com.medicare.health;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.*;

/**
 * Volet IA « lecture d'une mesure par photo » : le patient photographie l'écran de son appareil
 * (tensiomètre, thermomètre, balance, glucomètre), le modèle de vision local (Ollama, llava)
 * lit les chiffres affichés et le serveur vérifie qu'ils sont plausibles.
 * Rien n'est enregistré ici : les valeurs pré-remplissent seulement le formulaire de mesure,
 * que le patient vérifie, corrige au besoin et valide lui-même.
 */
@Slf4j
@Service
public class DeviceReadingService {

    /** Appareils pris en charge : une photo par appareil. */
    public enum Device { BLOOD_PRESSURE, TEMPERATURE, WEIGHT, GLYCEMIA }

    @Value("${app.ollama.base-url:http://localhost:11434}")
    private String ollamaBaseUrl;

    @Value("${app.ollama.vision-model:llava}")
    private String visionModel;

    @Value("${app.ollama.keep-alive:60m}")
    private String keepAlive;

    private final RestTemplate restTemplate;
    private final ObjectMapper mapper = new ObjectMapper();

    public DeviceReadingService() {
        var factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        factory.setReadTimeout(300_000);
        this.restTemplate = new RestTemplate(factory);
    }

    /**
     * Lit la photo de l'écran de l'appareil. Renvoie {@code success}, {@code values}
     * (clés du formulaire : systolic, diastolic, heartRate, weight, temperature, glycemia)
     * et un {@code message} à afficher au patient.
     */
    public Map<String, Object> read(Device device, String base64Image) {
        Map<String, Object> raw;
        try {
            raw = askVisionModel(prompt(device), base64Image);
        } catch (Exception e) {
            log.warn("Lecture d'appareil impossible ({}) : {}", device, e.getMessage());
            return failure("Le service de lecture IA est indisponible (Ollama / modèle « " + visionModel
                    + " »). Saisissez la mesure manuellement ou réessayez plus tard.");
        }
        log.info("Lecture brute {} : {}", device, raw);
        // Le modèle renvoie parfois les libellés de l'écran (SYS, DIA, PUL) au lieu des clés demandées.
        Map<String, Object> normalized = new HashMap<>();
        raw.forEach((k, v) -> normalized.put(k.toLowerCase(Locale.ROOT), v));
        alias(normalized, "systolic", "sys");
        alias(normalized, "diastolic", "dia");
        alias(normalized, "pulse", "pul", "heart_rate", "heartrate", "pr");
        raw = normalized;
        return switch (device) {
            case BLOOD_PRESSURE -> checkBloodPressure(raw);
            case TEMPERATURE -> checkTemperature(raw);
            case WEIGHT -> checkWeight(raw);
            case GLYCEMIA -> checkGlycemia(raw);
        };
    }

    // ── Consignes données au modèle de vision ───────────────────────────────

    /**
     * Consignes en anglais (llava les suit mieux) et SANS valeur d'exemple : testé, le modèle
     * recopiait l'exemple (« 72.4 ») ou inventait 120/80 sur une photo sans appareil.
     * Avec « set every value to null », une photo sans écran renvoie bien null → échec → reprendre la photo.
     */
    private static String prompt(Device device) {
        String rule = " Copy only numbers that are really shown on the display; never guess or invent. "
                + "If the photo shows no device display with numbers, set every value to null. ";
        return switch (device) {
            case BLOOD_PRESSURE -> "Read the digital display of the blood pressure monitor in this photo." + rule
                    + "Return JSON with keys systolic (SYS, top number), diastolic (DIA, middle number), "
                    + "pulse (PUL, bottom number).";
            case TEMPERATURE -> "Read the digital display of the thermometer in this photo." + rule
                    + "Return JSON with keys temperature (number with a decimal point) and unit (C or F).";
            case WEIGHT -> "Read the digital display of the bathroom scale in this photo." + rule
                    + "Return JSON with keys weight (number with a decimal point) and unit (kg or lb).";
            case GLYCEMIA -> "Read the digital display of the blood glucose meter in this photo." + rule
                    + "Return JSON with keys glycemia (the number shown) and unit (mg/dL, mmol/L or g/L as shown, "
                    + "null if no unit is visible).";
        };
    }

    private static void alias(Map<String, Object> map, String key, String... aliases) {
        if (map.get(key) != null) return;
        for (String a : aliases) {
            if (map.get(a) != null) { map.put(key, map.get(a)); return; }
        }
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> askVisionModel(String prompt, String base64Image) throws Exception {
        Map<String, Object> body = new HashMap<>();
        body.put("model", visionModel);
        body.put("prompt", prompt);
        body.put("images", List.of(base64Image));
        body.put("stream", false);
        body.put("format", "json");
        body.put("keep_alive", keepAlive);
        // Température 0 : on veut une lecture fidèle, pas une réponse créative. Réponse JSON très courte.
        body.put("options", Map.of("num_ctx", 2048, "num_predict", 80, "temperature", 0));
        var headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        ResponseEntity<Map> resp = restTemplate.exchange(
                ollamaBaseUrl + "/api/generate", HttpMethod.POST, new HttpEntity<>(body, headers), Map.class);
        String text = String.valueOf(resp.getBody().get("response")).trim();
        int start = text.indexOf('{');
        int end = text.lastIndexOf('}');
        if (start < 0 || end <= start) throw new IllegalStateException("Réponse du modèle sans JSON");
        return mapper.readValue(text.substring(start, end + 1), Map.class);
    }

    // ── Vérification de plausibilité ────────────────────────────────────────

    private static Map<String, Object> checkBloodPressure(Map<String, Object> raw) {
        Double sys = number(raw.get("systolic"));
        Double dia = number(raw.get("diastolic"));
        Double pulse = number(raw.get("pulse"));
        if (sys == null || dia == null) {
            return failure("La tension n'a pas pu être lue. Reprenez la photo bien en face de l'écran du tensiomètre, sans reflet.");
        }
        if (sys < 60 || sys > 260 || dia < 30 || dia > 160 || sys <= dia) {
            return failure(String.format(Locale.FRANCE,
                    "Lecture non plausible (%s/%s mmHg). Reprenez la photo de l'écran du tensiomètre.",
                    fmt(sys, 0), fmt(dia, 0)));
        }
        Map<String, Object> values = new LinkedHashMap<>();
        values.put("systolic", Math.round(sys));
        values.put("diastolic", Math.round(dia));
        String message = "Tension lue : " + Math.round(sys) + "/" + Math.round(dia) + " mmHg";
        if (pulse != null && pulse >= 30 && pulse <= 220) {
            values.put("heartRate", Math.round(pulse));
            message += ", pouls " + Math.round(pulse) + " bpm";
        } else {
            message += " (pouls illisible : saisissez-le si besoin)";
        }
        return success(values, message + ". Vérifiez avant de valider.");
    }

    private static Map<String, Object> checkTemperature(Map<String, Object> raw) {
        Double t = number(raw.get("temperature"));
        if (t == null) return failure("La température n'a pas pu être lue. Reprenez la photo de l'écran du thermomètre.");
        boolean fahrenheit = "F".equalsIgnoreCase(String.valueOf(raw.get("unit")).replace("°", "").trim()) || t > 80;
        if (fahrenheit) t = (t - 32) * 5 / 9;
        // Écran à virgule non lue : « 368 » pour 36,8 °C.
        if (t >= 340 && t <= 430) t = t / 10;
        if (t < 34 || t > 43) {
            return failure("Lecture non plausible (" + fmt(t, 1) + " °C). Reprenez la photo de l'écran du thermomètre.");
        }
        double value = Math.round(t * 10) / 10.0;
        return success(Map.of("temperature", value),
                "Température lue : " + fmt(value, 1) + " °C. Vérifiez avant de valider.");
    }

    private static Map<String, Object> checkWeight(Map<String, Object> raw) {
        Double w = number(raw.get("weight"));
        if (w == null) return failure("Le poids n'a pas pu être lu. Reprenez la photo de l'écran de la balance.");
        if ("lb".equalsIgnoreCase(String.valueOf(raw.get("unit")).trim())) w = w * 0.453592;
        if (w < 2 || w > 300) {
            return failure("Lecture non plausible (" + fmt(w, 1) + " kg). Reprenez la photo de l'écran de la balance.");
        }
        double value = Math.round(w * 10) / 10.0;
        return success(Map.of("weight", value), "Poids lu : " + fmt(value, 1) + " kg. Vérifiez avant de valider.");
    }

    private static Map<String, Object> checkGlycemia(Map<String, Object> raw) {
        Double g = number(raw.get("glycemia"));
        if (g == null) return failure("La glycémie n'a pas pu être lue. Reprenez la photo de l'écran du glucomètre.");
        String unit = String.valueOf(raw.get("unit")).toLowerCase(Locale.ROOT).replace(" ", "");
        // L'application enregistre la glycémie en g/L : conversion depuis l'unité affichée.
        double gPerL;
        String shown;
        if (unit.contains("mg")) { gPerL = g / 100; shown = "mg/dL"; }
        else if (unit.contains("mmol")) { gPerL = g * 0.18; shown = "mmol/L"; }
        else if (unit.contains("g/l")) { gPerL = g; shown = "g/L"; }
        else if (g >= 20) { gPerL = g / 100; shown = "mg/dL"; }      // unité absente : 95 → mg/dL
        else if (g > 3.5) { gPerL = g * 0.18; shown = "mmol/L"; }    // 5.4 → mmol/L
        else { gPerL = g; shown = "g/L"; }                           // 0.95 → g/L
        if (gPerL < 0.2 || gPerL > 6) {
            return failure("Lecture non plausible (" + fmt(gPerL, 2) + " g/L). Reprenez la photo de l'écran du glucomètre.");
        }
        double value = Math.round(gPerL * 100) / 100.0;
        return success(Map.of("glycemia", value), "Glycémie lue : " + fmt(value, 2) + " g/L"
                + ("g/L".equals(shown) ? "" : " (convertie depuis " + fmt(g, 1) + " " + shown + ")")
                + ". Vérifiez avant de valider.");
    }

    // ── Utilitaires ─────────────────────────────────────────────────────────

    /** Accepte 120, "120", "36,8", "120 mmHg" ; renvoie null si aucun nombre. */
    static Double number(Object value) {
        if (value instanceof Number n) return n.doubleValue();
        if (value == null) return null;
        var m = java.util.regex.Pattern.compile("-?\\d+(?:[.,]\\d+)?").matcher(String.valueOf(value));
        return m.find() ? Double.parseDouble(m.group().replace(',', '.')) : null;
    }

    private static String fmt(double v, int decimals) {
        return String.format(Locale.FRANCE, "%." + decimals + "f", v);
    }

    private static Map<String, Object> success(Map<String, Object> values, String message) {
        Map<String, Object> r = new HashMap<>();
        r.put("success", true);
        r.put("values", values);
        r.put("message", message);
        return r;
    }

    private static Map<String, Object> failure(String message) {
        Map<String, Object> r = new HashMap<>();
        r.put("success", false);
        r.put("values", Map.of());
        r.put("message", message);
        return r;
    }
}
