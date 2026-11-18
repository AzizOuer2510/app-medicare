package com.medicare.health;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.medicare.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

/** Mesure de santé : poids, fréquence cardiaque, tension, température, glycémie (g/L). */
@Entity
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class HealthRecord {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @JsonIgnore
    @ManyToOne(optional = false)
    private User user;
    @Column(nullable = false)
    private LocalDateTime recordedAt;
    private Double weight;
    private Integer heartRate;
    private Integer systolic;
    private Integer diastolic;
    private Double temperature;
    /** Glycémie en g/L. */
    private Double glycemia;
    @Column(length = 500)
    private String note;

    /** Médecin ayant saisi la mesure en consultation ; null si saisie par le patient. */
    @JsonIgnore
    @ManyToOne
    private User recordedBy;

    @JsonProperty("recordedById")
    public Long getRecordedById() {
        return recordedBy == null ? null : recordedBy.getId();
    }

    @JsonProperty("recordedByName")
    public String getRecordedByName() {
        return recordedBy == null ? null : recordedBy.getFullName();
    }
}
