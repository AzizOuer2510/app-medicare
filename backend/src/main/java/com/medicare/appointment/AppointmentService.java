package com.medicare.appointment;

import com.medicare.appointment.AppointmentDtos.AppointmentRequest;
import com.medicare.appointment.AppointmentDtos.AppointmentResponse;
import com.medicare.appointment.AppointmentDtos.AppointmentStatistics;
import com.medicare.appointment.AppointmentDtos.NoShowRisk;
import com.medicare.appointment.AppointmentDtos.PersonSummary;
import com.medicare.common.ApiException;
import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import com.medicare.user.repository.UserRepository;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AppointmentService {

    private final AppointmentRepository appointments;
    private final UserRepository users;
    private final SecretaryDoctorAssignmentRepository directory;

    private static final List<AppointmentStatus> UPCOMING_STATUSES =
            List.of(AppointmentStatus.PLANNED, AppointmentStatus.CONFIRMED);

    public List<PersonSummary> doctors() {
        return directory.findUsersByRole(Role.DOCTOR).stream()
                .map(d -> new PersonSummary(d.getId(), d.getFullName(), null))
                .toList();
    }

    public List<AppointmentResponse> list(String email, String status) {
        Long userId = currentUser(email).getId();
        var result = (status == null || status.isBlank())
                ? appointments.findByUserIdOrderByDateTimeDesc(userId)
                : appointments.findByUserIdAndStatusOrderByDateTimeDesc(userId, parseStatus(status));
        return result.stream().map(AppointmentResponse::from).toList();
    }

    public List<AppointmentResponse> history(String email) {
        Long userId = currentUser(email).getId();
        return appointments.findByUserIdAndStatusOrderByDateTimeDesc(userId, AppointmentStatus.COMPLETED)
                .stream()
                .map(AppointmentResponse::from)
                .toList();
    }

    public List<AppointmentResponse> upcoming(String email) {
        Long userId = currentUser(email).getId();
        return appointments.findByUserIdAndDateTimeAfterAndStatusInOrderByDateTimeAsc(
                        userId, LocalDateTime.now(), UPCOMING_STATUSES)
                .stream()
                .map(AppointmentResponse::from)
                .toList();
    }

    public AppointmentResponse get(String email, Long id) {
        return AppointmentResponse.from(findOwned(email, id));
    }

    public AppointmentStatistics statistics(String email) {
        Long userId = currentUser(email).getId();
        LocalDateTime now = LocalDateTime.now();
        return new AppointmentStatistics(
                appointments.countByUserId(userId),
                appointments.countByUserIdAndDateTimeAfterAndStatusIn(
                        userId, now, UPCOMING_STATUSES),
                appointments.countByUserIdAndStatus(userId, AppointmentStatus.CONFIRMED),
                appointments.countByUserIdAndStatus(userId, AppointmentStatus.COMPLETED),
                appointments.countByUserIdAndStatus(userId, AppointmentStatus.CANCELLED));
    }

    public NoShowRisk noShowRisk(String email, Long id) {
        Appointment appointment = findOwned(email, id);
        Long userId = currentUser(email).getId();
        long total = appointments.countByUserId(userId);
        long cancelled = appointments.countByUserIdAndStatus(userId, AppointmentStatus.CANCELLED);

        int score = 10;
        List<String> factors = new ArrayList<>();

        if (appointment.getStatus() == AppointmentStatus.PLANNED) {
            score += 25;
            factors.add("Rendez-vous non confirmé");
        } else if (appointment.getStatus() == AppointmentStatus.CONFIRMED) {
            score -= 10;
            factors.add("Rendez-vous confirmé");
        }

        long leadDays = Duration.between(LocalDateTime.now(), appointment.getDateTime()).toDays();
        if (leadDays > 14) {
            score += 15;
            factors.add("Pris plus de 14 jours à l'avance");
        } else if (leadDays > 7) {
            score += 5;
            factors.add("Pris plus de 7 jours à l'avance");
        }

        if (total >= 3) {
            int percent = (int) Math.round(100.0 * cancelled / total);
            if (percent >= 40) {
                score += 25;
                factors.add("Taux d'annulation élevé (" + percent + " %)");
            } else if (percent >= 20) {
                score += 10;
                factors.add("Taux d'annulation modéré (" + percent + " %)");
            }
        }

        score = Math.max(0, Math.min(100, score));
        String level = score >= 65 ? "HIGH" : score >= 35 ? "MEDIUM" : "LOW";
        return new NoShowRisk(id, score, level, List.copyOf(factors));
    }

    @Transactional
    public AppointmentResponse create(String email, AppointmentRequest request) {
        User user = currentUser(email);
        if (request.dateTime().isBefore(LocalDateTime.now())) {
            throw badRequest("La date du rendez-vous ne peut pas être dans le passé");
        }
        User doctor = resolveDoctor(request.doctorId(), request.doctorName());
        String doctorName = doctor != null ? doctor.getFullName() : request.doctorName().trim();
        ensureNoConflict(user.getId(), doctorName, request.dateTime(), null);

        Appointment appointment = Appointment.builder()
                .user(user)
                .doctor(doctor)
                .dateTime(request.dateTime())
                .doctorName(doctorName)
                .reason(normalize(request.reason()))
                .appointmentType(normalize(request.appointmentType()))
                .status(request.status() != null ? request.status() : AppointmentStatus.PLANNED)
                .build();
        return AppointmentResponse.from(appointments.save(appointment));
    }

    @Transactional
    public AppointmentResponse update(String email, Long id, AppointmentRequest request) {
        Appointment appointment = findOwned(email, id);
        if (appointment.getStatus().isTerminal()) {
            throw conflict("Un rendez-vous terminé ou annulé ne peut plus être modifié");
        }
        AppointmentStatus next = request.status();
        if (next != null && !appointment.getStatus().canTransitionTo(next)) {
            throw conflict("Transition de statut interdite : " + appointment.getStatus() + " -> " + next);
        }

        User doctor = resolveDoctor(request.doctorId(), request.doctorName());
        String doctorName = doctor != null ? doctor.getFullName() : request.doctorName().trim();
        ensureNoConflict(appointment.getUser().getId(), doctorName, request.dateTime(), id);

        if (!request.dateTime().equals(appointment.getDateTime())) {
            appointment.setReminderSentAt(null);
        }
        appointment.setDoctor(doctor);
        appointment.setDateTime(request.dateTime());
        appointment.setDoctorName(doctorName);
        appointment.setReason(normalize(request.reason()));
        appointment.setAppointmentType(normalize(request.appointmentType()));
        if (next != null) {
            appointment.setStatus(next);
        }
        return AppointmentResponse.from(appointment);
    }

    @Transactional
    public void delete(String email, Long id) {
        appointments.delete(findOwned(email, id));
    }

    private Appointment findOwned(String email, Long id) {
        Long userId = currentUser(email).getId();
        return appointments.findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Rendez-vous introuvable"));
    }

    private void ensureNoConflict(Long userId, String doctorName, LocalDateTime dateTime, Long excludedId) {
        boolean conflict = (excludedId == null)
                ? appointments.existsByUserIdAndDoctorNameIgnoreCaseAndDateTimeAndStatusNot(
                        userId, doctorName, dateTime, AppointmentStatus.CANCELLED)
                : appointments.existsByUserIdAndDoctorNameIgnoreCaseAndDateTimeAndStatusNotAndIdNot(
                        userId, doctorName, dateTime, AppointmentStatus.CANCELLED, excludedId);
        if (conflict) {
            throw new ApiException(HttpStatus.CONFLICT,
                    "Un rendez-vous existe déjà avec ce médecin à cette date et heure");
        }
    }

    // Links the appointment to a registered doctor so assigned secretaries can see it.
    private User resolveDoctor(Long doctorId, String doctorName) {
        if (doctorId != null) {
            return directory.findUserByIdAndRole(doctorId, Role.DOCTOR)
                    .orElseThrow(() -> badRequest("Médecin introuvable"));
        }
        var matches = directory.findUsersByRoleAndName(Role.DOCTOR, doctorName.trim());
        return matches.size() == 1 ? matches.get(0) : null;
    }

    private User currentUser(String email) {
        return users.findByEmailIgnoreCase(email)
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "Utilisateur introuvable"));
    }

    private AppointmentStatus parseStatus(String raw) {
        try {
            return AppointmentStatus.valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException ex) {
            throw badRequest("Statut invalide : " + raw);
        }
    }

    private static String normalize(String value) {
        return (value == null || value.isBlank()) ? null : value.trim();
    }

    private static ApiException badRequest(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, message);
    }

    private static ApiException conflict(String message) {
        return new ApiException(HttpStatus.CONFLICT, message);
    }
}
