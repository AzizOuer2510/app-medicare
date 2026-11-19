package com.medicare.document.dto;

import com.medicare.document.entity.DocumentShare;
import jakarta.validation.constraints.*;
import java.time.Instant;

public final class DocumentShareDtos {
    private DocumentShareDtos() {}

    public record CreateRequest(@NotNull @Min(15) @Max(1440) Integer durationMinutes,
                                @Size(max = 80) String label) {}
    public record AccessRequest(@NotNull @Pattern(regexp = "[A-Za-z0-9_-]{43}") String token,
                                @NotNull @Pattern(regexp = "[0-9]{6}") String pin) {}
    public record ShareResponse(Long id, String label, Instant createdAt, Instant expiresAt,
                                Instant revokedAt, String status, long accessCount, Instant lastAccessAt) {
        public static ShareResponse from(DocumentShare share) {
            String status = share.getRevokedAt() != null ? "REVOKED"
                    : !share.getExpiresAt().isAfter(Instant.now()) ? "EXPIRED"
                    : share.getFailedAttempts() >= 5 ? "LOCKED" : "ACTIVE";
            return new ShareResponse(share.getId(), share.getLabel(), share.getCreatedAt(), share.getExpiresAt(),
                    share.getRevokedAt(), status, share.getAccessCount(), share.getLastAccessAt());
        }
    }
    public record CreatedShare(ShareResponse share, String url, String pin) {}
    public record AccessResponse(Long id, Instant accessedAt) {}
    public record SharedContent(DocumentDtos.DocumentContent content, Instant expiresAt) {}
}
