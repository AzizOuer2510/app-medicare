package com.medicare.common;

import java.time.Instant;
import java.util.Map;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.*;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.support.MissingServletRequestPartException;

// Keep request-error handling local to M5; other modules retain their current behavior.
@RestControllerAdvice(basePackages = {"com.medicare.notification.controller", "com.medicare.document.controller"})
@Order(Ordered.HIGHEST_PRECEDENCE)
public class NotificationDocumentExceptionHandler {
    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<GlobalExceptionHandler.ErrorResponse> tooLarge(MaxUploadSizeExceededException ex) {
        return error(HttpStatus.PAYLOAD_TOO_LARGE, "Document exceeds the maximum file size");
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class,
            MissingServletRequestParameterException.class, MissingServletRequestPartException.class})
    public ResponseEntity<GlobalExceptionHandler.ErrorResponse> invalidRequest(Exception ex) {
        return error(HttpStatus.BAD_REQUEST, "Invalid request parameters or missing file");
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    public ResponseEntity<GlobalExceptionHandler.ErrorResponse> unsupportedMedia(Exception ex) {
        return error(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "Unsupported request content type");
    }

    private ResponseEntity<GlobalExceptionHandler.ErrorResponse> error(HttpStatus status, String message) {
        return ResponseEntity.status(status).body(new GlobalExceptionHandler.ErrorResponse(
                Instant.now(), status.value(), status.getReasonPhrase(), message, Map.of()));
    }
}
