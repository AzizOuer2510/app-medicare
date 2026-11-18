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
@RequestMapping("/api/hydration")
@RequiredArgsConstructor
public class HydrationController {
    private final HydrationRepository repo;
    private final HealthGoalRepository goals;
    private final HealthAccessService access;

    public record HydrationRequest(
        @NotNull @Min(10) @Max(5000) Integer quantityMl,
        @NotNull LocalDate recordedDate,
        LocalTime recordedTime,
        @Size(max = 255) String note
    ) {}

    @GetMapping
    public List<Hydration> all(@RequestParam(required = false) Long patientId, Authentication auth) {
        return repo.findByUserIdOrderByRecordedDateDescRecordedTimeDesc(access.resolve(auth, patientId).patient().getId());
    }

    /** Consommation du jour + objectif défini dans « Mes objectifs » (2 L par défaut). */
    @GetMapping("/today")
    public Map<String, Object> today(@RequestParam(required = false) Long patientId, Authentication auth) {
        User user = access.resolve(auth, patientId).patient();
        LocalDate today = LocalDate.now();
        Integer total = repo.sumQuantityByUserAndDate(user.getId(), today);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("entries", repo.findByUserIdAndRecordedDateOrderByRecordedTimeDesc(user.getId(), today));
        body.put("totalMl", total != null ? total : 0);
        body.put("goalMl", goalMl(user));
        return body;
    }

    /** Historique de l'hydratation : total par jour, du plus ancien au plus récent. */
    @GetMapping("/history")
    public List<Map<String, Object>> history(@RequestParam(defaultValue = "7") int days,
                                             @RequestParam(required = false) Long patientId,
                                             Authentication auth) {
        User user = access.resolve(auth, patientId).patient();
        int safeDays = Math.max(1, Math.min(days, 366));
        LocalDate from = LocalDate.now().minusDays(safeDays - 1L);
        Map<LocalDate, Integer> byDay = new TreeMap<>();
        for (int i = 0; i < safeDays; i++) byDay.put(from.plusDays(i), 0);
        for (Hydration h : repo.findByUserIdAndRecordedDateGreaterThanEqual(user.getId(), from)) {
            byDay.merge(h.getRecordedDate(), h.getQuantityMl(), Integer::sum);
        }
        int goal = goalMl(user);
        List<Map<String, Object>> result = new ArrayList<>();
        byDay.forEach((date, ml) -> {
            Map<String, Object> day = new LinkedHashMap<>();
            day.put("date", date.toString());
            day.put("totalMl", ml);
            day.put("goalMl", goal);
            result.add(day);
        });
        return result;
    }

    @PostMapping
    public Hydration create(@Valid @RequestBody HydrationRequest r, Authentication auth) {
        return repo.save(Hydration.builder()
            .user(access.current(auth)).quantityMl(r.quantityMl()).recordedDate(r.recordedDate())
            .recordedTime(r.recordedTime() != null ? r.recordedTime() : LocalTime.now().withNano(0))
            .note(r.note() == null || r.note().isBlank() ? null : r.note().trim()).build());
    }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable Long id, Authentication auth) {
        User user = access.current(auth);
        Hydration h = repo.findById(id).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Entrée introuvable"));
        if (!h.getUser().getId().equals(user.getId())) throw new ApiException(HttpStatus.FORBIDDEN, "Access denied");
        repo.delete(h);
    }

    private int goalMl(User user) {
        return goals.findByUserId(user.getId()).map(HealthGoal::waterGoalOrDefault).orElse(HealthGoal.DEFAULT_WATER_ML);
    }
}
