package com.medicare.medication;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Getter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MedicationStockEntry {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    private Medication medication;

    @ManyToOne(fetch = FetchType.LAZY)
    private MedicationReminder reminder;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private Type type;

    @Column(nullable = false, precision = 12, scale = 3)
    private BigDecimal quantityChange;

    @Column(nullable = false, precision = 12, scale = 3)
    private BigDecimal quantityAfter;

    @Column(length = 500)
    private String note;

    @Column(nullable = false)
    private LocalDateTime createdAt;

    public enum Type {
        INITIAL_STOCK,
        INTAKE_DEDUCTION,
        INTAKE_REFUND,
        REFILL,
        CORRECTION
    }
}
