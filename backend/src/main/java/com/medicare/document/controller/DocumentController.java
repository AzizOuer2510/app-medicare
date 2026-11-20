package com.medicare.document.controller;

import com.medicare.document.dto.DocumentDtos;
import com.medicare.document.entity.DocumentCategory;
import com.medicare.document.service.DocumentService;
import jakarta.validation.Valid;
import java.nio.charset.StandardCharsets;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.http.*;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/documents")
@RequiredArgsConstructor
public class DocumentController {
    private final DocumentService service;

    @GetMapping
    public List<DocumentDtos.DocumentResponse> list(Authentication authentication,
            @RequestParam(required = false) DocumentCategory category,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) Boolean favorite,
            @RequestParam(defaultValue = "recent") String sort,
            @RequestParam(required = false) Long patientId) {
        return service.list(authentication, category, q, favorite, sort, patientId);
    }

    @GetMapping("/{id}")
    public DocumentDtos.DocumentResponse get(Authentication authentication, @PathVariable Long id) {
        return service.get(authentication, id);
    }

    @GetMapping("/overview")
    public DocumentDtos.Overview overview(Authentication authentication) {
        return service.overview(authentication);
    }

    @PutMapping("/{id}")
    public DocumentDtos.DocumentResponse update(Authentication authentication, @PathVariable Long id,
            @Valid @RequestBody DocumentDtos.UploadRequest request) {
        return service.update(authentication, id, request);
    }

    @PatchMapping("/{id}/favorite")
    public DocumentDtos.DocumentResponse favorite(Authentication authentication, @PathVariable Long id,
            @Valid @RequestBody DocumentDtos.FavoriteRequest request) {
        return service.favorite(authentication, id, request.favorite());
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public DocumentDtos.DocumentResponse upload(Authentication authentication,
            @Valid @ModelAttribute DocumentDtos.UploadRequest request,
            @RequestPart("file") MultipartFile file) {
        return service.upload(authentication, request, file);
    }

    @GetMapping("/{id}/content")
    public ResponseEntity<byte[]> content(Authentication authentication, @PathVariable Long id,
                                          @RequestParam(defaultValue = "false") boolean download) {
        DocumentDtos.DocumentContent content = service.content(authentication, id);
        ContentDisposition disposition = (download ? ContentDisposition.attachment() : ContentDisposition.inline())
                .filename(content.filename(), StandardCharsets.UTF_8).build();
        return ResponseEntity.ok().contentType(MediaType.parseMediaType(content.contentType()))
                .contentLength(content.bytes().length)
                .header(HttpHeaders.CONTENT_DISPOSITION, disposition.toString())
                .header(HttpHeaders.CACHE_CONTROL, "no-store")
                .header("X-Content-Type-Options", "nosniff")
                .body(content.bytes());
    }

    @PutMapping("/{id}/doctor")
    public void shareWithDoctor(Authentication auth,@PathVariable Long id,@RequestParam boolean enabled,
                                @RequestParam(required=false) Long doctorId) {
        service.shareWithDoctor(auth,id,enabled,doctorId);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(Authentication authentication, @PathVariable Long id) {
        service.delete(authentication, id);
    }
}
