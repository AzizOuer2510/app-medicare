package com.medicare.medication;

import com.medicare.user.entity.User;
import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDate;
import java.time.LocalTime;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Medication {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false)
    private User user;

    @ManyToOne
    private Prescription prescription;

    @Column(nullable = false)
    private String name;

    @Column(length = 80)
    private String dosage;

    @Column(length = 80)
    private String frequency;

    private Integer frequencyPerDay;

    @Column(length = 1000)
    private String instructions;

    @Column(length = 80)
    private String pharmaceuticalForm;

    @Column(length = 2000)
    private String notes;

    @Column(precision = 12, scale = 3)
    private BigDecimal unitsPerDose;

    @ElementCollection
    @CollectionTable(name = "medication_weekdays", joinColumns = @JoinColumn(name = "medication_id"))
    @Column(name = "weekday", nullable = false, length = 10)
    @Enumerated(EnumType.STRING)
    @Builder.Default
    private List<java.time.DayOfWeek> weekdays = new ArrayList<>();

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20, columnDefinition = "varchar(20) default 'ACTIVE' not null")
    @Builder.Default
    private MedicationStatus status = MedicationStatus.ACTIVE;

    @Builder.Default
    @Column(nullable = false, columnDefinition = "boolean default true not null")
    private boolean remindersEnabled = true;

    @Builder.Default
    @Column(nullable = false, precision = 12, scale = 3, columnDefinition = "numeric(12,3) default 0 not null")
    private BigDecimal stockQuantity = BigDecimal.ZERO;

    @Column(length = 40)
    private String stockUnit;

    @Builder.Default
    @Column(nullable = false, precision = 12, scale = 3, columnDefinition = "numeric(12,3) default 0 not null")
    private BigDecimal lowStockThreshold = BigDecimal.ZERO;

    @Column(precision = 12, scale = 3)
    private BigDecimal packageQuantity;

    @Version
    private Long version;

    private LocalDate startDate;
    private LocalDate endDate;

    @ElementCollection
    @CollectionTable(name = "medication_reminder_times", joinColumns = @JoinColumn(name = "medication_id"))
    @Column(name = "reminder_time")
    @OrderColumn(name = "time_order")
    @Builder.Default
    private List<LocalTime> reminderTimes = new ArrayList<>();
}
