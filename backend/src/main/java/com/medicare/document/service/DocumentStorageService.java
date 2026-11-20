package com.medicare.document.service;

import com.medicare.common.ApiException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.Arrays;
import java.util.Locale;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

@Service
public class DocumentStorageService {
    private final Path root;
    private final long maxFileSize;

    public record StoredFile(String key, String filename, String contentType, long size) {}

    public DocumentStorageService(
            @Value("${app.documents.storage-path:./storage/documents}") String storagePath,
            @Value("${app.documents.max-file-size:10485760}") long maxFileSize) {
        this.root = Path.of(storagePath).toAbsolutePath().normalize();
        this.maxFileSize = maxFileSize;
    }

    public StoredFile store(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "A non-empty file is required");
        }
        if (file.getSize() > maxFileSize) {
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "Document exceeds the maximum file size");
        }
        try {
            return store(file.getOriginalFilename(), file.getBytes());
        } catch (IOException ex) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Document could not be stored");
        }
    }

    /** Enregistre un fichier déjà en mémoire (ex. ordonnance recopiée du module Médicaments). */
    public StoredFile store(String originalFilename, byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "A non-empty file is required");
        }
        if (bytes.length > maxFileSize) {
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "Document exceeds the maximum file size");
        }
        String filename = cleanFilename(originalFilename);
        int dot = filename.lastIndexOf('.');
        String extension = dot < 0 ? "" : filename.substring(dot + 1).toLowerCase(Locale.ROOT);
        if (!Arrays.asList("pdf", "png", "jpg", "jpeg").contains(extension)) {
            throw new ApiException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "Only PDF, PNG and JPEG documents are accepted");
        }
        try {
            String contentType = detectContentType(bytes);
            boolean matches = switch (extension) {
                case "pdf" -> "application/pdf".equals(contentType);
                case "png" -> "image/png".equals(contentType);
                default -> "image/jpeg".equals(contentType);
            };
            if (!matches) {
                throw new ApiException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "File content does not match its extension");
            }
            String key = UUID.randomUUID() + "." + extension;
            Files.createDirectories(root);
            Path destination = resolve(key);
            try {
                Files.write(destination, bytes, StandardOpenOption.CREATE_NEW);
            } catch (IOException ex) {
                Files.deleteIfExists(destination);
                throw ex;
            }
            return new StoredFile(key, filename, contentType, bytes.length);
        } catch (IOException ex) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Document could not be stored");
        }
    }

    public byte[] read(String key) {
        try {
            Path path = resolve(key);
            if (!Files.isRegularFile(path)) {
                throw new ApiException(HttpStatus.NOT_FOUND, "Document file not found");
            }
            return Files.readAllBytes(path);
        } catch (IOException ex) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Document could not be read");
        }
    }

    public void delete(String key) {
        try {
            Files.deleteIfExists(resolve(key));
        } catch (IOException ex) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Document file could not be deleted");
        }
    }

    private Path resolve(String key) {
        if (key == null || !key.matches("[0-9a-fA-F-]{36}\\.(pdf|png|jpg|jpeg)")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid document storage key");
        }
        Path path = root.resolve(key).normalize();
        if (!path.getParent().equals(root)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid document storage path");
        }
        return path;
    }

    private String cleanFilename(String original) {
        if (original == null) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "File name is required");
        }
        String filename = original.replace('\\', '/');
        filename = filename.substring(filename.lastIndexOf('/') + 1).replaceAll("[\\p{Cntrl}]", "").trim();
        if (filename.isEmpty() || filename.length() > 200) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "File name must contain between 1 and 200 characters");
        }
        return filename;
    }

    private String detectContentType(byte[] bytes) {
        if (bytes.length >= 5 && new String(bytes, 0, 5, StandardCharsets.US_ASCII).equals("%PDF-")) {
            return "application/pdf";
        }
        byte[] png = {(byte) 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a};
        if (bytes.length >= png.length && Arrays.equals(Arrays.copyOf(bytes, png.length), png)) {
            return "image/png";
        }
        if (bytes.length >= 3 && bytes[0] == (byte) 0xff && bytes[1] == (byte) 0xd8 && bytes[2] == (byte) 0xff) {
            return "image/jpeg";
        }
        return "application/octet-stream";
    }
}
