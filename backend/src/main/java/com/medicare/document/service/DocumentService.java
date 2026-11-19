package com.medicare.document.service;
import com.medicare.user.entity.Role;
import com.medicare.notification.service.CareRelationships;
import jakarta.persistence.EntityManager;

import com.medicare.common.ApiException;
import com.medicare.document.dto.DocumentDtos;
import com.medicare.document.entity.DocumentCategory;
import com.medicare.document.entity.MedicalDocument;
import com.medicare.document.repository.DocumentRepository;
import com.medicare.user.entity.User;
import com.medicare.user.repository.UserRepository;
import java.time.Instant;
import java.util.List;
import java.util.ArrayList;
import java.util.Locale;
import jakarta.persistence.criteria.Predicate;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.data.domain.Sort;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;

@Service
@RequiredArgsConstructor
@Slf4j
public class DocumentService {
    private final DocumentAccess access;
    private final CareRelationships care;
    private final EntityManager em;
    private final DocumentRepository documents;
    private final DocumentStorageService storage;
    private final UserRepository users;

    @Transactional(readOnly = true)
    public List<DocumentDtos.DocumentResponse> list(Authentication authentication, DocumentCategory category,
            String q, Boolean favorite, String sort) {
        User viewer = currentUser(authentication);
        Sort order = switch (sort) {
            case "recent" -> Sort.by(Sort.Order.desc("uploadedAt"), Sort.Order.desc("id"));
            case "oldest" -> Sort.by("uploadedAt", "id");
            case "name" -> Sort.by("title", "id");
            case "size" -> Sort.by(Sort.Order.desc("size"), Sort.Order.desc("id"));
            default -> throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid document sort order");
        };
        List<MedicalDocument> result = documents.findAll((root, query, cb) -> {
            var predicates = new ArrayList<Predicate>();
            predicates.add(access.visible(viewer).toPredicate(root,query,cb));
            if (category != null) predicates.add(cb.equal(root.get("category"), category));
            if (favorite != null) predicates.add(cb.equal(root.get("favorite"), favorite));
            if (q != null && !q.isBlank()) {
                String pattern = "%" + q.trim().toLowerCase(Locale.ROOT)
                        .replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
                predicates.add(cb.or(cb.like(cb.lower(root.get("title")), pattern, '\\'),
                        cb.like(cb.lower(root.get("description")), pattern, '\\'),
                        cb.like(cb.lower(root.get("originalFilename")), pattern, '\\')));
            }
            return cb.and(predicates.toArray(Predicate[]::new));
        }, order);
        return result.stream().map(DocumentDtos.DocumentResponse::from).toList();
    }

    @Transactional
    public DocumentDtos.DocumentResponse update(Authentication authentication, Long id, DocumentDtos.UploadRequest request) {
        MedicalDocument document = lockedDocument(authentication, id);
        document.setTitle(request.title().trim());
        document.setCategory(request.category());
        document.setDescription(trimToNull(request.description()));
        return DocumentDtos.DocumentResponse.from(document);
    }

    @Transactional
    public DocumentDtos.DocumentResponse favorite(Authentication authentication, Long id, boolean favorite) {
        MedicalDocument document = lockedDocument(authentication, id);
        document.setFavorite(favorite);
        return DocumentDtos.DocumentResponse.from(document);
    }

    private MedicalDocument lockedDocument(Authentication authentication, Long id) {
        return access.get(currentUser(authentication),id,true,true);
    }

    @Transactional(readOnly = true)
    public DocumentDtos.Overview overview(Authentication authentication) {
        User viewer = currentUser(authentication);
        var cb = em.getCriteriaBuilder();
        var query = cb.createQuery(Long.class);
        var root = query.from(MedicalDocument.class);
        var scope = access.visible(viewer);
        query.select(cb.coalesce(cb.sum(root.<Long>get("size")),0L)).where(scope.toPredicate(root,query,cb));
        return new DocumentDtos.Overview(documents.count(scope),
                documents.count(scope.and((r,q,b) -> b.isTrue(r.get("favorite")))),
                documents.count(scope.and((r,q,b) -> b.equal(r.get("category"),DocumentCategory.PRESCRIPTION))),
                documents.count(scope.and((r,q,b) -> b.equal(r.get("category"),DocumentCategory.ANALYSIS))),
                em.createQuery(query).getSingleResult(), viewer.getRole().name(), viewer.getId());
    }

    @Transactional(readOnly = true)
    public DocumentDtos.DocumentResponse get(Authentication authentication, Long id) {
        return DocumentDtos.DocumentResponse.from(ownedDocument(currentUser(authentication), id));
    }

    @Transactional
    public DocumentDtos.DocumentResponse upload(Authentication authentication,
                                                DocumentDtos.UploadRequest request, MultipartFile file) {
        User actor = currentUser(authentication);
        User user = care.recipient(actor,request.patientId());
        User selectedDoctor = request.doctorId()==null ? null : care.doctorFor(actor,request.doctorId());
        DocumentStorageService.StoredFile stored = storage.store(file);
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCompletion(int status) {
                if (status != STATUS_COMMITTED) {
                    deleteStoredFile(stored.key());
                }
            }
        });
        MedicalDocument document = MedicalDocument.builder().user(user).title(request.title().trim())
                .category(request.category()).description(trimToNull(request.description()))
                .originalFilename(stored.filename()).storageKey(stored.key())
                .contentType(stored.contentType()).size(stored.size()).uploadedAt(Instant.now()).build();
        if (selectedDoctor != null) setDoctor(document, selectedDoctor);
        if (!actor.getId().equals(user.getId())) {
            if (actor.getRole()==Role.DOCTOR) document.setSharedDoctor(actor);
            care.notify(user,"Nouveau document médical",actor.getFullName()+" a déposé « "+document.getTitle()+" ».");
        }
        return DocumentDtos.DocumentResponse.from(documents.saveAndFlush(document));
    }

    @Transactional(readOnly = true)
    public DocumentDtos.DocumentContent content(Authentication authentication, Long id) {
        MedicalDocument document = ownedDocument(currentUser(authentication), id);
        return new DocumentDtos.DocumentContent(document.getOriginalFilename(), document.getContentType(),
                storage.read(document.getStorageKey()));
    }

    @Transactional
    public void delete(Authentication authentication, Long id) {
        MedicalDocument document = lockedDocument(authentication,id);
        String key = document.getStorageKey();
        documents.delete(document);
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                deleteStoredFile(key);
            }
        });
    }

    private void deleteStoredFile(String key) {
        try {
            storage.delete(key);
        } catch (ApiException ex) {
            log.error("Could not clean up stored document {}", key, ex);
        }
    }

    private User currentUser(Authentication authentication) {
        if (authentication == null || authentication.getName() == null) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "Authentication required");
        }
        return care.actor(authentication);
    }

    private MedicalDocument ownedDocument(User user, Long id) {
        return access.get(user,id,false,false);
    }

    @Transactional
    public void shareWithDoctor(Authentication auth, Long id, boolean enabled, Long doctorId) {
        User patient = currentUser(auth);
        User doctor = enabled ? care.doctorFor(patient,doctorId) : null;
        MedicalDocument doc = lockedDocument(auth,id);
        if (patient.getRole()==Role.ADMIN && !enabled) {
            doc.setSharedDoctor(null);
            return;
        }
        if (patient.getRole()!=Role.USER || !doc.getUser().getId().equals(patient.getId()))
            throw CareRelationships.denied();
        setDoctor(doc,doctor);
    }

    private void setDoctor(MedicalDocument doc, User doctor) {
        if (doctor!=null && (doc.getSharedDoctor()==null || !doctor.getId().equals(doc.getSharedDoctor().getId())))
            care.notify(doctor,"Document partagé",doc.getUser().getFullName()+" a partagé « "+doc.getTitle()+" ».");
        doc.setSharedDoctor(doctor);
    }

    private String trimToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }
}
