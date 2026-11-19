package com.medicare.document.service;
import com.medicare.user.entity.User;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.medicare.common.ApiException;
import com.medicare.document.dto.AnalysisDtos.*;
import com.medicare.document.entity.*;
import com.medicare.document.repository.*;
import com.medicare.notification.dto.NotificationDtos.ReminderRequest;
import com.medicare.notification.entity.*;
import com.medicare.notification.repository.NotificationRepository;
import com.medicare.notification.service.NotificationService;
import com.medicare.user.repository.UserRepository;
import java.time.*;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service @RequiredArgsConstructor
public class DocumentAnalysisService {
    private final DocumentAccess access;
    private final com.medicare.notification.service.CareRelationships care;
    private final DocumentRepository documents;
    private final DocumentAnalysisRepository analyses;
    private final UserRepository users;
    private final NotificationRepository notifications;
    private final NotificationService reminders;
    private final ObjectMapper mapper;
    public record Work(Long documentId, Instant startedAt, String storageKey, String type) {}

    @Transactional
    public Result request(Authentication auth, Long id) {
        User requester = viewer(auth);
        MedicalDocument doc = access.get(requester,id,true,false);
        DocumentAnalysis a = analyses.findByDocumentId(id).orElseGet(DocumentAnalysis::new);
        if (a.getStatus()==null || a.getStatus()==Status.FAILED) {
            a.setDocument(doc);
            a.setRequestedById(requester.getId());
            a.setStatus(Status.QUEUED);
            a.setError(null);
            analyses.save(a);
        }
        return result(a);
    }

    @Transactional(readOnly=true)
    public Result get(Authentication auth,Long id) {
        access.get(viewer(auth),id,false,false);
        return analyses.findByDocumentId(id).map(this::result).orElse(new Result(null,null,null));
    }

    @Transactional
    public Optional<Work> claim() {
        var candidate = analyses.findFirstByStatusOrderByStartedAtAsc(Status.PROCESSING)
                .filter(a -> a.getStartedAt().isBefore(Instant.now().minusSeconds(900)))
                .or(() -> analyses.findFirstByStatusOrderById(Status.QUEUED));
        if (candidate.isEmpty()) return Optional.empty();
        Long id = candidate.get().getDocument().getId();
        if (documents.findLockedById(id).isEmpty()) return Optional.empty();
        // Re-read status under the document lock, including changes from another worker.
        DocumentAnalysis a = candidate.get();
        entityManager.refresh(a);
        if (a.getStatus()!=Status.QUEUED && !(a.getStatus()==Status.PROCESSING
                && a.getStartedAt().isBefore(Instant.now().minusSeconds(900)))) return Optional.empty();
        a.setStatus(Status.PROCESSING);
        a.setStartedAt(Instant.now().truncatedTo(java.time.temporal.ChronoUnit.MICROS));
        return Optional.of(new Work(id,a.getStartedAt(),a.getDocument().getStorageKey(),a.getDocument().getContentType()));
    }
    private final jakarta.persistence.EntityManager entityManager;

    @Transactional
    public void finish(Work work, Draft draft, String error) {
        var doc = documents.findLockedById(work.documentId());
        if (doc.isEmpty()) return;
        var a = analyses.findByDocumentId(work.documentId()).orElseThrow();
        if (a.getStatus()!=Status.PROCESSING || !work.startedAt().equals(a.getStartedAt())) return;
        a.setStatus(draft==null ? Status.FAILED : Status.READY);
        a.setError(error);
        if (draft!=null) {
            a.setDraftJson(encode(draft));
            notifications.save(Notification.builder().user(doc.get().getUser()).type(NotificationType.GENERAL)
                    .title("Analyse du document terminée").message("Les propositions pour « "+doc.get().getTitle()
                            +" » sont disponibles dans Documents médicaux.").createdAt(Instant.now()).build());
            Long requester = a.getRequestedById();
            MedicalDocument document = doc.get();
            if (requester!=null && !requester.equals(document.getUser().getId())) {
                users.findById(requester).filter(user -> user.getRole()==com.medicare.user.entity.Role.ADMIN
                        || (document.getSharedDoctor()!=null && document.getSharedDoctor().getId().equals(requester)
                        && care.follows(user, document.getUser().getId())))
                    .ifPresent(user -> care.notify(user,"Analyse du document terminée",
                            "Les propositions pour « "+document.getTitle()+" » sont disponibles dans Documents médicaux."));
            }
        }
    }

    @Transactional
    public Result confirm(Authentication auth,Long id,Review review) {
        MedicalDocument doc = access.get(viewer(auth),id,true,true);
        DocumentAnalysis a = analyses.findByDocumentId(id).orElseThrow(DocumentAnalysisService::missing);
        if (a.getStatus()==Status.CONFIRMED) return result(a);
        if (a.getStatus()!=Status.READY) throw new ApiException(HttpStatus.CONFLICT,"Analyse indisponible.");
        Draft draft = result(a).draft();
        if (review.reminderAt()!=null) {
            if (review.offsetMinutes()==null || draft.followUpDate()==null || !draft.followUpDate().equals(
                    review.reminderAt().atOffset(ZoneOffset.ofTotalSeconds(review.offsetMinutes()*60)).toLocalDate()))
                throw new ApiException(HttpStatus.BAD_REQUEST,"La date doit correspondre au suivi proposé.");
            reminders.createReminder(auth,new ReminderRequest("Suivi du document","Consulter « "+review.fields().title()+" ».",
                    NotificationType.GENERAL,null,review.reminderAt(),doc.getUser().getId()));
        }
        doc.setTitle(review.fields().title().trim());
        doc.setCategory(review.fields().category());
        a.setDraftJson(encode(new Draft(review.fields(),draft.followUpDate(),draft.evidence(),draft.sourceText())));
        a.setStatus(Status.CONFIRMED);
        return result(a);
    }
    private User viewer(Authentication auth) {
        return users.findByEmail(auth.getName()).orElseThrow(DocumentAnalysisService::missing);
    }
    private static ApiException missing() { return new ApiException(HttpStatus.NOT_FOUND,"Document introuvable."); }
    private String encode(Draft draft) {
        try { return mapper.writeValueAsString(draft); } catch(JsonProcessingException e) { throw new IllegalStateException(e); }
    }
    private Result result(DocumentAnalysis a) {
        try { return new Result(a.getStatus(), a.getDraftJson()==null ? null : mapper.readValue(a.getDraftJson(),Draft.class),a.getError()); }
        catch(JsonProcessingException e) { throw new IllegalStateException(e); }
    }
}
