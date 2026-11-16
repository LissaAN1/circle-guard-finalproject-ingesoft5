package com.circleguard.dashboard.client;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;

/**
 * HU-14: HTTP client for promotion-service with explicit timeouts. Without them a hung
 * promotion-service blocks the dashboard request indefinitely and the Circuit Breaker never sees it.
 */
@Configuration
public class PromotionClientConfig {

    @Bean
    public RestTemplate promotionRestTemplate(
            RestTemplateBuilder builder,
            @Value("${circleguard.promotion-service.http.connect-timeout:2s}") Duration connectTimeout,
            @Value("${circleguard.promotion-service.http.read-timeout:5s}") Duration readTimeout) {
        return builder
                .setConnectTimeout(connectTimeout)
                .setReadTimeout(readTimeout)
                .build();
    }
}
