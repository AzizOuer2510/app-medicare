package com.medicare.notification.repository;
import com.medicare.notification.entity.ReminderChange;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ReminderChangeRepository extends JpaRepository<ReminderChange,Long> {
    List<ReminderChange> findTop100ByOrderByIdDesc();
}
