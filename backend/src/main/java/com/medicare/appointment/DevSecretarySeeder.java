package com.medicare.appointment;

import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import com.medicare.user.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

// Demo accounts with known passwords: dev profile only.
@Component
@Profile("dev")
@org.springframework.core.annotation.Order(10)
@RequiredArgsConstructor
public class DevSecretarySeeder implements ApplicationRunner {

    private final UserRepository users;
    private final SecretaryDoctorAssignmentRepository assignments;
    private final PasswordEncoder encoder;

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        User ahmed = account("Dr Ahmed", "dr.ahmed@medicare.com", "Doctor@2026", Role.DOCTOR);
        User sarah = account("Dr Sarah", "dr.sarah@medicare.com", "Doctor@2026", Role.DOCTOR);
        User secretary1 = account("Secrétaire Dr Ahmed", "secretaire.ahmed@medicare.com", "Secret@2026", Role.USER);
        User secretary2 = account("Secrétaire Dr Sarah", "secretaire.sarah@medicare.com", "Secret@2026", Role.USER);
        assign(secretary1, ahmed);
        assign(secretary2, sarah);
    }

    private User account(String fullName, String email, String password, Role role) {
        return users.findByEmailIgnoreCase(email).orElseGet(() -> users.save(User.builder()
                .fullName(fullName)
                .email(email)
                .password(encoder.encode(password))
                .emailVerified(true)
                .role(role)
                .build()));
    }

    private void assign(User secretary, User doctor) {
        if (!assignments.existsBySecretaryIdAndDoctorId(secretary.getId(), doctor.getId())) {
            assignments.save(SecretaryDoctorAssignment.builder().secretary(secretary).doctor(doctor).build());
        }
    }
}
