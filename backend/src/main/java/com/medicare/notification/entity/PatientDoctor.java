package com.medicare.notification.entity;
import com.medicare.user.entity.User;
import jakarta.persistence.*;
import lombok.*;

@Entity @Getter @Setter @IdClass(PatientDoctor.Key.class)
public class PatientDoctor {
    @Getter @Setter @NoArgsConstructor @EqualsAndHashCode
    public static class Key implements java.io.Serializable {
        private Long patientId;
        private Long doctor;
    }
    @Id private Long patientId;
    @Id @ManyToOne(optional=false) private User doctor;
}
