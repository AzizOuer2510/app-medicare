package com.medicare.document;

import org.springframework.context.annotation.Configuration;

@Configuration
public class DocumentConfiguration {
    // Reuse the destination application's multipart resolver and configured
    // 10 MB / 11 MB limits, including for the existing M3 prescription endpoints.
}
