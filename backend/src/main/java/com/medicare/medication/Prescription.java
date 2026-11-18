package com.medicare.medication;

import com.medicare.user.entity.User;
import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

@Entity
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Prescription {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false)
    private User patient;

    @ManyToOne(optional = false)
    private User doctor;

    @Column(length = 500)
    private String diagnosis;

    private LocalDate prescriptionDate;

    @Column(length = 1000)
    private String notes;

    @Lob
    private byte[] documentData;

    @Column(length = 255)
    private String documentName;

    @Column(length = 100)
    private String documentContentType;

    @Builder.Default
    @Column(nullable = false, columnDefinition = "boolean default false not null")
    private boolean archived = false;

    @OneToMany(mappedBy = "prescription")
    @Builder.Default
    private List<Medication> medications = new ArrayList<>();
}
