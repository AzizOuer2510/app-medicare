package com.medicare.document.controller;

import com.medicare.document.dto.AnalysisDtos.*;
import com.medicare.document.service.DocumentAnalysisService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

@RestController @RequiredArgsConstructor
@RequestMapping("/api/documents/{id}/analysis")
public class DocumentAnalysisController {
    private final DocumentAnalysisService service;
    @PostMapping @ResponseStatus(HttpStatus.ACCEPTED)
    public Result request(Authentication auth,@PathVariable Long id) { return service.request(auth,id); }
    @GetMapping
    public Result state(Authentication auth,@PathVariable Long id) { return service.get(auth,id); }
    @PostMapping("/confirm")
    public Result confirm(Authentication auth,@PathVariable Long id,@RequestBody @Valid Review review) {
        return service.confirm(auth,id,review);
    }
}
