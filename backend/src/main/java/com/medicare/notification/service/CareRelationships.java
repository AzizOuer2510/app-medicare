package com.medicare.notification.service;

import com.medicare.common.ApiException;
import com.medicare.document.repository.DocumentRepository;
import com.medicare.notification.entity.*;
import com.medicare.notification.repository.*;
import com.medicare.user.entity.*;
import com.medicare.user.repository.UserRepository;
import com.medicare.health.HealthAccessService;
import com.medicare.security.account.AccountAccess;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.List;
import java.util.LinkedHashMap;
import java.util.Comparator;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service @RequiredArgsConstructor
public class CareRelationships {
    private final UserRepository users;
    private final PatientDoctorRepository links;
    private final DocumentRepository documents;
    private final NotificationRepository notifications;
    private final EntityManager em;
    private final AccountAccess accounts;
    private final HealthAccessService healthAccess;

    public record Contact(Long id, String name, boolean removable) {
        static Contact from(User u) { return new Contact(u.getId(),u.getFullName(),true); }
    }
    public User actor(Authentication auth) {
        User actor = accounts.current(auth);
        return actor.getRole() == Role.ADMIN ? accounts.admin(auth) : actor;
    }
    public boolean follows(User actor, Long patientId) {
        if (actor.getRole() != Role.DOCTOR) return false;
        return links.existsByPatientIdAndDoctorId(patientId, actor.getId())
                || users.findById(patientId).filter(p -> p.getRole() == Role.USER && p.getMergedIntoId() == null)
                        .map(p -> healthAccess.follows(actor, p)).orElse(false);
    }

    public List<Long> patientIds(User doctor) {
        return patients(doctor).stream().map(User::getId).toList();
    }

    private List<User> patients(User doctor) {
        var result = new LinkedHashMap<Long, User>();
        healthAccess.followedPatients(doctor).keySet().forEach(p -> result.put(p.getId(), p));
        em.createQuery("select p from User p, PatientDoctor l where p.id=l.patientId and l.doctor=:doctor "
                        + "and p.role=:role and p.mergedIntoId is null", User.class)
                .setParameter("doctor", doctor).setParameter("role", Role.USER).getResultList()
                .forEach(p -> result.put(p.getId(), p));
        return result.values().stream().sorted(Comparator.comparing(User::getFullName, String.CASE_INSENSITIVE_ORDER)).toList();
    }
    public User recipient(User actor, Long patientId) {
        if (patientId==null || actor.getId().equals(patientId)) return actor;
        if (actor.getRole()!=Role.ADMIN && actor.getRole()!=Role.DOCTOR) throw denied();
        User patient = users.findById(patientId).filter(u -> u.getMergedIntoId() == null)
                .filter(u -> actor.getRole()==Role.ADMIN || u.getRole()==Role.USER)
                .orElseThrow(CareRelationships::denied);
        em.lock(patient, LockModeType.PESSIMISTIC_WRITE);
        if (actor.getRole()!=Role.ADMIN && !follows(actor,patientId)) throw denied();
        return patient;
    }
    @Transactional(readOnly=true)
    public List<Contact> contacts(Authentication auth) {
        User actor = actor(auth);
        var result = switch(actor.getRole()) {
            case USER -> doctors(actor);
            case DOCTOR -> patients(actor);
            case ADMIN -> em.createQuery("select p from User p where p.mergedIntoId is null order by p.fullName,p.id",User.class).getResultList();
        };
        return result.stream().map(u -> new Contact(u.getId(),u.getFullName(),
                actor.getRole() != Role.USER || links.existsByPatientIdAndDoctorId(actor.getId(),u.getId()))).toList();
    }

    @Transactional
    public Contact addPatient(Authentication auth, String email) {
        User doctor = actor(auth);
        if (doctor.getRole() != Role.DOCTOR) throw denied();
        User patient = users.findByEmail(email.strip().toLowerCase(java.util.Locale.ROOT))
                .orElseThrow(CareRelationships::patientMissing);
        em.refresh(patient, LockModeType.PESSIMISTIC_WRITE);
        if (patient.getRole() != Role.USER) throw patientMissing();
        if (patient.getMergedIntoId() != null || !follows(doctor, patient.getId())) {
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "Le patient doit vous rattacher dans Mes médecins, ou être suivi via un traitement ou un rendez-vous.");
        }
        if (!links.existsByPatientIdAndDoctorId(patient.getId(),doctor.getId()) && links.existsByPatientId(patient.getId())) {
            throw new ApiException(HttpStatus.CONFLICT,"Le patient peut vous ajouter depuis « Mes médecins ».");
        }
        if (addLink(patient, doctor)) {
            notify(patient, "Rattachement à un médecin",
                    doctor.getFullName() + " vous a ajouté à ses patients. Vous pouvez gérer ce lien dans « Mes médecins ».");
        }
        return Contact.from(patient);
    }

    private static ApiException patientMissing() {
        return new ApiException(HttpStatus.NOT_FOUND, "Aucun compte patient trouvé pour cette adresse.");
    }

    @Transactional
    public void doctor(Authentication auth, String email) {
        User patient = actor(auth);
        if (patient.getRole()!=Role.USER) throw denied();
        em.lock(patient,LockModeType.PESSIMISTIC_WRITE);
        User doctor = users.findByEmail(email.strip().toLowerCase(java.util.Locale.ROOT))
                .filter(u -> u.getRole()==Role.DOCTOR).orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND,"Compte médecin introuvable."));
        addLink(patient, doctor);
    }

    private boolean addLink(User patient, User doctor) {
        if (links.existsByPatientIdAndDoctorId(patient.getId(), doctor.getId())) return false;
        var link = new PatientDoctor();
        link.setPatientId(patient.getId());
        link.setDoctor(doctor);
        links.save(link);
        return true;
    }

    @Transactional
    public void removeDoctor(Authentication auth, Long doctorId) {
        User patient = actor(auth);
        if (patient.getRole() != Role.USER) throw denied();
        em.lock(patient, LockModeType.PESSIMISTIC_WRITE);
        var candidates = links.findByPatientIdOrderByDoctorFullNameAscDoctorIdAsc(patient.getId());
        if (doctorId == null && candidates.size() > 1) throw chooseDoctor();
        candidates.stream().filter(link -> doctorId == null || link.getDoctor().getId().equals(doctorId))
                .findFirst().ifPresent(link -> {
                    documents.clearDoctorAccess(patient.getId(), link.getDoctor().getId());
                    links.delete(link);
                });
    }

    private List<User> doctors(User patient) {
        var result = new LinkedHashMap<Long, User>();
        links.findByPatientIdOrderByDoctorFullNameAscDoctorIdAsc(patient.getId()).stream()
                .map(PatientDoctor::getDoctor).filter(d -> d.getRole() == Role.DOCTOR)
                .forEach(d -> result.put(d.getId(), d));
        em.createQuery("select a.doctor from DoctorPatientAssignment a where a.patient=:patient and a.active=true", User.class)
                .setParameter("patient",patient).getResultList().forEach(d -> result.put(d.getId(),d));
        em.createQuery("select distinct a.doctor from Appointment a where a.user=:patient and a.doctor.role=:role "
                        + "and a.status<>:cancelled", User.class)
                .setParameter("patient",patient).setParameter("role",Role.DOCTOR)
                .setParameter("cancelled",com.medicare.appointment.AppointmentStatus.CANCELLED)
                .getResultList().forEach(d -> result.put(d.getId(),d));
        return result.values().stream().filter(d -> d.getMergedIntoId() == null)
                .sorted(Comparator.comparing(User::getFullName,String.CASE_INSENSITIVE_ORDER)).toList();
    }

    public User doctorFor(User patient, Long doctorId) {
        if (patient.getRole() != Role.USER) throw denied();
        em.lock(patient, LockModeType.PESSIMISTIC_WRITE);
        var candidates = doctors(patient);
        if (doctorId == null && candidates.size() != 1) throw chooseDoctor();
        return candidates.stream().filter(d -> doctorId == null || d.getId().equals(doctorId))
                .findFirst().orElseThrow(CareRelationships::denied);
    }

    private static ApiException chooseDoctor() {
        return new ApiException(HttpStatus.CONFLICT,"Choisissez un médecin parmi vos médecins rattachés.");
    }
    public void notify(User recipient,String title,String message) {
        notifications.save(Notification.builder().user(recipient).title(title).message(message)
                .type(NotificationType.GENERAL).createdAt(Instant.now()).build());
    }
    public static ApiException denied() { return new ApiException(HttpStatus.FORBIDDEN,"Action non autorisée."); }
}
