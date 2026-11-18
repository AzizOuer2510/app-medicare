package com.medicare.nutrition;

import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import java.util.List;

/** Consultation de la base d'aliments (valeurs pour 100 g / 100 ml). */
@RestController
@RequestMapping("/api/foods")
@RequiredArgsConstructor
public class FoodController {
    private final FoodRepository repo;

    @GetMapping
    public List<Food> search(@RequestParam(required = false) String search) {
        if (search == null || search.isBlank()) return repo.findAllByOrderByCategoryAscNameAsc();
        return repo.findByNameContainingIgnoreCaseOrderByNameAsc(search.trim());
    }
}
