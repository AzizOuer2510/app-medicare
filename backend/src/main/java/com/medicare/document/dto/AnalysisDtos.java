package com.medicare.document.dto;

import com.medicare.document.entity.DocumentCategory;
import jakarta.validation.constraints.*;
import java.time.*;

public final class AnalysisDtos {
    private AnalysisDtos() {}
    public enum Status { QUEUED, PROCESSING, READY, FAILED, CONFIRMED }
    public record Proposal(@NotBlank @Size(max=120) String title, @NotNull DocumentCategory category,
            LocalDate documentDate, @Size(max=160) String doctor, @Size(max=160) String facility,
            @Size(max=1000) String summary) {}
    public record Draft(Proposal fields, LocalDate followUpDate, String evidence, String sourceText) {}
    public record Review(@NotNull @jakarta.validation.Valid Proposal fields, @Future Instant reminderAt,
            @Min(-1080) @Max(1080) Integer offsetMinutes) {}
    public record Result(Status status, Draft draft, String error) {}
}
