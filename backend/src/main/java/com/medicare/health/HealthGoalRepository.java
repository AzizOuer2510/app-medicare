package com.medicare.health;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.Optional;

public interface HealthGoalRepository extends JpaRepository<HealthGoal, Long> {
    Optional<HealthGoal> findByUserId(Long userId);
}
