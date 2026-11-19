package com.medicare.document.controller;

import com.medicare.document.dto.DocumentShareDtos.AccessRequest;
import com.medicare.document.service.DocumentShareService;
import jakarta.validation.Valid;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.Resource;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

@RestController
@RequiredArgsConstructor
public class SharedDocumentController {
    private final DocumentShareService service;

    @GetMapping(value = "/share/document", produces = MediaType.TEXT_HTML_VALUE)
    public Resource page() { return new ClassPathResource("document-share/index.html"); }
    @GetMapping(value = "/share/document/style.css", produces = "text/css")
    public Resource style() { return new ClassPathResource("document-share/style.css"); }
    @GetMapping(value = "/share/document/app.js", produces = "application/javascript")
    public Resource script() { return new ClassPathResource("document-share/app.js"); }

    @PostMapping(value = "/api/document-shares/access", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<byte[]> access(@Valid @RequestBody AccessRequest request) {
        var result = service.access(request);
        var content = result.content();
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(content.contentType()))
                .contentLength(content.bytes().length)
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.inline()
                        .filename(content.filename(), StandardCharsets.UTF_8).build().toString())
                .header("X-Document-Filename", URLEncoder.encode(content.filename(), StandardCharsets.UTF_8))
                .header("X-Share-Expires-At", result.expiresAt().toString())
                .header(HttpHeaders.CACHE_CONTROL, "no-store")
                .body(content.bytes());
    }
}
