package com.medicare.medication;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.Optional;

public interface MedicationReminderRepository extends JpaRepository<MedicationReminder, Long> {
    List<MedicationReminder> findByMedicationIdAndDateOrderByTime(Long medicationId, LocalDate date);

    List<MedicationReminder> findByMedicationIdAndDateBetweenOrderByDateAscTimeAsc(
            Long medicationId, LocalDate from, LocalDate to);

    Optional<MedicationReminder> findByIdAndMedicationUserId(Long id, Long userId);

    Optional<MedicationReminder> findByIdAndMedicationPrescriptionDoctorId(Long id, Long doctorId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from MedicationReminder r where r.id = :id "
            + "and r.medication.prescription.doctor.id = :doctorId")
    Optional<MedicationReminder> findByIdAndMedicationPrescriptionDoctorIdForUpdate(
            @Param("id") Long id, @Param("doctorId") Long doctorId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from MedicationReminder r where r.id = :id")
    Optional<MedicationReminder> findByIdForUpdate(@Param("id") Long id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from MedicationReminder r where r.id = :id and r.medication.user.id = :userId")
    Optional<MedicationReminder> findByIdAndMedicationUserIdForUpdate(
            @Param("id") Long id, @Param("userId") Long userId);

    boolean existsByMedicationIdAndDateAndTime(Long medicationId, LocalDate date, LocalTime time);

    @Query("select r from MedicationReminder r where r.medication.id = :medicationId "
            + "and r.date between :from and :to order by r.date, r.time")
    List<MedicationReminder> findSchedule(@Param("medicationId") Long medicationId,
                                          @Param("from") LocalDate from, @Param("to") LocalDate to);

    @Modifying
    @Query("delete from MedicationReminder r where r.medication.id = :medicationId "
            + "and r.status = com.medicare.medication.IntakeStatus.PENDING "
            + "and (r.date > :date or (r.date = :date and r.time > :time))")
    int deleteFuturePending(@Param("medicationId") Long medicationId,
                            @Param("date") LocalDate date, @Param("time") LocalTime time);
}
