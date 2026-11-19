package com.medicare.notification;

import com.medicare.appointment.AppointmentDtos;
import com.medicare.health.HealthRecord;
import com.medicare.medication.MedicationController;
import com.medicare.medication.PrescriptionController;
import com.medicare.notification.service.ModuleNotificationTargets;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.MethodParameter;
import org.springframework.http.MediaType;
import org.springframework.http.converter.HttpMessageConverter;
import org.springframework.http.server.*;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseBodyAdvice;

/** Retains the original response and identifies the patient from server-owned results. */
@RestControllerAdvice
@RequiredArgsConstructor
@Slf4j
public class ModuleNotificationResponseAdvice implements ResponseBodyAdvice<Object> {
    public static final String RECIPIENT = ModuleNotificationResponseAdvice.class.getName() + ".recipient";
    private final ModuleNotificationTargets targets;

    @Override public boolean supports(MethodParameter method, Class<? extends HttpMessageConverter<?>> converter) {
        return method.getDeclaringClass().getPackageName().matches("com\\.medicare\\.(appointment|medication|health)");
    }

    @Override public Object beforeBodyWrite(Object body, MethodParameter method, MediaType type,
            Class<? extends HttpMessageConverter<?>> converter, ServerHttpRequest request, ServerHttpResponse response) {
        if (!(request instanceof ServletServerHttpRequest servlet)
                || !java.util.Set.of("POST", "PUT", "PATCH", "DELETE").contains(servlet.getServletRequest().getMethod())) return body;
        try {
            Long recipient = null;
            if (body instanceof AppointmentDtos.AppointmentResponse appointment) recipient = appointment.user().id();
            else if (body instanceof AppointmentDtos.SecretaryAppointmentResponse appointment) recipient = appointment.patientId();
            else if (body instanceof HealthRecord record) recipient = record.getUser().getId();
            else if (body instanceof MedicationController.MedicationResponse medication) recipient = targets.medication(medication.id());
            else if (body instanceof MedicationController.IntakeResponse intake) recipient = targets.medication(intake.medicationId());
            else if (body instanceof MedicationController.StockResponse stock) recipient = targets.medication(stock.medicationId());
            else if (body instanceof PrescriptionController.PrescriptionResponse prescription) recipient = prescription.patientId();
            if (recipient != null) servlet.getServletRequest().setAttribute(RECIPIENT, recipient);
        } catch (RuntimeException error) {
            log.error("M5 could not identify a module notification recipient ({})", error.getClass().getSimpleName());
        }
        return body;
    }
}
