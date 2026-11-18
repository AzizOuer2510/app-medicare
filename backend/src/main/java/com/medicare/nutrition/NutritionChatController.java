package com.medicare.nutrition;

import com.medicare.common.ApiException;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.*;

/** Chatbot NutriCoach. */
@RestController
@RequestMapping("/api/nutrition/chat")
@RequiredArgsConstructor
public class NutritionChatController {

    private final AiNutritionService aiService;

    public record ChatRequest(String message, List<Map<String, String>> history) {}

    @PostMapping
    public Map<String, Object> chat(@RequestBody ChatRequest req) {
        if (req.message() == null || req.message().isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Message vide.");
        }
        String message = req.message().trim();
        if (message.length() > 2000) message = message.substring(0, 2000);
        List<Map<String, String>> history = req.history() == null ? List.of()
                : req.history().subList(Math.max(0, req.history().size() - 20), req.history().size());
        Map<String, Object> result = new HashMap<>();
        result.put("reply", aiService.chat(message, history));
        return result;
    }
}
