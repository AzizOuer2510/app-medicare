package com.medicare.appointment;

import com.medicare.appointment.AppointmentDtos.AssignmentRequest;
import com.medicare.appointment.AppointmentDtos.AssignmentResponse;
import com.medicare.appointment.AppointmentDtos.PatientSummary;
import com.medicare.appointment.AppointmentDtos.PersonSummary;
import com.medicare.appointment.AppointmentDtos.SecretaryAppointmentRequest;
import com.medicare.appointment.AppointmentDtos.SecretaryAppointmentResponse;
import com.medicare.appointment.AppointmentDtos.SecretaryProfile;
import com.medicare.common.ApiException;
import com.medicare.security.account.AccountAccess;
import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import com.medicare.user.repository.UserRepository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Secretariat: a secretary is any account with at least one doctor assignment
 * and only sees / manages the appointments of the doctors assigned to them.
 * An ADMIN sees every doctor and manages the assignments.
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class SecretaryAppointmentService {

    private final AppointmentRepository appointments;
    private final SecretaryDoctorAssignmentRepository assignments;
    private final UserRepository users;
    private final AccountAccess access;

    public SecretaryProfile me(Authentication auth) {
        User user = access.current(auth);
        boolean admin = user.getRole() == Role.ADMIN;
        boolean secretary = assignments.existsBySecretaryId(user.getId());
        List<PersonSummary> doctors = (admin || secretary) ? doctorsOf(user) : List.of();
        return new SecretaryProfile(secretary, admin, doctors);
    }

    public List<PersonSummary> doctors(Authentication auth) {
        return doctorsOf(staff(auth));
    }

    public List<PatientSummary> patients(Authentication auth) {
        staff(auth);
        return assignments.findActivePatients(Role.USER).stream()
                .map(u -> new PatientSummary(u.getId(), u.getFullName(), u.getEmail()))
                .toList();
    }

    public List<SecretaryAppointmentResponse> list(String status, Authentication auth) {
        Set<Long> doctorIds = doctorIds(staff(auth));
        if (doctorIds.isEmpty()) {
            return List.of();
        }
        var result = (status == null || status.isBlank())
                ? appointments.findByDoctorIdInOrderByDateTimeDesc(doctorIds)
                : appointments.findByDoctorIdInAndStatusOrderByDateTimeDesc(doctorIds, parseStatus(status));
        return result.stream().map(SecretaryAppointmentResponse::from).toList();
    }

    @Transactional
    public SecretaryAppointmentResponse create(SecretaryAppointmentRequest request, Authentication auth) {
        User staff = staff(auth);
        User patient = findPatient(request.patientId());
        if (request.dateTime().isBefore(LocalDateTime.now())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "La date du rendez-vous ne peut pas être dans le passé");
        }
        User doctor = allowedDoctor(staff, request.doctorId());
        ensureDoctorAvailable(doctor.getFullName(), request.dateTime(), null);

        Appointment appointment = Appointment.builder()
                .user(patient)
                .doctor(doctor)
                .dateTime(request.dateTime())
                .doctorName(doctor.getFullName())
                .reason(normalize(request.reason()))
                .appointmentType(normalize(request.appointmentType()))
                .status(request.status() != null ? request.status() : AppointmentStatus.PLANNED)
                .build();
        return SecretaryAppointmentResponse.from(appointments.save(appointment));
    }

    @Transactional
    public SecretaryAppointmentResponse update(Long id, SecretaryAppointmentRequest request, Authentication auth) {
        User staff = staff(auth);
        Appointment appointment = findAllowed(staff, id);
        if (appointment.getStatus().isTerminal()) {
            throw conflict("Un rendez-vous terminé ou annulé ne peut plus être modifié");
        }
        AppointmentStatus next = request.status();
        if (next != null && !appointment.getStatus().canTransitionTo(next)) {
            throw conflict("Transition de statut interdite : " + appointment.getStatus() + " -> " + next);
        }
        User doctor = allowedDoctor(staff, request.doctorId());
        ensureDoctorAvailable(doctor.getFullName(), request.dateTime(), id);

        appointment.setUser(findPatient(request.patientId()));
        if (!request.dateTime().equals(appointment.getDateTime())) {
            appointment.setReminderSentAt(null);
        }
        appointment.setDoctor(doctor);
        appointment.setDoctorName(doctor.getFullName());
        appointment.setDateTime(request.dateTime());
        appointment.setReason(normalize(request.reason()));
        appointment.setAppointmentType(normalize(request.appointmentType()));
        if (next != null) {
            appointment.setStatus(next);
        }
        return SecretaryAppointmentResponse.from(appointment);
    }

    @Transactional
    public void delete(Long id, Authentication auth) {
        appointments.delete(findAllowed(staff(auth), id));
    }

    public void ensureStaff(Authentication auth) {
        staff(auth);
    }

    // ---- Admin: secretary <-> doctor assignments ----

    public List<AssignmentResponse> listAssignments(Authentication auth) {
        access.admin(auth);
        return assignments.findAllWithUsers().stream().map(AssignmentResponse::from).toList();
    }

    @Transactional
    public AssignmentResponse assign(AssignmentRequest request, Authentication auth) {
        access.admin(auth);
        User secretary = users.findByEmailIgnoreCase(request.secretaryEmail().trim())
                .filter(u -> u.getMergedIntoId() == null)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Compte secrétaire introuvable"));
        if (secretary.getRole() != Role.USER) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Ce compte ne peut pas être secrétaire");
        }
        User doctor = assignments.findUserByIdAndRole(request.doctorId(), Role.DOCTOR)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Médecin introuvable"));
        if (assignments.existsBySecretaryIdAndDoctorId(secretary.getId(), doctor.getId())) {
            throw conflict("Ce médecin est déjà affecté à cette secrétaire");
        }
        var saved = assignments.save(SecretaryDoctorAssignment.builder().secretary(secretary).doctor(doctor).build());
        return AssignmentResponse.from(saved);
    }

    @Transactional
    public void unassign(Long id, Authentication auth) {
        access.admin(auth);
        if (!assignments.existsById(id)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Affectation introuvable");
        }
        assignments.deleteById(id);
    }

    // ---- helpers ----

    private User staff(Authentication auth) {
        User user = access.current(auth);
        if (user.getRole() == Role.ADMIN || assignments.existsBySecretaryId(user.getId())) {
            return user;
        }
        throw new ApiException(HttpStatus.FORBIDDEN, "Accès réservé au secrétariat");
    }

    private List<User> doctorEntities(User staff) {
        return staff.getRole() == Role.ADMIN
                ? assignments.findUsersByRole(Role.DOCTOR)
                : assignments.findDoctorsOfSecretary(staff.getId());
    }

    private List<PersonSummary> doctorsOf(User staff) {
        return doctorEntities(staff).stream()
                .map(d -> new PersonSummary(d.getId(), d.getFullName(), d.getEmail()))
                .toList();
    }

    private Set<Long> doctorIds(User staff) {
        return doctorEntities(staff).stream().map(User::getId).collect(Collectors.toSet());
    }

    private User allowedDoctor(User staff, Long doctorId) {
        return doctorEntities(staff).stream()
                .filter(d -> d.getId().equals(doctorId))
                .findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "Ce médecin ne vous est pas affecté"));
    }

    private Appointment findAllowed(User staff, Long id) {
        Appointment appointment = appointments.findById(id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Rendez-vous introuvable"));
        Long doctorId = appointment.getDoctor() == null ? null : appointment.getDoctor().getId();
        if (doctorId == null || !doctorIds(staff).contains(doctorId)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Rendez-vous introuvable");
        }
        return appointment;
    }

    private User findPatient(Long patientId) {
        return users.findById(patientId)
                .filter(u -> u.getRole() == Role.USER && u.getMergedIntoId() == null)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Patient introuvable"));
    }

    // A doctor cannot have two active appointments at the same time, whatever the patient.
    private void ensureDoctorAvailable(String doctorName, LocalDateTime dateTime, Long excludedId) {
        boolean taken = (excludedId == null)
                ? appointments.existsByDoctorNameIgnoreCaseAndDateTimeAndStatusNot(
                        doctorName, dateTime, AppointmentStatus.CANCELLED)
                : appointments.existsByDoctorNameIgnoreCaseAndDateTimeAndStatusNotAndIdNot(
                        doctorName, dateTime, AppointmentStatus.CANCELLED, excludedId);
        if (taken) {
            throw conflict("Ce médecin a déjà un rendez-vous à cette date et heure");
        }
    }

    private AppointmentStatus parseStatus(String raw) {
        try {
            return AppointmentStatus.valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException ex) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Statut invalide : " + raw);
        }
    }

    private static String normalize(String value) {
        return (value == null || value.isBlank()) ? null : value.trim();
    }

    private static ApiException conflict(String message) {
        return new ApiException(HttpStatus.CONFLICT, message);
    }
}
