package com.medicare.document.dto;

import com.medicare.document.entity.DocumentCategory;
import com.medicare.document.entity.MedicalDocument;
import jakarta.validation.constraints.*;
import java.time.Instant;

public final class DocumentDtos {
    private DocumentDtos() {}

    public record UploadRequest(
            @NotBlank @Size(max = 120) String title,
            @NotNull DocumentCategory category,
            @Size(max = 2000) String description, @Positive Long patientId, @Positive Long doctorId
    ) {}

    public record DocumentResponse(
            Long id, String title, DocumentCategory category, String description,
            String filename, String contentType, long size, Instant uploadedAt, boolean favorite, Long ownerId, String ownerName, Long sharedDoctorId, String sharedDoctorName
    ) {
        public static DocumentResponse from(MedicalDocument document) {
            return new DocumentResponse(document.getId(), document.getTitle(), document.getCategory(),
                    document.getDescription(), document.getOriginalFilename(), document.getContentType(),
                    document.getSize(), document.getUploadedAt(), document.isFavorite(), document.getUser().getId(), document.getUser().getFullName(),
                    document.getSharedDoctor()==null ? null : document.getSharedDoctor().getId(),
                    document.getSharedDoctor()==null ? null : document.getSharedDoctor().getFullName());
        }
    }

    public record DocumentContent(String filename, String contentType, byte[] bytes) {}
    public record FavoriteRequest(@NotNull Boolean favorite) {}
    public record Overview(long total, long favorites, long prescriptions, long analyses, long totalBytes, String role, Long viewerId) {}
}
