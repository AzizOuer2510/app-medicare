package com.medicare.document;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/** This dedicated chain leaves the existing account authentication unchanged. */
@Configuration
public class DocumentShareSecurityConfiguration {
    @Bean
    @Order(1)
    public SecurityFilterChain documentShareSecurity(HttpSecurity http) throws Exception {
        return http.securityMatcher("/share/document", "/share/document/**", "/api/document-shares/access")
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.GET, "/share/document", "/share/document/style.css", "/share/document/app.js").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/document-shares/access").permitAll()
                        .anyRequest().denyAll())
                .headers(headers -> headers
                        .contentSecurityPolicy(csp -> csp.policyDirectives("default-src 'none'; script-src 'self'; style-src 'self'; "
                                + "connect-src 'self'; img-src blob:; frame-src blob:; object-src 'none'; base-uri 'none'; "
                                + "form-action 'none'; frame-ancestors 'none'"))
                        .addHeaderWriter((request, response) -> {
                            response.setHeader("Referrer-Policy", "no-referrer");
                            response.setHeader("Cache-Control", "no-store");
                            response.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
                            response.setHeader("X-Robots-Tag", "noindex, nofollow, noarchive");
                        }))
                .build();
    }
}
