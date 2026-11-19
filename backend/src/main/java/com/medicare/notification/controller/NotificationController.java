package com.medicare.notification.controller;

import com.medicare.notification.dto.NotificationDtos;
import com.medicare.notification.entity.NotificationType;
import com.medicare.notification.service.NotificationService;
import jakarta.validation.Valid;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/notifications")
@RequiredArgsConstructor
public class NotificationController {
    private final NotificationService service;

    @GetMapping
    public List<NotificationDtos.NotificationResponse> list(Authentication authentication,
            @RequestParam(required = false) Boolean read,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) NotificationType type,
            @RequestParam(defaultValue = "false") boolean archived) {
        return service.list(authentication, read, q, type, archived);
    }

    @GetMapping("/deliveries")
    public List<NotificationDtos.Delivery> deliveries(Authentication auth) { return service.deliveries(auth); }

    @GetMapping("/unread-count")
    public NotificationDtos.UnreadCountResponse unreadCount(Authentication authentication) {
        return service.unreadCount(authentication);
    }

    @GetMapping("/overview")
    public NotificationDtos.Overview overview(Authentication authentication) {
        return service.overview(authentication);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public NotificationDtos.NotificationResponse create(Authentication authentication,
            @Valid @RequestBody NotificationDtos.CreateNotificationRequest request) {
        return service.create(authentication, request);
    }

    @PatchMapping("/{id}/read")
    public NotificationDtos.NotificationResponse markRead(Authentication authentication, @PathVariable Long id) {
        return service.markRead(authentication, id);
    }

    @PatchMapping("/read-all")
    public NotificationDtos.MarkAllReadResponse markAllRead(Authentication authentication) {
        return service.markAllRead(authentication);
    }

    @PatchMapping("/{id}/unread")
    public NotificationDtos.NotificationResponse markUnread(Authentication authentication, @PathVariable Long id) {
        return service.markUnread(authentication, id);
    }

    @PatchMapping("/{id}/archive")
    public NotificationDtos.NotificationResponse archive(Authentication authentication, @PathVariable Long id,
            @Valid @RequestBody NotificationDtos.ArchiveRequest request) {
        return service.archive(authentication, id, request.archived());
    }
}
