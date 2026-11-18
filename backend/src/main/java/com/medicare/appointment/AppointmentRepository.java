package com.medicare.appointment;

import com.medicare.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface AppointmentRepository extends JpaRepository<Appointment, Long> {

    @Modifying
    @Query("update Appointment r set r.user = :target where r.user.id = :source")
    int transfer(@Param("source") Long source, @Param("target") User target);

    List<Appointment> findByDoctorIdInOrderByDateTimeDesc(Collection<Long> doctorIds);

    /** Patients ayant au moins un rendez-vous non annulé avec ce médecin (lien Rendez-vous → Suivi santé). */
    @Query("select distinct a.user from Appointment a where a.doctor.id = :doctorId "
            + "and a.status <> com.medicare.appointment.AppointmentStatus.CANCELLED")
    List<User> findPatientsOfDoctor(@Param("doctorId") Long doctorId);

    boolean existsByDoctorIdAndUserIdAndStatusNot(Long doctorId, Long userId, AppointmentStatus status);

    List<Appointment> findByDoctorIdInAndStatusOrderByDateTimeDesc(
            Collection<Long> doctorIds, AppointmentStatus status);

    List<Appointment> findByUserIdOrderByDateTimeDesc(Long userId);

    List<Appointment> findByUserIdAndStatusOrderByDateTimeDesc(Long userId, AppointmentStatus status);

    List<Appointment> findByUserIdAndDateTimeBeforeOrderByDateTimeDesc(Long userId, LocalDateTime before);

    List<Appointment> findByUserIdAndDateTimeAfterAndStatusInOrderByDateTimeAsc(
            Long userId, LocalDateTime after, Collection<AppointmentStatus> statuses);

    Optional<Appointment> findByIdAndUserId(Long id, Long userId);

    long countByUserId(Long userId);

    long countByUserIdAndStatus(Long userId, AppointmentStatus status);

    long countByUserIdAndDateTimeAfterAndStatusIn(Long userId, LocalDateTime after, Collection<AppointmentStatus> statuses);

    List<Appointment> findAllByOrderByDateTimeDesc();

    List<Appointment> findByDateTimeBetweenAndStatusInAndReminderSentAtIsNull(
            LocalDateTime from, LocalDateTime to, Collection<AppointmentStatus> statuses);

    List<Appointment> findByStatusOrderByDateTimeDesc(AppointmentStatus status);

    boolean existsByDoctorNameIgnoreCaseAndDateTimeAndStatusNot(
            String doctorName, LocalDateTime dateTime, AppointmentStatus status);

    boolean existsByDoctorNameIgnoreCaseAndDateTimeAndStatusNotAndIdNot(
            String doctorName, LocalDateTime dateTime, AppointmentStatus status, Long id);

    boolean existsByUserIdAndDoctorNameIgnoreCaseAndDateTimeAndStatusNot(
            Long userId, String doctorName, LocalDateTime dateTime, AppointmentStatus status);

    boolean existsByUserIdAndDoctorNameIgnoreCaseAndDateTimeAndStatusNotAndIdNot(
            Long userId, String doctorName, LocalDateTime dateTime, AppointmentStatus status, Long id);
}
