package com.medicare.roles;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class DoctorRoleRequestAutoGrant implements ApplicationRunner {
    private final RoleChangeService roleChanges;

    @Override
    public void run(ApplicationArguments arguments) {
        roleChanges.autoGrantPendingDoctorRequests();
    }
}
