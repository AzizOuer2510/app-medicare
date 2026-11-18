package com.medicare.appointment;

import com.medicare.user.entity.User;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Table(indexes = {
        @Index(name = "idx_appointment_user_date", columnList = "user_id, date_time"),
        @Index(name = "idx_appointment_user_status", columnList = "user_id, status")
})
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Appointment {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    // Null for legacy appointments typed with a free-text doctor name.
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "doctor_id")
    private User doctor;

    @Column(nullable = false)
    private LocalDateTime dateTime;

    @Column(nullable = false, length = 120)
    private String doctorName;

    @Column(length = 500)
    private String reason;

    @Column(name = "appointment_type", length = 80)
    private String appointmentType;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    @Builder.Default
    private AppointmentStatus status = AppointmentStatus.PLANNED;

    private LocalDateTime reminderSentAt;
}
