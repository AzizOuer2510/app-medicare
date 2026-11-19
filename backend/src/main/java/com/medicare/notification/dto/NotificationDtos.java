package com.medicare.notification.dto;

import com.medicare.notification.entity.Notification;
import com.medicare.notification.entity.NotificationType;
import com.medicare.notification.entity.Reminder;
import com.medicare.notification.entity.ReminderStatus;
import jakarta.validation.constraints.*;
import java.time.Instant;

public final class NotificationDtos {
    private NotificationDtos() {}

    public record CreateNotificationRequest(
            @NotBlank @Size(max = 120) String title,
            @NotBlank @Size(max = 2000) String message,
            @NotNull NotificationType type,
            @Positive Long referenceId,
            @Positive Long userId
    ) {}

    public record UpdateNotificationRequest(
            @NotBlank @Size(max = 120) String title,
            @NotBlank @Size(max = 2000) String message,
            @NotNull NotificationType type,
            @Positive Long referenceId,
            Boolean read
    ) {}

    public record Recipient(Long id, String name, String role) {}

    public record AdminNotificationResponse(NotificationResponse notification, Long userId, String recipientName) {}

    public record ReminderRequest(
            @NotBlank @Size(max = 120) String title,
            @NotBlank @Size(max = 2000) String message,
            @NotNull NotificationType type,
            @Positive Long referenceId,
            @NotNull @Future Instant scheduledFor,
            @Positive Long patientId
    ) {}

    public record NotificationResponse(
            Long id, String title, String message, NotificationType type,
            Long referenceId, Long reminderId, Instant createdAt, Instant readAt, boolean read, boolean archived
    ) {
        public static NotificationResponse from(Notification notification) {
            return new NotificationResponse(notification.getId(), notification.getTitle(),
                    notification.getMessage(), notification.getType(), notification.getReferenceId(),
                    notification.getReminderId(), notification.getCreatedAt(),
                    notification.getReadAt(), notification.getReadAt() != null, notification.isArchived());
        }
    }

    public record ReminderResponse(
            Long id, String title, String message, NotificationType type, Long referenceId,
            Instant scheduledFor, ReminderStatus status, Instant createdAt, Instant sentAt, Long recipientId, String recipientName,
            Long authorId, String authorName, Instant instructionAt, Instant deliveryFailedAt
    ) {
        public static ReminderResponse from(Reminder reminder) {
            return new ReminderResponse(reminder.getId(), reminder.getTitle(), reminder.getMessage(),
                    reminder.getType(), reminder.getReferenceId(), reminder.getScheduledFor(),
                    reminder.getStatus(), reminder.getCreatedAt(), reminder.getSentAt(),
                    reminder.getUser().getId(), reminder.getUser().getFullName(),
                    reminder.getAuthor()==null ? null : reminder.getAuthor().getId(),
                    reminder.getAuthor()==null ? null : reminder.getAuthor().getFullName(),
                    reminder.getInstructionAt(), reminder.getDeliveryFailedAt());
        }
    }

    public record Delivery(String title, String recipientName, Instant at, Long failedReminderId) {}
    public record UnreadCountResponse(long count) {}
    public record MarkAllReadResponse(int updated) {}

    public record ArchiveRequest(@NotNull Boolean archived) {}
    public record SnoozeRequest(@NotNull @Min(1) @Max(10080) Integer minutes) {}
    public record Overview(long unread, long inbox, long archived, long pendingReminders,
                           long sentReminders, ReminderResponse nextReminder, String role, Long viewerId) {}
}
