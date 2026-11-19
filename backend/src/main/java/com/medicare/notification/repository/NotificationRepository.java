package com.medicare.notification.repository;

import com.medicare.notification.entity.Notification;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;

public interface NotificationRepository extends JpaRepository<Notification, Long>, JpaSpecificationExecutor<Notification> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select n from Notification n where n.id = :id")
    Optional<Notification> findLockedById(@Param("id") Long id);
    List<Notification> findByUserIdOrderByCreatedAtDescIdDesc(Long userId);
    List<Notification> findByUserIdAndReadAtIsNullOrderByCreatedAtDescIdDesc(Long userId);
    List<Notification> findByUserIdAndReadAtIsNotNullOrderByCreatedAtDescIdDesc(Long userId);
    Optional<Notification> findByIdAndUserId(Long id, Long userId);
    long countByUserIdAndReadAtIsNull(Long userId);
    long countByUserIdAndReadAtIsNullAndArchivedFalse(Long userId);
    long countByUserIdAndArchived(Long userId, boolean archived);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select n from Notification n where n.id = :id and n.user.id = :userId")
    Optional<Notification> findLockedByIdAndUserId(@Param("id") Long id, @Param("userId") Long userId);

    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update Notification n set n.readAt = :now where n.user.id = :userId and n.readAt is null and n.archived = false")
    int markAllRead(@Param("userId") Long userId, @Param("now") Instant now);
}
