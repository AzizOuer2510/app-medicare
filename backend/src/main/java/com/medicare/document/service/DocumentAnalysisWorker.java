package com.medicare.document.service;

import com.medicare.document.dto.AnalysisDtos.Draft;
import jakarta.annotation.PreDestroy;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component @RequiredArgsConstructor
@ConditionalOnProperty(name="app.analysis.worker-enabled",matchIfMissing=true,havingValue="true")
public class DocumentAnalysisWorker {
    private final DocumentAnalysisService service;
    private final DocumentTextReader reader;
    private final DocumentStorageService storage;
    private final LocalDocumentModel model;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicBoolean busy = new AtomicBoolean();
    @Scheduled(fixedDelay=2000)
    public void tick() {
        if (busy.compareAndSet(false,true)) executor.submit(() -> {
            try { service.claim().ifPresent(this::process); }
            finally { busy.set(false); }
        });
    }
    private void process(DocumentAnalysisService.Work work) {
        String source;
        try { source = reader.read(work.type(),storage.read(work.storageKey())); }
        catch (Exception e) {
            service.finish(work,null,"Lecture impossible. Vérifiez le fichier, sa taille et la configuration OCR.");
            return;
        }
        Draft draft;
        try { draft = model.analyze(source); }
        catch (Exception e) {
            service.finish(work,null,"Le modèle local est indisponible ou sa réponse est incomplète. Réessayez.");
            return;
        }
        service.finish(work,draft,null);
    }
    @PreDestroy public void shutdown() { executor.shutdownNow(); }
}
