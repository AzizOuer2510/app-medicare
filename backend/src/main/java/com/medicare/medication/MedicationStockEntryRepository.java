package com.medicare.medication;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface MedicationStockEntryRepository extends JpaRepository<MedicationStockEntry, Long> {
    List<MedicationStockEntry> findByMedicationIdOrderByCreatedAtDescIdDesc(Long medicationId);
    java.util.Optional<MedicationStockEntry> findFirstByReminderIdOrderByCreatedAtDescIdDesc(Long reminderId);
}
