package com.medicare.auth;

import com.fasterxml.jackson.databind.*;
import com.medicare.auth.service.*;
import com.medicare.common.ApiException;
import com.medicare.security.JwtService;
import com.medicare.security.account.*;
import com.medicare.roles.*;
import com.medicare.identity.*;
import com.medicare.user.entity.*;
import com.medicare.user.repository.UserRepository;
import com.medicare.appointment.*;
import com.medicare.medication.*;
import com.medicare.health.HealthRecordRepository;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.*;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.*;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties = {
        "app.security.rate-limit-enabled=false",
        "app.notifications.module-events-enabled=false",
        "app.jwt.secret=authentication-test-secret-key-with-at-least-32-characters",
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "app.bootstrap-admin.email=",
        "spring.datasource.url=jdbc:h2:mem:medicare;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.jpa.database-platform=org.hibernate.dialect.H2Dialect"
})
@AutoConfigureMockMvc @ActiveProfiles("test")
class AuthenticationIntegrationTest {
    private static final String PASSWORD = "InitialPassword123!";
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;
    @Autowired UserRepository users;
    @Autowired PasswordEncoder encoder;
    @Autowired JwtService jwt;
    @Autowired EmailChallengeRepository challenges;
    @Autowired RecoveryCodeRepository recovery;
    @Autowired RecoveryCodeService recoveryService;
    @Autowired PasswordHistoryRepository history;
    @Autowired RoleChangeRepository roles;
    @Autowired RoleChangeService roleChangeService;
    @Autowired AccountMergeRepository merges;
    @Autowired SecurityAuditRepository audit;
    @Autowired AppointmentRepository appointments;
    @Autowired MedicationRepository medications;
    @Autowired MedicationReminderRepository medicationReminders;
    @Autowired MedicationStockEntryRepository medicationStockEntries;
    @Autowired PrescriptionRepository prescriptions;
    @Autowired DoctorPatientAssignmentRepository assignments;
    @Autowired HealthRecordRepository health;
    @Autowired PlatformTransactionManager transactionManager;
    @MockitoBean PasswordResetMailService mail;
    @MockitoBean CompromisedPasswordChecker checker;
    @MockitoBean PrescriptionOcrService prescriptionOcrService;
    record Account(User user, String token, List<String> codes) {}

    @BeforeEach void clean() {
        appointments.deleteAll(); medicationStockEntries.deleteAll(); medicationReminders.deleteAll();
        medications.deleteAll(); prescriptions.deleteAll(); assignments.deleteAll(); health.deleteAll();
        challenges.deleteAll(); recovery.deleteAll(); history.deleteAll(); roles.deleteAll(); merges.deleteAll(); audit.deleteAll();
        users.deleteAll(); reset(mail, checker);
    }
    private Account account(String email, Role role, boolean mfa) {
        User u = users.save(User.builder().fullName("Alice Martin").email(email).password(encoder.encode(PASSWORD))
                .role(role).emailVerified(true).mfaEnabled(mfa).build());
        List<String> codes = mfa ? new TransactionTemplate(transactionManager).execute(status -> recoveryService.rotate(u.getId())) : List.of();
        return new Account(u, jwt.generateToken(u), codes);
    }
    private ResultActions send(String path, String token, Map<String, ?> body) throws Exception {
        var request = post(path).contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body));
        if (token != null) request.header("Authorization", "Bearer " + token);
        return mvc.perform(request);
    }
    private JsonNode postJson(String path, String token, Map<String, ?> body, int status) throws Exception {
        return json.readTree(send(path, token, body).andExpect(status().is(status)).andReturn().getResponse().getContentAsString());
    }
    private String code(String email, String purpose) {
        var captor = ArgumentCaptor.forClass(String.class);
        verify(mail, atLeastOnce()).sendVerificationCode(eq(email), captor.capture(), eq(purpose));
        return captor.getValue();
    }
    private String wrong(String value) { return value.equals("000000") ? "111111" : "000000"; }
    private JsonNode login(String identifier, String password) throws Exception {
        return postJson("/api/auth/login", null, Map.of("identifier", identifier, "password", password), 200);
    }
    private JsonNode verifyChallenge(JsonNode c, String email, String purpose) throws Exception {
        return postJson("/api/auth/verify", null, Map.of("challengeId", c.get("challengeId").asText(), "code", code(email, purpose)), 200);
    }
    private void age(String email, EmailChallenge.Purpose purpose) {
        var c = challenges.findFirstByUserIdAndPurposeOrderByCreatedAtDesc(users.findByEmail(email).orElseThrow().getId(), purpose).orElseThrow();
        c.setCreatedAt(Instant.now().minusSeconds(61)); challenges.save(c);
    }
    private String resetCode(String email) throws Exception {
        postJson("/api/auth/forgot-password", null, Map.of("email", email), 200);
        var captor = ArgumentCaptor.forClass(String.class); verify(mail, atLeastOnce()).sendCode(eq(email), captor.capture()); return captor.getValue();
    }
    private Map<String, Object> registration(String email) { return new HashMap<>(Map.of("fullName", "Alice Martin", "email", email, "password", PASSWORD)); }

    @Test void signupRequiresEmailProofCreatesRecoveryCodesAndDoesNotGrantRequestedPrivileges() throws Exception {
        var body = registration("alice@example.fr"); body.put("requestedRole", "ADMIN"); body.put("username", "alice.martin");
        var challenge = postJson("/api/auth/register", null, body, 201);
        assertThat(challenge.get("token").isNull()).isTrue();
        User u = users.findByEmail("alice@example.fr").orElseThrow();
        assertThat(u.getRole()).isEqualTo(Role.USER); assertThat(u.isEmailVerified()).isFalse(); assertThat(u.isMfaEnabled()).isTrue();
        var session = verifyChallenge(challenge, "alice@example.fr", "SIGNUP");
        assertThat(session.get("token").asText()).isNotBlank(); assertThat(session.get("recoveryCodes")).hasSize(10);
        assertThat(roles.findAll()).singleElement().satisfies(r -> assertThat(r.getStatus()).isEqualTo(RoleChangeRequest.Status.PENDING));
        assertThat(recovery.findAll()).allSatisfy(r -> assertThat(r.getCodeHash()).hasSize(64));
        send("/api/auth/verify", null, Map.of("challengeId", challenge.get("challengeId").asText(), "code", code("alice@example.fr", "SIGNUP"))).andExpect(status().isBadRequest());
    }
    @Test void doctorRoleIsGrantedAtSignupAfterEmailVerificationWithoutAdminRequest() throws Exception {
        var body = registration("doctor@example.fr"); body.put("requestedRole", "DOCTOR");
        var challenge = postJson("/api/auth/register", null, body, 201);
        User doctor = users.findByEmail("doctor@example.fr").orElseThrow();
        assertThat(doctor.getRole()).isEqualTo(Role.DOCTOR);
        assertThat(doctor.isEmailVerified()).isFalse();
        assertThat(roles.findAll()).isEmpty();

        JsonNode session = verifyChallenge(challenge, "doctor@example.fr", "SIGNUP");
        assertThat(session.get("user").get("role").asText()).isEqualTo("DOCTOR");
    }
    @Test void passwordStepDoesNotIssueJwtUntilOtpAndMfaCodesAreSingleUse() throws Exception {
        Account a = account("alice@example.fr", Role.USER, true);
        var c = login("ALICE@example.fr", PASSWORD); assertThat(c.get("token").isNull()).isTrue();
        var session = verifyChallenge(c, "alice@example.fr", "MFA_LOGIN");
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer " + session.get("token").asText())).andExpect(status().isOk());
        send("/api/auth/verify", null, Map.of("challengeId", c.get("challengeId").asText(), "code", code("alice@example.fr", "MFA_LOGIN"))).andExpect(status().isBadRequest());
        assertThat(a.codes()).hasSize(10);
    }
    @Test void fiveWrongGuessesPersistAcrossRequestsAndLockTheChallenge() throws Exception {
        account("alice@example.fr", Role.USER, true); var c = login("alice@example.fr", PASSWORD);
        String id = c.get("challengeId").asText(), actual = code("alice@example.fr", "MFA_LOGIN");
        for (int attempt = 1; attempt <= 5; attempt++) {
            send("/api/auth/verify", null, Map.of("challengeId", id, "code", wrong(actual))).andExpect(status().isBadRequest());
            assertThat(challenges.findById(id).orElseThrow().getAttempts()).isEqualTo(attempt);
        }
        send("/api/auth/verify", null, Map.of("challengeId", id, "code", actual)).andExpect(status().isBadRequest());
    }
    @Test void expiredAndWrongPurposeChallengesCannotAuthenticate() throws Exception {
        Account a = account("alice@example.fr", Role.USER, true); var c = login("alice@example.fr", PASSWORD);
        var stored = challenges.findById(c.get("challengeId").asText()).orElseThrow(); stored.setExpiresAt(Instant.now().minusSeconds(1)); challenges.save(stored);
        send("/api/auth/verify", null, Map.of("challengeId", stored.getId(), "code", code("alice@example.fr", "MFA_LOGIN"))).andExpect(status().isBadRequest());
        var security = postJson("/api/security/challenge", a.token(), Map.of("action", "RECOVERY_ROTATE", "currentPassword", PASSWORD), 200);
        send("/api/auth/verify", null, Map.of("challengeId", security.get("challengeId").asText(), "code", code("alice@example.fr", "RECOVERY_ROTATE"))).andExpect(status().isBadRequest());
    }
    @Test void recoveryCodeIsConsumedAtomicallyAndCannotBeReusedOnNewChallenge() throws Exception {
        Account a = account("alice@example.fr", Role.USER, true); var c = login("alice@example.fr", PASSWORD);
        postJson("/api/auth/mfa/recover", null, Map.of("challengeId", c.get("challengeId").asText(), "code", a.codes().getFirst()), 200);
        age("alice@example.fr", EmailChallenge.Purpose.MFA_LOGIN); var next = login("alice@example.fr", PASSWORD);
        send("/api/auth/mfa/recover", null, Map.of("challengeId", next.get("challengeId").asText(), "code", a.codes().getFirst())).andExpect(status().isBadRequest());
        assertThat(recovery.countByUserIdAndUsedAtIsNull(a.user().getId())).isEqualTo(9);
    }
    @Test void passwordlessCannotBypassMfaAndConsumesARecoveryCode() throws Exception {
        Account a = account("alice@example.fr", Role.USER, true);
        var c = postJson("/api/auth/passwordless/request", null, Map.of("email", "alice@example.fr"), 200);
        var proof = new HashMap<String, Object>(Map.of("challengeId", c.get("challengeId").asText(), "code", code("alice@example.fr", "PASSWORDLESS")));
        send("/api/auth/verify", null, proof).andExpect(status().isBadRequest()).andExpect(jsonPath("message").value("PASSWORDLESS_RECOVERY_REQUIRED"));
        proof.put("recoveryCode", a.codes().getFirst()); postJson("/api/auth/verify", null, proof, 200);
        assertThat(recovery.countByUserIdAndUsedAtIsNull(a.user().getId())).isEqualTo(9);
    }
    @Test void passwordlessWorksWithoutPasswordForAccountsWithoutMfaAndMasksUnknownEmails() throws Exception {
        account("alice@example.fr", Role.USER, false);
        var known = postJson("/api/auth/passwordless/request", null, Map.of("email", "alice@example.fr"), 200);
        var unknown = postJson("/api/auth/passwordless/request", null, Map.of("email", "missing@example.fr"), 200);
        assertThat(known.fieldNames()).toIterable().containsExactlyElementsOf(() -> unknown.fieldNames());
        assertThat(unknown.get("token").isNull()).isTrue();
        verifyChallenge(known, "alice@example.fr", "PASSWORDLESS");
        send("/api/auth/verify", null, Map.of("challengeId", unknown.get("challengeId").asText(), "code", "123456")).andExpect(status().isBadRequest());
    }
    @Test void resendingRespectsCooldownAndInvalidatesEarlierChallenge() throws Exception {
        account("alice@example.fr", Role.USER, true); var c = login("alice@example.fr", PASSWORD);
        String oldId = c.get("challengeId").asText();
        send("/api/auth/challenges/"+oldId+"/resend", null, Map.of()).andExpect(status().isTooManyRequests());
        age("alice@example.fr", EmailChallenge.Purpose.MFA_LOGIN);
        var next = postJson("/api/auth/challenges/"+oldId+"/resend", null, Map.of(), 200);
        send("/api/auth/verify", null, Map.of("challengeId", oldId, "code", code("alice@example.fr", "MFA_LOGIN"))).andExpect(status().isBadRequest());
        verifyChallenge(next, "alice@example.fr", "MFA_LOGIN");
    }
    @Test void recoveryRotationRequiresPasswordAndEmailAndRevokesOldCodesAndSessions() throws Exception {
        Account a = account("alice@example.fr", Role.USER, true);
        send("/api/security/challenge", a.token(), Map.of("action", "RECOVERY_ROTATE", "currentPassword", "wrong")).andExpect(status().isBadRequest());
        var c = postJson("/api/security/challenge", a.token(), Map.of("action", "RECOVERY_ROTATE", "currentPassword", PASSWORD), 200);
        var session = postJson("/api/security/confirm", a.token(), Map.of("challengeId", c.get("challengeId").asText(), "code", code("alice@example.fr", "RECOVERY_ROTATE")), 200);
        assertThat(session.get("recoveryCodes")).hasSize(10);
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer "+a.token())).andExpect(status().isUnauthorized());
        var login = login("alice@example.fr", PASSWORD);
        send("/api/auth/mfa/recover", null, Map.of("challengeId", login.get("challengeId").asText(), "code", a.codes().getFirst())).andExpect(status().isBadRequest());
    }
    @Test void emailAndIdentifierDuplicatesAreRejectedIgnoringCase() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false); a.user().setUsername("alice.unique"); users.save(a.user());
        send("/api/auth/register", null, registration("ALICE@example.fr")).andExpect(status().isConflict());
        var body = registration("another@example.fr"); body.put("username", "ALICE.UNIQUE");
        send("/api/auth/register", null, body).andExpect(status().isConflict());
        assertThat(login("ALICE.UNIQUE", PASSWORD).get("token").asText()).isNotBlank();
    }
    @Test void doctorRoleRequestIsGrantedImmediatelyAndRevokesTheOldSession() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false), admin = account("admin@example.fr", Role.ADMIN, false);
        var request = postJson("/api/security/role-requests", a.token(), Map.of("requestedRole", "DOCTOR", "reason", "Professional role requested"), 200);
        assertThat(request.get("status").asText()).isEqualTo("APPROVED");
        User doctor = users.findById(a.user().getId()).orElseThrow();
        assertThat(doctor.getRole()).isEqualTo(Role.DOCTOR);
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer "+a.token())).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/security/admin/role-requests")
                        .header("Authorization", "Bearer "+jwt.generateToken(doctor)))
                .andExpect(status().isForbidden());
        mvc.perform(get("/api/security/admin/role-requests").header("Authorization", "Bearer "+admin.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
        assertThat(audit.findAll()).anySatisfy(e -> {
            assertThat(e.getAction()).isEqualTo("ROLE_AUTO_GRANTED");
            assertThat(e.getSubjectId()).isEqualTo(a.user().getId());
        });
    }
    @Test void administratorRoleStillRequiresIndependentApproval() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false), admin = account("admin@example.fr", Role.ADMIN, false);
        var request = postJson("/api/security/role-requests", a.token(), Map.of("requestedRole", "ADMIN", "reason", "Administrator role requested"), 200);
        assertThat(request.get("status").asText()).isEqualTo("PENDING");
        String path = "/api/security/admin/role-requests/"+request.get("id").asLong()+"/decision";
        postJson(path, admin.token(), Map.of("approve", true, "note", "Administrator role reviewed"), 200);
        assertThat(users.findById(a.user().getId()).orElseThrow().getRole()).isEqualTo(Role.ADMIN);
        assertThat(audit.findAll()).anySatisfy(e -> {
            assertThat(e.getAction()).isEqualTo("ROLE_APPROVED");
            assertThat(e.getActorId()).isEqualTo(admin.user().getId());
        });
    }
    @Test void existingPendingDoctorRequestsAreAutomaticallyResolved() {
        Account patient = account("legacy-doctor@example.fr", Role.USER, false);
        RoleChangeRequest request = new RoleChangeRequest();
        request.setUserId(patient.user().getId());
        request.setPreviousRole(Role.USER);
        request.setRequestedRole(Role.DOCTOR);
        request.setStatus(RoleChangeRequest.Status.PENDING);
        request.setReason("Legacy doctor request");
        request.setRequestedAt(Instant.now());
        roles.save(request);

        assertThat(roleChangeService.autoGrantPendingDoctorRequests()).isEqualTo(1);
        assertThat(users.findById(patient.user().getId()).orElseThrow().getRole()).isEqualTo(Role.DOCTOR);
        assertThat(roles.findById(request.getId()).orElseThrow().getStatus())
                .isEqualTo(RoleChangeRequest.Status.APPROVED);
    }
    @Test void rolesCannotBeSelfApprovedOrChangedThroughLegacyEndpoint() throws Exception {
        Account admin = account("admin@example.fr", Role.ADMIN, false);
        var r = postJson("/api/security/role-requests", admin.token(), Map.of("requestedRole", "USER", "reason", "A different role is requested"), 200);
        send("/api/security/admin/role-requests/"+r.get("id").asLong()+"/decision", admin.token(), Map.of("approve", true, "note", "Cannot approve my own request")).andExpect(status().isForbidden());
        mvc.perform(patch("/api/users/"+admin.user().getId()+"/role").header("Authorization", "Bearer "+admin.token()).contentType(MediaType.APPLICATION_JSON).content("{\"role\":\"USER\"}"))
                .andExpect(status().isConflict());
    }
    @Test void rejectingRoleRequestPreservesRoleAndRecordsDecision() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false), admin = account("admin@example.fr", Role.ADMIN, false);
        var r = postJson("/api/security/role-requests", a.token(), Map.of("requestedRole", "ADMIN", "reason", "Administrator role requested"), 200);
        postJson("/api/security/admin/role-requests/"+r.get("id").asLong()+"/decision", admin.token(), Map.of("approve", false, "note", "Professional evidence is insufficient"), 200);
        assertThat(users.findById(a.user().getId()).orElseThrow().getRole()).isEqualTo(Role.USER);
        assertThat(roles.findAll()).singleElement().satisfies(v -> { assertThat(v.getStatus()).isEqualTo(RoleChangeRequest.Status.REJECTED); assertThat(v.getDecisionNote()).contains("insufficient"); });
    }
    @Test void passwordHistoryRejectsReuseAndChangeReturnsFreshSession() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false);
        var response = mvc.perform(put("/api/users/me/password").header("Authorization", "Bearer "+a.token()).contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("currentPassword", PASSWORD, "newPassword", "DifferentPassword456!"))))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String token = json.readTree(response).get("token").asText();
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer "+a.token())).andExpect(status().isUnauthorized());
        mvc.perform(put("/api/users/me/password").header("Authorization", "Bearer "+token).contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("currentPassword", "DifferentPassword456!", "newPassword", PASSWORD))))
                .andExpect(status().isBadRequest()).andExpect(jsonPath("message").value("PASSWORD_REUSED"));
        assertThat(history.findAll()).singleElement().satisfies(h -> assertThat(h.getPasswordHash()).startsWith("$2"));
    }
    @Test void compromisedPasswordAndUnavailableScreeningFailBeforeAccountCreation() throws Exception {
        doThrow(new ApiException(HttpStatus.BAD_REQUEST, "PASSWORD_COMPROMISED")).when(checker).rejectCompromised(PASSWORD);
        send("/api/auth/register", null, registration("alice@example.fr")).andExpect(status().isBadRequest()).andExpect(jsonPath("message").value("PASSWORD_COMPROMISED"));
        doThrow(new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "PASSWORD_SCREENING_UNAVAILABLE")).when(checker).rejectCompromised(PASSWORD);
        send("/api/auth/register", null, registration("alice@example.fr")).andExpect(status().isServiceUnavailable());
        assertThat(users.count()).isZero();
    }
    @Test void confirmedIncidentBlocksPasswordAndPasswordlessAndResetClearsFlag() throws Exception {
        Account a = account("alice@example.fr", Role.USER, true), admin = account("admin@example.fr", Role.ADMIN, false);
        postJson("/api/security/admin/users/"+a.user().getId()+"/incident", admin.token(), Map.of("reason", "Confirmed credential theft incident"), 200);
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer "+a.token())).andExpect(status().isUnauthorized());
        send("/api/auth/login", null, Map.of("identifier", "alice@example.fr", "password", PASSWORD)).andExpect(status().isLocked());
        var c = postJson("/api/auth/passwordless/request", null, Map.of("email", "alice@example.fr"), 200);
        send("/api/auth/verify", null, Map.of("challengeId", c.get("challengeId").asText(), "code", code("alice@example.fr", "PASSWORDLESS"), "recoveryCode", a.codes().getFirst())).andExpect(status().isLocked());
        assertThat(recovery.countByUserIdAndUsedAtIsNull(a.user().getId())).isZero();
        String code = resetCode("alice@example.fr");
        postJson("/api/auth/reset-password", null, Map.of("email", "alice@example.fr", "code", code, "newPassword", "AfterIncidentPassword123!"), 200);
        assertThat(users.findById(a.user().getId()).orElseThrow().isPasswordResetRequired()).isFalse();
        verifyChallenge(login("alice@example.fr", "AfterIncidentPassword123!"), "alice@example.fr", "MFA_LOGIN");
    }
    @Test void resetCodeIsHashedSingleUseAndWrongAttemptsAreCommitted() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false); String actual = resetCode("alice@example.fr");
        assertThat(users.findById(a.user().getId()).orElseThrow().getResetCodeHash()).isNotEqualTo(actual);
        for (int i=1; i<=5; i++) {
            send("/api/auth/reset-password", null, Map.of("email", "alice@example.fr", "code", wrong(actual), "newPassword", "NewPassword123!"))
                    .andExpect(status().isBadRequest());
            assertThat(users.findById(a.user().getId()).orElseThrow().getResetCodeAttempts()).isEqualTo(i);
        }
        send("/api/auth/reset-password", null, Map.of("email", "alice@example.fr", "code", actual, "newPassword", "NewPassword123!"))
                .andExpect(status().isBadRequest());
    }
    @Test void resetRequestMasksUnknownEmailAndMailFailureRollsBackCode() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false);
        var known = postJson("/api/auth/forgot-password", null, Map.of("email", "alice@example.fr"), 200);
        var unknown = postJson("/api/auth/forgot-password", null, Map.of("email", "unknown@example.fr"), 200);
        assertThat(known).isEqualTo(unknown);
        var user = users.findById(a.user().getId()).orElseThrow(); user.setResetCodeRequestedAt(Instant.now().minusSeconds(61)); user.setResetCodeHash(null); users.save(user);
        doThrow(new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "Mail unavailable")).when(mail).sendCode(anyString(), anyString());
        send("/api/auth/forgot-password", null, Map.of("email", "alice@example.fr")).andExpect(status().isServiceUnavailable());
        assertThat(users.findById(a.user().getId()).orElseThrow().getResetCodeHash()).isNull();
    }
    @Test void mergeRequiresBothProofsExplicitConflictsAndIndependentReviewThenPreservesMedicalRecords() throws Exception {
        Account a = account("alice@example.fr", Role.USER, true), b = account("second@example.fr", Role.USER, false), admin = account("admin@example.fr", Role.ADMIN, false);
        b.user().setFullName("Alice Different Name"); b.user().setPassword(encoder.encode("SecondaryPassword456!")); users.save(b.user());
        appointments.save(Appointment.builder().user(b.user()).doctorName("Dr Example").dateTime(LocalDateTime.now().plusDays(1)).build());
        prescriptions.save(Prescription.builder().patient(b.user()).doctor(admin.user())
                .diagnosis("Routine care").prescriptionDate(LocalDate.now()).build());
        var r = postJson("/api/security/merges", a.token(), Map.of("targetEmail", "second@example.fr", "reason", "Both accounts belong to the same person"), 200);
        String path = "/api/security/admin/merges/"+r.get("id").asText()+"/decision";
        send(path, admin.token(), Map.of("approve", true, "note", "Cannot approve without ownership proofs")).andExpect(status().isConflict());
        String primary = code("alice@example.fr", "MERGE_PRIMARY"), secondary = code("second@example.fr", "MERGE_SECONDARY");
        send("/api/security/merges/"+r.get("id").asText()+"/verify", a.token(), Map.of("primaryCode", primary, "secondaryCode", wrong(secondary))).andExpect(status().isBadRequest());
        postJson("/api/security/merges/"+r.get("id").asText()+"/verify", a.token(), Map.of("primaryCode", primary, "secondaryCode", secondary), 200);
        assertThat(users.findById(b.user().getId()).orElseThrow().getMergedIntoId()).isNull();
        send(path, admin.token(), Map.of("approve", true, "note", "Resolve all conflicts explicitly")).andExpect(status().isConflict()).andExpect(jsonPath("message").value("MERGE_CONFLICTS_UNRESOLVED"));
        postJson(path, admin.token(), Map.of("approve", true, "note", "Both identities and conflicts reviewed", "fieldSources", Map.of("fullName", "PRIMARY")), 200);
        assertThat(users.findById(b.user().getId()).orElseThrow().getMergedIntoId()).isEqualTo(a.user().getId());
        assertThat(appointments.findByUserIdOrderByDateTimeDesc(a.user().getId())).hasSize(1);
        assertThat(prescriptions.findByPatientIdOrderByPrescriptionDateDesc(a.user().getId())).hasSize(1);
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer "+a.token())).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/users/me").header("Authorization", "Bearer "+b.token())).andExpect(status().isUnauthorized());
        send("/api/auth/login", null, Map.of("identifier", "second@example.fr", "password", "SecondaryPassword456!")).andExpect(status().isUnauthorized());
        verifyChallenge(login("second@example.fr", PASSWORD), "alice@example.fr", "MFA_LOGIN");
        assertThat(audit.findAll()).anySatisfy(e -> assertThat(e.getAction()).isEqualTo("ACCOUNTS_MERGED"));
    }
    @Test void privilegedAccountsCannotBeMergedAndUnprovenProfilesAreNotDisclosed() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false), b = account("doctor@example.fr", Role.DOCTOR, false), admin = account("admin@example.fr", Role.ADMIN, false);
        var r = postJson("/api/security/merges", a.token(), Map.of("targetEmail", "doctor@example.fr", "reason", "Request requires special role handling"), 200);
        assertThat(r.get("secondaryProfile").size()).isZero(); assertThat(r.get("secondaryUserId").isNull()).isTrue();
        postJson("/api/security/merges/"+r.get("id").asText()+"/verify", a.token(), Map.of("primaryCode", code("alice@example.fr", "MERGE_PRIMARY"), "secondaryCode", code("doctor@example.fr", "MERGE_SECONDARY")), 200);
        send("/api/security/admin/merges/"+r.get("id").asText()+"/decision", admin.token(), Map.of("approve", true, "note", "Professional privileges cannot be combined")).andExpect(status().isConflict());
        assertThat(users.findById(b.user().getId()).orElseThrow().getMergedIntoId()).isNull();
    }
    @Test void changedCredentialsInvalidateMergeProofAndOrdinaryUsersCannotInspectAdminData() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false), b = account("second@example.fr", Role.USER, false), admin = account("admin@example.fr", Role.ADMIN, false);
        var r = postJson("/api/security/merges", a.token(), Map.of("targetEmail", "second@example.fr", "reason", "Both accounts belong to the same person"), 200);
        postJson("/api/security/merges/"+r.get("id").asText()+"/verify", a.token(), Map.of("primaryCode", code("alice@example.fr", "MERGE_PRIMARY"), "secondaryCode", code("second@example.fr", "MERGE_SECONDARY")), 200);
        var secondary = users.findById(b.user().getId()).orElseThrow(); AccountAccess.revoke(secondary); users.save(secondary);
        send("/api/security/admin/merges/"+r.get("id").asText()+"/decision", admin.token(), Map.of("approve", true, "note", "Proof is stale after credentials change")).andExpect(status().isConflict());
        for (String path : List.of("/api/security/admin/duplicates", "/api/security/admin/audit", "/api/security/admin/merges"))
            mvc.perform(get(path).header("Authorization", "Bearer "+a.token())).andExpect(status().isForbidden());
    }
    @Test void profileEditsCannotReplaceAuthenticationEmailOrRedirectOtp() throws Exception {
        Account a = account("alice@example.fr", Role.USER, true);
        mvc.perform(put("/api/users/me").header("Authorization", "Bearer "+a.token()).contentType(MediaType.APPLICATION_JSON)
                .content(json.writeValueAsString(Map.of("fullName", "Alice Martin", "email", "replacement@example.fr"))))
                .andExpect(status().isConflict()).andExpect(jsonPath("message").value("EMAIL_CHANGE_REQUIRES_VERIFICATION"));
        assertThat(users.findById(a.user().getId()).orElseThrow().getEmail()).isEqualTo("alice@example.fr");
    }
    @Test void concurrentOtpVerificationsIssueOnlyOneSession() throws Exception {
        account("alice@example.fr", Role.USER, true);
        var challenge = login("alice@example.fr", PASSWORD);
        Map<String, String> body = Map.of("challengeId", challenge.get("challengeId").asText(), "code", code("alice@example.fr", "MFA_LOGIN"));
        var executor = java.util.concurrent.Executors.newFixedThreadPool(2);
        var start = new java.util.concurrent.CountDownLatch(1);
        try {
            java.util.concurrent.Callable<Integer> verify = () -> { start.await(); return send("/api/auth/verify", null, body).andReturn().getResponse().getStatus(); };
            var first = executor.submit(verify); var second = executor.submit(verify); start.countDown();
            assertThat(List.of(first.get(10, java.util.concurrent.TimeUnit.SECONDS), second.get(10, java.util.concurrent.TimeUnit.SECONDS))).containsExactlyInAnyOrder(200, 400);
        } finally { executor.shutdownNow(); }
    }
    @Test void medicalResponsesNeverExposeAuthenticationSecrets() throws Exception {
        Account a = account("alice@example.fr", Role.USER, false);
        User u = users.findById(a.user().getId()).orElseThrow();
        u.setTokenVersion(0L); u.setResetCodeHash("private-reset-code-hash"); u.setResetCodeAttempts(3);
        u.setResetCodeExpiresAt(Instant.now().plusSeconds(600)); users.save(u);
        appointments.save(Appointment.builder().user(u).doctorName("Dr Example").dateTime(LocalDateTime.now().plusDays(1)).build());
        mvc.perform(get("/api/appointments").header("Authorization", "Bearer "+a.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].user.email").value("alice@example.fr"))
                .andExpect(jsonPath("$[0].user.password").doesNotExist())
                .andExpect(jsonPath("$[0].user.tokenVersion").doesNotExist())
                .andExpect(jsonPath("$[0].user.resetCodeHash").doesNotExist())
                .andExpect(jsonPath("$[0].user.resetCodeExpiresAt").doesNotExist())
                .andExpect(jsonPath("$[0].user.resetCodeAttempts").doesNotExist());
    }
    @Test void doctorsMustBeAssignedToPatientsBeforeWritingPrescriptionAndAdminsCanListAllPrescriptions() throws Exception {
        Account admin = account("admin@example.fr", Role.ADMIN, false);
        Account doctor = account("doctor@example.fr", Role.DOCTOR, false);
        Account otherDoctor = account("other-doctor@example.fr", Role.DOCTOR, false);
        Account patient = account("patient@example.fr", Role.USER, false);
        Account otherPatient = account("other@example.fr", Role.USER, false);

        assignments.save(DoctorPatientAssignment.builder().doctor(otherDoctor.user()).patient(otherPatient.user()).active(true).build());
        send("/api/prescriptions", doctor.token(), Map.of("patientId", otherPatient.user().getId(), "diagnosis", "Blocked")).andExpect(status().isForbidden());

        JsonNode prescription = postJson("/api/prescriptions", doctor.token(), Map.of("patientId", patient.user().getId(), "diagnosis", "Routine care"), 200);
        assertThat(prescription.get("patientId").asLong()).isEqualTo(patient.user().getId());
        assertThat(assignments.existsByDoctorIdAndPatientId(doctor.user().getId(), patient.user().getId())).isTrue();
        mvc.perform(get("/api/prescriptions").header("Authorization", "Bearer " + admin.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].patientId").value(patient.user().getId()));
    }

    @Test void doctorsCanSearchAssignablePatientsByName() throws Exception {
        Account doctor = account("doctor@example.fr", Role.DOCTOR, false);
        Account available = account("available@example.fr", Role.USER, false);
        Account assignedElsewhere = account("assigned@example.fr", Role.USER, false);
        Account otherDoctor = account("other-doctor@example.fr", Role.DOCTOR, false);
        assignments.save(DoctorPatientAssignment.builder()
                .doctor(otherDoctor.user()).patient(assignedElsewhere.user()).active(true).build());

        JsonNode results = json.readTree(mvc.perform(get("/api/prescriptions/patients")
                        .param("search", "Alice")
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString());
        Set<Long> patientIds = new HashSet<>();
        results.forEach(item -> patientIds.add(item.get("id").asLong()));
        assertThat(patientIds).contains(available.user().getId()).doesNotContain(assignedElsewhere.user().getId());

        mvc.perform(get("/api/prescriptions/patients")
                        .param("search", "A")
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isBadRequest());
        mvc.perform(get("/api/prescriptions/patients")
                        .param("search", "Alice")
                        .header("Authorization", "Bearer " + available.token()))
                .andExpect(status().isForbidden());
    }

    @Test void doctorsCanListOnlyTheirActiveFollowedPatients() throws Exception {
        Account doctor = account("doctor@example.fr", Role.DOCTOR, false);
        Account otherDoctor = account("other-doctor@example.fr", Role.DOCTOR, false);
        Account followed = account("followed@example.fr", Role.USER, false);
        Account otherFollowed = account("other-followed@example.fr", Role.USER, false);
        assignments.save(DoctorPatientAssignment.builder()
                .doctor(doctor.user()).patient(followed.user()).active(true).build());
        assignments.save(DoctorPatientAssignment.builder()
                .doctor(otherDoctor.user()).patient(otherFollowed.user()).active(true).build());

        mvc.perform(get("/api/prescriptions/patients/followed")
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray())
                .andExpect(jsonPath("$[0].id").value(followed.user().getId()))
                .andExpect(jsonPath("$[0].fullName").isNotEmpty())
                .andExpect(jsonPath("$[1]").doesNotExist());
        mvc.perform(get("/api/prescriptions/patients/followed")
                        .header("Authorization", "Bearer " + followed.token()))
                .andExpect(status().isForbidden());
    }

    @Test void doctorCanUploadAndPatientCanReadAnAttachedPrescription() throws Exception {
        Account doctor = account("doctor@example.fr", Role.DOCTOR, false);
        Account patient = account("patient@example.fr", Role.USER, false);
        byte[] pdf = "%PDF-1.7\nOrdonnance de test".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
        MockMultipartFile file = new MockMultipartFile(
                "file", "ordonnance.pdf", MediaType.APPLICATION_PDF_VALUE, pdf);

        JsonNode uploaded = json.readTree(mvc.perform(multipart("/api/prescriptions/upload")
                        .file(file)
                        .param("patientId", patient.user().getId().toString())
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.hasDocument").value(true))
                .andExpect(jsonPath("$.documentName").value("ordonnance.pdf"))
                .andReturn().getResponse().getContentAsString());

        long prescriptionId = uploaded.get("id").asLong();
        assertThat(assignments.existsByDoctorIdAndPatientId(
                doctor.user().getId(), patient.user().getId())).isTrue();
        mvc.perform(get("/api/prescriptions/" + prescriptionId + "/document")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_PDF))
                .andExpect(content().bytes(pdf));

        Account unrelatedPatient = account("unrelated@example.fr", Role.USER, false);
        mvc.perform(get("/api/prescriptions/" + prescriptionId + "/document")
                        .header("Authorization", "Bearer " + unrelatedPatient.token()))
                .andExpect(status().isNotFound());

        mvc.perform(post("/api/prescriptions/" + prescriptionId + "/extract-medications")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isForbidden());

        when(prescriptionOcrService.extract(any(byte[].class), eq(MediaType.APPLICATION_PDF_VALUE)))
                .thenReturn(new PrescriptionMedicationParser.ExtractionResult(
                        List.of(), "No medication detected"));
        mvc.perform(post("/api/prescriptions/" + prescriptionId + "/extract-medications")
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.medications").isEmpty())
                .andExpect(jsonPath("$.notice").value("No medication detected"));
        verify(prescriptionOcrService, times(1))
                .extract(any(byte[].class), eq(MediaType.APPLICATION_PDF_VALUE));

        long prescriptionsBeforeDraftExtraction = prescriptions.count();
        mvc.perform(multipart("/api/prescriptions/extract-medications")
                        .file(file)
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.medications").isEmpty())
                .andExpect(jsonPath("$.notice").value("No medication detected"));
        mvc.perform(multipart("/api/prescriptions/extract-medications")
                        .file(file)
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isForbidden());
        assertThat(prescriptions.count()).isEqualTo(prescriptionsBeforeDraftExtraction);
        verify(prescriptionOcrService, times(2))
                .extract(any(byte[].class), eq(MediaType.APPLICATION_PDF_VALUE));

        MockMultipartFile spoofed = new MockMultipartFile(
                "file", "ordonnance.pdf", MediaType.APPLICATION_PDF_VALUE, "not a pdf".getBytes());
        mvc.perform(multipart("/api/prescriptions/upload")
                        .file(spoofed)
                        .param("patientId", patient.user().getId().toString())
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isUnsupportedMediaType());
    }

    @Test void doctorCanEditReplaceAndArchiveOwnPrescription() throws Exception {
        Account doctor = account("doctor@example.fr", Role.DOCTOR, false);
        Account otherDoctor = account("other-doctor@example.fr", Role.DOCTOR, false);
        Account patient = account("patient@example.fr", Role.USER, false);
        JsonNode created = postJson("/api/prescriptions", doctor.token(),
                Map.of("patientId", patient.user().getId(), "diagnosis", "Initial diagnosis"), 200);
        long prescriptionId = created.get("id").asLong();
        MockMultipartFile replacement = new MockMultipartFile(
                "file", "updated-ordonnance.pdf", MediaType.APPLICATION_PDF_VALUE,
                "%PDF-1.7\nUpdated ordonnance".getBytes(java.nio.charset.StandardCharsets.US_ASCII));

        mvc.perform(multipart("/api/prescriptions/" + prescriptionId)
                        .file(replacement)
                        .queryParam("prescriptionDate", "2026-11-15")
                        .queryParam("diagnosis", "Updated diagnosis")
                        .queryParam("notes", "Updated notes")
                        .with(request -> {
                            request.setMethod("PUT");
                            return request;
                        })
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.patientId").value(patient.user().getId()))
                .andExpect(jsonPath("$.diagnosis").value("Updated diagnosis"))
                .andExpect(jsonPath("$.notes").value("Updated notes"))
                .andExpect(jsonPath("$.prescriptionDate").value("2026-11-15"))
                .andExpect(jsonPath("$.documentName").value("updated-ordonnance.pdf"));

        mvc.perform(delete("/api/prescriptions/" + prescriptionId)
                        .header("Authorization", "Bearer " + otherDoctor.token()))
                .andExpect(status().isNotFound());
        mvc.perform(delete("/api/prescriptions/" + prescriptionId)
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isForbidden());
        mvc.perform(delete("/api/prescriptions/" + prescriptionId)
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isNoContent());

        assertThat(prescriptions.findById(prescriptionId).orElseThrow().isArchived()).isTrue();
        mvc.perform(get("/api/prescriptions").header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk())
                .andExpect(content().json("[]"));
        mvc.perform(get("/api/prescriptions/" + prescriptionId + "/document")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk())
                .andExpect(content().bytes(replacement.getBytes()));
    }

    @Test void medicationSchedulesAndPrescriptionsAreScopedToTheAuthenticatedUsers() throws Exception {
        Account patient = account("patient@example.fr", Role.USER, false);
        Account doctor = account("doctor@example.fr", Role.DOCTOR, false);
        Account otherPatient = account("other@example.fr", Role.USER, false);
        Account otherDoctor = account("other-doctor@example.fr", Role.DOCTOR, false);

        JsonNode prescription = postJson("/api/prescriptions", doctor.token(),
                Map.of("patientId", patient.user().getId(), "diagnosis", "Routine care"), 200);
        long prescriptionId = prescription.get("id").asLong();

        mvc.perform(post("/api/medications")
                        .header("Authorization", "Bearer " + patient.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of(
                                "name", "Patient-created medication",
                                "startDate", LocalDate.now().toString(),
                                "reminderTimes", List.of("08:00:00")))))
                .andExpect(status().isForbidden());

        Map<String, Object> invalidMedication = new HashMap<>(Map.of(
                "name", "Invalid date medication",
                "startDate", LocalDate.now().toString(),
                "endDate", LocalDate.now().minusDays(1).toString(),
                "reminderTimes", List.of("08:00:00"),
                "prescriptionId", prescriptionId));
        mvc.perform(post("/api/medications")
                        .header("Authorization", "Bearer " + doctor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(invalidMedication)))
                .andExpect(status().isBadRequest());
        postJson("/api/medications", doctor.token(), Map.of(
                "name", "Medication without a schedule",
                "prescriptionId", prescriptionId), 400);

        mvc.perform(get("/api/prescriptions").header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(prescriptionId))
                .andExpect(jsonPath("$[0].doctorName").value(doctor.user().getFullName()));

        String today = LocalDate.now().toString();
        JsonNode medication = postJson("/api/medications", doctor.token(), Map.of(
                "name", "Daily medication",
                "dosage", "10 mg",
                "frequency", "2 fois / jour",
                "frequencyPerDay", 2,
                "instructions", "After food",
                "startDate", today,
                "endDate", today,
                "reminderTimes", List.of("08:00:00", "20:00:00"),
                "prescriptionId", prescriptionId), 200);
        long medicationId = medication.get("id").asLong();
        assertThat(medication.has("user")).isFalse();
        assertThat(medication.get("stockTracked").asBoolean()).isFalse();
        assertThat(medication.get("prescriptionId").asLong()).isEqualTo(prescriptionId);

        mvc.perform(get("/api/medications").header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].reminderTimes[0]").value("08:00:00"))
                .andExpect(jsonPath("$[0].reminderTimes[1]").value("20:00:00"));
        mvc.perform(get("/api/medications").header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(medicationId));
        mvc.perform(get("/api/medications/" + medicationId)
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reminderTimes[0]").value("08:00:00"));
        mvc.perform(post("/api/medications")
                        .header("Authorization", "Bearer " + otherDoctor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of(
                                "name", "Wrong prescription",
                                "prescriptionId", prescriptionId,
                                "reminderTimes", List.of("08:00:00")))))
                .andExpect(status().isNotFound());

        String schedule = mvc.perform(get("/api/medications/" + medicationId + "/schedule")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray())
                .andExpect(jsonPath("$").isNotEmpty())
                .andReturn().getResponse().getContentAsString();
        JsonNode reminders = json.readTree(schedule);
        assertThat(reminders).hasSize(2);
        long reminderId = reminders.get(0).get("id").asLong();
        postJson("/api/medications/reminders/" + reminderId + "/taken",
                patient.token(), Map.of(), 403);
        postJson("/api/medications/reminders/" + reminderId + "/taken",
                doctor.token(), Map.of(), 200);
        mvc.perform(get("/api/medications/" + medicationId + "/history")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].taken").value(true));

        send("/api/prescriptions", patient.token(),
                Map.of("patientId", patient.user().getId())).andExpect(status().isForbidden());
        mvc.perform(get("/api/prescriptions/" + prescriptionId)
                        .header("Authorization", "Bearer " + otherPatient.token()))
                .andExpect(status().isNotFound());
        mvc.perform(get("/api/medications/" + medicationId)
                        .header("Authorization", "Bearer " + otherPatient.token()))
                .andExpect(status().isNotFound());
    }

    @Test void medicationIntakeStockSchedulesAdherenceAndLifecycleAreTransactionalAndOwned() throws Exception {
        Account patient = account("stock-patient@example.fr", Role.USER, false);
        Account other = account("stock-other@example.fr", Role.USER, false);
        Account doctor = account("stock-doctor@example.fr", Role.DOCTOR, false);
        long prescriptionId = postJson("/api/prescriptions", doctor.token(),
                Map.of("patientId", patient.user().getId(), "diagnosis", "Medication plan"), 200)
                .get("id").asLong();
        String today = LocalDate.now().toString();
        String earlier = LocalTime.MIDNIGHT.toString();
        JsonNode medication = postJson("/api/medications", doctor.token(), Map.ofEntries(
                Map.entry("name", "Tracked medicine"), Map.entry("startDate", today),
                Map.entry("endDate", today), Map.entry("reminderTimes", List.of(earlier)),
                Map.entry("weekdays", List.of(LocalDate.now().getDayOfWeek().name())),
                Map.entry("pharmaceuticalForm", "tablet"), Map.entry("notes", "With water"),
                Map.entry("unitsPerDose", 2), Map.entry("stockQuantity", 4),
                Map.entry("stockUnit", "tablets"), Map.entry("lowStockThreshold", 2),
                Map.entry("prescriptionId", prescriptionId),
                Map.entry("packageQuantity", 30)), 200);
        long medicationId = medication.get("id").asLong();
        assertThat(medication.get("status").asText()).isEqualTo("ACTIVE");
        assertThat(medication.get("weekdays")).hasSize(1);

        JsonNode scheduled = json.readTree(mvc.perform(get("/api/medications/" + medicationId + "/schedule")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        assertThat(scheduled).hasSize(1);
        long reminderId = scheduled.get(0).get("id").asLong();
        mvc.perform(post("/api/medications/reminders/" + reminderId + "/snooze")
                        .header("Authorization", "Bearer " + patient.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("minutes", 15))))
                .andExpect(status().isForbidden());
        mvc.perform(post("/api/medications/reminders/" + reminderId + "/snooze")
                        .header("Authorization", "Bearer " + doctor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("minutes", 15))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("SNOOZED"))
                .andExpect(jsonPath("$.snoozedUntil").exists());
        mvc.perform(get("/api/medications/today")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$").isArray());
        mvc.perform(get("/api/medications/" + medicationId + "/schedule")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$").isArray());
        String duplicateCheck = mvc.perform(get("/api/medications/" + medicationId + "/schedule")
                        .param("from", today).param("to", today)
                        .header("Authorization", "Bearer " + patient.token()))
                .andReturn().getResponse().getContentAsString();
        assertThat(json.readTree(duplicateCheck)).hasSize(1);

        JsonNode wrongWeekday = postJson("/api/medications", doctor.token(), Map.of(
                "name", "Wrong weekday", "startDate", today, "endDate", today,
                "reminderTimes", List.of("07:00:00"),
                "prescriptionId", prescriptionId,
                "weekdays", List.of(LocalDate.now().plusDays(1).getDayOfWeek().name())), 200);
        mvc.perform(get("/api/medications/" + wrongWeekday.get("id").asLong() + "/schedule")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
        JsonNode suspended = postJson("/api/medications", doctor.token(), Map.of(
                "name", "Suspended medicine", "startDate", today, "endDate", today,
                "reminderTimes", List.of("09:00:00"), "status", "SUSPENDED",
                "prescriptionId", prescriptionId), 200);
        mvc.perform(get("/api/medications/" + suspended.get("id").asLong() + "/schedule")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());

        postJson("/api/medications/reminders/" + reminderId + "/taken", patient.token(), Map.of(), 403);
        postJson("/api/medications/reminders/" + reminderId + "/taken", doctor.token(), Map.of(), 200);
        postJson("/api/medications/reminders/" + reminderId + "/taken", doctor.token(), Map.of(), 200);
        mvc.perform(get("/api/medications/" + medicationId + "/stock")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.quantity").value(2))
                .andExpect(jsonPath("$.lowStock").value(true));
        mvc.perform(post("/api/medications/reminders/" + reminderId + "/pending")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isForbidden());
        mvc.perform(post("/api/medications/reminders/" + reminderId + "/pending")
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PENDING"));
        mvc.perform(get("/api/medications/" + medicationId + "/stock")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.quantity").value(4));

        postJson("/api/medications/reminders/" + reminderId + "/taken", doctor.token(), Map.of(), 200);
        mvc.perform(get("/api/medications/adherence?period=DAILY")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.eligibleDoses").value(1))
                .andExpect(jsonPath("$.taken").value(1)).andExpect(jsonPath("$.adherencePercent").value(100.0))
                .andExpect(jsonPath("$.days[0].taken").value(1));
        mvc.perform(get("/api/medications/adherence")
                        .param("period", "DAILY")
                        .param("patientId", patient.user().getId().toString())
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.eligibleDoses").value(1))
                .andExpect(jsonPath("$.taken").value(1))
                .andExpect(jsonPath("$.adherencePercent").value(100.0));
        mvc.perform(get("/api/medications/today")
                        .param("patientId", patient.user().getId().toString())
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$").isArray());
        mvc.perform(get("/api/medications/adherence")
                        .param("patientId", other.user().getId().toString())
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isNotFound());
        mvc.perform(get("/api/medications/adherence")
                        .param("patientId", patient.user().getId().toString())
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isNotFound());
        mvc.perform(post("/api/medications/" + medicationId + "/stock/refill")
                        .header("Authorization", "Bearer " + patient.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("quantity", 5, "note", "New package"))))
                .andExpect(status().isForbidden());
        mvc.perform(post("/api/medications/" + medicationId + "/stock/refill")
                        .header("Authorization", "Bearer " + doctor.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("quantity", 5, "note", "New package"))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.quantity").value(7));
        mvc.perform(get("/api/medications/statistics?period=week")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.period").value("WEEKLY"));
        mvc.perform(patch("/api/medications/reminders/" + reminderId)
                        .header("Authorization", "Bearer " + other.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("status", "SKIPPED"))))
                .andExpect(status().isForbidden());
        mvc.perform(patch("/api/medications/reminders/" + reminderId)
                        .header("Authorization", "Bearer " + patient.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("status", "PENDING"))))
                .andExpect(status().isForbidden());
        mvc.perform(patch("/api/medications/reminders/" + reminderId)
                        .header("Authorization", "Bearer " + doctor.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("status", "PENDING"))))
                .andExpect(status().isOk());
        mvc.perform(patch("/api/medications/reminders/" + reminderId)
                        .header("Authorization", "Bearer " + doctor.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("status", "SKIPPED", "note", "Not needed"))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SKIPPED"));
        mvc.perform(get("/api/medications/" + medicationId + "/stock")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.quantity").value(9))
                .andExpect(jsonPath("$.entries.length()").value(6));
        mvc.perform(put("/api/medications/" + medicationId + "/stock")
                        .header("Authorization", "Bearer " + patient.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("quantity", 1, "note", "Counted stock",
                                "unit", "capsules", "lowStockThreshold", 3, "packageQuantity", 20))))
                .andExpect(status().isForbidden());
        mvc.perform(put("/api/medications/" + medicationId + "/stock")
                        .header("Authorization", "Bearer " + doctor.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("quantity", 1, "note", "Counted stock",
                                "unit", "capsules", "lowStockThreshold", 3, "packageQuantity", 20))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.quantity").value(1))
                .andExpect(jsonPath("$.unit").value("capsules"))
                .andExpect(jsonPath("$.lowStockThreshold").value(3))
                .andExpect(jsonPath("$.packageQuantity").value(20))
                .andExpect(jsonPath("$.lowStock").value(true)).andExpect(jsonPath("$.entries.length()").value(7));

        mvc.perform(put("/api/medications/" + medicationId)
                        .header("Authorization", "Bearer " + doctor.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("name", "Tracked medicine",
                                "startDate", today, "endDate", LocalDate.now().minusDays(1).toString(),
                                "reminderTimes", List.of(earlier),
                                "prescriptionId", prescriptionId))))
                .andExpect(status().isBadRequest());
        mvc.perform(put("/api/medications/" + medicationId)
                        .header("Authorization", "Bearer " + patient.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("name", "Patient update attempt"))))
                .andExpect(status().isForbidden());
        mvc.perform(put("/api/medications/" + medicationId)
                        .header("Authorization", "Bearer " + doctor.token()).contentType(MediaType.APPLICATION_JSON)
                        .content(json.writeValueAsString(Map.of("name", "Tracked medicine",
                                "startDate", today, "endDate", today, "reminderTimes", List.of(earlier),
                                "status", "SUSPENDED", "prescriptionId", prescriptionId))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("SUSPENDED"));
        mvc.perform(get("/api/medications/" + medicationId + "/history")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].status").value("SKIPPED"));
        mvc.perform(delete("/api/medications/" + medicationId)
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isForbidden());
        mvc.perform(delete("/api/medications/" + medicationId)
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isOk());
        mvc.perform(get("/api/medications/" + medicationId)
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("DISCONTINUED"));

        JsonNode emptyStock = postJson("/api/medications", doctor.token(), Map.of(
                "name", "Empty stock medicine", "startDate", today, "endDate", today,
                "reminderTimes", List.of(earlier), "unitsPerDose", 1,
                "stockQuantity", 0, "stockUnit", "tablet",
                "prescriptionId", prescriptionId), 200);
        JsonNode emptySchedule = json.readTree(mvc.perform(get(
                        "/api/medications/" + emptyStock.get("id").asLong() + "/schedule")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        mvc.perform(post("/api/medications/reminders/" + emptySchedule.get(0).get("id").asLong() + "/taken")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isForbidden());
        mvc.perform(post("/api/medications/reminders/" + emptySchedule.get(0).get("id").asLong() + "/taken")
                        .header("Authorization", "Bearer " + doctor.token()))
                .andExpect(status().isConflict());
        mvc.perform(get("/api/medications/" + emptyStock.get("id").asLong() + "/stock")
                        .header("Authorization", "Bearer " + patient.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$.quantity").value(0));
    }
    @Test void verifiedGmailVariantsAreSuggestedWithoutAutomaticallyMerging() throws Exception {
        Account a = account("alice.martin@gmail.com", Role.USER, false);
        Account b = account("alicemartin+health@gmail.com", Role.USER, false);
        Account admin = account("admin@example.fr", Role.ADMIN, false);
        String response = mvc.perform(get("/api/security/admin/duplicates").header("Authorization", "Bearer "+admin.token()))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        assertThat(json.readTree(response)).hasSize(1);
        assertThat(json.readTree(response).get(0).get("reason").asText()).contains("Gmail");
        assertThat(users.findById(a.user().getId()).orElseThrow().getMergedIntoId()).isNull();
        assertThat(users.findById(b.user().getId()).orElseThrow().getMergedIntoId()).isNull();
    }
    @Test void unverifiedAliasesAndOrganizationDomainsAreNotUsedAsIdentityEvidence() throws Exception {
        account("alice.martin@gmail.com", Role.USER, false);
        Account pending = account("alicemartin+work@gmail.com", Role.USER, false);
        pending.user().setEmailVerified(false); users.save(pending.user());
        account("alice.martin@example.fr", Role.USER, false); account("alicemartin@example.fr", Role.USER, false);
        Account admin = account("admin@example.fr", Role.ADMIN, false);
        mvc.perform(get("/api/security/admin/duplicates").header("Authorization", "Bearer "+admin.token()))
                .andExpect(status().isOk()).andExpect(jsonPath("$").isEmpty());
    }
    @Test void backupLoginWorksWhenSmtpIsUnavailableAndStillRequiresPasswordAndUnusedCode() throws Exception {
        Account a = account("alice@example.fr", Role.USER, true);
        doThrow(new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "Mail unavailable")).when(mail).ensureAvailable();
        send("/api/auth/login", null, Map.of("identifier", "alice@example.fr", "password", PASSWORD)).andExpect(status().isServiceUnavailable());
        send("/api/auth/login/recovery", null, Map.of("identifier", "alice@example.fr", "password", "wrong", "code", a.codes().getFirst())).andExpect(status().isUnauthorized());
        assertThat(recovery.countByUserIdAndUsedAtIsNull(a.user().getId())).isEqualTo(10);
        var body = Map.of("identifier", "alice@example.fr", "password", PASSWORD, "code", a.codes().getFirst());
        postJson("/api/auth/login/recovery", null, body, 200);
        send("/api/auth/login/recovery", null, body).andExpect(status().isBadRequest());
        assertThat(recovery.countByUserIdAndUsedAtIsNull(a.user().getId())).isEqualTo(9);
    }
}
