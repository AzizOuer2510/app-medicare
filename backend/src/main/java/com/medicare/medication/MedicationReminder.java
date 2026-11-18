package com.medicare.medication;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;

@Entity
@Table(uniqueConstraints = @UniqueConstraint(
        name = "uk_medication_reminder_dose",
        columnNames = {"medication_id", "date", "time"}))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MedicationReminder {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false)
    private Medication medication;

    @Column(nullable = false)
    private LocalDate date;

    @Column(nullable = false)
    private LocalTime time;

    @Builder.Default
    private boolean taken = false;

    private LocalDateTime takenAt;

    private LocalDateTime snoozedUntil;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20, columnDefinition = "varchar(20) default 'PENDING' not null")
    @Builder.Default
    private IntakeStatus status = IntakeStatus.PENDING;

    @Column(length = 1000)
    private String intakeNote;

    @PostLoad
    private void restoreLegacyTakenStatus() {
        if (taken && status == IntakeStatus.PENDING) status = IntakeStatus.TAKEN;
    }
}
