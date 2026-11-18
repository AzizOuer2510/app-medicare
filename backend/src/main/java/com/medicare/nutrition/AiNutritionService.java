package com.medicare.nutrition;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
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
@Service
public class AiNutritionService {

    @Value("${app.ollama.base-url:http://localhost:11434}")
    private String ollamaBaseUrl;

    @Value("${app.ollama.chat-model:llama3.2}")
    private String chatModel;

    @Value("${app.ollama.vision-model:llava}")
    private String visionModel;

    private final RestTemplate restTemplate;
    private final ObjectMapper mapper = new ObjectMapper();

    public AiNutritionService() {
        // Les modèles locaux peuvent être lents au premier chargement.
        var factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(5_000);
        factory.setReadTimeout(300_000);
        this.restTemplate = new RestTemplate(factory);
    }

    // ── Vision : analyse d'une photo de repas ────────────────────────────────
    @SuppressWarnings("unchecked")
    public Map<String, Object> analyzeFoodImage(String base64Image) {
        try {
            String prompt = "Analyse cette photo de repas. Identifie chaque aliment visible. " +
                "Retourne UNIQUEMENT du JSON valide sans markdown : " +
                "{\"foods\":[{\"name\":\"nom en français\",\"quantity\":\"quantité\",\"calories\":0,\"protein\":0,\"carbs\":0,\"fat\":0}]," +
                "\"total_calories\":0,\"total_protein\":0,\"total_carbs\":0,\"total_fat\":0," +
                "\"description\":\"description courte en français\"}";

            Map<String, Object> body = new HashMap<>();
            body.put("model", visionModel);
            body.put("prompt", prompt);
            body.put("images", List.of(base64Image));
            body.put("stream", false);

            ResponseEntity<Map> resp = restTemplate.exchange(
                ollamaBaseUrl + "/api/generate", HttpMethod.POST, new HttpEntity<>(body, jsonHeaders()), Map.class);
            return parseJson((String) resp.getBody().get("response"));
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
            return parseJson(chatCompletion(List.of(Map.of("role", "user", "content", prompt)), 1024, 0.3));
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
                for (Map<String, String> entry : history) {
                    String role = entry.get("role");
                    String content = entry.get("content");
                    if (("user".equals(role) || "assistant".equals(role)) && content != null) {
                        messages.add(Map.of("role", role, "content", content));
                    }
                }
            }
            messages.add(Map.of("role", "user", "content", userMessage));
            return chatCompletion(messages, 512, 0.7).trim();
        } catch (Exception e) {
            return "NutriCoach n'est pas disponible pour l'instant. Vérifiez qu'Ollama est démarré "
                    + "(commande : ollama serve) et que le modèle « " + chatModel + " » est installé.";
        }
    }

    // ── Analyse IA des mesures de santé ──────────────────────────────────────
    public Map<String, Object> analyzeHealthRecords(List<Map<String, Object>> records, Map<String, Object> goal) {
        try {
            StringBuilder data = new StringBuilder("Mesures récentes du patient :\n");
            for (Map<String, Object> r : records) {
                data.append("- Date: ").append(r.get("recordedAt"));
                if (r.get("weight") != null)      data.append(", Poids: ").append(r.get("weight")).append(" kg");
                if (r.get("heartRate") != null)   data.append(", FC: ").append(r.get("heartRate")).append(" bpm");
                if (r.get("systolic") != null)    data.append(", TA: ").append(r.get("systolic")).append("/").append(r.get("diastolic")).append(" mmHg");
                if (r.get("temperature") != null) data.append(", Temp: ").append(r.get("temperature")).append(" °C");
                if (r.get("glycemia") != null)    data.append(", Glycémie: ").append(r.get("glycemia")).append(" g/L");
                data.append("\n");
            }
            if (goal != null) {
                data.append("\nObjectifs : taille ").append(goal.get("heightCm")).append(" cm, poids cible ")
                    .append(goal.get("targetWeight")).append(" kg\n");
            }

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
                + "Retourne ce JSON exact sans markdown :\n"
                + "{\"status\":\"bon\","
                + "\"statusColor\":\"green\","
                + "\"alerts\":[{\"metric\":\"nom\",\"value\":\"valeur\",\"normal\":\"plage normale\",\"severity\":\"high|medium|low\",\"message\":\"explication courte\"}],"
                + "\"possibleConditions\":[\"tendance1\",\"tendance2\"],"
                + "\"recommendations\":[\"conseil1\",\"conseil2\",\"conseil3\"],"
                + "\"summary\":\"résumé global en 2-3 phrases\","
                + "\"urgency\":\"normal|attention|urgent\"}\n"
                + "Pour status utilise: 'bon', 'attention', ou 'alerte'. Pour statusColor: 'green', 'orange', ou 'red'.";

            return parseJson(chatCompletion(List.of(Map.of("role", "user", "content", prompt)), 1024, 0.2));
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
    private String chatCompletion(List<? extends Map<String, ?>> messages, int maxTokens, double temperature) {
        Map<String, Object> body = new HashMap<>();
        body.put("model", chatModel);
        body.put("messages", messages);
        body.put("max_tokens", maxTokens);
        body.put("temperature", temperature);
        ResponseEntity<Map> resp = restTemplate.exchange(
            ollamaBaseUrl + "/v1/chat/completions", HttpMethod.POST, new HttpEntity<>(body, jsonHeaders()), Map.class);
        List<Map<String, Object>> choices = (List<Map<String, Object>>) resp.getBody().get("choices");
        Map<String, Object> msg = (Map<String, Object>) choices.get(0).get("message");
        return (String) msg.get("content");
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
