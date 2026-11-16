package com.circleguard.auth.client;

import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.springboot3.circuitbreaker.autoconfigure.CircuitBreakerAutoConfiguration;
import io.github.resilience4j.springboot3.retry.autoconfigure.RetryAutoConfiguration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.autoconfigure.aop.AopAutoConfiguration;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * HU-14: injects failures into identity-service (a mocked HTTP server) and verifies that the Circuit
 * Breaker opens, that an open circuit stops calling identity-service, that Retry absorbs a transient
 * failure and that the circuit closes again once identity-service recovers.
 *
 * <p>The Resilience4j aspects run for real: the Spring context loads the production settings from
 * resilience4j.yml; only the retry back-off is shortened to keep the test fast.
 */
@SpringBootTest(
        classes = IdentityClientResilienceTest.TestConfig.class,
        properties = {
                "spring.config.import=classpath:resilience4j.yml",
                "identity.api.url=http://identity.test",
                "resilience4j.retry.instances.identity.wait-duration=10ms"
        })
class IdentityClientResilienceTest {

    private static final String MAP_URL = "http://identity.test/api/v1/identities/map";

    @Configuration
    @ImportAutoConfiguration({
            AopAutoConfiguration.class,
            CircuitBreakerAutoConfiguration.class,
            RetryAutoConfiguration.class
    })
    @Import(IdentityClient.class)
    static class TestConfig {
        @Bean
        RestTemplate identityRestTemplate() {
            return new RestTemplate();
        }
    }

    @Autowired
    private IdentityClient client;

    @Autowired
    @Qualifier("identityRestTemplate")
    private RestTemplate restTemplate;

    @Autowired
    private CircuitBreakerRegistry circuitBreakerRegistry;

    private CircuitBreaker circuitBreaker;
    private MockRestServiceServer identityService;

    @BeforeEach
    void setUp() {
        circuitBreaker = circuitBreakerRegistry.circuitBreaker(IdentityClient.INSTANCE);
        circuitBreaker.reset();
        identityService = MockRestServiceServer.bindTo(restTemplate).build();
    }

    @Test
    void usesTheProductionSettingsFromResilience4jYml() {
        var config = circuitBreaker.getCircuitBreakerConfig();
        assertEquals(5, config.getMinimumNumberOfCalls());
        assertEquals(50f, config.getFailureRateThreshold());
        assertEquals(10, config.getSlidingWindowSize());
    }

    @Test
    void opensTheCircuitAfterInjectedFailuresAndStopsCallingIdentityService() {
        // identity-service answers 500 to every request; exactly 5 requests may reach it.
        identityService.expect(ExpectedCount.times(5), requestTo(MAP_URL)).andRespond(withServerError());

        // Call 1: 3 attempts (1 + 2 retries) fail; 3 recorded calls < minimum of 5, circuit stays closed.
        assertThrows(IdentityServiceUnavailableException.class, () -> client.getAnonymousId("ana@icesi.edu.co"));
        assertEquals(CircuitBreaker.State.CLOSED, circuitBreaker.getState());

        // Call 2: attempts 4 and 5 fail -> failure rate 100 % >= 50 %, the circuit opens and the
        // third attempt is rejected without reaching identity-service.
        assertThrows(IdentityServiceUnavailableException.class, () -> client.getAnonymousId("ana@icesi.edu.co"));
        assertEquals(CircuitBreaker.State.OPEN, circuitBreaker.getState());
        assertEquals(5, circuitBreaker.getMetrics().getNumberOfFailedCalls());

        // Call 3: the open circuit fails fast; the fallback reports the rejection as the cause.
        IdentityServiceUnavailableException rejected = assertThrows(
                IdentityServiceUnavailableException.class, () -> client.getAnonymousId("ana@icesi.edu.co"));
        assertInstanceOf(CallNotPermittedException.class, rejected.getCause());
        // Rejected without a request: the 3rd attempt of call 2 and call 3.
        assertEquals(2, circuitBreaker.getMetrics().getNumberOfNotPermittedCalls());

        // Only the 5 requests made while the circuit was closed reached identity-service.
        identityService.verify();
    }

    @Test
    void closesTheCircuitAgainWhenIdentityServiceRecovers() {
        circuitBreaker.transitionToOpenState();
        // After wait-duration-in-open-state the circuit lets 2 trial calls through (half-open).
        circuitBreaker.transitionToHalfOpenState();
        UUID anonymousId = UUID.randomUUID();
        identityService.expect(ExpectedCount.times(2), requestTo(MAP_URL))
                .andRespond(withSuccess("{\"anonymousId\":\"" + anonymousId + "\"}", APPLICATION_JSON));

        assertEquals(anonymousId, client.getAnonymousId("ana@icesi.edu.co"));
        assertEquals(anonymousId, client.getAnonymousId("ana@icesi.edu.co"));

        assertEquals(CircuitBreaker.State.CLOSED, circuitBreaker.getState());
        identityService.verify();
    }

    @Test
    void retriesATransientFailureAndReturnsTheAnonymousId() {
        UUID anonymousId = UUID.randomUUID();
        identityService.expect(ExpectedCount.once(), requestTo(MAP_URL)).andRespond(withServerError());
        identityService.expect(ExpectedCount.once(), requestTo(MAP_URL))
                .andRespond(withSuccess("{\"anonymousId\":\"" + anonymousId + "\"}", APPLICATION_JSON));

        assertEquals(anonymousId, client.getAnonymousId("ana@icesi.edu.co"));

        assertEquals(1, circuitBreaker.getMetrics().getNumberOfFailedCalls());
        assertEquals(1, circuitBreaker.getMetrics().getNumberOfSuccessfulCalls());
        assertEquals(CircuitBreaker.State.CLOSED, circuitBreaker.getState());
        identityService.verify();
    }

    @Test
    void doesNotRetryNorCountAClientError() {
        identityService.expect(ExpectedCount.once(), requestTo(MAP_URL)).andRespond(withStatus(HttpStatus.BAD_REQUEST));

        assertThrows(HttpClientErrorException.class, () -> client.getAnonymousId("ana@icesi.edu.co"));

        assertEquals(0, circuitBreaker.getMetrics().getNumberOfFailedCalls());
        identityService.verify();
    }
}
