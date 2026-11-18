package com.medicare.medication;

import com.medicare.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PrescriptionRepository extends JpaRepository<Prescription, Long> {
    List<Prescription> findAllByOrderByPrescriptionDateDesc();

    List<Prescription> findAllByArchivedFalseOrderByPrescriptionDateDesc();

    List<Prescription> findByPatientIdOrderByPrescriptionDateDesc(Long patientId);

    List<Prescription> findByPatientIdAndArchivedFalseOrderByPrescriptionDateDesc(Long patientId);

    List<Prescription> findByDoctorIdOrderByPrescriptionDateDesc(Long doctorId);

    List<Prescription> findByDoctorIdAndArchivedFalseOrderByPrescriptionDateDesc(Long doctorId);

    Optional<Prescription> findByIdAndPatientId(Long id, Long patientId);

    Optional<Prescription> findByIdAndDoctorId(Long id, Long doctorId);

    @Modifying
    @Query("update Prescription p set p.patient = :target where p.patient.id = :source")
    int transferPatient(@Param("source") Long source, @Param("target") User target);
}
