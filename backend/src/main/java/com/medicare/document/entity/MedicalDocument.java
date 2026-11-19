package com.medicare.document.entity;

import com.medicare.user.entity.User;
import jakarta.persistence.*;
import java.time.Instant;
import lombok.*;

@Entity
@Table(name = "medical_documents", indexes = @Index(columnList = "user_id,uploaded_at"))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class MedicalDocument {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    private User sharedDoctor;

    @Column(nullable = false, length = 120)
    private String title;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private DocumentCategory category;

    @Column(length = 2000)
    private String description;

    @Column(nullable = false, length = 200)
    private String originalFilename;

    @Column(nullable = false, unique = true, length = 50)
    private String storageKey;

    @Column(nullable = false, length = 50)
    private String contentType;

    @Column(nullable = false)
    private long size;

    @Column(name = "uploaded_at", nullable = false)
    private Instant uploadedAt;

    @Column(nullable = false, columnDefinition = "boolean default false")
    private boolean favorite;
}
