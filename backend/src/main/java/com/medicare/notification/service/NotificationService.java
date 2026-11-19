package com.medicare.notification.service;
import com.medicare.user.entity.Role;
import org.springframework.data.jpa.domain.Specification;
import com.medicare.notification.repository.ReminderChangeRepository;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.dao.DataAccessException;

import com.medicare.appointment.AppointmentRepository;
import com.medicare.common.ApiException;
import com.medicare.medication.MedicationRepository;
import com.medicare.notification.dto.NotificationDtos;
import com.medicare.notification.entity.*;
import com.medicare.notification.repository.NotificationRepository;
import com.medicare.notification.repository.ReminderRepository;
import com.medicare.user.entity.User;
import com.medicare.user.repository.UserRepository;
import jakarta.persistence.criteria.CriteriaBuilder;
import jakarta.persistence.criteria.Predicate;
import jakarta.persistence.criteria.Root;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.ArrayList;
import java.util.Locale;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class NotificationService {
    private final CareRelationships care;
    private final ReminderChangeRepository changes;
    private final PlatformTransactionManager transactionManager;
    private final NotificationRepository notifications;
    private final ReminderRepository reminders;
    private final UserRepository users;
    private final AppointmentRepository appointments;
    private final MedicationRepository medications;

    @Transactional(readOnly = true)
    public List<NotificationDtos.NotificationResponse> list(Authentication authentication, Boolean read,
                                                           String q, NotificationType type, boolean archived) {
        Long userId = currentUser(authentication).getId();
        List<Notification> result = notifications.findAll((root, query, cb) -> {
            var predicates = new ArrayList<Predicate>();
            predicates.add(cb.equal(root.get("user").get("id"), userId));
            predicates.add(cb.equal(root.get("archived"), archived));
            if (read != null) {
                predicates.add(read ? cb.isNotNull(root.get("readAt")) : cb.isNull(root.get("readAt")));
            }
            if (type != null) predicates.add(cb.equal(root.get("type"), type));
            if (q != null && !q.isBlank()) predicates.add(matchingText(root, cb, q));
            return cb.and(predicates.toArray(Predicate[]::new));
        }, Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id")));
        return result.stream().map(NotificationDtos.NotificationResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public NotificationDtos.UnreadCountResponse unreadCount(Authentication authentication) {
        return new NotificationDtos.UnreadCountResponse(
                notifications.countByUserIdAndReadAtIsNullAndArchivedFalse(currentUser(authentication).getId()));
    }

    @Transactional
    public NotificationDtos.NotificationResponse create(
            Authentication authentication, NotificationDtos.CreateNotificationRequest request) {
        User actor = requireAdmin(authentication);
        User user = request.userId() == null ? actor : users.findById(request.userId())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Destinataire introuvable."));
        validateReference(user, request.type(), request.referenceId());
        return NotificationDtos.NotificationResponse.from(notifications.save(Notification.builder()
                .user(user).title(request.title().trim()).message(request.message().trim())
                .type(request.type()).referenceId(request.referenceId()).createdAt(Instant.now()).build()));
    }

    /** Server-side integration point. The recipient is selected by trusted module code. */
    @Transactional
    public NotificationDtos.NotificationResponse notify(Long userId, NotificationType type, String message) {
        String title = switch (type) {
            case APPOINTMENT -> "Rendez-vous";
            case MEDICATION -> "Médicaments";
            case GENERAL -> "Information MediCare";
        };
        return notify(userId, type, title, message);
    }

    @Transactional
    public NotificationDtos.NotificationResponse notify(Long userId, NotificationType type, String title, String message) {
        if (type == null || title == null || title.isBlank() || title.length() > 120
                || message == null || message.isBlank() || message.length() > 2000)
            throw new ApiException(HttpStatus.BAD_REQUEST, "Notification invalide.");
        User recipient = users.findById(userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Destinataire introuvable."));
        return NotificationDtos.NotificationResponse.from(notifications.save(Notification.builder()
                .user(recipient).type(type).title(title.trim()).message(message.trim()).createdAt(Instant.now()).build()));
    }

    @Transactional(readOnly = true)
    public List<NotificationDtos.Recipient> recipients(Authentication auth) {
        requireAdmin(auth);
        return users.findAll(Sort.by("fullName", "id")).stream()
                .map(u -> new NotificationDtos.Recipient(u.getId(), u.getFullName(), u.getRole().name())).toList();
    }

    @Transactional(readOnly = true)
    public List<NotificationDtos.AdminNotificationResponse> administration(Authentication auth, Long userId) {
        requireAdmin(auth);
        if (userId != null && userId <= 0) throw new ApiException(HttpStatus.BAD_REQUEST, "Destinataire invalide.");
        return notifications.findAll((root, query, cb) -> userId == null ? cb.conjunction()
                        : cb.equal(root.get("user").get("id"), userId),
                Sort.by(Sort.Order.desc("createdAt"), Sort.Order.desc("id"))).stream()
                .map(n -> new NotificationDtos.AdminNotificationResponse(NotificationDtos.NotificationResponse.from(n),
                        n.getUser().getId(), n.getUser().getFullName())).toList();
    }

    @Transactional
    public NotificationDtos.NotificationResponse updateNotification(Authentication auth, Long id,
            NotificationDtos.UpdateNotificationRequest request) {
        requireAdmin(auth);
        Notification notification = notifications.findLockedById(id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Notification introuvable."));
        if (request.referenceId() != null || notification.getReferenceId() != null || request.type() != notification.getType())
            validateReference(notification.getUser(), request.type(), request.referenceId());
        notification.setTitle(request.title().trim());
        notification.setMessage(request.message().trim());
        notification.setType(request.type());
        notification.setReferenceId(request.referenceId());
        if (request.read() != null) notification.setReadAt(request.read() ? Instant.now() : null);
        return NotificationDtos.NotificationResponse.from(notification);
    }

    @Transactional
    public void deleteNotification(Authentication auth, Long id) {
        requireAdmin(auth);
        Notification notification = notifications.findLockedById(id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Notification introuvable."));
        notifications.delete(notification);
    }

    private User requireAdmin(Authentication auth) {
        User actor = currentUser(auth);
        if (actor.getRole() != Role.ADMIN) throw CareRelationships.denied();
        return actor;
    }

    @Transactional
    public NotificationDtos.NotificationResponse markRead(Authentication authentication, Long id) {
        Notification notification = ownedNotification(authentication, id);
        if (notification.getReadAt() == null) {
            notification.setReadAt(Instant.now().truncatedTo(ChronoUnit.MICROS));
        }
        return NotificationDtos.NotificationResponse.from(notification);
    }

    @Transactional
    public NotificationDtos.MarkAllReadResponse markAllRead(Authentication authentication) {
        return new NotificationDtos.MarkAllReadResponse(
                notifications.markAllRead(currentUser(authentication).getId(), Instant.now()));
    }

    @Transactional
    public NotificationDtos.NotificationResponse markUnread(Authentication authentication, Long id) {
        Notification notification = ownedNotification(authentication, id);
        notification.setReadAt(null);
        return NotificationDtos.NotificationResponse.from(notification);
    }

    @Transactional
    public NotificationDtos.NotificationResponse archive(Authentication authentication, Long id, boolean archived) {
        Notification notification = ownedNotification(authentication, id);
        notification.setArchived(archived);
        return NotificationDtos.NotificationResponse.from(notification);
    }

    private Notification ownedNotification(Authentication authentication, Long id) {
        return notifications.findLockedByIdAndUserId(id, currentUser(authentication).getId())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Notification not found"));
    }

    @Transactional(readOnly = true)
    public NotificationDtos.Overview overview(Authentication authentication) {
        User viewer = currentUser(authentication);
        Long id = viewer.getId();
        var visible = reminderScope(viewer);
        var pending = visible.and((r,q,b) -> b.equal(r.get("status"),ReminderStatus.PENDING));
        return new NotificationDtos.Overview(notifications.countByUserIdAndReadAtIsNullAndArchivedFalse(id),
                notifications.countByUserIdAndArchived(id, false), notifications.countByUserIdAndArchived(id, true),
                reminders.count(pending), reminders.count(visible.and((r,q,b) -> b.equal(r.get("status"),ReminderStatus.SENT))),
                reminders.findAll(pending,PageRequest.of(0,1,Sort.by("scheduledFor","id"))).stream().findFirst()
                        .map(NotificationDtos.ReminderResponse::from).orElse(null),viewer.getRole().name(),id);
    }

    @Transactional(readOnly = true)
    public List<NotificationDtos.ReminderResponse> listReminders(Authentication authentication,
            String q, NotificationType type, ReminderStatus status) {
        User viewer = currentUser(authentication);
        return reminders.findAll((root, query, cb) -> {
            var predicates = new ArrayList<Predicate>();
            predicates.add(reminderScope(viewer).toPredicate(root,query,cb));
            if (type != null) predicates.add(cb.equal(root.get("type"), type));
            if (status != null) predicates.add(cb.equal(root.get("status"), status));
            if (q != null && !q.isBlank()) predicates.add(matchingText(root, cb, q));
            return cb.and(predicates.toArray(Predicate[]::new));
        }, Sort.by("scheduledFor", "id")).stream()
                .map(NotificationDtos.ReminderResponse::from).toList();
    }

    private Specification<Reminder> reminderScope(User viewer) {
        return (root,query,cb) -> {
            if (viewer.getRole()==Role.ADMIN) return cb.conjunction();
            var own = cb.equal(root.get("user"),viewer);
            if (viewer.getRole()!=Role.DOCTOR) return own;
            return cb.or(own,cb.and(cb.equal(root.get("author"),viewer),
                    root.get("user").get("id").in(care.patientIds(viewer))));
        };
    }

    private Predicate matchingText(Root<?> root, CriteriaBuilder cb, String q) {
        String pattern = "%" + q.trim().toLowerCase(Locale.ROOT)
                .replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        return cb.or(cb.like(cb.lower(root.get("title")), pattern, '\\'),
                cb.like(cb.lower(root.get("message")), pattern, '\\'));
    }

    @Transactional
    public NotificationDtos.ReminderResponse createReminder(
            Authentication authentication, NotificationDtos.ReminderRequest request) {
        User actor = currentUser(authentication);
        User user = care.recipient(actor,request.patientId());
        validateReference(user, request.type(), request.referenceId());
        requireFuture(request.scheduledFor());
        Reminder reminder = Reminder.builder().user(user).status(ReminderStatus.PENDING)
                .createdAt(Instant.now()).build();
        applyReminder(reminder, request);
        if (!user.getId().equals(actor.getId())) {
            reminder.setAuthor(actor);
            reminder.setInstructionAt(request.scheduledFor());
            announce(reminder,actor,"programmé");
        }
        reminders.save(reminder);
        record(reminder,actor,"Création");
        return NotificationDtos.ReminderResponse.from(reminder);
    }

    @Transactional
    public NotificationDtos.ReminderResponse updateReminder(
            Authentication authentication, Long id, NotificationDtos.ReminderRequest request) {
        User user = currentUser(authentication);
        Reminder reminder = manageable(user, id);
        requirePending(reminder);
        validateReference(reminder.getUser(), request.type(), request.referenceId());
        requireFuture(request.scheduledFor());
        Instant alert = reminder.getScheduledFor();
        boolean retainAlert = reminder.getAuthor()!=null && request.scheduledFor().equals(reminder.getInstructionAt())
                && alert.isAfter(Instant.now());
        applyReminder(reminder, request);
        if (reminder.getAuthor()!=null) {
            reminder.setInstructionAt(request.scheduledFor());
            if (retainAlert) reminder.setScheduledFor(alert);
            announce(reminder,user,"modifié");
        }
        reminder.setDeliveryFailedAt(null);
        record(reminder,user,"Modification");
        return NotificationDtos.ReminderResponse.from(reminder);
    }

    @Transactional
    public NotificationDtos.ReminderResponse cancelReminder(Authentication authentication, Long id) {
        User actor = currentUser(authentication);
        Reminder reminder = manageable(actor,id);
        if (reminder.getStatus() != ReminderStatus.CANCELLED) {
            requirePending(reminder);
            reminder.setStatus(ReminderStatus.CANCELLED);
            record(reminder,actor,"Annulation");
            if (reminder.getAuthor()!=null) announce(reminder,actor,"annulé");
        }
        return NotificationDtos.ReminderResponse.from(reminder);
    }

    @Transactional
    public void deleteReminder(Authentication authentication, Long id) {
        User actor = currentUser(authentication);
        Reminder reminder = manageable(actor,id);
        if (reminder.getAuthor()!=null && actor.getRole()!=Role.ADMIN) throw CareRelationships.denied();
        if (reminder.getAuthor()!=null) announce(reminder,actor,"supprimé");
        record(reminder,actor,"Suppression");
        reminders.delete(reminder);
    }

    @Transactional
    public NotificationDtos.ReminderResponse snoozeReminder(Authentication authentication, Long id, int minutes) {
        User user = currentUser(authentication);
        Reminder reminder = user.getRole() == Role.ADMIN ? manageable(user, id) : ownedReminder(user, id);
        if (reminder.getStatus() == ReminderStatus.CANCELLED) {
            throw new ApiException(HttpStatus.CONFLICT, "A cancelled reminder cannot be postponed");
        }
        validateReference(reminder.getUser(), reminder.getType(), reminder.getReferenceId());
        Instant now = Instant.now();
        Instant base = reminder.getStatus() == ReminderStatus.PENDING && reminder.getScheduledFor().isAfter(now)
                ? reminder.getScheduledFor() : now;
        Instant next = base.plusSeconds(minutes * 60L);
        if (reminder.getStatus() == ReminderStatus.SENT) {
            // A sent occurrence remains immutable; the next occurrence has a new id.
            reminder = reminders.save(Reminder.builder().user(reminder.getUser()).title(reminder.getTitle())
                    .author(reminder.getAuthor()).instructionAt(reminder.getInstructionAt())
                    .message(reminder.getMessage()).type(reminder.getType()).referenceId(reminder.getReferenceId())
                    .scheduledFor(next).createdAt(Instant.now()).status(ReminderStatus.PENDING).build());
        } else {
            reminder.setScheduledFor(next);
            reminder.setDeliveryFailedAt(null);
        }
        record(reminder,user,"Report de l’alerte");
        return NotificationDtos.ReminderResponse.from(reminder);
    }

    @Transactional
    public NotificationDtos.ReminderResponse setAlert(Authentication auth, Long id, Instant at) {
        User actor = currentUser(auth);
        Reminder reminder = actor.getRole() == Role.ADMIN ? manageable(actor, id) : ownedReminder(actor,id);
        requirePending(reminder);
        requireFuture(at);
        reminder.setScheduledFor(at);
        reminder.setDeliveryFailedAt(null);
        record(reminder,actor,"Heure de l’alerte");
        return NotificationDtos.ReminderResponse.from(reminder);
    }
    private Reminder manageable(User actor,Long id) {
        Reminder r = reminders.findLockedById(id).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,"Rappel introuvable."));
        if (actor.getRole()==Role.ADMIN) return r;
        if (r.getAuthor()==null && r.getUser().getId().equals(actor.getId())) return r;
        if (r.getAuthor()!=null && r.getAuthor().getId().equals(actor.getId()) && care.follows(actor,r.getUser().getId())) return r;
        if (r.getUser().getId().equals(actor.getId())) throw CareRelationships.denied();
        throw new ApiException(HttpStatus.NOT_FOUND,"Rappel introuvable.");
    }
    private void announce(Reminder r,User actor,String action) {
        care.notify(r.getUser(),"Rappel de suivi "+action,actor.getFullName()+" a "+action+" le rappel « "+r.getTitle()+" ».");
    }
    private void record(Reminder r,User actor,String action) {
        ReminderChange entry = new ReminderChange();
        entry.setReminderId(r.getId());
        entry.setActorId(actor.getId());
        entry.setActorName(actor.getFullName());
        entry.setChangedAt(Instant.now());
        entry.setAction(action);
        changes.save(entry);
    }
    @Transactional(readOnly=true)
    public List<NotificationDtos.Delivery> deliveries(Authentication auth) {
        if (currentUser(auth).getRole()!=Role.ADMIN) throw CareRelationships.denied();
        var result = new ArrayList<NotificationDtos.Delivery>();
        for (Reminder r : reminders.findTop100ByStatusAndDeliveryFailedAtIsNotNullOrderByDeliveryFailedAtDesc(ReminderStatus.PENDING))
            result.add(new NotificationDtos.Delivery(r.getTitle(),r.getUser().getFullName(),r.getDeliveryFailedAt(),r.getId()));
        for (Notification n : notifications.findAll(PageRequest.of(0,100,Sort.by(Sort.Order.desc("createdAt"),Sort.Order.desc("id")))))
            result.add(new NotificationDtos.Delivery(n.getTitle(),n.getUser().getFullName(),n.getCreatedAt(),null));
        return result;
    }
    public List<ReminderChange> history(Authentication auth) {
        if (currentUser(auth).getRole()!=Role.ADMIN) throw CareRelationships.denied();
        return changes.findTop100ByOrderByIdDesc();
    }
    @Transactional
    public void retry(Authentication auth,Long id) {
        User actor=currentUser(auth);
        if (actor.getRole()!=Role.ADMIN) throw CareRelationships.denied();
        Reminder r=manageable(actor,id);
        requirePending(r);
        if (r.getDeliveryFailedAt()==null) throw new ApiException(HttpStatus.CONFLICT,"Aucun échec à relancer.");
        r.setDeliveryFailedAt(null);
        record(r,actor,"Relance de l’envoi");
    }
    public void deliverDueReminders() {
        var tx = new TransactionTemplate(transactionManager);
        Instant now = Instant.now();
        for (Long id : reminders.dueIds(now,PageRequest.of(0,100))) {
            try {
                tx.executeWithoutResult(status -> reminders.findLockedById(id).filter(r -> due(r,now)).ifPresent(r -> deliver(r,now)));
            } catch (DataAccessException ex) {
                tx.executeWithoutResult(status -> reminders.findLockedById(id).filter(r -> due(r,now)).ifPresent(r -> r.setDeliveryFailedAt(now)));
            }
        }
    }
    private boolean due(Reminder r,Instant now) {
        return r.getStatus()==ReminderStatus.PENDING && r.getDeliveryFailedAt()==null && !r.getScheduledFor().isAfter(now);
    }
    private void deliver(Reminder reminder,Instant now) {
        if (!referenceAvailable(reminder.getUser(), reminder.getType(), reminder.getReferenceId())) {
            reminder.setStatus(ReminderStatus.CANCELLED);
            return;
        }
        notifications.save(Notification.builder().user(reminder.getUser()).title(reminder.getTitle())
                .message(reminder.getMessage()).type(reminder.getType()).referenceId(reminder.getReferenceId())
                .reminderId(reminder.getId()).createdAt(now).build());
        reminder.setStatus(ReminderStatus.SENT);
        reminder.setSentAt(now);
    }

    private User currentUser(Authentication authentication) {
        if (authentication == null || authentication.getName() == null) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Authentication required");
        }
        return care.actor(authentication);
    }

    private Reminder ownedReminder(User user, Long id) {
        return reminders.findByIdAndUserId(id, user.getId())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Reminder not found"));
    }

    private void requirePending(Reminder reminder) {
        if (reminder.getStatus() != ReminderStatus.PENDING) {
            throw new ApiException(HttpStatus.CONFLICT, "Only pending reminders can be changed");
        }
    }

    private void requireFuture(Instant scheduledFor) {
        if (scheduledFor == null || !scheduledFor.isAfter(Instant.now())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Reminder date must be in the future");
        }
    }

    private void applyReminder(Reminder reminder, NotificationDtos.ReminderRequest request) {
        reminder.setTitle(request.title().trim());
        reminder.setMessage(request.message().trim());
        reminder.setType(request.type());
        reminder.setReferenceId(request.referenceId());
        reminder.setScheduledFor(request.scheduledFor());
    }

    private void validateReference(User user, NotificationType type, Long referenceId) {
        if (type == NotificationType.GENERAL && referenceId != null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "General notifications must not have a reference");
        }
        if (type != NotificationType.GENERAL && referenceId == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "A related appointment or medication is required");
        }
        if (!referenceAvailable(user, type, referenceId)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "Related appointment or medication not found");
        }
    }

    private boolean referenceAvailable(User user, NotificationType type, Long referenceId) {
        return switch (type) {
            case GENERAL -> referenceId == null;
            case APPOINTMENT -> referenceId != null && appointments.findById(referenceId)
                    .filter(a -> a.getUser().getId().equals(user.getId()))
                    .filter(a -> a.getStatus() != com.medicare.appointment.AppointmentStatus.CANCELLED).isPresent();
            case MEDICATION -> referenceId != null && medications.findById(referenceId)
                    .filter(m -> m.getStatus() != com.medicare.medication.MedicationStatus.DISCONTINUED)
                    .filter(m -> m.getUser().getId().equals(user.getId())).isPresent();
        };
    }
}
