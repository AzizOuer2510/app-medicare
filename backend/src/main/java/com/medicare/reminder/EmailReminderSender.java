package com.medicare.reminder;

import java.util.Optional;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class EmailReminderSender {

    private final Optional<JavaMailSender> mailSender;
    private final String from;

    public EmailReminderSender(ObjectProvider<JavaMailSender> mailSender,
                               @Value("${app.mail.from:no-reply@medicare.local}") String from,
                               @Value("${spring.mail.host:}") String mailHost) {
        this.mailSender = mailHost == null || mailHost.isBlank()
                ? Optional.empty()
                : Optional.ofNullable(mailSender.getIfAvailable());
        this.from = from;
    }

    /** Returns true when the email was handed to the SMTP server (or simulated when SMTP is not configured). */
    public boolean send(String to, String subject, String body) {
        if (to == null || to.isBlank()) {
            return false;
        }
        if (mailSender.isEmpty()) {
            log.info("[SIMULATION EMAIL] to={} subject={}\n{}", to, subject, body);
            return true;
        }
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(from);
            message.setTo(to);
            message.setSubject(subject);
            message.setText(body);
            mailSender.get().send(message);
            return true;
        } catch (Exception ex) {
            log.warn("Echec envoi email de rappel a {} : {}", to, ex.getMessage());
            return false;
        }
    }
}
