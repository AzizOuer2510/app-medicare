package com.medicare.notification.service;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "app.notifications.reminders-enabled", havingValue = "true", matchIfMissing = true)
public class ReminderScheduler {
    private final NotificationService service;

    @Scheduled(fixedDelayString = "${app.notifications.reminder-poll-ms:15000}")
    public void deliver() {
        service.deliverDueReminders();
    }
}
