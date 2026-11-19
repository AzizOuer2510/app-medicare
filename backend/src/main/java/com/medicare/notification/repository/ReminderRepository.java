package com.medicare.notification.repository;
import org.springframework.data.jpa.repository.Query;

import com.medicare.notification.entity.Reminder;
import com.medicare.notification.entity.ReminderStatus;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Lock;

public interface ReminderRepository extends JpaRepository<Reminder, Long>, JpaSpecificationExecutor<Reminder> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<Reminder> findLockedById(Long id);

    @Query("select r.id from Reminder r where r.status=com.medicare.notification.entity.ReminderStatus.PENDING and r.deliveryFailedAt is null and r.scheduledFor<=:now order by r.scheduledFor,r.id")
    List<Long> dueIds(Instant now, Pageable page);

    List<Reminder> findTop100ByStatusAndDeliveryFailedAtIsNotNullOrderByDeliveryFailedAtDesc(ReminderStatus status);

    List<Reminder> findByUserIdOrderByScheduledForAscIdAsc(Long userId);
    long countByUserIdAndStatus(Long userId, ReminderStatus status);
    Optional<Reminder> findFirstByUserIdAndStatusOrderByScheduledForAscIdAsc(Long userId, ReminderStatus status);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<Reminder> findByIdAndUserId(Long id, Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    List<Reminder> findByStatusAndScheduledForLessThanEqualOrderByScheduledForAsc(
            ReminderStatus status, Instant now, Pageable pageable);
}
