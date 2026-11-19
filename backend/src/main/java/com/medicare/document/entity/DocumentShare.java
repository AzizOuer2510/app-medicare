package com.medicare.document.entity;

import jakarta.persistence.*;
import java.time.Instant;
import lombok.*;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

@Entity
@Table(name = "document_shares", indexes = @Index(columnList = "document_id,created_at"))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class DocumentShare {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "document_id", nullable = false)
    @OnDelete(action = OnDeleteAction.CASCADE)
    private MedicalDocument document;

    @Column(nullable = false, unique = true, length = 64)
    private String tokenHash;
    @Column(nullable = false, length = 60)
    private String pinHash;
    @Column(nullable = false, length = 80)
    private String label;
    @Column(name = "created_at", nullable = false)
    private Instant createdAt;
    @Column(nullable = false)
    private Instant expiresAt;
    private Instant revokedAt;
    @Column(nullable = false)
    private int failedAttempts;
    @Column(nullable = false)
    private long accessCount;
    private Instant lastAccessAt;
}
