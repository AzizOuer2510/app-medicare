package com.medicare.notification;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.medicare.notification.entity.NotificationType;
import com.medicare.notification.entity.PatientDoctor;
import com.medicare.medication.DoctorPatientAssignment;
import com.medicare.medication.DoctorPatientAssignmentRepository;
import com.medicare.notification.repository.PatientDoctorRepository;
import com.medicare.notification.service.NotificationService;
import com.medicare.security.JwtService;
import com.medicare.user.entity.*;
import com.medicare.user.repository.UserRepository;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:m5-roles;DB_CLOSE_DELAY=-1",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.jpa.hibernate.ddl-auto=create-drop", "app.notifications.reminders-enabled=false",
        "app.analysis.worker-enabled=false", "app.notifications.module-events-enabled=true",
        "app.security.rate-limit-enabled=false", "app.security.compromised-password-check=false",
        "app.jwt.secret=m5-integration-test-secret-key-of-at-least-32-characters"
})
@AutoConfigureMockMvc
class M5IntegrationRolesApiTest {
    @TempDir static Path storage;
    @DynamicPropertySource static void storage(DynamicPropertyRegistry registry) {
        registry.add("app.documents.storage-path", () -> storage.toString());
    }
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired UserRepository users;
    @Autowired PasswordEncoder passwords;
    @Autowired JwtService jwt;
    @Autowired PatientDoctorRepository links;
    @Autowired DoctorPatientAssignmentRepository assignments;
    @Autowired NotificationService notifications;
    @Autowired com.medicare.medication.MedicationRepository medications;
    @Autowired com.medicare.notification.repository.ReminderRepository reminders;
    @Autowired com.medicare.appointment.AppointmentRepository appointments;
    @Autowired com.medicare.notification.service.ModuleNotificationTargets targets;
    User admin, patient, other, doctor;
    static final String PASSWORD = "M5-Test-Password!2026";
    static final byte[] PDF = "%PDF-1.4\nM5 synthetic test\n%%EOF".getBytes(StandardCharsets.US_ASCII);

    @BeforeEach void accounts() {
        admin = account(Role.ADMIN); patient = account(Role.USER); other = account(Role.USER); doctor = account(Role.DOCTOR);
        assignments.saveAndFlush(DoctorPatientAssignment.builder().patient(patient).doctor(doctor).active(true).build());
    }

    @Test void existingVerifiedAccountStillLogsInAndLoadsProfile() throws Exception {
        String email = patient.getEmail();
        JsonNode login = call(post("/api/auth/login"), null, Map.of("email", email, "password", PASSWORD), 200);
        assertThat(login.path("token").asText()).isNotBlank();
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + login.path("token").asText()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.email").value(email));
    }

    @Test void adminManagesNotificationsForEveryExistingRoleWithoutChangingPersonalInboxScope() throws Exception {
        for (User recipient : new User[]{patient, doctor, admin}) {
            JsonNode created = call(post("/api/notifications/admin"), admin,
                    Map.of("title", "Information", "message", "Message personnel", "type", "GENERAL", "userId", recipient.getId()), 201);
            long id = created.path("id").asLong();
            JsonNode list = call(get("/api/notifications/admin").param("userId", recipient.getId().toString()), admin, null, 200);
            assertThat(list).hasSize(1);
            assertThat(list.get(0).path("userId").asLong()).isEqualTo(recipient.getId());
            assertThat(call(get("/api/notifications/unread-count"), recipient, null, 200).path("count").asInt()).isEqualTo(1);
            call(put("/api/notifications/admin/" + id), admin,
                    Map.of("title", "Mis à jour", "message", "Lu", "type", "GENERAL", "read", true), 200);
            assertThat(call(get("/api/notifications/unread-count"), recipient, null, 200).path("count").asInt()).isZero();
            call(delete("/api/notifications/admin/" + id), admin, null, 204);
            assertThat(call(get("/api/notifications/admin").param("userId", recipient.getId().toString()), admin, null, 200)).isEmpty();
        }
        assertThat(call(get("/api/notifications/admin/recipients"), admin, null, 200).toString()).doesNotContain("password");
        call(get("/api/notifications/admin").param("userId", "-1"), admin, null, 400);
    }

    @Test void patientAndDoctorCannotUseAdministrationOrAnotherInbox() throws Exception {
        long foreign = notifications.notify(other.getId(), NotificationType.GENERAL, "Message privé").id();
        for (User actor : new User[]{patient, doctor}) {
            call(get("/api/notifications/admin"), actor, null, 403);
            call(get("/api/notifications/admin/recipients"), actor, null, 403);
            call(post("/api/notifications/admin"), actor, Map.of("title", "X", "message", "X", "type", "GENERAL"), 403);
            call(put("/api/notifications/admin/" + foreign), actor, Map.of("title", "X", "message", "X", "type", "GENERAL"), 403);
            call(delete("/api/notifications/admin/" + foreign), actor, null, 403);
            call(patch("/api/notifications/" + foreign + "/read"), actor, null, 404);
            assertThat(call(get("/api/notifications"), actor, null, 200)).isEmpty();
        }
        call(post("/api/reminders"), patient, reminder(other.getId()), 403);
    }

    @Test void adminCanCreateDocumentsAndRemindersForDoctorAndManageTheirAlert() throws Exception {
        JsonNode reminder = call(post("/api/reminders"), admin, reminder(doctor.getId()), 201);
        long id = reminder.path("id").asLong();
        JsonNode postponed = call(post("/api/reminders/" + id + "/snooze"), admin, Map.of("minutes", 15), 200);
        assertThat(postponed.path("recipientId").asLong()).isEqualTo(doctor.getId());
        call(patch("/api/reminders/" + id + "/alert"), admin, Map.of("at", Instant.now().plusSeconds(7200).toString()), 200);
        call(delete("/api/reminders/" + id), admin, null, 204);
        long document = upload(admin, doctor.getId(), 201);
        call(get("/api/documents/" + document + "/content"), doctor, null, 200);
        call(put("/api/documents/" + document), admin,
                Map.of("title", "Document corrigé", "category", "OTHER"), 200);
        call(delete("/api/documents/" + document), admin, null, 204);
        call(get("/api/documents/" + document), doctor, null, 404);
    }

    @Test void doctorReadsAllDocumentsOfFollowedPatientsButCannotChangeThem() throws Exception {
        // Synchronisation médecin ↔ patient : le médecin qui suit le patient voit tous ses documents,
        // en lecture seule ; il ne peut ni les modifier ni les supprimer.
        long patientDocument = upload(patient, null, 201);
        call(get("/api/documents/" + patientDocument), doctor, null, 200);
        call(put("/api/documents/" + patientDocument), doctor,
                Map.of("title", "Modifié par le médecin", "category", "OTHER"), 404);
        call(delete("/api/documents/" + patientDocument), doctor, null, 404);
        call(get("/api/documents/" + patientDocument), other, null, 404);
        long sharedDocument = upload(doctor, patient.getId(), 201);
        call(get("/api/documents/" + sharedDocument + "/content"), doctor, null, 200);
        call(get("/api/documents/" + sharedDocument + "/content"), patient, null, 200);
        call(get("/api/documents/" + sharedDocument), other, null, 404);
        upload(doctor, other.getId(), 403);
        upload(patient, other.getId(), 403);
        call(post("/api/reminders"), doctor, reminder(patient.getId()), 201);
        call(post("/api/reminders"), doctor, reminder(other.getId()), 403);
    }

    @Test void successfulM2M3M4AndDocumentMutationsGenerateNotificationsAndReadsAndErrorsDoNot() throws Exception {
        long appointment = call(post("/api/appointments"), patient,
                Map.of("dateTime", "2030-12-15T10:00:00", "doctorId", doctor.getId(), "doctorName", doctor.getFullName()), 201).path("id").asLong();
        long prescription = call(post("/api/prescriptions"), doctor,
                Map.of("patientId", patient.getId(), "prescriptionDate", "2030-12-14"), 200).path("id").asLong();
        Map<String,Object> medicationRequest = Map.of("name", "Traitement fictif", "prescriptionId", prescription,
                "reminderTimes", java.util.List.of("10:00"), "frequencyPerDay", 1);
        long medication = call(post("/api/medications"), doctor, medicationRequest, 200).path("id").asLong();
        assertThat(targets.medication(medication)).isEqualTo(patient.getId());
        long measure = call(post("/api/health-records"), patient,
                Map.of("recordedAt", "2030-12-14T10:00:00", "weight", 70), 200).path("id").asLong();
        upload(patient, null, 201);
        // 5 notifications de module + « Nouveau traitement » (médicament ajouté par le médecin au planning du patient).
        assertThat(call(get("/api/notifications"), patient, null, 200)).hasSize(6);
        assertThat(call(get("/api/notifications"), doctor, null, 200)).isEmpty();
        for (String path : new String[]{"/api/appointments", "/api/medications", "/api/health-records"})
            assertThat(call(get(path), patient, null, 200)).hasSize(1);
        call(post("/api/appointments"), patient, Map.of("doctorName", "Sans date"), 400);
        assertThat(call(get("/api/notifications"), patient, null, 200)).hasSize(6);
        call(post("/api/medications"), patient, Map.of("name", "Action interdite"), 403);
        call(put("/api/appointments/" + appointment), patient,
                Map.of("dateTime", "2030-12-16T10:00:00", "doctorName", "Médecin test"), 200);
        call(put("/api/medications/" + medication), doctor, medicationRequest, 200);
        call(delete("/api/health-records/" + measure), patient, null, 200);
        assertThat(call(get("/api/notifications"), patient, null, 200)).hasSize(9);
        assertThat(call(get("/api/notifications"), other, null, 200)).isEmpty();
    }

    @Test void m5RecognizesBothExistingClinicalRelationshipsAndRequiresConsentForANewDoctor() throws Exception {
        appointments.saveAndFlush(com.medicare.appointment.Appointment.builder().user(other).doctor(doctor)
                .doctorName(doctor.getFullName()).dateTime(java.time.LocalDateTime.now().plusDays(5)).build());
        JsonNode contacts = call(get("/api/notifications/care/contacts"), doctor, null, 200);
        assertThat(contacts).hasSize(2);
        assertThat(call(get("/api/notifications/care/contacts"), patient, null, 200).get(0).path("removable").asBoolean()).isFalse();
        User newDoctor = account(Role.DOCTOR);
        call(put("/api/notifications/care/patients"), newDoctor, Map.of("email", patient.getEmail()), 403);
        call(put("/api/notifications/care/doctor"), patient, Map.of("email", newDoctor.getEmail()), 200);
        assertThat(call(get("/api/notifications/care/contacts"), newDoctor, null, 200)).hasSize(1);
        upload(newDoctor, patient.getId(), 201);
        call(delete("/api/notifications/care/doctor").param("doctorId", newDoctor.getId().toString()), patient, null, 200);
        assertThat(call(get("/api/documents"), newDoctor, null, 200)).isEmpty();
    }

    @Test void schedulerDeliversOnceAndCancelsWhenTheExistingM3TreatmentIsStopped() throws Exception {
        var medication = medications.saveAndFlush(com.medicare.medication.Medication.builder()
                .user(patient).name("Traitement fictif").build());
        Map<String,Object> request = Map.of("title", "Prise", "message", "Rappel personnel", "type", "MEDICATION",
                "referenceId", medication.getId(), "scheduledFor", Instant.now().plusSeconds(3600).toString());
        long id = call(post("/api/reminders"), patient, request, 201).path("id").asLong();
        var reminder = reminders.findById(id).orElseThrow();
        reminder.setScheduledFor(Instant.now().minusSeconds(5)); reminders.saveAndFlush(reminder);
        notifications.deliverDueReminders(); notifications.deliverDueReminders();
        assertThat(call(get("/api/notifications"), patient, null, 200)).hasSize(1);
        assertThat(reminders.findById(id).orElseThrow().getStatus()).isEqualTo(com.medicare.notification.entity.ReminderStatus.SENT);
        long cancelled = call(post("/api/reminders"), patient, request, 201).path("id").asLong();
        medication.setStatus(com.medicare.medication.MedicationStatus.DISCONTINUED); medications.saveAndFlush(medication);
        reminder = reminders.findById(cancelled).orElseThrow();
        reminder.setScheduledFor(Instant.now().minusSeconds(5)); reminders.saveAndFlush(reminder);
        notifications.deliverDueReminders();
        assertThat(reminders.findById(cancelled).orElseThrow().getStatus()).isEqualTo(com.medicare.notification.entity.ReminderStatus.CANCELLED);
        assertThat(call(get("/api/notifications"), patient, null, 200)).hasSize(1);
    }

    @Test void anUnverifiedAdministratorCannotUseM5Administration() throws Exception {
        admin.setEmailVerified(false); users.saveAndFlush(admin);
        call(get("/api/notifications/admin"), admin, null, 403);
        call(get("/api/documents"), admin, null, 403);
    }

    private User account(Role role) {
        return users.saveAndFlush(User.builder().fullName("M5 " + role).email(UUID.randomUUID() + "@test.invalid")
                .password(passwords.encode(PASSWORD)).role(role).emailVerified(true).mfaEnabled(false).build());
    }
    private Map<String, Object> reminder(Long recipient) {
        return Map.of("title", "Suivi", "message", "Rappel fictif", "type", "GENERAL", "patientId", recipient,
                "scheduledFor", Instant.now().plusSeconds(3600).toString());
    }
    private long upload(User actor, Long recipient, int expected) throws Exception {
        var request = multipart("/api/documents").file(new MockMultipartFile("file", "test.pdf", "application/pdf", PDF))
                .param("title", "Document de test").param("category", "OTHER");
        if (recipient != null) request.param("patientId", recipient.toString());
        return call(request, actor, null, expected).path("id").asLong();
    }
    private JsonNode call(MockHttpServletRequestBuilder request, User actor, Object body, int expected) throws Exception {
        if (actor != null) request.header("Authorization", "Bearer " + jwt.generateToken(actor));
        if (body != null) request.contentType(MediaType.APPLICATION_JSON).content(mapper.writeValueAsString(body));
        String content = mvc.perform(request).andExpect(status().is(expected)).andReturn().getResponse().getContentAsString();
        return content.isBlank() || (!content.startsWith("{") && !content.startsWith("["))
                ? mapper.nullNode() : mapper.readTree(content);
    }
}
