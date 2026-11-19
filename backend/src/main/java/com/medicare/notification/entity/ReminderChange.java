package com.medicare.notification.entity;
import jakarta.persistence.*;
import java.time.Instant;
import lombok.*;

@Entity @Getter @Setter
public class ReminderChange {
    @Id @GeneratedValue(strategy=GenerationType.IDENTITY) private Long id;
    private Long reminderId;
    private Long actorId;
    private String actorName;
    private String action;
    private Instant changedAt;
}
