package com.medicare.medication;

import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import com.medicare.user.entity.User;
import java.util.List;
import java.util.Optional;
import jakarta.persistence.LockModeType;

public interface MedicationRepository extends JpaRepository<Medication, Long> {
    List<Medication> findByUserIdOrderByName(Long userId);
    Optional<Medication> findByIdAndUserId(Long id, Long userId);

    @Query("select m from Medication m join m.prescription p where p.doctor.id = :doctorId order by m.name")
    List<Medication> findByPrescriptionDoctorIdOrderByName(@Param("doctorId") Long doctorId);

    @Query("""
            select m from Medication m
            join m.prescription p
            where p.doctor.id = :doctorId and m.user.id = :patientId
            order by m.name
            """)
    List<Medication> findByPrescriptionDoctorIdAndUserIdOrderByName(
            @Param("doctorId") Long doctorId, @Param("patientId") Long patientId);

    @Query("select m from Medication m join m.prescription p where m.id = :id and p.doctor.id = :doctorId")
    Optional<Medication> findByIdAndPrescriptionDoctorId(
            @Param("id") Long id, @Param("doctorId") Long doctorId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select m from Medication m where m.id = :id and m.user.id = :userId")
    Optional<Medication> findByIdAndUserIdForUpdate(@Param("id") Long id, @Param("userId") Long userId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select m from Medication m join m.prescription p where m.id = :id and p.doctor.id = :doctorId")
    Optional<Medication> findByIdAndPrescriptionDoctorIdForUpdate(
            @Param("id") Long id, @Param("doctorId") Long doctorId);

    @Modifying
    @Query("update Medication r set r.user = :target where r.user.id = :source")
    int transfer(@Param("source") Long source, @Param("target") User target);
}
