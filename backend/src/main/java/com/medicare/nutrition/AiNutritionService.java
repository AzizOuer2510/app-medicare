package com.medicare.nutrition;

import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.http.*;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import java.util.*;

/**
 * Service IA du module Suivi santé et nutrition — utilise Ollama (local, gratuit).
 * - Analyse photo d'un repas : modèle de vision (llava)
 * - Analyse d'un repas décrit en texte : llama3.2
 * - Chatbot NutriCoach : llama3.2
 * - Analyse des mesures de santé : llama3.2
 * Si Ollama n'est pas démarré, des réponses de démonstration sont renvoyées (champ demo_mode = true).
 */
@Slf4j
@Service
public class AiNutritionService {

    @Value("${app.ollama.base-url:http://localhost:11434}")
    private String ollamaBaseUrl;

    @Value("${app.ollama.chat-model:llama3.2}")
    private String chatModel;

    @Value("${app.ollama.vision-model:llava}")
    private String visionModel;

    /** Durée pendant laquelle Ollama garde le modèle en mémoire après un appel (évite le rechargement). */
    @Value("${app.ollama.keep-alive:60m}")
    private String keepAlive;

    /**
     * Fenêtre de contexte identique pour tous les appels au modèle texte : un changement
     * de num_ctx entre deux appels force Ollama à recharger le modèle.
     */
    private static final int CONTEXT_TOKENS = 2048;
    /** Nombre de messages précédents envoyés à NutriCoach (les plus récents). */
    private static final int CHAT_HISTORY_LIMIT = 8;

    private final RestTemplate restTemplate;
    private final ObjectMapper mapper = new ObjectMapper();

    public AiNutritionService() {
        // Les modèles locaux peuvent être lents au premier chargement.
        var factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        factory.setReadTimeout(300_000);
        this.restTemplate = new RestTemplate(factory);
    }

    /**
     * Charge le modèle texte en mémoire dès le démarrage du backend, en arrière-plan,
     * pour que la première analyse demandée par un utilisateur ne paie pas le chargement.
     */
    @EventListener(ApplicationReadyEvent.class)
    public void warmUp() {
        Thread warm = new Thread(() -> {
            try {
                chatCompletion(List.of(Map.of("role", "user", "content", "OK")), 1, 0, false);
                log.info("Modèle IA « {} » chargé en mémoire (keep_alive {}).", chatModel, keepAlive);
            } catch (Exception e) {
                log.info("Ollama indisponible au démarrage : les écrans IA passeront en mode démonstration.");
            }
        }, "ollama-warmup");
        warm.setDaemon(true);
        warm.start();
    }

    // ── Vision : analyse d'une photo de repas ────────────────────────────────
    @SuppressWarnings("unchecked")
    public Map<String, Object> analyzeFoodImage(String base64Image) {
        try {
            // Le schéma est décrit en mots, sans valeurs d'exemple : avec un gabarit littéral,
            // le modèle de vision recopiait parfois « nom en français » au lieu d'analyser l'image.
            String prompt = "Analyse cette photo de repas et identifie chaque aliment réellement visible. " +
                "Réponds uniquement par un objet JSON avec les clés : " +
                "foods (liste d'objets avec name = nom de l'aliment en français, quantity = quantité estimée avec son unité, " +
                "calories, protein, carbs, fat = nombres estimés pour cette quantité), " +
                "total_calories, total_protein, total_carbs, total_fat (sommes des aliments) " +
                "et description (une phrase en français décrivant le repas). " +
                "Si la photo ne montre aucun aliment, renvoie foods vide, des totaux à 0 " +
                "et description = \"Aucun aliment reconnu sur la photo\".";

            Map<String, Object> body = new HashMap<>();
            body.put("model", visionModel);
            body.put("prompt", prompt);
            body.put("images", List.of(base64Image));
            body.put("stream", false);
            body.put("format", "json");
            body.put("keep_alive", keepAlive);
            // Contexte réduit : le modèle tient davantage sur le GPU ; réponse JSON courte.
            body.put("options", Map.of("num_ctx", CONTEXT_TOKENS, "num_predict", 400, "temperature", 0.2));

            ResponseEntity<Map> resp = restTemplate.exchange(
                ollamaBaseUrl + "/api/generate", HttpMethod.POST, new HttpEntity<>(body, jsonHeaders()), Map.class);
            Map<String, Object> result = parseJson((String) resp.getBody().get("response"));
            if (String.valueOf(result.get("foods")).contains("nom en français")) {
                throw new IllegalStateException("Réponse du modèle de vision non exploitable");
            }
            return result;
        } catch (Exception e) {
            return mockFoodResponse("Analyse photo indisponible — démarrez Ollama avec le modèle « "
                    + visionModel + " ». Valeurs d'exemple, modifiables avant l'enregistrement.");
        }
    }

    // ── Analyse d'un repas décrit en texte ──────────────────────────────────
    public Map<String, Object> analyzeByDescription(String description) {
        try {
            String prompt = "Tu es un expert en nutrition. Repas décrit : \"" + description + "\"\n" +
                "Identifie les aliments et estime les valeurs nutritionnelles.\n" +
                "Retourne UNIQUEMENT du JSON valide sans markdown ni texte supplémentaire :\n" +
                "{\"foods\":[{\"name\":\"nom en français\",\"quantity\":\"quantité estimée\",\"calories\":0,\"protein\":0,\"carbs\":0,\"fat\":0}]," +
                "\"total_calories\":0,\"total_protein\":0,\"total_carbs\":0,\"total_fat\":0," +
                "\"description\":\"résumé court en français\"}";
            return parseJson(chatCompletion(List.of(Map.of("role", "user", "content", prompt)), 400, 0.3, true));
        } catch (Exception e) {
            return mockFoodResponse("Service IA indisponible — démarrez Ollama (ollama serve). "
                    + "Valeurs d'exemple, modifiables avant l'enregistrement.");
        }
    }

    // ── Chatbot NutriCoach ───────────────────────────────────────────────────
    public String chat(String userMessage, List<Map<String, String>> history) {
        try {
            List<Map<String, Object>> messages = new ArrayList<>();
            messages.add(Map.of("role", "system", "content",
                "Tu es NutriCoach, un assistant nutritionnel expert et bienveillant dans l'application MediCare. " +
                "Tu aides les utilisateurs à améliorer leur alimentation, comprendre les macronutriments, " +
                "planifier leurs repas et atteindre leurs objectifs de santé. " +
                "Réponds toujours en français, de manière claire, chaleureuse et motivante. " +
                "Donne des conseils pratiques, des recettes simples et des explications scientifiques accessibles. " +
                "Tu ne poses jamais de diagnostic médical et tu recommandes de consulter un professionnel si nécessaire. " +
                "Limite tes réponses à 200 mots sauf si on demande un plan ou une liste détaillée."));
            if (history != null) {
                // Seuls les derniers échanges sont renvoyés : un historique long ralentit chaque réponse.
                var recent = history.subList(Math.max(0, history.size() - CHAT_HISTORY_LIMIT), history.size());
                for (Map<String, String> entry : recent) {
                    String role = entry.get("role");
                    String content = entry.get("content");
                    if (("user".equals(role) || "assistant".equals(role)) && content != null) {
                        messages.add(Map.of("role", role, "content", content));
                    }
                }
            }
            messages.add(Map.of("role", "user", "content", userMessage));
            return chatCompletion(messages, 350, 0.7, false).trim();
        } catch (Exception e) {
            return "NutriCoach n'est pas disponible pour l'instant. Vérifiez qu'Ollama est démarré "
                    + "(commande : ollama serve) et que le modèle « " + chatModel + " » est installé.";
        }
    }

    // ── Analyse IA des mesures de santé ──────────────────────────────────────
    public Map<String, Object> analyzeHealthRecords(List<Map<String, Object>> records, Map<String, Object> goal,
                                                    List<String> alerts) {
        try {
            // Synthèse calculée côté serveur (dernière valeur, plage, évolution, normalité) :
            // un petit modèle interprète mal une longue liste brute et inverse parfois les tendances.
            StringBuilder data = new StringBuilder("Synthèse des mesures des 30 derniers jours :\n");
            data.append(metricLine(records, "weight", "Poids", "kg", null, null));
            data.append(metricLine(records, "heartRate", "Fréquence cardiaque", "bpm", 60.0, 100.0));
            data.append(metricLine(records, "systolic", "Tension systolique", "mmHg", 90.0, 120.0));
            data.append(metricLine(records, "diastolic", "Tension diastolique", "mmHg", 60.0, 80.0));
            data.append(metricLine(records, "temperature", "Température", "°C", 36.1, 37.2));
            data.append(metricLine(records, "glycemia", "Glycémie à jeun", "g/L", 0.70, 1.00));
            Double lastWeight = records.stream().map(r -> r.get("weight")).filter(v -> v instanceof Number)
                    .map(v -> ((Number) v).doubleValue()).findFirst().orElse(null);
            if (goal != null && lastWeight != null) {
                if (goal.get("targetWeight") instanceof Number target) {
                    double gap = lastWeight - target.doubleValue();
                    data.append(String.format(Locale.FRANCE, "- Poids cible : %.1f kg ; écart actuel %+.1f kg (poids actuel %s du poids cible)\n",
                            target.doubleValue(), gap, Math.abs(gap) < 0.5 ? "égal au" : gap > 0 ? "AU-DESSUS" : "EN DESSOUS"));
                }
                if (goal.get("heightCm") instanceof Number height && height.doubleValue() > 0) {
                    double bmi = lastWeight / Math.pow(height.doubleValue() / 100, 2);
                    String category = bmi < 18.5 ? "insuffisance pondérale" : bmi < 25 ? "corpulence normale" : bmi < 30 ? "surpoids" : "obésité";
                    data.append(String.format(Locale.FRANCE, "- IMC actuel : %.1f (%s)\n", bmi, category));
                }
            }
            data.append(alerts == null || alerts.isEmpty()
                    ? "Alertes médicales détectées : aucune.\n"
                    : "Alertes médicales détectées (à mentionner dans le résumé) : " + String.join(", ", alerts) + ".\n");

            String prompt = "Tu es un assistant santé IA dans l'application MediCare. Analyse ces données de santé "
                + "sans poser de diagnostic médical et retourne UNIQUEMENT du JSON valide :\n\n"
                + data
                + "\nValeurs normales de référence :\n"
                + "- Température : 36,1-37,2 °C (fièvre >37,5 °C, hyperthermie >38,5 °C)\n"
                + "- Glycémie à jeun : 0,70-1,00 g/L (élevée 1,01-1,25 g/L, diabète >1,26 g/L)\n"
                + "- Fréquence cardiaque : 60-100 bpm (bradycardie <60, tachycardie >100)\n"
                + "- Tension systolique : 90-120 mmHg (hypertension >140)\n"
                + "- Tension diastolique : 60-80 mmHg (hypertension >90)\n"
                + "- IMC normal : 18,5-24,9\n\n"
                // Les alertes sont calculées par des seuils fixes dans HealthAiController :
                // le modèle ne rédige que le résumé, les tendances et les conseils.
                + "Réponds uniquement par un objet JSON avec les clés : "
                + "summary (résumé global en 2 phrases, sans diagnostic), "
                + "possibleConditions (liste de 0 à 2 tendances observées dans les mesures, liste vide si tout est normal), "
                + "recommendations (liste de 3 conseils courts et concrets). "
                + "Reprends exactement les évolutions (en baisse, en hausse, stable) et les états "
                + "(NORMALE, SOUS ou AU-DESSUS de la normale) indiqués dans la synthèse, sans les contredire. "
                + "Une valeur NORMALE ne doit pas être présentée comme un problème.";

            Map<String, Object> result = parseJson(chatCompletion(
                    List.of(Map.of("role", "user", "content", prompt)), 300, 0.2, true));
            result.put("possibleConditions", realItems(result.get("possibleConditions")));
            result.put("recommendations", realItems(result.get("recommendations")));
            return result;
        } catch (Exception e) {
            return mockHealthResponse();
        }
    }

    public Map<String, Object> emptyHealthResponse() {
        Map<String, Object> result = new HashMap<>();
        result.put("status", "bon");
        result.put("statusColor", "green");
        result.put("alerts", List.of());
        result.put("possibleConditions", List.of());
        result.put("recommendations", List.of(
                "Enregistrez vos premières mesures (poids, tension, fréquence cardiaque...)",
                "Mesurez-vous régulièrement, idéalement à la même heure",
                "Renseignez votre taille dans vos objectifs pour calculer votre IMC"));
        result.put("summary", "Aucune mesure sur les 30 derniers jours : l'analyse sera disponible dès vos premières mesures.");
        result.put("urgency", "normal");
        return result;
    }

    // ── Utilitaires ──────────────────────────────────────────────────────────
    @SuppressWarnings("unchecked")
    /**
     * Appel à l'API native d'Ollama (/api/chat), qui accepte keep_alive et les options
     * du modèle, contrairement à l'API compatible OpenAI utilisée auparavant.
     * json = true force une sortie JSON valide (format "json"), sans texte autour.
     */
    private String chatCompletion(List<? extends Map<String, ?>> messages, int maxTokens, double temperature, boolean json) {
        Map<String, Object> body = new HashMap<>();
        body.put("model", chatModel);
        body.put("messages", messages);
        body.put("stream", false);
        body.put("keep_alive", keepAlive);
        if (json) body.put("format", "json");
        body.put("options", Map.of("num_ctx", CONTEXT_TOKENS, "num_predict", maxTokens, "temperature", temperature));
        ResponseEntity<Map> resp = restTemplate.exchange(
            ollamaBaseUrl + "/api/chat", HttpMethod.POST, new HttpEntity<>(body, jsonHeaders()), Map.class);
        Map<String, Object> msg = (Map<String, Object>) resp.getBody().get("message");
        return (String) msg.get("content");
    }

    /**
     * Une ligne de synthèse pour une constante. records est trié du plus récent au plus ancien.
     * Exemple : "- Poids : dernière 74,8 kg ; min 74,8 / max 77,1 ; évolution -2,3 kg (en baisse)".
     */
    private static String metricLine(List<Map<String, Object>> records, String key, String label,
                                     String unit, Double normalMin, Double normalMax) {
        List<Double> values = records.stream()
                .map(r -> r.get(key))
                .filter(v -> v instanceof Number)
                .map(v -> ((Number) v).doubleValue())
                .toList();
        if (values.isEmpty()) return "";
        double last = values.get(0), oldest = values.get(values.size() - 1);
        double min = Collections.min(values), max = Collections.max(values), delta = last - oldest;
        String trend = Math.abs(delta) < 0.005 * Math.max(1, Math.abs(oldest)) ? "stable"
                : delta < 0 ? "en baisse" : "en hausse";
        StringBuilder line = new StringBuilder("- ").append(label)
                .append(String.format(Locale.FRANCE, " : dernière %.2f %s ; min %.2f / max %.2f ; évolution %+.2f %s (%s) sur %d mesures",
                        last, unit, min, max, delta, unit, trend, values.size()));
        if (normalMin != null && normalMax != null) {
            String state = last < normalMin ? "SOUS la normale" : last > normalMax ? "AU-DESSUS de la normale" : "NORMALE";
            line.append(String.format(Locale.FRANCE, " ; normale %.2f-%.2f ; dernière valeur %s", normalMin, normalMax, state));
        }
        return line.append("\n").toString();
    }

    /** Garde les textes réels d'une liste renvoyée par le modèle et écarte les gabarits recopiés. */
    private static List<String> realItems(Object value) {
        if (!(value instanceof List<?> list)) return List.of();
        return list.stream()
                // Le modèle renvoie parfois un objet au lieu d'un texte : on garde ses valeurs.
                .map(item -> item instanceof Map<?, ?> map
                        ? String.join(", ", map.values().stream().map(String::valueOf).toList())
                        : String.valueOf(item))
                .map(String::trim)
                .filter(s -> !s.isEmpty() && !s.matches("(?i)(tendance|conseil)\\s*\\d*"))
                .limit(3)
                .toList();
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> parseJson(String text) throws Exception {
        String cleaned = text.replaceAll("```json\\s*", "").replaceAll("```\\s*", "").trim();
        int start = cleaned.indexOf('{');
        int end = cleaned.lastIndexOf('}');
        if (start >= 0 && end > start) cleaned = cleaned.substring(start, end + 1);
        return new HashMap<>(mapper.readValue(cleaned, Map.class));
    }

    private static HttpHeaders jsonHeaders() {
        HttpHeaders h = new HttpHeaders();
        h.setContentType(MediaType.APPLICATION_JSON);
        return h;
    }

    private Map<String, Object> mockHealthResponse() {
        Map<String, Object> result = new HashMap<>();
        result.put("status", "bon");
        result.put("statusColor", "green");
        result.put("alerts", List.of());
        result.put("possibleConditions", List.of());
        result.put("recommendations", List.of("Continuez vos bonnes habitudes", "Restez hydraté", "Dormez 7 à 8 h par nuit"));
        result.put("summary", "Le service IA (Ollama) est indisponible : seules les alertes automatiques ci-dessous sont calculées.");
        result.put("urgency", "normal");
        result.put("demo_mode", true);
        return result;
    }

    private Map<String, Object> mockFoodResponse(String description) {
        List<Map<String, Object>> foods = new ArrayList<>();
        foods.add(new HashMap<>(Map.of("name", "Poulet grillé", "quantity", "150 g", "calories", 248, "protein", 46, "carbs", 0, "fat", 5)));
        foods.add(new HashMap<>(Map.of("name", "Riz blanc cuit", "quantity", "100 g", "calories", 130, "protein", 3, "carbs", 28, "fat", 0)));
        foods.add(new HashMap<>(Map.of("name", "Salade verte", "quantity", "80 g", "calories", 12, "protein", 1, "carbs", 2, "fat", 0)));
        Map<String, Object> result = new HashMap<>();
        result.put("foods", foods);
        result.put("total_calories", 390);
        result.put("total_protein", 50);
        result.put("total_carbs", 30);
        result.put("total_fat", 5);
        result.put("description", description);
        result.put("demo_mode", true);
        return result;
    }
}
