package com.medicare.document;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.medicare.document.repository.DocumentShareRepository;
import com.medicare.document.repository.DocumentShareAccessRepository;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.*;
import java.util.concurrent.*;
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
        "spring.datasource.url=jdbc:h2:mem:document-sharing;DB_CLOSE_DELAY=-1",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.jpa.hibernate.ddl-auto=create-drop", "app.notifications.reminders-enabled=false",
        "app.notifications.module-events-enabled=false", "app.analysis.worker-enabled=false",
        "app.jwt.secret=m5-sharing-test-secret-key-of-at-least-32-characters"
})
@AutoConfigureMockMvc
class DocumentShareApiTest {
    @TempDir static Path storage;
    @DynamicPropertySource
    static void storage(DynamicPropertyRegistry registry) {
        registry.add("app.documents.storage-path", () -> storage.toString());
    }
    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired DocumentShareRepository shares;
    @Autowired DocumentShareAccessRepository accesses;
    @Autowired PasswordEncoder encoder;
    @Autowired com.medicare.user.repository.UserRepository users;
    @Autowired com.medicare.security.JwtService jwt;
    String owner, other;
    long documentId;
    static final byte[] PDF = "%PDF-1.4\nFictitious document\n%%EOF".getBytes(StandardCharsets.UTF_8);

    @BeforeEach
    void prepare() throws Exception {
        owner = account(); other = account();
        documentId = send(multipart("/api/documents")
                .file(new MockMultipartFile("file", "analyse fictive.pdf", "application/pdf", PDF))
                .param("title", "Analyse fictive").param("category", "ANALYSIS"), owner, null, 201).get("id").asLong();
    }

    @Test
    void sharesUseRandomTokensAndHashedPinsAndOnlyRevealCredentialsOnce() throws Exception {
        JsonNode created = create(15);
        URI url = URI.create(created.get("url").asText());
        assertThat(url.getPath()).isEqualTo("/share/document");
        assertThat(url.getQuery()).isNull();
        assertThat(url.getFragment()).matches("[A-Za-z0-9_-]{43}");
        String pin = created.get("pin").asText();
        assertThat(pin).matches("[0-9]{6}");
        var saved = shares.findById(id(created)).orElseThrow();
        assertThat(saved.getTokenHash()).isEqualTo(HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(url.getFragment().getBytes(StandardCharsets.UTF_8))));
        assertThat(saved.getPinHash()).isNotEqualTo(pin);
        assertThat(encoder.matches(pin, saved.getPinHash())).isTrue();
        assertThat(saved.getExpiresAt()).isEqualTo(saved.getCreatedAt().plusSeconds(900));
        JsonNode listed = send(get(path()), owner, null, 200);
        assertThat(listed.get(0).get("status").asText()).isEqualTo("ACTIVE");
        assertThat(listed.toString()).doesNotContain(pin, url.getFragment(), "tokenHash", "pinHash", "storageKey");
        assertThat(create(60).get("url").asText()).isNotEqualTo(url.toString());
    }

    @Test
    void validAnonymousAccessReturnsExactFileRecordsHistoryAndNotifiesOnlyTheOwner() throws Exception {
        JsonNode created = create(60);
        for (int i = 0; i < 2; i++) {
            mvc.perform(access(created, created.get("pin").asText()))
                    .andExpect(status().isOk()).andExpect(content().bytes(PDF))
                    .andExpect(content().contentType(MediaType.APPLICATION_PDF))
                    .andExpect(header().string("Cache-Control", "no-store"))
                    .andExpect(header().string("Referrer-Policy", "no-referrer"))
                    .andExpect(header().string("X-Share-Expires-At", created.get("share").get("expiresAt").asText()));
        }
        JsonNode list = send(get(path()), owner, null, 200);
        assertThat(list.get(0).get("accessCount").asInt()).isEqualTo(2);
        assertThat(list.get(0).get("lastAccessAt").isNull()).isFalse();
        JsonNode history = send(get(path() + "/" + id(created) + "/accesses"), owner, null, 200);
        assertThat(history.size()).isEqualTo(2);
        assertThat(Instant.parse(history.get(0).get("accessedAt").asText()))
                .isAfterOrEqualTo(Instant.parse(history.get(1).get("accessedAt").asText()));
        JsonNode notifications = send(get("/api/notifications"), owner, null, 200);
        assertThat(notifications.size()).isEqualTo(2);
        assertThat(notifications.get(0).get("title").asText()).isEqualTo("Document partagé consulté");
        assertThat(notifications.toString()).doesNotContain(created.get("pin").asText(), token(created));
        assertThat(send(get("/api/notifications"), other, null, 200).size()).isZero();
    }

    @Test
    void allManagementRoutesAreOwnerScopedAndOriginalContentRemainsPrivate() throws Exception {
        JsonNode created = create(15);
        send(post(path()), other, Map.of("durationMinutes", 15), 404);
        send(get(path()), other, null, 404);
        send(patch(path() + "/" + id(created) + "/revoke"), other, null, 404);
        send(get(path() + "/" + id(created) + "/accesses"), other, null, 404);
        mvc.perform(get(path())).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/documents/{id}/content", documentId)).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/medications")).andExpect(status().isUnauthorized());
        assertThat(send(get(path()), owner, null, 200).get(0).get("status").asText()).isEqualTo("ACTIVE");
    }

    @Test
    void revocationIsIdempotentAndImmediatelyBlocksAnOtherwiseCorrectPin() throws Exception {
        JsonNode created = create(15);
        mvc.perform(access(created, created.get("pin").asText())).andExpect(status().isOk());
        JsonNode revoked = send(patch(path() + "/" + id(created) + "/revoke"), owner, null, 200);
        assertThat(revoked.get("status").asText()).isEqualTo("REVOKED");
        JsonNode again = send(patch(path() + "/" + id(created) + "/revoke"), owner, null, 200);
        assertThat(again.get("revokedAt")).isEqualTo(revoked.get("revokedAt"));
        mvc.perform(access(created, created.get("pin").asText())).andExpect(status().isGone());
        assertThat(accesses.findTop50ByShareIdOrderByAccessedAtDescIdDesc(id(created))).hasSize(1);
    }

    @Test
    void expirationAndDeletionInvalidateLinksAndDeleteDependentRecords() throws Exception {
        JsonNode expired = create(15);
        var share = shares.findById(id(expired)).orElseThrow();
        share.setExpiresAt(Instant.now().minusSeconds(1)); shares.saveAndFlush(share);
        mvc.perform(access(expired, expired.get("pin").asText())).andExpect(status().isGone());
        assertThat(send(get(path()), owner, null, 200).get(0).get("status").asText()).isEqualTo("EXPIRED");
        JsonNode active = create(15);
        mvc.perform(access(active, active.get("pin").asText())).andExpect(status().isOk());
        send(delete("/api/documents/{id}", documentId), owner, null, 204);
        mvc.perform(access(active, active.get("pin").asText())).andExpect(status().isNotFound());
        assertThat(shares.findById(id(active))).isEmpty();
        assertThat(shares.findById(id(expired))).isEmpty();
        assertThat(accesses.findTop50ByShareIdOrderByAccessedAtDescIdDesc(id(active))).isEmpty();
    }

    @Test
    void wrongPinAttemptsPersistAndCannotBeBypassedByConcurrentRequests() throws Exception {
        JsonNode created = create(15);
        String wrong = created.get("pin").asText().equals("000000") ? "000001" : "000000";
        try (var executor = Executors.newFixedThreadPool(6)) {
            List<Callable<Integer>> requests = new ArrayList<>();
            for (int i = 0; i < 6; i++) requests.add(() -> mvc.perform(access(created, wrong)).andReturn().getResponse().getStatus());
            List<Integer> statuses = new ArrayList<>();
            for (Future<Integer> future : executor.invokeAll(requests)) statuses.add(future.get(15, TimeUnit.SECONDS));
            assertThat(statuses).containsOnly(403, 429);
            assertThat(Collections.frequency(statuses, 403)).isEqualTo(4);
            assertThat(Collections.frequency(statuses, 429)).isEqualTo(2);
        }
        assertThat(shares.findById(id(created)).orElseThrow().getFailedAttempts()).isEqualTo(5);
        mvc.perform(access(created, created.get("pin").asText())).andExpect(status().isTooManyRequests());
        assertThat(send(get(path()), owner, null, 200).get(0).get("status").asText()).isEqualTo("LOCKED");
        assertThat(send(get("/api/notifications"), owner, null, 200).size()).isZero();
        assertThat(accesses.findTop50ByShareIdOrderByAccessedAtDescIdDesc(id(created))).isEmpty();
    }

    @Test
    void aWrongPinDoesNotRevealContentAndUnknownTokensAreRejected() throws Exception {
        JsonNode created = create(15);
        String wrong = created.get("pin").asText().equals("000000") ? "000001" : "000000";
        mvc.perform(access(created, wrong)).andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("Code PIN incorrect."))
                .andExpect(header().doesNotExist("X-Document-Filename"));
        mvc.perform(access(created, created.get("pin").asText())).andExpect(status().isOk());
        assertThat(shares.findById(id(created)).orElseThrow().getAccessCount()).isEqualTo(1);
        send(post("/api/document-shares/access"), null, Map.of("token", "x".repeat(43), "pin", "123456"), 404);
    }

    @Test
    void invalidDurationsInputsAndTooManyActiveSharesAreRejected() throws Exception {
        for (Object body : List.of(Map.of(), Map.of("durationMinutes", 0), Map.of("durationMinutes", 30),
                Map.of("durationMinutes", 1441), Map.of("durationMinutes", 15, "label", "x".repeat(81)))) {
            send(post(path()), owner, body, 400);
        }
        for (Object body : List.of(Map.of(), Map.of("token", "x", "pin", "123456"),
                Map.of("token", "x".repeat(43), "pin", "12345"), Map.of("token", "x".repeat(43), "pin", "abcdef"))) {
            send(post("/api/document-shares/access"), null, body, 400);
        }
        JsonNode first = create(15);
        for (int i = 1; i < 10; i++) create(1440);
        send(post(path()), owner, Map.of("durationMinutes", 15), 409);
        send(patch(path() + "/" + id(first) + "/revoke"), owner, null, 200);
        create(15);
    }

    @Test
    void recipientPageWorksWithoutAuthenticationAndDoesNotExposeFilesOrLoosenOtherRoutes() throws Exception {
        mvc.perform(get("/share/document")).andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(header().string("X-Frame-Options", "DENY"))
                .andExpect(header().exists("Content-Security-Policy"));
        mvc.perform(get("/share/document/app.js")).andExpect(status().isOk());
        mvc.perform(get("/share/document/style.css")).andExpect(status().isOk());
        mvc.perform(get("/share/document/anything-else")).andExpect(status().isForbidden());
        mvc.perform(get("/api/document-shares/access")).andExpect(status().isForbidden());
        mvc.perform(get("/api/health")).andExpect(status().isOk());
        mvc.perform(post("/api/document-shares/access").header("Origin", "https://unrelated.example")
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(header().doesNotExist("Access-Control-Allow-Origin"));
    }

    private String path() { return "/api/documents/" + documentId + "/shares"; }
    private long id(JsonNode created) { return created.get("share").get("id").asLong(); }
    private String token(JsonNode created) { return URI.create(created.get("url").asText()).getFragment(); }
    private JsonNode create(int minutes) throws Exception {
        return send(post(path()), owner, Map.of("durationMinutes", minutes, "label", "Consultation démo"), 201);
    }
    private MockHttpServletRequestBuilder access(JsonNode created, String pin) throws Exception {
        return post("/api/document-shares/access").contentType(MediaType.APPLICATION_JSON)
                .content(mapper.writeValueAsBytes(Map.of("token", token(created), "pin", pin)));
    }
    private String account() throws Exception {
        var user = users.saveAndFlush(com.medicare.user.entity.User.builder().fullName("Share Test")
                .email(UUID.randomUUID() + "@example.test").password(encoder.encode("ShareTestPassword!2026"))
                .role(com.medicare.user.entity.Role.USER).emailVerified(true).mfaEnabled(false).build());
        return "Bearer " + jwt.generateToken(user);
    }
    private JsonNode send(MockHttpServletRequestBuilder request, String token, Object body, int expected) throws Exception {
        if (token != null) request.header("Authorization", token);
        if (body != null) request.contentType(MediaType.APPLICATION_JSON).content(mapper.writeValueAsBytes(body));
        String response = mvc.perform(request).andExpect(status().is(expected)).andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
        return response.isBlank() ? null : mapper.readTree(response);
    }
}
