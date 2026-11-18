package com.medicare.appointment;

import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface SecretaryDoctorAssignmentRepository extends JpaRepository<SecretaryDoctorAssignment, Long> {

    boolean existsBySecretaryId(Long secretaryId);

    boolean existsBySecretaryIdAndDoctorId(Long secretaryId, Long doctorId);

    @Query("select a.doctor from SecretaryDoctorAssignment a where a.secretary.id = :secretaryId order by a.doctor.fullName")
    List<User> findDoctorsOfSecretary(@Param("secretaryId") Long secretaryId);

    @Query("select a from SecretaryDoctorAssignment a join fetch a.secretary join fetch a.doctor order by a.secretary.email")
    List<SecretaryDoctorAssignment> findAllWithUsers();

    @Query("select u from User u where u.role = :role order by u.fullName")
    List<User> findUsersByRole(@Param("role") Role role);

    @Query("select u from User u where lower(u.fullName) = lower(:name) and u.role = :role")
    List<User> findUsersByRoleAndName(@Param("role") Role role, @Param("name") String name);

    @Query("select u from User u where u.id = :id and u.role = :role")
    Optional<User> findUserByIdAndRole(@Param("id") Long id, @Param("role") Role role);

    @Query("select u from User u where u.role = :role and u.emailVerified = true and u.mergedIntoId is null order by u.fullName")
    List<User> findActivePatients(@Param("role") Role role);
}
