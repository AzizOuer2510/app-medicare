package com.medicare.user.repository;

import com.medicare.user.entity.User;
import java.util.Optional;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.domain.Pageable;
import jakarta.persistence.LockModeType;

public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByEmail(String email);
    Optional<User> findByEmailIgnoreCase(String email);
    Optional<User> findByUsernameIgnoreCase(String username);
    boolean existsByEmailIgnoreCase(String email);
    boolean existsByUsernameIgnoreCase(String username);
    boolean existsByEmailIgnoreCaseAndIdNot(String email, Long id);
    List<User> findByMergedIntoId(Long mergedIntoId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from User u where u.id = :id")
    Optional<User> findByIdForUpdate(@Param("id") Long id);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select u from User u where u.email = :email")
    Optional<User> findForPasswordReset(@Param("email") String email);

    boolean existsByEmail(String email);

    boolean existsByEmailAndIdNot(String email, Long id);

    @Query("""
            select patient from User patient
            where patient.role = com.medicare.user.entity.Role.USER
              and patient.emailVerified = true
              and patient.mergedIntoId is null
              and lower(patient.fullName) like lower(concat('%', :search, '%'))
              and (:doctorId is null or not exists (
                  select assignment.id from DoctorPatientAssignment assignment
                  where assignment.patient.id = patient.id and assignment.doctor.id <> :doctorId
              ))
            order by patient.fullName
            """)
    List<User> findAssignablePatients(
            @Param("doctorId") Long doctorId,
            @Param("search") String search,
            Pageable pageable);
}
