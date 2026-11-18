package com.medicare.nutrition;

import com.medicare.common.ApiException;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

/** Reconnaissance des aliments (photo) ou estimation à partir d'une description. */
@RestController
@RequestMapping("/api/nutrition/ai")
@RequiredArgsConstructor
public class NutritionAiController {

    /** ~6 Mo d'image encodée en base64. */
    private static final int MAX_IMAGE_BASE64_LENGTH = 8_000_000;

    private final AiNutritionService aiService;

    public record AnalyzeRequest(String image, String mediaType, String description) {}

    @PostMapping("/analyze")
    public Map<String, Object> analyze(@RequestBody AnalyzeRequest req) {
        if (req.image() != null && !req.image().isBlank()) {
            if (req.image().length() > MAX_IMAGE_BASE64_LENGTH) {
                throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "Image trop volumineuse (6 Mo maximum).");
            }
            return aiService.analyzeFoodImage(req.image());
        }
        if (req.description() == null || req.description().isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Ajoutez une photo ou une description du repas.");
        }
        String description = req.description().trim();
        if (description.length() > 1000) description = description.substring(0, 1000);
        return aiService.analyzeByDescription(description);
    }
}
