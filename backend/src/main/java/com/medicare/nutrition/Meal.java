package com.medicare.nutrition;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.medicare.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDate;
import java.time.LocalTime;

/** Repas du journal alimentaire. Les valeurs nutritionnelles sont des estimations. */
@Entity
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Meal {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @JsonIgnore
    @ManyToOne(optional = false)
    private User user;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private MealType mealType;

    @Column(nullable = false)
    private LocalDate mealDate;

    private LocalTime mealTime;

    /** Aliments et quantités, ex : « Poulet grillé 150 g, Riz 100 g ». */
    @Column(length = 1000)
    private String description;

    /** Commentaire libre de l'utilisateur. */
    @Column(length = 1000)
    private String comment;

    private Double calories;
    private Double protein;
    private Double carbohydrates;
    private Double fat;
    private Double fiber;

    public enum MealType { BREAKFAST, LUNCH, DINNER, SNACK }
}
