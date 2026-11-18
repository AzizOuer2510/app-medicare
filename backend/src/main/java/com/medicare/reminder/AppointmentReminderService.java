package com.medicare.reminder;

import com.medicare.appointment.Appointment;
import com.medicare.appointment.AppointmentRepository;
import com.medicare.appointment.AppointmentStatus;
import com.medicare.user.entity.User;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Slf4j
@Service
@RequiredArgsConstructor
public class AppointmentReminderService {

    private static final DateTimeFormatter DATE =
            DateTimeFormatter.ofPattern("EEEE d MMMM yyyy", Locale.FRENCH);
    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("HH'h'mm");

    private final AppointmentRepository appointments;
    private final EmailReminderSender emailSender;
    private final SmsReminderSender smsSender;

    @Value("${app.reminders.enabled:true}")
    private boolean enabled;

    @Value("${app.reminders.hours-before:24}")
    private long hoursBefore;

    @Scheduled(cron = "${app.reminders.cron:0 0 * * * *}")
    @Transactional
    public void scheduledRun() {
        if (enabled) {
            sendDueReminders();
        }
    }

    /** Sends email + SMS for upcoming appointments within the reminder window. Returns the number reminded. */
    @Transactional
    public int sendDueReminders() {
        LocalDateTime now = LocalDateTime.now();
        List<Appointment> due = appointments.findByDateTimeBetweenAndStatusInAndReminderSentAtIsNull(
                now, now.plusHours(hoursBefore),
                List.of(AppointmentStatus.PLANNED, AppointmentStatus.CONFIRMED));

        int sent = 0;
        for (Appointment appointment : due) {
            if (send(appointment, now)) {
                sent++;
            }
        }
        if (!due.isEmpty()) {
            log.info("Rappels de rendez-vous : {} envoyes sur {} a traiter", sent, due.size());
        }
        return sent;
    }

    @Transactional
    public boolean sendImmediately(Appointment appointment) {
        if (!enabled
                || appointment.getReminderSentAt() != null
                || (appointment.getStatus() != AppointmentStatus.PLANNED
                        && appointment.getStatus() != AppointmentStatus.CONFIRMED)) {
            return false;
        }
        return send(appointment, LocalDateTime.now());
    }

    private boolean send(Appointment appointment, LocalDateTime sentAt) {
        User patient = appointment.getUser();
        boolean mailOk = emailSender.send(patient.getEmail(), subject(appointment), emailBody(appointment));
        boolean smsOk = smsSender.send(patient.getPhoneNumber(), smsBody(appointment));
        if (mailOk || smsOk) {
            appointment.setReminderSentAt(sentAt);
            return true;
        }
        return false;
    }

    private String subject(Appointment a) {
        return "Rappel : rendez-vous le " + a.getDateTime().format(DATE) + " a " + a.getDateTime().format(TIME);
    }

    private String emailBody(Appointment a) {
        StringBuilder sb = new StringBuilder()
                .append("Bonjour ").append(a.getUser().getFullName()).append(",\n\n")
                .append("Nous vous rappelons votre rendez-vous :\n")
                .append("  - Date : ").append(a.getDateTime().format(DATE)).append('\n')
                .append("  - Heure : ").append(a.getDateTime().format(TIME)).append('\n')
                .append("  - Medecin : ").append(a.getDoctorName()).append('\n');
        if (a.getReason() != null) {
            sb.append("  - Motif : ").append(a.getReason()).append('\n');
        }
        if (a.getStatus() == AppointmentStatus.PLANNED) {
            sb.append("\nCe rendez-vous n'est pas encore confirme : merci de le confirmer dans l'application MediCare.\n");
        }
        return sb.append("\nConseils :\n")
                .append("  - Arrivez 10 minutes en avance.\n")
                .append("  - Apportez votre carte vitale, votre mutuelle et vos ordonnances.\n")
                .append("\nEn cas d'empechement, annulez le rendez-vous dans l'application ou contactez le secretariat.\n\n")
                .append("L'equipe MediCare")
                .toString();
    }

    private String smsBody(Appointment a) {
        return "MediCare : rappel RDV " + a.getDateTime().format(DATE) + " a " + a.getDateTime().format(TIME)
                + " avec " + a.getDoctorName()
                + ". Arrivez 10 min en avance avec votre carte vitale. En cas d'empechement, annulez via l'app.";
    }
}
