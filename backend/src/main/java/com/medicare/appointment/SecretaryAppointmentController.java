package com.medicare.appointment;

import com.medicare.appointment.AppointmentDtos.AssignmentRequest;
import com.medicare.appointment.AppointmentDtos.AssignmentResponse;
import com.medicare.appointment.AppointmentDtos.PatientSummary;
import com.medicare.appointment.AppointmentDtos.PersonSummary;
import com.medicare.appointment.AppointmentDtos.SecretaryAppointmentRequest;
import com.medicare.appointment.AppointmentDtos.SecretaryAppointmentResponse;
import com.medicare.appointment.AppointmentDtos.SecretaryProfile;
import com.medicare.reminder.AppointmentReminderService;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/secretary")
@RequiredArgsConstructor
public class SecretaryAppointmentController {

    private final SecretaryAppointmentService service;
    private final AppointmentReminderService reminders;

    @GetMapping("/me")
    public SecretaryProfile me(Authentication auth) {
        return service.me(auth);
    }

    @GetMapping("/doctors")
    public List<PersonSummary> doctors(Authentication auth) {
        return service.doctors(auth);
    }

    @GetMapping("/patients")
    public List<PatientSummary> patients(Authentication auth) {
        return service.patients(auth);
    }

    @GetMapping("/appointments")
    public List<SecretaryAppointmentResponse> list(@RequestParam(required = false) String status,
                                                   Authentication auth) {
        return service.list(status, auth);
    }

    @PostMapping("/appointments")
    public ResponseEntity<SecretaryAppointmentResponse> create(@Valid @RequestBody SecretaryAppointmentRequest req,
                                                               Authentication auth) {
        return ResponseEntity.status(HttpStatus.CREATED).body(service.create(req, auth));
    }

    @PutMapping("/appointments/{id}")
    public SecretaryAppointmentResponse update(@PathVariable Long id,
                                               @Valid @RequestBody SecretaryAppointmentRequest req,
                                               Authentication auth) {
        return service.update(id, req, auth);
    }

    @DeleteMapping("/appointments/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id, Authentication auth) {
        service.delete(id, auth);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/reminders/run")
    public Map<String, Integer> runReminders(Authentication auth) {
        service.ensureStaff(auth);
        return Map.of("sent", reminders.sendDueReminders());
    }

    @GetMapping("/admin/assignments")
    public List<AssignmentResponse> assignments(Authentication auth) {
        return service.listAssignments(auth);
    }

    @PostMapping("/admin/assignments")
    public ResponseEntity<AssignmentResponse> assign(@Valid @RequestBody AssignmentRequest req,
                                                     Authentication auth) {
        return ResponseEntity.status(HttpStatus.CREATED).body(service.assign(req, auth));
    }

    @DeleteMapping("/admin/assignments/{id}")
    public ResponseEntity<Void> unassign(@PathVariable Long id, Authentication auth) {
        service.unassign(id, auth);
        return ResponseEntity.noContent().build();
    }
}
