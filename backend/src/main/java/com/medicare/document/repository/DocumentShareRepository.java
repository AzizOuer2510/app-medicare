package com.medicare.document.repository;

import com.medicare.document.entity.DocumentShare;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface DocumentShareRepository extends JpaRepository<DocumentShare, Long> {
    List<DocumentShare> findByDocumentIdOrderByCreatedAtDescIdDesc(Long documentId);
    long countByDocumentIdAndRevokedAtIsNullAndExpiresAtAfterAndFailedAttemptsLessThan(
            Long documentId, Instant now, int attempts);
    @Query("select s.document.id from DocumentShare s where s.tokenHash = :hash")
    Optional<Long> findDocumentIdByTokenHash(@Param("hash") String hash);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<DocumentShare> findLockedByTokenHash(String tokenHash);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<DocumentShare> findLockedByIdAndDocumentId(Long id, Long documentId);
    Optional<DocumentShare> findByIdAndDocumentId(Long id, Long documentId);
}
