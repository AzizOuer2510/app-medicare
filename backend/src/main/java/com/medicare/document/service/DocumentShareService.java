package com.medicare.document.service;

import com.medicare.common.ApiException;
import com.medicare.document.dto.DocumentDtos;
import com.medicare.document.dto.DocumentShareDtos.*;
import com.medicare.document.entity.*;
import com.medicare.document.repository.*;
import com.medicare.notification.entity.Notification;
import com.medicare.notification.entity.NotificationType;
import com.medicare.notification.repository.NotificationRepository;
import com.medicare.user.repository.UserRepository;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class DocumentShareService {
    private final DocumentRepository documents;
    private final DocumentShareRepository shares;
    private final DocumentShareAccessRepository accesses;
    private final DocumentStorageService storage;
    private final UserRepository users;
    private final NotificationRepository notifications;
    private final PasswordEncoder passwordEncoder;
    private final SecureRandom random = new SecureRandom();

    @Transactional
    public CreatedShare create(Authentication authentication, Long documentId, CreateRequest request, String baseUrl) {
        MedicalDocument document = owned(authentication, documentId, true);
        if (!List.of(15, 60, 1440).contains(request.durationMinutes())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Choisissez une durée de 15 minutes, 1 heure ou 24 heures.");
        }
        Instant now = now();
        if (shares.countByDocumentIdAndRevokedAtIsNullAndExpiresAtAfterAndFailedAttemptsLessThan(documentId, now, 5) >= 10) {
            throw new ApiException(HttpStatus.CONFLICT, "Révoquez un partage actif avant d’en créer un autre (maximum 10).");
        }
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        String pin = String.format(Locale.ROOT, "%06d", random.nextInt(1_000_000));
        String label = request.label() == null || request.label().isBlank() ? "Consultation" : request.label().trim();
        DocumentShare share = shares.saveAndFlush(DocumentShare.builder().document(document)
                .tokenHash(hash(token)).pinHash(passwordEncoder.encode(pin)).label(label)
                .createdAt(now).expiresAt(now.plusSeconds(request.durationMinutes() * 60L)).build());
        // The fragment is never sent as part of the HTTP URL or Referer header.
        return new CreatedShare(ShareResponse.from(share), baseUrl + "/share/document#" + token, pin);
    }

    @Transactional(readOnly = true)
    public List<ShareResponse> list(Authentication authentication, Long documentId) {
        owned(authentication, documentId, false);
        return shares.findByDocumentIdOrderByCreatedAtDescIdDesc(documentId).stream().map(ShareResponse::from).toList();
    }

    @Transactional
    public ShareResponse revoke(Authentication authentication, Long documentId, Long shareId) {
        owned(authentication, documentId, true);
        DocumentShare share = shares.findLockedByIdAndDocumentId(shareId, documentId)
                .orElseThrow(() -> unavailable(HttpStatus.NOT_FOUND));
        if (share.getRevokedAt() == null) share.setRevokedAt(now());
        return ShareResponse.from(share);
    }

    @Transactional(readOnly = true)
    public List<AccessResponse> history(Authentication authentication, Long documentId, Long shareId) {
        owned(authentication, documentId, false);
        shares.findByIdAndDocumentId(shareId, documentId).orElseThrow(() -> unavailable(HttpStatus.NOT_FOUND));
        return accesses.findTop50ByShareIdOrderByAccessedAtDescIdDesc(shareId).stream()
                .map(access -> new AccessResponse(access.getId(), access.getAccessedAt())).toList();
    }

    // Wrong PIN attempts must commit even though the HTTP response is an error.
    @Transactional(noRollbackFor = WrongPinException.class)
    public SharedContent access(AccessRequest request) {
        String tokenHash = hash(request.token());
        Long documentId = shares.findDocumentIdByTokenHash(tokenHash)
                .orElseThrow(() -> unavailable(HttpStatus.NOT_FOUND));
        // Same lock order as create/revoke/delete: document, then share.
        MedicalDocument document = documents.findLockedById(documentId)
                .orElseThrow(() -> unavailable(HttpStatus.NOT_FOUND));
        DocumentShare share = shares.findLockedByTokenHash(tokenHash)
                .orElseThrow(() -> unavailable(HttpStatus.NOT_FOUND));
        if (share.getRevokedAt() != null || !share.getExpiresAt().isAfter(now())) {
            throw unavailable(HttpStatus.GONE);
        }
        if (share.getFailedAttempts() >= 5) throw locked();
        if (!passwordEncoder.matches(request.pin(), share.getPinHash())) {
            share.setFailedAttempts(share.getFailedAttempts() + 1);
            if (share.getFailedAttempts() >= 5) throw locked();
            throw new WrongPinException(HttpStatus.FORBIDDEN, "Code PIN incorrect.");
        }
        byte[] bytes = storage.read(document.getStorageKey());
        Instant accessedAt = now();
        if (!share.getExpiresAt().isAfter(accessedAt)) throw unavailable(HttpStatus.GONE);
        share.setAccessCount(share.getAccessCount() + 1);
        share.setLastAccessAt(accessedAt);
        accesses.save(DocumentShareAccess.builder().share(share).accessedAt(accessedAt).build());
        notifications.save(Notification.builder().user(document.getUser()).type(NotificationType.GENERAL)
                .title("Document partagé consulté")
                .message("Le document « " + document.getTitle() + " » a été ouvert via le partage « "
                        + share.getLabel() + " ». Consultez l’historique dans vos documents.")
                .createdAt(accessedAt).build());
        return new SharedContent(new DocumentDtos.DocumentContent(document.getOriginalFilename(),
                document.getContentType(), bytes), share.getExpiresAt());
    }

    private final DocumentAccess access;
    private MedicalDocument owned(Authentication authentication, Long id, boolean locked) {
        if (authentication == null) throw new ApiException(HttpStatus.UNAUTHORIZED, "Authentication required");
        var viewer = users.findByEmail(authentication.getName()).orElseThrow(() -> unavailable(HttpStatus.UNAUTHORIZED));
        return access.get(viewer,id,locked,true);
    }

    private static Instant now() { return Instant.now().truncatedTo(ChronoUnit.MICROS); }
    private static String hash(String token) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException ex) { throw new IllegalStateException(ex); }
    }
    private static ApiException unavailable(HttpStatus status) {
        return new ApiException(status, "Ce partage n’est plus disponible. Demandez un nouveau lien au patient.");
    }
    private static WrongPinException locked() {
        return new WrongPinException(HttpStatus.TOO_MANY_REQUESTS,
                "Partage bloqué après 5 codes incorrects. Demandez un nouveau lien au patient.");
    }
    private static final class WrongPinException extends ApiException {
        WrongPinException(HttpStatus status, String message) { super(status, message); }
    }
}
