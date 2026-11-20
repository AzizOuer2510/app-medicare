package com.medicare.document.service;

import com.medicare.document.entity.DocumentCategory;
import com.medicare.document.entity.MedicalDocument;
import com.medicare.document.repository.DocumentRepository;
import com.medicare.medication.Prescription;
import com.medicare.medication.PrescriptionRepository;
import com.medicare.notification.service.CareRelationships;
import java.time.Instant;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Synchronisation des ordonnances : toute ordonnance envoyée par un médecin (module Médicaments)
 * est recopiée dans les documents du patient, catégorie « Ordonnance ». Le patient la consulte dans
 * Documents ; le médecin la retrouve dans le dossier du patient. Il n'y a donc plus qu'un seul
 * endroit pour les ordonnances et les documents.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class PrescriptionDocumentSync {
    private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("dd/MM/yyyy", Locale.FRANCE);

    private final PrescriptionRepository prescriptions;
    private final DocumentRepository documents;
    private final DocumentStorageService storage;
    private final CareRelationships care;
    private final TransactionTemplate transactions;

    /** Au démarrage : recopie les ordonnances déjà enregistrées qui ne sont pas encore dans Documents. */
    @EventListener(ApplicationReadyEvent.class)
    public void syncExisting() {
        int copied = 0;
        List<Long> ids;
        try {
            // Dans une transaction : le fichier (@Lob) ne se lit pas en auto-commit sur PostgreSQL.
            ids = transactions.execute(status -> prescriptions.findIdsToCopyIntoDocuments());
        } catch (RuntimeException e) {
            log.warn("Synchronisation des ordonnances ignorée : {}", e.getMessage());
            return;
        }
        for (Long id : ids == null ? List.<Long>of() : ids) {
            try {
                Boolean done = transactions.execute(status ->
                        prescriptions.findById(id).map(fresh -> mirror(fresh, false)).orElse(false));
                if (Boolean.TRUE.equals(done)) copied++;
            } catch (RuntimeException e) {
                log.warn("Ordonnance {} non recopiée dans Documents : {}", id, e.getMessage());
            }
        }
        if (copied > 0) log.info("{} ordonnance(s) recopiée(s) dans les documents des patients.", copied);
    }

    /** Recopie (ou met à jour) l'ordonnance dans les documents du patient et le prévient. */
    @Transactional
    public void sync(Prescription prescription) {
        mirror(prescription, true);
    }

    private boolean mirror(Prescription p, boolean notify) {
        if (p.isArchived() || p.getDocumentData() == null || p.getDocumentData().length == 0) return false;
        MedicalDocument existing = p.getDocumentId() == null ? null : documents.findById(p.getDocumentId()).orElse(null);
        var stored = storage.store(filename(p), p.getDocumentData());
        String oldKey = existing == null ? null : existing.getStorageKey();
        MedicalDocument doc = existing != null ? existing : MedicalDocument.builder()
                .user(p.getPatient())
                .category(DocumentCategory.PRESCRIPTION)
                .uploadedAt(Instant.now())
                .build();
        doc.setTitle(title(p));
        doc.setDescription(description(p));
        doc.setSharedDoctor(p.getDoctor());
        doc.setOriginalFilename(stored.filename());
        doc.setStorageKey(stored.key());
        doc.setContentType(stored.contentType());
        doc.setSize(stored.size());
        doc = documents.saveAndFlush(doc);
        p.setDocumentId(doc.getId());
        prescriptions.save(p);
        if (oldKey != null && !oldKey.equals(stored.key())) {
            try { storage.delete(oldKey); } catch (RuntimeException ignored) { }
        }
        if (notify && existing == null) {
            care.notify(p.getPatient(), "Nouvelle ordonnance",
                    p.getDoctor().getFullName() + " vous a envoyé une ordonnance. Retrouvez-la dans Documents → Ordonnances.");
        }
        return true;
    }

    private static String title(Prescription p) {
        String date = p.getPrescriptionDate() == null ? "" : " du " + p.getPrescriptionDate().format(DATE);
        String title = "Ordonnance" + date + " – " + p.getDoctor().getFullName();
        return title.length() > 120 ? title.substring(0, 120) : title;
    }

    private static String description(Prescription p) {
        StringBuilder text = new StringBuilder("Ordonnance envoyée par " + p.getDoctor().getFullName());
        if (p.getDiagnosis() != null && !p.getDiagnosis().isBlank() && !"Ordonnance jointe".equals(p.getDiagnosis())) {
            text.append(". Motif : ").append(p.getDiagnosis().trim());
        }
        if (p.getNotes() != null && !p.getNotes().isBlank()) text.append(". Notes : ").append(p.getNotes().trim());
        return text.length() > 2000 ? text.substring(0, 2000) : text.toString();
    }

    /** Nom de fichier avec une extension cohérente avec le contenu (exigée par le stockage des documents). */
    private static String filename(Prescription p) {
        String type = p.getDocumentContentType() == null ? "" : p.getDocumentContentType();
        String ext = type.contains("pdf") ? "pdf" : type.contains("png") ? "png" : "jpg";
        String base = p.getDocumentName() == null || p.getDocumentName().isBlank() ? "ordonnance" : p.getDocumentName().trim();
        int dot = base.lastIndexOf('.');
        if (dot > 0) base = base.substring(0, dot);
        if (base.length() > 180) base = base.substring(0, 180);
        return base + "." + ext;
    }
}
