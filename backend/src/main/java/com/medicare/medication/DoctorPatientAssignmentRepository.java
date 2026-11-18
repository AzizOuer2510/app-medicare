package com.medicare.medication;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface DoctorPatientAssignmentRepository extends JpaRepository<DoctorPatientAssignment, Long> {
    Optional<DoctorPatientAssignment> findByDoctorIdAndPatientId(Long doctorId, Long patientId);

    boolean existsByDoctorIdAndPatientId(Long doctorId, Long patientId);

    boolean existsByDoctorIdAndPatientIdAndActiveTrue(Long doctorId, Long patientId);

    boolean existsByPatientId(Long patientId);

    @Query("""
            select assignment from DoctorPatientAssignment assignment
            join fetch assignment.patient
            where assignment.doctor.id = :doctorId and assignment.active = true
            order by assignment.patient.fullName
            """)
    List<DoctorPatientAssignment> findActiveByDoctorId(@Param("doctorId") Long doctorId);
}
