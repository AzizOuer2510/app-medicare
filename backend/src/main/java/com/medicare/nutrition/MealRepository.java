package com.medicare.nutrition;

import com.medicare.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.time.LocalDate;
import java.util.List;

public interface MealRepository extends JpaRepository<Meal, Long> {
    List<Meal> findByUserIdOrderByMealDateDescMealTimeDesc(Long userId);
    List<Meal> findByUserIdAndMealDateOrderByMealTimeDesc(Long userId, LocalDate date);
    List<Meal> findByUserIdAndMealDateGreaterThanEqualOrderByMealDateDescMealTimeDesc(Long userId, LocalDate from);
    boolean existsByUserId(Long userId);

    @Modifying
    @Query("update Meal m set m.user = :target where m.user.id = :source")
    int transfer(@Param("source") Long source, @Param("target") User target);
}
