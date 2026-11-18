package com.medicare.reminder;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;

@Slf4j
@Component
public class SmsReminderSender {

    private final RestClient restClient = RestClient.create("https://api.twilio.com");
    private final String accountSid;
    private final String authToken;
    private final String fromNumber;
    private final String defaultCountryCode;

    public SmsReminderSender(@Value("${app.reminders.sms.twilio-account-sid:}") String accountSid,
                             @Value("${app.reminders.sms.twilio-auth-token:}") String authToken,
                             @Value("${app.reminders.sms.twilio-from:}") String fromNumber,
                             @Value("${app.reminders.sms.default-country-code:+33}") String defaultCountryCode) {
        this.accountSid = accountSid;
        this.authToken = authToken;
        this.fromNumber = fromNumber;
        this.defaultCountryCode = defaultCountryCode;
    }

    /** Returns true when the SMS was accepted by Twilio (or simulated when Twilio is not configured). */
    public boolean send(String rawPhone, String body) {
        String to = toE164(rawPhone);
        if (to == null) {
            return false;
        }
        if (accountSid.isBlank() || authToken.isBlank() || fromNumber.isBlank()) {
            log.info("[SIMULATION SMS] to={}\n{}", to, body);
            return true;
        }
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("To", to);
        form.add("From", fromNumber);
        form.add("Body", body);
        try {
            restClient.post()
                    .uri("/2010-04-01/Accounts/{sid}/Messages.json", accountSid)
                    .headers(h -> h.setBasicAuth(accountSid, authToken))
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(form)
                    .retrieve()
                    .toBodilessEntity();
            return true;
        } catch (Exception ex) {
            log.warn("Echec envoi SMS de rappel a {} : {}", to, ex.getMessage());
            return false;
        }
    }

    // Accepts "06 12 34 56 78", "0612345678" or "+33612345678".
    String toE164(String raw) {
        if (raw == null) {
            return null;
        }
        String digits = raw.replaceAll("[\\s.\\-()]", "");
        if (digits.matches("\\+\\d{8,15}")) {
            return digits;
        }
        if (digits.matches("00\\d{8,15}")) {
            return "+" + digits.substring(2);
        }
        if (digits.matches("0\\d{9}")) {
            return defaultCountryCode + digits.substring(1);
        }
        return null;
    }
}
