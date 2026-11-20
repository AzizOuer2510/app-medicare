package com.medicare.document.service;

import com.medicare.common.ApiException;
import com.medicare.document.entity.MedicalDocument;
import com.medicare.document.repository.DocumentRepository;
import com.medicare.notification.entity.PatientDoctor;
import com.medicare.notification.service.CareRelationships;
import com.medicare.user.entity.*;
import lombok.RequiredArgsConstructor;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;

@Component @RequiredArgsConstructor
public class DocumentAccess {
    private final DocumentRepository documents;
    private final CareRelationships care;

    public Specification<MedicalDocument> visible(User viewer) {
        return (root,query,cb) -> {
            if (viewer.getRole()==Role.ADMIN) return cb.conjunction();
            var owner = cb.equal(root.get("user"),viewer);
            if (viewer.getRole()!=Role.DOCTOR) return owner;
            // Synchronisation médecin ↔ patient : le médecin voit tous les documents (ordonnances,
            // analyses…) des patients qu'il suit, en lecture seule.
            var patientIds = care.patientIds(viewer);
            return patientIds.isEmpty() ? owner : cb.or(owner, root.get("user").get("id").in(patientIds));
        };
    }
    public MedicalDocument get(User viewer,Long id,boolean lock,boolean manage) {
        if (viewer.getRole() == Role.ADMIN && !viewer.isEmailVerified())
            throw new ApiException(HttpStatus.FORBIDDEN, "EMAIL_NOT_VERIFIED");
        var doc = (lock ? documents.findLockedById(id) : documents.findById(id)).orElseThrow(DocumentAccess::missing);
        if (viewer.getRole()==Role.ADMIN || viewer.getId().equals(doc.getUser().getId())) return doc;
        if (!manage && viewer.getRole()==Role.DOCTOR && care.follows(viewer, doc.getUser().getId())) return doc;
        throw missing();
    }
    private static ApiException missing() { return new ApiException(HttpStatus.NOT_FOUND,"Document introuvable."); }
}
