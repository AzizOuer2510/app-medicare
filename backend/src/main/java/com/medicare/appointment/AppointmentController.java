package com.medicare.appointment;

import com.medicare.appointment.AppointmentDtos.AppointmentRequest;
import com.medicare.appointment.AppointmentDtos.AppointmentResponse;
import com.medicare.appointment.AppointmentDtos.AppointmentStatistics;
import com.medicare.appointment.AppointmentDtos.NoShowRisk;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api/appointments")
@RequiredArgsConstructor
public class AppointmentController {

    private final AppointmentService service;

    @GetMapping
    public List<AppointmentResponse> list(@RequestParam(required = false) String status,
                                          Authentication auth) {
        return service.list(auth.getName(), status);
    }

    @GetMapping("/doctors")
    public List<AppointmentDtos.PersonSummary> doctors() {
        return service.doctors();
    }

    @GetMapping("/history")
    public List<AppointmentResponse> history(Authentication auth) {
        return service.history(auth.getName());
    }

    @GetMapping("/upcoming")
    public List<AppointmentResponse> upcoming(Authentication auth) {
        return service.upcoming(auth.getName());
    }

    @GetMapping("/statistics")
    public AppointmentStatistics statistics(Authentication auth) {
        return service.statistics(auth.getName());
    }

    @GetMapping("/{id}")
    public AppointmentResponse get(@PathVariable Long id, Authentication auth) {
        return service.get(auth.getName(), id);
    }

    @GetMapping("/{id}/no-show-risk")
    public NoShowRisk noShowRisk(@PathVariable Long id, Authentication auth) {
        return service.noShowRisk(auth.getName(), id);
    }

    @PostMapping
    public ResponseEntity<AppointmentResponse> create(@Valid @RequestBody AppointmentRequest req,
                                                      Authentication auth) {
        return ResponseEntity.status(HttpStatus.CREATED).body(service.create(auth.getName(), req));
    }

    @PutMapping("/{id}")
    public AppointmentResponse update(@PathVariable Long id,
                                      @Valid @RequestBody AppointmentRequest req,
                                      Authentication auth) {
        return service.update(auth.getName(), id, req);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id, Authentication auth) {
        service.delete(auth.getName(), id);
        return ResponseEntity.noContent().build();
    }
}

