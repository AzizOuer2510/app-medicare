package com.medicare.appointment;

import com.medicare.user.entity.User;
import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(
        name = "appointment_secretary_doctors",
        uniqueConstraints = @UniqueConstraint(columnNames = {"secretary_id", "doctor_id"}))
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class SecretaryDoctorAssignment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "secretary_id", nullable = false)
    private User secretary;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "doctor_id", nullable = false)
    private User doctor;
}
