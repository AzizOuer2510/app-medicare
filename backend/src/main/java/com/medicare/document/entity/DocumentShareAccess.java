package com.medicare.document.entity;

import jakarta.persistence.*;
import java.time.Instant;
import lombok.*;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

@Entity
@Table(name = "document_share_accesses", indexes = @Index(columnList = "share_id,accessed_at"))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class DocumentShareAccess {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "share_id", nullable = false)
    @OnDelete(action = OnDeleteAction.CASCADE)
    private DocumentShare share;
    @Column(name = "accessed_at", nullable = false)
    private Instant accessedAt;
}
