package com.medicare.document.service;

import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class DocumentFollowUpTest {
    private final LocalDate today = LocalDate.of(2026, 11, 18);

    @Test
    void extractsTheExplicitAppointmentAndPreservesItsSource() {
        String line = "Prochain rendez-vous : 15/12/2030";
        var match = LocalDocumentModel.findAppointment("Date du document : 18/11/2026\n" + line, today);
        assertEquals(LocalDate.of(2030, 12, 15), match.date());
        assertEquals(line, match.line());
        assertEquals(match.date(), LocalDocumentModel.findAppointment("Contrôle le 15 décembre 2030", today).date());
    }

    @Test
    void omitsAmbiguousInvalidCancelledOrPastDates() {
        for (String text : new String[]{"RDV le 15/12/2030\nSuivi le 18/12/2030",
                "RDV le 31/02/2030", "Prochain contrôle dans 3 mois",
                "Pas de suivi le 15/12/2030", "RDV le 15/12/2030 annulé", "RDV le 15/12/2022"}) {
            assertNull(LocalDocumentModel.findAppointment(text, today), text);
        }
    }
}
