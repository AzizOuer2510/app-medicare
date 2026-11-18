package com.medicare.health;

import com.medicare.common.ApiException;
import com.medicare.user.entity.Role;
import com.medicare.user.entity.User;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Mesures de santé.
 * Patient : gère ses mesures (sauf celles saisies par son médecin, en lecture seule).
 * Médecin : consulte les mesures de ses patients (paramètre patientId), ajoute des mesures
 * prises en consultation et ne modifie / supprime que celles qu'il a saisies.
 */
@RestController
@RequestMapping("/api/health-records")
@RequiredArgsConstructor
public class HealthRecordController {
    private final HealthRecordRepository repo;
    private final HealthAccessService access;

    public record HealthRequest(@NotNull LocalDateTime recordedAt,
                                @DecimalMin("1") @DecimalMax("500") Double weight,
                                @Min(20) @Max(250) Integer heartRate,
                                @Min(50) @Max(260) Integer systolic,
                                @Min(30) @Max(160) Integer diastolic,
                                @DecimalMin("30") @DecimalMax("45") Double temperature,
                                @DecimalMin("0.1") @DecimalMax("10") Double glycemia,
                                @Size(max = 500) String note) {
        boolean isEmpty() {
            return weight == null && heartRate == null && systolic == null && diastolic == null
                    && temperature == null && glycemia == null;
        }
    }

    /** Toutes les mesures, de la plus récente à la plus ancienne. */
    @GetMapping
    public List<HealthRecord> all(@RequestParam(required = false) Long patientId, Authentication auth) {
        return repo.findByUserIdOrderByRecordedAtDesc(access.resolve(auth, patientId).patient().getId());
    }

    /** Historique chronologique sur une période (7, 30, 90, 180 jours...). */
    @GetMapping("/history")
    public List<HealthRecord> history(@RequestParam(defaultValue = "30") int days,
                                      @RequestParam(required = false) Long patientId,
                                      Authentication auth) {
        int safeDays = Math.max(1, Math.min(days, 3650));
        return repo.findByUserIdAndRecordedAtAfterOrderByRecordedAtAsc(
                access.resolve(auth, patientId).patient().getId(), LocalDateTime.now().minusDays(safeDays));
    }

    /** Sans patientId : mesure personnelle. Avec patientId : mesure prise par le médecin en consultation. */
    @PostMapping
    public HealthRecord create(@Valid @RequestBody HealthRequest r,
                               @RequestParam(required = false) Long patientId,
                               Authentication auth) {
        requireValue(r);
        var ctx = access.resolve(auth, patientId);
        HealthRecord record = HealthRecord.builder()
                .user(ctx.patient())
                .recordedBy(ctx.doctorView() ? ctx.viewer() : null)
                .build();
        apply(record, r);
        return repo.save(record);
    }

    @PutMapping("/{id}")
    public HealthRecord update(@PathVariable Long id, @Valid @RequestBody HealthRequest r, Authentication auth) {
        requireValue(r);
        HealthRecord record = editable(id, access.current(auth));
        apply(record, r);
        return repo.save(record);
    }

    @DeleteMapping("/{id}")
    public void delete(@PathVariable Long id, Authentication auth) {
        repo.delete(editable(id, access.current(auth)));
    }

    private static void requireValue(HealthRequest r) {
        if (r.isEmpty()) throw new ApiException(HttpStatus.BAD_REQUEST, "Renseignez au moins une mesure.");
    }

    /** Vérifie que l'utilisateur peut modifier ou supprimer cette mesure. */
    private HealthRecord editable(Long id, User user) {
        HealthRecord record = repo.findById(id)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Mesure introuvable"));
        boolean owner = record.getUser().getId().equals(user.getId());
        User author = record.getRecordedBy();
        if (owner && author == null) return record;
        if (owner) {
            throw new ApiException(HttpStatus.FORBIDDEN,
                    "Cette mesure a été saisie par votre médecin : seul lui peut la modifier.");
        }
        if (user.getRole() == Role.DOCTOR && author != null && author.getId().equals(user.getId())
                && access.follows(user, record.getUser())) {
            return record;
        }
        throw new ApiException(HttpStatus.FORBIDDEN, "Access denied");
    }

    private static void apply(HealthRecord h, HealthRequest r) {
        h.setRecordedAt(r.recordedAt());
        h.setWeight(r.weight());
        h.setHeartRate(r.heartRate());
        h.setSystolic(r.systolic());
        h.setDiastolic(r.diastolic());
        h.setTemperature(r.temperature());
        h.setGlycemia(r.glycemia());
        h.setNote(r.note() == null || r.note().isBlank() ? null : r.note().trim());
    }
}
