package com.medicare.medication;

import org.junit.jupiter.api.Test;

import javax.imageio.ImageIO;
import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;

import static org.assertj.core.api.Assertions.assertThat;

class PrescriptionOcrServiceTest {
    @Test
    void recognizesMedicationTextLocallyFromAnImage() throws Exception {
        BufferedImage image = new BufferedImage(2600, 320, BufferedImage.TYPE_INT_RGB);
        Graphics2D graphics = image.createGraphics();
        graphics.setColor(Color.WHITE);
        graphics.fillRect(0, 0, image.getWidth(), image.getHeight());
        graphics.setColor(Color.BLACK);
        graphics.setFont(new Font(Font.SANS_SERIF, Font.BOLD, 72));
        graphics.drawString(
                "Amoxicilline 500 mg 1 gelule matin et soir tous les jours",
                24,
                180);
        graphics.dispose();

        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        ImageIO.write(image, "png", bytes);
        image.flush();

        PrescriptionOcrService service = new PrescriptionOcrService(
                new PrescriptionMedicationParser());
        var result = service.extract(bytes.toByteArray(), "image/png");

        assertThat(result.medications()).hasSize(1);
        assertThat(result.medications().getFirst().name())
                .containsIgnoringCase("amoxicilline");
        assertThat(result.medications().getFirst().dosage()).isEqualTo("500 mg");
        assertThat(result.medications().getFirst().reminderTimes()).isEmpty();
    }
}
