package com.circleguard.auth.client;

import java.time.Duration;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

/**
 * HU-14: HTTP client for identity-service with explicit timeouts. Without them a hung identity-service
 * blocks the login thread indefinitely and the Circuit Breaker never sees the failure.
 */
@Configuration
public class IdentityClientConfig {

    @Bean
    public RestTemplate identityRestTemplate(
            RestTemplateBuilder builder,
            @Value("${identity.http.connect-timeout:2s}") Duration connectTimeout,
            @Value("${identity.http.read-timeout:3s}") Duration readTimeout) {
        return builder
                .setConnectTimeout(connectTimeout)
                .setReadTimeout(readTimeout)
                .build();
    }
}
