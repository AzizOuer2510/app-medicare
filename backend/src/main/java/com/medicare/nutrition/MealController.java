package com.medicare.nutrition;

import com.medicare.common.ApiException;
import com.medicare.health.HealthGoal;
import com.medicare.health.HealthGoalRepository;
import com.medicare.health.HealthAccessService;
import com.medicare.user.entity.User;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import java.time.LocalDate;
import java.time.LocalTime;
import java.util.*;

@RestController
@RequestMapping("/api/meals")
@RequiredArgsConstructor
public class MealController {
    private final MealRepository repo;
    private final HealthGoalRepository goals;
    private final HealthAccessService access;

    public record MealRequest(
        @NotNull Meal.MealType mealType,
        @NotNull LocalDate mealDate,
        LocalTime mealTime,
        @Size(max = 1000) String description,
        @Size(max = 1000) String comment,
        @DecimalMin("0") @DecimalMax("10000") Double calories,
        @DecimalMin("0") @DecimalMax("1000") Double protein,
        @DecimalMin("0") @DecimalMax("1000") Double carbohydrates,
        @DecimalMin("0") @DecimalMax("1000") Double fat,
        @DecimalMin("0") @DecimalMax("500") Double fiber
    ) {}

    @GetMapping
    public List<Meal> all(@RequestParam(required = false) Long patientId, Authentication auth) {
        return repo.findByUserIdOrderByMealDateDescMealTimeDesc(access.resolve(auth, patientId).patient().getId());
    }

    @GetMapping("/today")
    public List<Meal> today(@RequestParam(required = false) Long patientId, Authentication auth) {
        return repo.findByUserIdAndMealDateOrderByMealTimeDesc(access.resolve(auth, patientId).patient().getId(), LocalDate.now());
    }

    /** Historique nutritionnel sur une période. */
    @GetMapping("/history")
    public List<Meal> history(@RequestParam(defaultValue = "30") int days,
                              @RequestParam(required = false) Long patientId, Authentication auth) {
        return repo.findByUserIdAndMealDateGreaterThanEqualOrderByMealDateDescMealTimeDesc(
            access.resolve(auth, patientId).patient().getId(), LocalDate.now().minusDays(clampDays(days) - 1L));
    }

    @GetMapping("/stats/today")
    public Map<String, Object> statsToday(@RequestParam(required = false) Long patientId, Authentication auth) {
        User user = access.resolve(auth, patientId).patient();
        var meals = repo.findByUserIdAndMealDateOrderByMealTimeDesc(user.getId(), LocalDate.now());
        Map<String, Object> body = totals(meals);
        body.put("mealCount", (long) meals.size());
        body.put("calorieGoal", goals.findByUserId(user.getId())
            .map(HealthGoal::calorieGoalOrDefault).orElse(HealthGoal.DEFAULT_CALORIES));
        return body;
    }

    /** Totaux par jour sur la période (jours sans repas inclus, à zéro), du plus ancien au plus récent. */
    @GetMapping("/stats/daily")
    public List<Map<String, Object>> statsDaily(@RequestParam(defaultValue = "7") int days,
                                                @RequestParam(required = false) Long patientId,
                                                Authentication auth) {
        int safeDays = clampDays(days);
        LocalDate from = LocalDate.now().minusDays(safeDays - 1L);
        var meals = repo.findByUserIdAndMealDateGreaterThanEqualOrderByMealDateDescMealTimeDesc(
            access.resolve(auth, patientId).patient().getId(), from);
        Map<LocalDate, List<Meal>> byDay = new TreeMap<>();
        for (int i = 0; i < safeDays; i++) byDay.put(from.plusDays(i), new ArrayList<>());
        for (Meal m : meals) byDay.computeIfAbsent(m.getMealDate(), d -> new ArrayList<>()).add(m);
        List<Map<String, Object>> result = new ArrayList<>();
        byDay.forEach((date, list) -> {
            Map<String, Object> day = totals(list);
            day.put("date", date.toString());
            day.put("mealCount", (long) list.size());
            result.add(day);
        });
        return result;
    }

    @PostMapping
    public Meal create(@Valid @RequestBody MealRequest r, Authentication auth) {
        Meal meal = Meal.builder().user(access.current(auth)).build();
        apply(meal, r);
        return repo.save(meal);
    }

    @PutMapping("/{id}")
    public Meal update(@PathVariable Long id, @Valid @RequestBody MealRequest r, Authentication auth) {
        Meal meal = owned(id, access.current(auth));
        apply(meal, r);
        return repo.save(meal);
    }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable Long id, Authentication auth) {
        repo.delete(owned(id, access.current(auth)));
    }

    private Meal owned(Long id, User user) {
        Meal meal = repo.findById(id).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Repas introuvable"));
        if (!meal.getUser().getId().equals(user.getId())) throw new ApiException(HttpStatus.FORBIDDEN, "Access denied");
        return meal;
    }

    private static void apply(Meal m, MealRequest r) {
        m.setMealType(r.mealType());
        m.setMealDate(r.mealDate());
        m.setMealTime(r.mealTime() != null ? r.mealTime() : LocalTime.now().withNano(0));
        m.setDescription(blankToNull(r.description()));
        m.setComment(blankToNull(r.comment()));
        m.setCalories(r.calories());
        m.setProtein(r.protein());
        m.setCarbohydrates(r.carbohydrates());
        m.setFat(r.fat());
        m.setFiber(r.fiber());
    }

    private static Map<String, Object> totals(List<Meal> meals) {
        double cal = 0, prot = 0, carbs = 0, fat = 0, fiber = 0;
        for (Meal m : meals) {
            cal += nz(m.getCalories()); prot += nz(m.getProtein());
            carbs += nz(m.getCarbohydrates()); fat += nz(m.getFat()); fiber += nz(m.getFiber());
        }
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("totalCalories", round(cal));
        body.put("totalProtein", round(prot));
        body.put("totalCarbohydrates", round(carbs));
        body.put("totalFat", round(fat));
        body.put("totalFiber", round(fiber));
        return body;
    }

    private static int clampDays(int days) { return Math.max(1, Math.min(days, 366)); }
    private static double nz(Double v) { return v == null ? 0 : v; }
    private static double round(double v) { return Math.round(v * 10) / 10.0; }
    private static String blankToNull(String v) { return v == null || v.isBlank() ? null : v.trim(); }
}
