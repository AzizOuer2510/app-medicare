package com.medicare.notification.entity;

import com.medicare.user.entity.User;
import jakarta.persistence.*;
import java.time.Instant;
import lombok.*;

@Entity
@Table(name = "notifications", indexes = @Index(columnList = "user_id,created_at"))
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class Notification {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(nullable = false, length = 120)
    private String title;

    @Column(nullable = false, length = 2000)
    private String message;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private NotificationType type;

    private Long referenceId;

    // An occurrence can be delivered only once, including with multiple scheduler instances.
    @Column(unique = true)
    private Long reminderId;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    private Instant readAt;

    @Column(nullable = false, columnDefinition = "boolean default false")
    private boolean archived;
}
