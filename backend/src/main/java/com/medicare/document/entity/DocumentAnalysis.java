package com.medicare.document.entity;

import com.medicare.document.dto.AnalysisDtos.Status;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import java.time.Instant;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

@Entity @Getter @Setter
@Table(name="document_analyses")
public class DocumentAnalysis {
    @Id @GeneratedValue(strategy=GenerationType.IDENTITY) private Long id;
    @OneToOne(fetch=FetchType.LAZY, optional=false)
    @JoinColumn(name="document_id", nullable=false, unique=true)
    @OnDelete(action=OnDeleteAction.CASCADE)
    private MedicalDocument document;
    @Enumerated(EnumType.STRING) @Column(nullable=false) private Status status;
    private Instant startedAt;
    private Long requestedById;
    @Column(columnDefinition="text") private String draftJson;
    private String error;
}
