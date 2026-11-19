package com.medicare.notification.controller;
import com.medicare.notification.entity.ReminderChange;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Future;
import java.time.Instant;

import com.medicare.notification.dto.NotificationDtos;
import com.medicare.notification.entity.NotificationType;
import com.medicare.notification.entity.ReminderStatus;
import com.medicare.notification.service.NotificationService;
import jakarta.validation.Valid;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/reminders")
@RequiredArgsConstructor
public class ReminderController {
    private final NotificationService service;

    public record AlertRequest(@NotNull @Future Instant at) {}
    @PatchMapping("/{id}/alert")
    public NotificationDtos.ReminderResponse alert(Authentication auth,@PathVariable Long id,@Valid @RequestBody AlertRequest body) {
        return service.setAlert(auth,id,body.at());
    }

    @GetMapping("/history")
    public List<ReminderChange> history(Authentication auth) { return service.history(auth); }

    @PostMapping("/{id}/retry")
    public void retry(Authentication auth,@PathVariable Long id) { service.retry(auth,id); }

    @GetMapping
    public List<NotificationDtos.ReminderResponse> list(Authentication authentication,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) NotificationType type,
            @RequestParam(required = false) ReminderStatus status) {
        return service.listReminders(authentication, q, type, status);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public NotificationDtos.ReminderResponse create(Authentication authentication,
            @Valid @RequestBody NotificationDtos.ReminderRequest request) {
        return service.createReminder(authentication, request);
    }

    @PutMapping("/{id}")
    public NotificationDtos.ReminderResponse update(Authentication authentication, @PathVariable Long id,
            @Valid @RequestBody NotificationDtos.ReminderRequest request) {
        return service.updateReminder(authentication, id, request);
    }

    @PatchMapping("/{id}/cancel")
    public NotificationDtos.ReminderResponse cancel(Authentication authentication, @PathVariable Long id) {
        return service.cancelReminder(authentication, id);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(Authentication authentication, @PathVariable Long id) {
        service.deleteReminder(authentication, id);
    }

    @PostMapping("/{id}/snooze")
    public NotificationDtos.ReminderResponse snooze(Authentication authentication, @PathVariable Long id,
            @Valid @RequestBody NotificationDtos.SnoozeRequest request) {
        return service.snoozeReminder(authentication, id, request.minutes());
    }
}
