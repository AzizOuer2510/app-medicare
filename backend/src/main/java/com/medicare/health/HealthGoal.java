package com.medicare.health;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.medicare.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

/** Objectifs personnels : taille (IMC), poids cible, calories et eau par jour. */
@Entity
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class HealthGoal {
    public static final int DEFAULT_WATER_ML = 2000;
    public static final int DEFAULT_CALORIES = 2000;

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @JsonIgnore
    @OneToOne(optional = false)
    @JoinColumn(name = "user_id", unique = true, nullable = false)
    private User user;

    private Double targetWeight;
    private Double heightCm;
    private Integer dailyCalorieGoal;
    private Integer dailyWaterGoalMl;
    private Integer dailyStepsGoal;
    @Column(length = 1000)
    private String notes;

    @Builder.Default
    private LocalDateTime updatedAt = LocalDateTime.now();

    /** Dernière personne ayant modifié les objectifs (le patient ou son médecin). */
    @JsonIgnore
    @ManyToOne
    private User updatedBy;

    public int waterGoalOrDefault() {
        return dailyWaterGoalMl == null ? DEFAULT_WATER_ML : dailyWaterGoalMl;
    }

    public int calorieGoalOrDefault() {
        return dailyCalorieGoal == null ? DEFAULT_CALORIES : dailyCalorieGoal;
    }
}
