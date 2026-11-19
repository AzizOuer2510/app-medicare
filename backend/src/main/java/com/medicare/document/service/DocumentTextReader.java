package com.medicare.document.service;

import java.awt.image.BufferedImage;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.concurrent.TimeUnit;
import javax.imageio.ImageIO;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.rendering.PDFRenderer;
import org.apache.pdfbox.text.PDFTextStripper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class DocumentTextReader {
    private final String executable;
    public DocumentTextReader(@Value("${app.analysis.tesseract:tesseract}") String executable) {
        this.executable = executable;
    }

    public String read(String type, byte[] bytes) throws Exception {
        String text;
        if ("application/pdf".equals(type)) {
            try (var pdf = Loader.loadPDF(bytes)) {
                if (pdf.getNumberOfPages() > 12) throw new IOException("Limite de 12 pages dépassée.");
                var renderer = new PDFRenderer(pdf);
                renderer.setSubsamplingAllowed(true);
                var result = new StringBuilder();
                var stripper = new PDFTextStripper();
                for (int i = 0; i < pdf.getNumberOfPages(); i++) {
                    stripper.setStartPage(i+1);
                    stripper.setEndPage(i+1);
                    String page = stripper.getText(pdf).strip();
                    if (page.length() < 20) {
                        var box = pdf.getPage(i).getCropBox();
                        float scale = Math.min(2.5f, 2200f / Math.max(box.getWidth(), box.getHeight()));
                        BufferedImage image = renderer.renderImage(i, scale);
                        var buffer = new ByteArrayOutputStream();
                        ImageIO.write(image, "png", buffer);
                        image.flush();
                        page = ocr(buffer.toByteArray());
                    }
                    result.append(page).append('\n');
                    if (result.length() > 8000) throw new IOException("Texte trop long.");
                }
                text = result.toString();
            }
        } else {
            try (var stream = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
                var readers = ImageIO.getImageReaders(stream);
                if (!readers.hasNext()) throw new IOException("Image illisible.");
                var reader = readers.next();
                try {
                    reader.setInput(stream);
                    if ((long)reader.getWidth(0)*reader.getHeight(0)>24_000_000) throw new IOException("Image trop grande.");
                } finally { reader.dispose(); }
            }
            text = ocr(bytes);
        }
        if (text.strip().length()<8 || text.length()>8000) throw new IOException("Texte illisible ou trop long.");
        return text.strip();
    }

    private String ocr(byte[] bytes) throws Exception {
        Path input = Files.createTempFile("medicare-ocr-", ".img");
        Path output = Path.of(input + ".txt");
        Process worker = null;
        try {
            Files.write(input, bytes);
            worker = new ProcessBuilder(executable, input.toString(), input.toString(), "-l", "fra+eng")
                    .redirectError(ProcessBuilder.Redirect.DISCARD).redirectOutput(ProcessBuilder.Redirect.DISCARD).start();
            if (!worker.waitFor(25, TimeUnit.SECONDS) || worker.exitValue()!=0 || !Files.exists(output)
                    || Files.size(output)>64000) throw new IOException("Lecture OCR impossible.");
            return Files.readString(output, StandardCharsets.UTF_8);
        } finally {
            if (worker != null && worker.isAlive()) worker.destroyForcibly().waitFor();
            Files.deleteIfExists(output);
            Files.deleteIfExists(input);
        }
    }
}
