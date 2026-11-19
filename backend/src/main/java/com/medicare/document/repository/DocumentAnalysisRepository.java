package com.medicare.document.repository;

import com.medicare.document.dto.AnalysisDtos.Status;
import com.medicare.document.entity.DocumentAnalysis;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DocumentAnalysisRepository extends JpaRepository<DocumentAnalysis, Long> {
    Optional<DocumentAnalysis> findFirstByStatusOrderByStartedAtAsc(Status status);
    Optional<DocumentAnalysis> findByDocumentId(Long documentId);
    Optional<DocumentAnalysis> findFirstByStatusOrderById(Status status);
}
