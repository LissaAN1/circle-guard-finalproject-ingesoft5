package com.circleguard.dashboard.client;

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
import org.springframework.web.client.RestTemplate;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withStatus;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * HU-14: injects failures into promotion-service (a mocked HTTP server) and verifies that the
 * Circuit Breaker opens, that an open circuit serves the degraded payload without calling
 * promotion-service, that Retry absorbs a transient failure and that the circuit closes again.
 *
 * <p>The Resilience4j aspects run for real: the Spring context loads the production settings from
 * resilience4j.yml; only the retry back-off is shortened to keep the test fast.
 */
@SpringBootTest(
        classes = PromotionClientResilienceTest.TestConfig.class,
        properties = {
                "spring.config.import=classpath:resilience4j.yml",
                "circleguard.promotion-service.url=http://promotion.test",
                "resilience4j.retry.instances.promotion.wait-duration=10ms"
        })
class PromotionClientResilienceTest {

    private static final String STATS_URL = "http://promotion.test/api/v1/health-status/stats";
    private static final String DEPT_URL = STATS_URL + "/department/engineering";
    private static final String STATS_JSON = "{\"totalUsers\":120,\"confirmedCount\":3}";

    @Configuration
    @ImportAutoConfiguration({
            AopAutoConfiguration.class,
            CircuitBreakerAutoConfiguration.class,
            RetryAutoConfiguration.class
    })
    @Import(PromotionClient.class)
    static class TestConfig {
        @Bean
        RestTemplate promotionRestTemplate() {
            return new RestTemplate();
        }
    }

    @Autowired
    private PromotionClient client;

    @Autowired
    @Qualifier("promotionRestTemplate")
    private RestTemplate restTemplate;

    @Autowired
    private CircuitBreakerRegistry circuitBreakerRegistry;

    private CircuitBreaker circuitBreaker;
    private MockRestServiceServer promotionService;

    @BeforeEach
    void setUp() {
        circuitBreaker = circuitBreakerRegistry.circuitBreaker(PromotionClient.INSTANCE);
        circuitBreaker.reset();
        promotionService = MockRestServiceServer.bindTo(restTemplate).build();
    }

    @Test
    void usesTheProductionSettingsFromResilience4jYml() {
        var config = circuitBreaker.getCircuitBreakerConfig();
        assertEquals(5, config.getMinimumNumberOfCalls());
        assertEquals(50f, config.getFailureRateThreshold());
        assertEquals(10, config.getSlidingWindowSize());
    }

    @Test
    void opensTheCircuitAfterInjectedFailuresAndServesTheDegradedPayload() {
        // promotion-service answers 500 to every request; exactly 5 requests may reach it.
        promotionService.expect(ExpectedCount.times(5), requestTo(STATS_URL)).andRespond(withServerError());

        // Call 1: 3 attempts fail; 3 recorded calls < minimum of 5, the circuit stays closed.
        assertDegraded(client.getHealthStats());
        assertEquals(CircuitBreaker.State.CLOSED, circuitBreaker.getState());

        // Call 2: attempts 4 and 5 fail -> failure rate 100 % >= 50 %, the circuit opens and the
        // third attempt is rejected without reaching promotion-service.
        assertDegraded(client.getHealthStats());
        assertEquals(CircuitBreaker.State.OPEN, circuitBreaker.getState());
        assertEquals(5, circuitBreaker.getMetrics().getNumberOfFailedCalls());

        // Call 3: the open circuit answers immediately with the fallback.
        assertDegraded(client.getHealthStats());
        // Rejected without a request: the 3rd attempt of call 2 and call 3.
        assertEquals(2, circuitBreaker.getMetrics().getNumberOfNotPermittedCalls());

        // Only the 5 requests made while the circuit was closed reached promotion-service.
        promotionService.verify();
    }

    @Test
    void sharesTheCircuitBetweenBothStatisticsCalls() {
        circuitBreaker.transitionToOpenState();

        Map<String, Object> result = client.getHealthStatsByDepartment("engineering");

        assertDegraded(result);
        assertEquals("engineering", result.get("department"));
        // No expectation was registered: any request to promotion-service would fail verify().
        promotionService.verify();
    }

    @Test
    void closesTheCircuitAgainWhenPromotionServiceRecovers() {
        circuitBreaker.transitionToOpenState();
        // After wait-duration-in-open-state the circuit lets 2 trial calls through (half-open).
        circuitBreaker.transitionToHalfOpenState();
        promotionService.expect(ExpectedCount.times(2), requestTo(STATS_URL))
                .andRespond(withSuccess(STATS_JSON, APPLICATION_JSON));

        assertEquals(120, client.getHealthStats().get("totalUsers"));
        assertEquals(120, client.getHealthStats().get("totalUsers"));

        assertEquals(CircuitBreaker.State.CLOSED, circuitBreaker.getState());
        promotionService.verify();
    }

    @Test
    void retriesATransientFailureAndReturnsTheStatistics() {
        promotionService.expect(ExpectedCount.once(), requestTo(DEPT_URL)).andRespond(withServerError());
        promotionService.expect(ExpectedCount.once(), requestTo(DEPT_URL))
                .andRespond(withSuccess(STATS_JSON, APPLICATION_JSON));

        Map<String, Object> result = client.getHealthStatsByDepartment("engineering");

        assertEquals(120, result.get("totalUsers"));
        assertEquals(1, circuitBreaker.getMetrics().getNumberOfFailedCalls());
        assertEquals(CircuitBreaker.State.CLOSED, circuitBreaker.getState());
        promotionService.verify();
    }

    @Test
    void doesNotRetryNorCountAClientError() {
        promotionService.expect(ExpectedCount.once(), requestTo(DEPT_URL)).andRespond(withStatus(HttpStatus.NOT_FOUND));

        assertDegraded(client.getHealthStatsByDepartment("engineering"));

        assertEquals(0, circuitBreaker.getMetrics().getNumberOfFailedCalls());
        promotionService.verify();
    }

    private static void assertDegraded(Map<String, Object> result) {
        assertEquals("Service unavailable", result.get("error"));
        assertEquals(true, result.get("degraded"));
    }
}
