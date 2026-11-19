package com.medicare.document.controller;

import com.medicare.document.dto.DocumentShareDtos.*;
import com.medicare.document.service.DocumentShareService;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import java.net.URI;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.support.ServletUriComponentsBuilder;

@RestController
@RequestMapping("/api/documents/{documentId}/shares")
@RequiredArgsConstructor
public class DocumentShareController {
    private final DocumentShareService service;
    @Value("${app.documents.share-base-url:}")
    private String configuredBaseUrl;

    @ModelAttribute
    public void noCache(HttpServletResponse response) { response.setHeader("Cache-Control", "no-store"); }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public CreatedShare create(Authentication authentication, @PathVariable Long documentId,
                               @Valid @RequestBody CreateRequest request) {
        String baseUrl = configuredBaseUrl.isBlank()
                ? ServletUriComponentsBuilder.fromCurrentContextPath().build().toUriString()
                : configuredBaseUrl.replaceAll("/+$", "");
        URI uri = URI.create(baseUrl);
        if (!List.of("http", "https").contains(uri.getScheme()) || uri.getHost() == null
                || uri.getUserInfo() != null || uri.getFragment() != null || uri.getQuery() != null) {
            throw new IllegalStateException("Invalid document sharing base URL configuration");
        }
        return service.create(authentication, documentId, request, baseUrl);
    }

    @GetMapping
    public List<ShareResponse> list(Authentication authentication, @PathVariable Long documentId) {
        return service.list(authentication, documentId);
    }

    @PatchMapping("/{shareId}/revoke")
    public ShareResponse revoke(Authentication authentication, @PathVariable Long documentId, @PathVariable Long shareId) {
        return service.revoke(authentication, documentId, shareId);
    }

    @GetMapping("/{shareId}/accesses")
    public List<AccessResponse> history(Authentication authentication, @PathVariable Long documentId, @PathVariable Long shareId) {
        return service.history(authentication, documentId, shareId);
    }
}
