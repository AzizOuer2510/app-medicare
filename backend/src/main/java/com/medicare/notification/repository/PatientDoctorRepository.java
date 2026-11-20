package com.medicare.notification.repository;
import com.medicare.notification.entity.PatientDoctor;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PatientDoctorRepository extends JpaRepository<PatientDoctor, PatientDoctor.Key> {
    boolean existsByPatientIdAndDoctorId(Long patientId, Long doctorId);
    java.util.List<PatientDoctor> findByPatientIdOrderByDoctorFullNameAscDoctorIdAsc(Long patientId);
    boolean existsByPatientId(Long patientId);
    java.util.List<PatientDoctor> findByDoctorId(Long doctorId);
}
