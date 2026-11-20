package com.medicare.health;

import com.medicare.appointment.AppointmentRepository;
import com.medicare.appointment.AppointmentStatus;
import com.medicare.common.ApiException;
import com.medicare.medication.DoctorPatientAssignmentRepository;
import com.medicare.notification.repository.PatientDoctorRepository;
import com.medicare.security.account.AccountAccess;
import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import com.medicare.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;

import java.util.*;

/**
 * Règles d'accès du module Suivi santé et nutrition.
 *
 * <ul>
 *   <li>Chaque utilisateur accède à ses propres données.</li>
 *   <li>Un médecin accède au suivi d'un patient qu'il suit, c'est-à-dire :
 *     <ul>
 *       <li>un patient à qui il a prescrit un traitement (module Médicaments, suivi actif), ou</li>
 *       <li>un patient ayant un rendez-vous non annulé avec lui (module Rendez-vous), ou</li>
 *       <li>un patient qui l'a rattaché dans « Mes médecins » (module Notifications et documents).</li>
 *     </ul>
 *   </li>
 *   <li>Aucun autre rôle (secrétaire, administrateur) ne voit les données de santé d'autrui.</li>
 * </ul>
 * C'est la règle unique de suivi médecin ↔ patient : les modules Médicaments, Documents et
 * Notifications l'utilisent aussi, pour que le médecin voie partout les mêmes patients.
 */
@Service
@RequiredArgsConstructor
public class HealthAccessService {
    public static final String SOURCE_MEDICATIONS = "MEDICATIONS";
    public static final String SOURCE_APPOINTMENTS = "APPOINTMENTS";
    public static final String SOURCE_CARE_LINK = "CARE_LINK";

    private final AccountAccess accounts;
    private final UserRepository users;
    private final DoctorPatientAssignmentRepository assignments;
    private final AppointmentRepository appointments;
    private final PatientDoctorRepository careLinks;

    /** Utilisateur connecté et patient dont on consulte le suivi. */
    public record Access(User viewer, User patient) {
        public boolean doctorView() {
            return !viewer.getId().equals(patient.getId());
        }
    }

    public User current(Authentication auth) {
        return accounts.current(auth);
    }

    /** Sans patientId : ses propres données. Avec patientId : réservé au médecin qui suit ce patient. */
    public Access resolve(Authentication auth, Long patientId) {
        User viewer = accounts.current(auth);
        if (patientId == null || patientId.equals(viewer.getId())) return new Access(viewer, viewer);
        if (viewer.getRole() != Role.DOCTOR) {
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "Seul le médecin qui suit ce patient peut consulter son suivi de santé.");
        }
        User patient = users.findById(patientId)
                .filter(u -> u.getRole() == Role.USER && u.getMergedIntoId() == null)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Patient introuvable"));
        if (!follows(viewer, patient)) throw new ApiException(HttpStatus.NOT_FOUND, "Patient introuvable");
        return new Access(viewer, patient);
    }

    public boolean follows(User doctor, User patient) {
        if (doctor.getRole() != Role.DOCTOR) return false;
        return assignments.existsByDoctorIdAndPatientIdAndActiveTrue(doctor.getId(), patient.getId())
                || appointments.existsByDoctorIdAndUserIdAndStatusNot(
                        doctor.getId(), patient.getId(), AppointmentStatus.CANCELLED)
                || careLinks.existsByPatientIdAndDoctorId(patient.getId(), doctor.getId());
    }

    /** Patients suivis par le médecin, avec l'origine du lien (Médicaments, Rendez-vous). */
    public Map<User, Set<String>> followedPatients(User doctor) {
        if (doctor.getRole() != Role.DOCTOR) {
            throw new ApiException(HttpStatus.FORBIDDEN, "Réservé aux médecins.");
        }
        Map<Long, User> byId = new LinkedHashMap<>();
        Map<Long, Set<String>> sources = new HashMap<>();
        for (var assignment : assignments.findActiveByDoctorId(doctor.getId())) {
            User p = assignment.getPatient();
            byId.putIfAbsent(p.getId(), p);
            sources.computeIfAbsent(p.getId(), k -> new TreeSet<>()).add(SOURCE_MEDICATIONS);
        }
        for (User p : appointments.findPatientsOfDoctor(doctor.getId())) {
            if (p.getRole() != Role.USER || p.getMergedIntoId() != null) continue;
            byId.putIfAbsent(p.getId(), p);
            sources.computeIfAbsent(p.getId(), k -> new TreeSet<>()).add(SOURCE_APPOINTMENTS);
        }
        for (var link : careLinks.findByDoctorId(doctor.getId())) {
            users.findById(link.getPatientId())
                    .filter(p -> p.getRole() == Role.USER && p.getMergedIntoId() == null)
                    .ifPresent(p -> {
                        byId.putIfAbsent(p.getId(), p);
                        sources.computeIfAbsent(p.getId(), k -> new TreeSet<>()).add(SOURCE_CARE_LINK);
                    });
        }
        Map<User, Set<String>> result = new LinkedHashMap<>();
        byId.values().stream()
                .sorted(Comparator.comparing(User::getFullName, String.CASE_INSENSITIVE_ORDER))
                .forEach(p -> result.put(p, sources.get(p.getId())));
        return result;
    }
}
