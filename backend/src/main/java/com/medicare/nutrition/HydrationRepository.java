package com.medicare.nutrition;

import com.medicare.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.time.LocalDate;
import java.util.List;

public interface HydrationRepository extends JpaRepository<Hydration, Long> {
    List<Hydration> findByUserIdAndRecordedDateOrderByRecordedTimeDesc(Long userId, LocalDate date);
    List<Hydration> findByUserIdOrderByRecordedDateDescRecordedTimeDesc(Long userId);
    List<Hydration> findByUserIdAndRecordedDateGreaterThanEqual(Long userId, LocalDate from);

    @Query("SELECT COALESCE(SUM(h.quantityMl),0) FROM Hydration h WHERE h.user.id=:userId AND h.recordedDate=:date")
    Integer sumQuantityByUserAndDate(@Param("userId") Long userId, @Param("date") LocalDate date);

    @Modifying
    @Query("update Hydration h set h.user = :target where h.user.id = :source")
    int transfer(@Param("source") Long source, @Param("target") User target);
}
