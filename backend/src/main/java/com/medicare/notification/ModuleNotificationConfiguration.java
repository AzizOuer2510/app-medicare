package com.medicare.notification;

import com.medicare.notification.entity.NotificationType;
import com.medicare.notification.service.CareRelationships;
import com.medicare.notification.service.NotificationService;
import com.medicare.notification.service.ModuleNotificationTargets;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.Map;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** Observes successful HTTP mutations without changing M1-M4 or their transactions. */
@Configuration
@RequiredArgsConstructor
@Slf4j
@ConditionalOnProperty(name = "app.notifications.module-events-enabled", havingValue = "true", matchIfMissing = true)
public class ModuleNotificationConfiguration implements WebMvcConfigurer {
    private final NotificationService notifications;
    private final CareRelationships care;
    private final ModuleNotificationTargets targets;
    private static final Map<String, String> MODULES = Map.of(
            "com.medicare.appointment.AppointmentController", "Rendez-vous",
            "com.medicare.appointment.SecretaryAppointmentController", "Rendez-vous",
            "com.medicare.medication.MedicationController", "Médicaments",
            "com.medicare.medication.PrescriptionController", "Médicaments",
            "com.medicare.health.HealthRecordController", "Mesures de santé",
            "com.medicare.document.controller.DocumentController", "Documents médicaux");

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(new HandlerInterceptor() {
            @Override public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
                if (!Set.of("POST", "PUT", "PATCH", "DELETE").contains(request.getMethod())) return true;
                try {
                    Long recipient = targets.existing(request.getRequestURI());
                    if (recipient != null) request.setAttribute(ModuleNotificationResponseAdvice.RECIPIENT, recipient);
                } catch (RuntimeException error) {
                    log.error("M5 could not resolve an existing module recipient ({})", error.getClass().getSimpleName());
                }
                return true;
            }
            @Override
            public void afterCompletion(HttpServletRequest request, HttpServletResponse response,
                    Object handler, Exception exception) {
                if (exception != null || response.getStatus() < 200 || response.getStatus() >= 300
                        || !Set.of("POST", "PUT", "PATCH", "DELETE").contains(request.getMethod())
                        || !(handler instanceof HandlerMethod method)) return;
                String module = MODULES.get(method.getBeanType().getName());
                if (module == null || request.getRequestURI().endsWith("/extract-medications")) return;
                var authentication = SecurityContextHolder.getContext().getAuthentication();
                if (authentication == null || !authentication.isAuthenticated()) return;
                NotificationType type = module.equals("Rendez-vous") ? NotificationType.APPOINTMENT
                        : module.equals("Médicaments") ? NotificationType.MEDICATION : NotificationType.GENERAL;
                String action = switch (request.getMethod()) {
                    case "POST" -> "Ajout enregistré";
                    case "DELETE" -> "Suppression enregistrée";
                    default -> "Modification enregistrée";
                };
                try {
                    Long recipient = (Long) request.getAttribute(ModuleNotificationResponseAdvice.RECIPIENT);
                    if (recipient == null) recipient = care.actor(authentication).getId();
                    notifications.notify(recipient, type, module, action + " : " + module + ".");
                } catch (RuntimeException failure) {
                    // A secondary notification must never turn a completed M2-M4 action into a failure.
                    log.error("M5 could not record a module notification ({})", failure.getClass().getSimpleName());
                }
            }
        }).addPathPatterns("/api/appointments/**", "/api/secretary/appointments/**", "/api/medications/**",
                "/api/prescriptions/**", "/api/health-records/**", "/api/documents/**");
    }
}
