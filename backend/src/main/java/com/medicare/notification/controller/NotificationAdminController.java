package com.medicare.notification.controller;

import com.medicare.notification.dto.NotificationDtos;
import com.medicare.notification.service.NotificationService;
import jakarta.validation.Valid;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/notifications/admin")
@RequiredArgsConstructor
@PreAuthorize("hasRole('ADMIN')")
public class NotificationAdminController {
    private final NotificationService service;

    @GetMapping
    public List<NotificationDtos.AdminNotificationResponse> list(Authentication auth,
            @RequestParam(required = false) Long userId) {
        return service.administration(auth, userId);
    }

    @GetMapping("/recipients")
    public List<NotificationDtos.Recipient> recipients(Authentication auth) {
        return service.recipients(auth);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public NotificationDtos.NotificationResponse create(Authentication auth,
            @Valid @RequestBody NotificationDtos.CreateNotificationRequest request) {
        return service.create(auth, request);
    }

    @PutMapping("/{id}")
    public NotificationDtos.NotificationResponse update(Authentication auth, @PathVariable Long id,
            @Valid @RequestBody NotificationDtos.UpdateNotificationRequest request) {
        return service.updateNotification(auth, id, request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(Authentication auth, @PathVariable Long id) {
        service.deleteNotification(auth, id);
    }
}
