package com.medicare.nutrition;

import jakarta.persistence.*;
import lombok.*;

/** Base d'aliments : valeurs nutritionnelles pour 100 g (ou 100 ml pour les boissons). */
@Entity
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Food {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 120)
    private String name;

    @Column(nullable = false, length = 60)
    private String category;

    /** « g » ou « ml ». */
    @Column(nullable = false, length = 5)
    private String unit;

    private Double calories;
    private Double protein;
    private Double carbohydrates;
    private Double fat;
    private Double fiber;
}
