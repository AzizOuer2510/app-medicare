package com.medicare.health;

import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Objectifs de santé. Le patient gère les siens ; le médecin qui suit le patient
 * peut les consulter et les ajuster (paramètre patientId).
 */
@RestController
@RequestMapping("/api/health-goals")
@RequiredArgsConstructor
public class HealthGoalController {
    private final HealthGoalRepository repo;
    private final HealthAccessService access;

    public record GoalRequest(@DecimalMin("1") @DecimalMax("500") Double targetWeight,
                              @DecimalMin("50") @DecimalMax("260") Double heightCm,
                              @Min(500) @Max(10000) Integer dailyCalorieGoal,
                              @Min(250) @Max(10000) Integer dailyWaterGoalMl,
                              @Min(0) @Max(100000) Integer dailyStepsGoal,
                              @Size(max = 1000) String notes) {}

    /** Renvoie toujours un objet JSON, avec les valeurs par défaut si rien n'est encore saisi. */
    @GetMapping
    public Map<String, Object> get(@RequestParam(required = false) Long patientId, Authentication auth) {
        return view(access.resolve(auth, patientId).patient());
    }

    @PostMapping
    public Map<String, Object> save(@Valid @RequestBody GoalRequest r,
                                    @RequestParam(required = false) Long patientId,
                                    Authentication auth) {
        var ctx = access.resolve(auth, patientId);
        User patient = ctx.patient();
        var goal = repo.findByUserId(patient.getId()).orElse(HealthGoal.builder().user(patient).build());
        goal.setTargetWeight(r.targetWeight());
        goal.setHeightCm(r.heightCm());
        goal.setDailyCalorieGoal(r.dailyCalorieGoal());
        goal.setDailyWaterGoalMl(r.dailyWaterGoalMl());
        goal.setDailyStepsGoal(r.dailyStepsGoal());
        goal.setNotes(r.notes() == null || r.notes().isBlank() ? null : r.notes().trim());
        goal.setUpdatedAt(LocalDateTime.now());
        goal.setUpdatedBy(ctx.viewer());
        repo.save(goal);
        return view(patient);
    }

    private Map<String, Object> view(User patient) {
        var goal = repo.findByUserId(patient.getId()).orElse(null);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("configured", goal != null);
        body.put("targetWeight", goal == null ? null : goal.getTargetWeight());
        body.put("heightCm", goal == null ? null : goal.getHeightCm());
        body.put("dailyCalorieGoal", goal == null ? HealthGoal.DEFAULT_CALORIES : goal.calorieGoalOrDefault());
        body.put("dailyWaterGoalMl", goal == null ? HealthGoal.DEFAULT_WATER_ML : goal.waterGoalOrDefault());
        body.put("dailyStepsGoal", goal == null ? null : goal.getDailyStepsGoal());
        body.put("notes", goal == null ? null : goal.getNotes());
        body.put("updatedAt", goal == null ? null : goal.getUpdatedAt());
        User author = goal == null ? null : goal.getUpdatedBy();
        body.put("updatedByName", author == null ? null : author.getFullName());
        body.put("updatedByDoctor", author != null && author.getRole() == Role.DOCTOR
                && !author.getId().equals(patient.getId()));
        return body;
    }
}
