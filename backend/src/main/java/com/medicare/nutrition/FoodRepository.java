package com.medicare.nutrition;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface FoodRepository extends JpaRepository<Food, Long> {
    List<Food> findAllByOrderByCategoryAscNameAsc();
    List<Food> findByNameContainingIgnoreCaseOrderByNameAsc(String name);
    boolean existsByNameIgnoreCase(String name);
}
