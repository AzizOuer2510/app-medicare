package com.medicare.medication;

import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import com.medicare.user.repository.UserRepository;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.List;

@RestController
@RequestMapping("/api/prescriptions")
@RequiredArgsConstructor
public class PrescriptionController {
    private static final int MAX_DOCUMENT_BYTES = 10 * 1024 * 1024;
    private static final int MAX_PATIENT_SEARCH_RESULTS = 50;

    private final PrescriptionRepository prescriptions;
    private final UserRepository users;
    private final DoctorPatientAssignmentRepository assignments;
    private final PrescriptionOcrService ocrService;

    public record PrescriptionRequest(
            @NotNull Long patientId,
            String diagnosis,
            LocalDate prescriptionDate,
            String notes) {}

    public record PrescriptionResponse(
            Long id,
            Long patientId,
            String patientName,
            Long doctorId,
            String doctorName,
            String diagnosis,
            LocalDate prescriptionDate,
            String notes,
            List<Long> medicationIds,
            boolean hasDocument,
            String documentName) {
        static PrescriptionResponse from(Prescription prescription) {
            return new PrescriptionResponse(
                    prescription.getId(),
                    prescription.getPatient().getId(),
                    prescription.getPatient().getFullName(),
                    prescription.getDoctor().getId(),
                    prescription.getDoctor().getFullName(),
                    prescription.getDiagnosis(),
                    prescription.getPrescriptionDate(),
                    prescription.getNotes(),
                    prescription.getMedications().stream().map(Medication::getId).toList(),
                    prescription.getDocumentData() != null,
                    prescription.getDocumentName());
        }
    }

    public record PatientOption(Long id, String fullName) {}

    @GetMapping("/patients")
    @Transactional(readOnly = true)
    public List<PatientOption> searchablePatients(
            @RequestParam String search,
            Authentication auth) {
        User doctor = currentUser(auth);
        if (doctor.getRole() != Role.DOCTOR && doctor.getRole() != Role.ADMIN) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only a doctor can search patients");
        }
        String normalized = search.trim();
        if (normalized.length() < 2 || normalized.length() > 80) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Search must contain 2 to 80 characters");
        }
        Long doctorId = doctor.getRole() == Role.DOCTOR ? doctor.getId() : null;
        return users.findAssignablePatients(doctorId, normalized, PageRequest.of(0, MAX_PATIENT_SEARCH_RESULTS))
                .stream()
                .map(patient -> new PatientOption(patient.getId(), patient.getFullName()))
                .toList();
    }

    @GetMapping("/patients/followed")
    @Transactional(readOnly = true)
    public List<PatientOption> followedPatients(Authentication auth) {
        User doctor = currentUser(auth);
        if (doctor.getRole() != Role.DOCTOR) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Only a doctor can view followed patients");
        }
        return assignments.findActiveByDoctorId(doctor.getId())
                .stream()
                .map(assignment -> assignment.getPatient())
                .map(patient -> new PatientOption(patient.getId(), patient.getFullName()))
                .toList();
    }

    @GetMapping
    @Transactional(readOnly = true)
    public List<PrescriptionResponse> mine(Authentication auth) {
        User current = currentUser(auth);
        List<Prescription> results;
        if (current.getRole() == Role.DOCTOR) {
            results = prescriptions.findByDoctorIdAndArchivedFalseOrderByPrescriptionDateDesc(current.getId());
        } else if (current.getRole() == Role.ADMIN) {
            results = prescriptions.findAllByArchivedFalseOrderByPrescriptionDateDesc();
        } else {
            results = prescriptions.findByPatientIdAndArchivedFalseOrderByPrescriptionDateDesc(current.getId());
        }
        return results.stream().map(PrescriptionResponse::from).toList();
    }

    @GetMapping("/{id}")
    @Transactional(readOnly = true)
    public PrescriptionResponse one(@PathVariable Long id, Authentication auth) {
        User current = currentUser(auth);
        Prescription prescription = prescriptions.findById(id)
                .filter(item -> current.getRole() == Role.ADMIN
                        || item.getPatient().getId().equals(current.getId())
                        || item.getDoctor().getId().equals(current.getId()))
                .filter(item -> !item.isArchived())
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Prescription not found"));
        return PrescriptionResponse.from(prescription);
    }

    @PostMapping
    @Transactional
    public PrescriptionResponse create(
            @Valid @RequestBody PrescriptionRequest request,
            Authentication auth) {
        User doctor = currentUser(auth);
        User patient = users.findById(request.patientId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Patient not found"));
        return createPrescription(doctor, patient, request.diagnosis(), request.prescriptionDate(),
                request.notes(), null, null, null);
    }

    @PostMapping(value = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @Transactional
    public PrescriptionResponse upload(
            @RequestParam("patientId") @NotNull Long patientId,
            @RequestPart("file") MultipartFile file,
            Authentication auth) throws IOException {
        User doctor = currentUser(auth);
        User patient = users.findById(patientId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Patient not found"));
        byte[] data = validateDocument(file);
        String contentType = detectDocumentType(file.getOriginalFilename(), data);
        String name = safeFileName(file.getOriginalFilename());
        return createPrescription(doctor, patient, "Ordonnance jointe", LocalDate.now(), null,
                data, name, contentType);
    }

    @PostMapping(value = "/extract-medications", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public PrescriptionMedicationParser.ExtractionResult extractUploadedDocument(
            @RequestPart("file") MultipartFile file,
            Authentication auth) throws IOException {
        requireDoctor(currentUser(auth));
        byte[] data = validateDocument(file);
        String contentType = detectDocumentType(file.getOriginalFilename(), data);
        return ocrService.extract(data, contentType);
    }

    @PostMapping("/{id}/extract-medications")
    public PrescriptionMedicationParser.ExtractionResult extractMedications(
            @PathVariable Long id,
            Authentication auth) {
        User current = currentUser(auth);
        requireDoctor(current);
        Prescription prescription = prescriptions.findById(id)
                .filter(item -> current.getRole() == Role.ADMIN
                        || item.getDoctor().getId().equals(current.getId()))
                .filter(item -> !item.isArchived())
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Prescription not found"));
        if (prescription.getDocumentData() == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Prescription document not found");
        }
        return ocrService.extract(
                prescription.getDocumentData().clone(),
                prescription.getDocumentContentType());
    }

    @PutMapping(value = "/{id}", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @Transactional
    public PrescriptionResponse update(
            @PathVariable Long id,
            @RequestParam("prescriptionDate")
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate prescriptionDate,
            @RequestParam(value = "diagnosis", required = false) String diagnosis,
            @RequestParam(value = "notes", required = false) String notes,
            @RequestPart(value = "file", required = false) MultipartFile file,
            Authentication auth) throws IOException {
        User current = currentUser(auth);
        Prescription prescription = editablePrescription(id, current);
        if (diagnosis != null && diagnosis.length() > 500) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Diagnosis must not exceed 500 characters");
        }
        if (notes != null && notes.length() > 1000) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Notes must not exceed 1000 characters");
        }
        if (prescriptionDate == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Prescription date is required");
        }
        prescription.setDiagnosis(trimOrNull(diagnosis));
        prescription.setPrescriptionDate(prescriptionDate);
        prescription.setNotes(trimOrNull(notes));
        if (file != null && !file.isEmpty()) {
            byte[] data = validateDocument(file);
            prescription.setDocumentData(data);
            prescription.setDocumentName(safeFileName(file.getOriginalFilename()));
            prescription.setDocumentContentType(
                    detectDocumentType(file.getOriginalFilename(), data));
        }
        return PrescriptionResponse.from(prescriptions.save(prescription));
    }

    @DeleteMapping("/{id}")
    @Transactional
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void archive(@PathVariable Long id, Authentication auth) {
        Prescription prescription = editablePrescription(id, currentUser(auth));
        prescription.setArchived(true);
        prescriptions.save(prescription);
    }

    @GetMapping("/{id}/document")
    @Transactional(readOnly = true)
    public ResponseEntity<byte[]> document(@PathVariable Long id, Authentication auth) {
        User current = currentUser(auth);
        Prescription prescription = prescriptions.findById(id)
                .filter(item -> current.getRole() == Role.ADMIN
                        || item.getPatient().getId().equals(current.getId())
                        || item.getDoctor().getId().equals(current.getId()))
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Prescription not found"));
        if (prescription.getDocumentData() == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Prescription document not found");
        }
        ContentDisposition disposition = ContentDisposition.inline()
                .filename(prescription.getDocumentName(), StandardCharsets.UTF_8)
                .build();
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(prescription.getDocumentContentType()))
                .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
                .body(prescription.getDocumentData());
    }

    private PrescriptionResponse createPrescription(
            User doctor,
            User patient,
            String diagnosis,
            LocalDate prescriptionDate,
            String notes,
            byte[] documentData,
            String documentName,
            String documentContentType) {
        requireDoctor(doctor);
        if (doctor.getRole() == Role.DOCTOR && !canAssignPatient(doctor, patient)) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "Doctor is not assigned to this patient");
        }
        Prescription saved = prescriptions.save(Prescription.builder()
                .doctor(doctor)
                .patient(patient)
                .diagnosis(diagnosis)
                .prescriptionDate(prescriptionDate == null ? LocalDate.now() : prescriptionDate)
                .notes(notes)
                .documentData(documentData)
                .documentName(documentName)
                .documentContentType(documentContentType)
                .build());
        if (doctor.getRole() == Role.DOCTOR) {
            assignments.findByDoctorIdAndPatientId(doctor.getId(), patient.getId())
                    .orElseGet(() -> assignments.save(DoctorPatientAssignment.builder()
                            .doctor(doctor)
                            .patient(patient)
                            .active(true)
                            .build()));
        }
        return PrescriptionResponse.from(saved);
    }

    private void requireDoctor(User doctor) {
        if (doctor.getRole() != Role.DOCTOR && doctor.getRole() != Role.ADMIN) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "Only a doctor can create a prescription");
        }
    }

    private byte[] validateDocument(MultipartFile file) throws IOException {
        if (file == null || file.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Choose an ordonnance file");
        }
        if (file.getSize() > MAX_DOCUMENT_BYTES) {
            throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE, "File size must not exceed 10 MB");
        }
        return file.getBytes();
    }

    private String detectDocumentType(String originalName, byte[] data) {
        String name = originalName == null ? "" : originalName.toLowerCase(java.util.Locale.ROOT);
        if (name.endsWith(".pdf") && hasPdfSignature(data)) return MediaType.APPLICATION_PDF_VALUE;
        if ((name.endsWith(".jpg") || name.endsWith(".jpeg"))
                && data.length >= 3 && (data[0] & 0xff) == 0xff
                && (data[1] & 0xff) == 0xd8 && (data[2] & 0xff) == 0xff) {
            return MediaType.IMAGE_JPEG_VALUE;
        }
        if (name.endsWith(".png") && hasPngSignature(data)) return MediaType.IMAGE_PNG_VALUE;
        throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                "Only PDF, JPEG and PNG ordonnance files are supported");
    }

    private boolean hasPdfSignature(byte[] data) {
        byte[] signature = "%PDF-".getBytes(StandardCharsets.US_ASCII);
        int searchLimit = Math.min(data.length - signature.length, 1024);
        for (int i = 0; i <= searchLimit; i++) {
            boolean matches = true;
            for (int j = 0; j < signature.length; j++) {
                if (data[i + j] != signature[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) return true;
        }
        return false;
    }

    private boolean hasPngSignature(byte[] data) {
        byte[] signature = {(byte) 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a};
        if (data.length < signature.length) return false;
        for (int i = 0; i < signature.length; i++) {
            if (data[i] != signature[i]) return false;
        }
        return true;
    }

    private String safeFileName(String originalName) {
        String name = originalName == null ? "ordonnance" : originalName.replace('\\', '/');
        int separator = name.lastIndexOf('/');
        name = name.substring(separator + 1).replaceAll("[\\p{Cntrl}]", "").trim();
        if (name.isEmpty()) name = "ordonnance";
        return name.length() > 255 ? name.substring(name.length() - 255) : name;
    }

    private boolean canAssignPatient(User doctor, User patient) {
        if (doctor.getRole() == Role.ADMIN) {
            return true;
        }
        if (doctor.getRole() != Role.DOCTOR) {
            return false;
        }
        if (patient.getRole() != Role.USER || !patient.isEmailVerified()
                || patient.getMergedIntoId() != null || patient.isPasswordResetRequired()) {
            return false;
        }
        if (assignments.existsByDoctorIdAndPatientId(doctor.getId(), patient.getId())) {
            return true;
        }
        return !assignments.existsByPatientId(patient.getId());
    }

    private Prescription editablePrescription(Long id, User current) {
        requireDoctor(current);
        Prescription prescription = current.getRole() == Role.ADMIN
                ? prescriptions.findById(id).orElse(null)
                : prescriptions.findByIdAndDoctorId(id, current.getId()).orElse(null);
        if (prescription == null || prescription.isArchived()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Prescription not found");
        }
        return prescription;
    }

    private String trimOrNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private User currentUser(Authentication auth) {
        return users.findByEmail(auth.getName())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "User not found"));
    }
}
