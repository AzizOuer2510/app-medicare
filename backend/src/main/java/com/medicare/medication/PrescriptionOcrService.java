package com.medicare.medication;

import net.sourceforge.tess4j.Tesseract;
import net.sourceforge.tess4j.TesseractException;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Iterator;
import java.util.List;

@Service
public class PrescriptionOcrService {
    private static final int MAX_PDF_PAGES = 10;
    private static final long MAX_IMAGE_PIXELS = 20_000_000L;
    private static final String[] LANGUAGE_MODELS = {"eng.traineddata", "fra.traineddata"};

    private final PrescriptionMedicationParser parser;
    private volatile Path tessdataDirectory;

    public PrescriptionOcrService(PrescriptionMedicationParser parser) {
        this.parser = parser;
    }

    public PrescriptionMedicationParser.ExtractionResult extract(byte[] document, String contentType) {
        try {
            StringBuilder text = new StringBuilder();
            if ("application/pdf".equalsIgnoreCase(contentType)) {
                recognizePdf(document, text);
            } else if ("image/jpeg".equalsIgnoreCase(contentType)
                    || "image/png".equalsIgnoreCase(contentType)) {
                try (ImageInputStream input = ImageIO.createImageInputStream(
                        new ByteArrayInputStream(document))) {
                    if (input == null) {
                        throw new ResponseStatusException(
                                HttpStatus.UNPROCESSABLE_ENTITY, "The ordonnance image could not be read");
                    }
                    Iterator<ImageReader> readers = ImageIO.getImageReaders(input);
                    if (!readers.hasNext()) {
                        throw new ResponseStatusException(
                                HttpStatus.UNPROCESSABLE_ENTITY, "The ordonnance image could not be read");
                    }
                    ImageReader reader = readers.next();
                    try {
                        reader.setInput(input, true, true);
                        ensureImageSize(reader.getWidth(0), reader.getHeight(0));
                        BufferedImage image = reader.read(0);
                        if (image == null) {
                            throw new ResponseStatusException(
                                    HttpStatus.UNPROCESSABLE_ENTITY, "The ordonnance image could not be read");
                        }
                        text.append(recognize(image));
                        image.flush();
                    } finally {
                        reader.dispose();
                    }
                }
            } else {
                throw new ResponseStatusException(
                        HttpStatus.UNSUPPORTED_MEDIA_TYPE, "Only PDF, JPEG and PNG are supported");
            }
            return parser.parse(text.toString());
        } catch (ResponseStatusException error) {
            throw error;
        } catch (IOException error) {
            throw new ResponseStatusException(
                    HttpStatus.UNPROCESSABLE_ENTITY, "The ordonnance document could not be read");
        } catch (TesseractException error) {
            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE, "Local ordonnance OCR could not process this document");
        }
    }

    private void recognizePdf(byte[] document, StringBuilder text) throws IOException, TesseractException {
        try (PDDocument pdf = Loader.loadPDF(document)) {
            int pageCount = pdf.getNumberOfPages();
            if (pageCount == 0) {
                throw new ResponseStatusException(
                        HttpStatus.UNPROCESSABLE_ENTITY, "The ordonnance PDF contains no pages");
            }
            if (pageCount > MAX_PDF_PAGES) {
                throw new ResponseStatusException(
                        HttpStatus.PAYLOAD_TOO_LARGE, "OCR supports up to 10 pages per ordonnance");
            }
            PDFRenderer renderer = new PDFRenderer(pdf);
            for (int page = 0; page < pageCount; page++) {
                PDPage pdfPage = pdf.getPage(page);
                double scale = 200.0 / 72.0;
                ensureImageSize(
                        (int) Math.ceil(pdfPage.getCropBox().getWidth() * scale),
                        (int) Math.ceil(pdfPage.getCropBox().getHeight() * scale));
                BufferedImage image = renderer.renderImageWithDPI(page, 200);
                text.append(recognize(image)).append('\n');
                image.flush();
            }
        }
    }

    private void ensureImageSize(int width, int height) {
        if (width <= 0 || height <= 0 || (long) width * height > MAX_IMAGE_PIXELS) {
            throw new ResponseStatusException(
                    HttpStatus.PAYLOAD_TOO_LARGE, "The ordonnance image resolution is too large for OCR");
        }
    }

    private String recognize(BufferedImage image) throws TesseractException {
        Tesseract engine = new Tesseract();
        engine.setDatapath(tessdataDirectory().toString());
        engine.setLanguage("fra+eng");
        engine.setOcrEngineMode(1);
        engine.setPageSegMode(6);
        return engine.doOCR(image);
    }

    private Path tessdataDirectory() {
        Path current = tessdataDirectory;
        if (current != null) return current;
        synchronized (this) {
            if (tessdataDirectory != null) return tessdataDirectory;
            try {
                Path directory = Files.createTempDirectory("medicare-tessdata-");
                directory.toFile().deleteOnExit();
                for (String model : LANGUAGE_MODELS) {
                    String resource = "/tessdata/" + model;
                    try (InputStream input = PrescriptionOcrService.class.getResourceAsStream(resource)) {
                        if (input == null) {
                            throw new ResponseStatusException(
                                    HttpStatus.SERVICE_UNAVAILABLE,
                                    "Local OCR language data is missing: " + model);
                        }
                        Path modelPath = directory.resolve(model);
                        Files.copy(input, modelPath, StandardCopyOption.REPLACE_EXISTING);
                        modelPath.toFile().deleteOnExit();
                    }
                }
                tessdataDirectory = directory;
                return directory;
            } catch (IOException error) {
                throw new ResponseStatusException(
                        HttpStatus.SERVICE_UNAVAILABLE, "Local OCR language data could not be prepared");
            }
        }
    }
}
