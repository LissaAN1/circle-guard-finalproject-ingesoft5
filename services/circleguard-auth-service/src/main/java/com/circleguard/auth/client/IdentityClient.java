package com.circleguard.auth.client;

import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;

/**
 * Client of identity-service, which maps a real identity to its anonymous id.
 *
 * <p>HU-14: protected with a Circuit Breaker and a Retry (instance "identity", configured in
 * resilience4j.yml). Resilience4j applies Retry outside the Circuit Breaker, so every attempt is
 * recorded by the circuit and, once it opens, the call fails fast without reaching identity-service.
 * The fallback lives on the Retry so that it runs only after the retries are exhausted.
 */
@Component
public class IdentityClient {

    static final String INSTANCE = "identity";

    private static final Logger log = LoggerFactory.getLogger(IdentityClient.class);

    private final RestTemplate restTemplate;
    private final String identityUrl;

    public IdentityClient(@Qualifier("identityRestTemplate") RestTemplate restTemplate,
                          @Value("${identity.api.url}") String identityUrl) {
        this.restTemplate = restTemplate;
        this.identityUrl = identityUrl;
    }

    @CircuitBreaker(name = INSTANCE)
    @Retry(name = INSTANCE, fallbackMethod = "anonymousIdFallback")
    public UUID getAnonymousId(String realIdentity) {
        Map<String, String> request = Map.of("realIdentity", realIdentity);
        Map<?, ?> response = restTemplate.postForObject(
            identityUrl + "/api/v1/identities/map",
            request,
            Map.class
        );
        if (response == null || response.get("anonymousId") == null) {
            throw new IllegalStateException("identity-service returned no anonymousId");
        }
        return UUID.fromString(response.get("anonymousId").toString());
    }

    /**
     * Fallback: without the anonymous id no token can be issued, so there is no safe default value.
     * Infrastructure failures become {@link IdentityServiceUnavailableException} (HTTP 503); a 4xx is a
     * caller error and is propagated unchanged.
     */
    @SuppressWarnings("unused")
    private UUID anonymousIdFallback(String realIdentity, Throwable cause) {
        if (cause instanceof HttpClientErrorException clientError) {
            throw clientError;
        }
        if (cause instanceof CallNotPermittedException) {
            log.warn("identity-service circuit is open; rejecting the call without contacting it");
        } else {
            log.warn("identity-service unavailable after retries: {}", cause.toString());
        }
        throw new IdentityServiceUnavailableException("identity-service is unavailable", cause);
    }
}
