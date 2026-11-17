package com.circleguard.dashboard.cache;

import com.circleguard.dashboard.client.PromotionClient;
import com.fasterxml.jackson.databind.ObjectMapper;
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
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.converter.json.Jackson2ObjectMapperBuilder;
import org.springframework.test.web.client.ExpectedCount;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import java.net.ConnectException;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withException;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

/**
 * HU-16 acceptance criteria with an injected failure. The real {@link PromotionClient} (with the HU-14 Retry
 * and Circuit Breaker from resilience4j.yml) talks to a mocked promotion-service; Redis is the in-memory
 * double and the clock is moved forward to expire the fresh TTL.
 */
@SpringBootTest(
        classes = PromotionStatsCacheFailureInjectionTest.TestConfig.class,
        properties = {
                "spring.config.import=classpath:resilience4j.yml",
                "circleguard.promotion-service.url=http://promotion.test",
                "circleguard.dashboard.cache.fresh-ttl=60s",
                "circleguard.dashboard.cache.stale-ttl=24h",
                "resilience4j.retry.instances.promotion.wait-duration=10ms"
        })
class PromotionStatsCacheFailureInjectionTest {

    private static final String STATS_URL = "http://promotion.test/api/v1/health-status/stats";
    private static final Instant START = Instant.parse("2026-11-16T15:00:00Z");
    private static final String STATS_JSON = "{\"totalUsers\":120,\"confirmedCount\":3}";

    @Configuration
    @ImportAutoConfiguration({
            AopAutoConfiguration.class,
            CircuitBreakerAutoConfiguration.class,
            RetryAutoConfiguration.class
    })
    @Import({PromotionClient.class, PromotionStatsCache.class})
    static class TestConfig {
        @Bean
        RestTemplate promotionRestTemplate() {
            return new RestTemplate();
        }

        @Bean
        InMemoryRedis inMemoryRedis() {
            return new InMemoryRedis();
        }

        @Bean
        StringRedisTemplate stringRedisTemplate(InMemoryRedis redis) {
            return redis.template;
        }

        @Bean
        ObjectMapper objectMapper() {
            return Jackson2ObjectMapperBuilder.json().build();
        }

        @Bean
        MutableClock clock() {
            return new MutableClock(START);
        }
    }

    @Autowired
    private PromotionStatsCache cache;

    @Autowired
    @Qualifier("promotionRestTemplate")
    private RestTemplate restTemplate;

    @Autowired
    private InMemoryRedis redis;

    @Autowired
    private MutableClock clock;

    @Autowired
    private CircuitBreakerRegistry circuitBreakerRegistry;

    private MockRestServiceServer promotionService;

    @BeforeEach
    void setUp() {
        // The Spring context (and so these beans) is shared by the tests of this class.
        redis.values.clear();
        clock.set(START);
        circuitBreakerRegistry.circuitBreaker("promotion").reset();
        promotionService = MockRestServiceServer.bindTo(restTemplate).build();
    }

    @Test
    void aRepeatedQueryBeforeTheTtlDoesNotReachPromotion() {
        // Exactly one request may reach promotion-service.
        promotionService.expect(ExpectedCount.once(), requestTo(STATS_URL))
                .andRespond(withSuccess(STATS_JSON, APPLICATION_JSON));

        assertEquals(120, cache.getHealthStats().get("totalUsers"));
        clock.advance(Duration.ofSeconds(30));
        assertEquals(120, cache.getHealthStats().get("totalUsers"));

        promotionService.verify();
    }

    @Test
    void withPromotionStoppedTheDashboardAnswersWithTheLastStoredValue() {
        promotionService.expect(ExpectedCount.once(), requestTo(STATS_URL))
                .andRespond(withSuccess(STATS_JSON, APPLICATION_JSON));
        // promotion-service stops: every attempt of the Retry (3) gets "connection refused".
        promotionService.expect(ExpectedCount.times(3), requestTo(STATS_URL))
                .andRespond(withException(new ConnectException("Connection refused")));

        cache.getHealthStats();
        clock.advance(Duration.ofMinutes(5));
        Map<String, Object> result = cache.getHealthStats();

        assertEquals(120, result.get("totalUsers"));
        assertEquals(true, result.get("stale"));
        assertEquals(START.toString(), result.get("cachedAt"));
        promotionService.verify();
    }

    @Test
    void withTheCircuitOpenTheLastValueIsServedWithoutCallingPromotion() {
        promotionService.expect(ExpectedCount.once(), requestTo(STATS_URL))
                .andRespond(withSuccess(STATS_JSON, APPLICATION_JSON));
        cache.getHealthStats();
        promotionService.verify();
        promotionService.reset();

        circuitBreakerRegistry.circuitBreaker("promotion").transitionToOpenState();
        clock.advance(Duration.ofMinutes(5));
        Map<String, Object> result = cache.getHealthStats();

        assertEquals(120, result.get("totalUsers"));
        assertEquals(true, result.get("stale"));
        assertEquals(CircuitBreaker.State.OPEN, circuitBreakerRegistry.circuitBreaker("promotion").getState());
        // No expectation registered after reset(): any request would fail verify().
        promotionService.verify();
    }
}
