package com.medicare.document.repository;
import org.springframework.data.jpa.repository.Modifying;

import com.medicare.document.entity.DocumentCategory;
import com.medicare.document.entity.MedicalDocument;
import jakarta.persistence.LockModeType;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface DocumentRepository extends JpaRepository<MedicalDocument, Long>, JpaSpecificationExecutor<MedicalDocument> {
    @Modifying
    @Query("update MedicalDocument d set d.sharedDoctor=null where d.user.id=:patient and d.sharedDoctor.id=:doctor")
    void clearDoctorAccess(@Param("patient") Long patient,@Param("doctor") Long doctor);

    List<MedicalDocument> findByUserIdOrderByUploadedAtDescIdDesc(Long userId);
    List<MedicalDocument> findByUserIdAndCategoryOrderByUploadedAtDescIdDesc(Long userId, DocumentCategory category);
    Optional<MedicalDocument> findByIdAndUserId(Long id, Long userId);
    long countByUserId(Long userId);
    long countByUserIdAndFavoriteTrue(Long userId);
    long countByUserIdAndCategory(Long userId, DocumentCategory category);

    @Query("select coalesce(sum(d.size), 0) from MedicalDocument d where d.user.id = :userId")
    long totalSize(@Param("userId") Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<MedicalDocument> findLockedByIdAndUserId(Long id, Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<MedicalDocument> findLockedById(Long id);
}
