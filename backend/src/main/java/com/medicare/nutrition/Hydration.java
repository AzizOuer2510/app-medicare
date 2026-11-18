package com.medicare.nutrition;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.medicare.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDate;
import java.time.LocalTime;

/** Consommation d'eau. */
@Entity
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Hydration {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @JsonIgnore
    @ManyToOne(optional = false)
    private User user;

    @Column(nullable = false)
    private Integer quantityMl;

    @Column(nullable = false)
    private LocalDate recordedDate;

    private LocalTime recordedTime;

    @Column(length = 255)
    private String note;
}
