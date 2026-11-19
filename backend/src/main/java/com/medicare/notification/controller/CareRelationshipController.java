package com.medicare.notification.controller;
import com.medicare.notification.service.CareRelationships;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController @RequiredArgsConstructor @RequestMapping("/api/notifications/care")
public class CareRelationshipController {
    private final CareRelationships care;
    public record DoctorRequest(@NotBlank @Email String email) {}
    public record PatientRequest(@NotBlank @Email String email) {}
    @PutMapping("/patients")
    public CareRelationships.Contact addPatient(Authentication auth,@Valid @RequestBody PatientRequest request) {
        return care.addPatient(auth,request.email());
    }
    @GetMapping("/contacts")
    public List<CareRelationships.Contact> contacts(Authentication auth) { return care.contacts(auth); }
    @PutMapping("/doctor")
    public void link(Authentication auth,@Valid @RequestBody DoctorRequest request) { care.doctor(auth,request.email()); }
    @DeleteMapping("/doctor")
    public void unlink(Authentication auth, @RequestParam(required=false) Long doctorId) { care.removeDoctor(auth,doctorId); }
}
