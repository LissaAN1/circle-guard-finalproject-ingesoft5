package com.circleguard.dashboard.client;

import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.*;

/**
 * Client of promotion-service for the health statistics shown in the dashboard.
 *
 * <p>HU-14: both calls are protected with a Circuit Breaker and a Retry (instance "promotion",
 * configured in resilience4j.yml). Resilience4j applies Retry outside the Circuit Breaker, so every
 * attempt is recorded by the circuit and, once it opens, the dashboard answers immediately with the
 * degraded response instead of waiting on promotion-service. The fallback lives on the Retry so that
 * it runs only after the retries are exhausted.
 */
@Component
@Slf4j
public class PromotionClient {

    static final String INSTANCE = "promotion";

    private final RestTemplate restTemplate;
    private final String promotionServiceUrl;

    public PromotionClient(@Qualifier("promotionRestTemplate") RestTemplate restTemplate,
                           @Value("${circleguard.promotion-service.url:http://localhost:8088}") String promotionServiceUrl) {
        this.restTemplate = restTemplate;
        this.promotionServiceUrl = promotionServiceUrl;
    }

    @SuppressWarnings("unchecked")
    @CircuitBreaker(name = INSTANCE)
    @Retry(name = INSTANCE, fallbackMethod = "healthStatsFallback")
    public Map<String, Object> getHealthStats() {
        return restTemplate.getForObject(
                promotionServiceUrl + "/api/v1/health-status/stats",
                Map.class
        );
    }

    @SuppressWarnings("unchecked")
    @CircuitBreaker(name = INSTANCE)
    @Retry(name = INSTANCE, fallbackMethod = "departmentStatsFallback")
    public Map<String, Object> getHealthStatsByDepartment(String department) {
        return restTemplate.getForObject(
                promotionServiceUrl + "/api/v1/health-status/stats/department/" + department,
                Map.class
        );
    }

    /**
     * Fallback: the dashboard is read-only, so it degrades to an explicit "unavailable" payload instead
     * of failing the request. The payload keeps the previous contract (error + timestamp) and adds
     * {@code degraded=true} so the client can tell it apart from real statistics.
     */
    @SuppressWarnings("unused")
    private Map<String, Object> healthStatsFallback(Throwable cause) {
        logFallback("health stats", cause);
        return degraded(null);
    }

    @SuppressWarnings("unused")
    private Map<String, Object> departmentStatsFallback(String department, Throwable cause) {
        logFallback("department stats", cause);
        return degraded(department);
    }

    private static Map<String, Object> degraded(String department) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("error", "Service unavailable");
        body.put("degraded", true);
        if (department != null) {
            body.put("department", department);
        }
        body.put("timestamp", new Date());
        return body;
    }

    private static void logFallback(String what, Throwable cause) {
        if (cause instanceof CallNotPermittedException) {
            log.warn("promotion-service circuit is open; serving degraded {}", what);
        } else {
            log.error("Failed to fetch {} from promotion-service: {}", what, cause.toString());
        }
    }
}
