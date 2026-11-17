package com.circleguard.dashboard.cache;

import com.circleguard.dashboard.client.PromotionClient;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.data.redis.RedisConnectionFailureException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.converter.json.Jackson2ObjectMapperBuilder;

import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** HU-16: behaviour of the cache-aside with promotion-service and Redis replaced by test doubles. */
class PromotionStatsCacheTest {

    private static final Duration FRESH_TTL = Duration.ofSeconds(60);
    private static final Duration STALE_TTL = Duration.ofHours(24);
    private static final Instant START = Instant.parse("2026-11-16T15:00:00Z");

    private final ObjectMapper objectMapper = Jackson2ObjectMapperBuilder.json().build();
    private PromotionClient promotion;
    private InMemoryRedis redis;
    private MutableClock clock;
    private PromotionStatsCache cache;

    @BeforeEach
    void setUp() {
        promotion = Mockito.mock(PromotionClient.class);
        redis = new InMemoryRedis();
        clock = new MutableClock(START);
        cache = newCache(redis.template);
    }

    @Test
    void repeatedQueryWithinTheTtlDoesNotCallPromotion() {
        when(promotion.getHealthStats()).thenReturn(stats(120));

        assertEquals(120, cache.getHealthStats().get("totalUsers"));
        clock.advance(Duration.ofSeconds(59));
        assertEquals(120, cache.getHealthStats().get("totalUsers"));

        verify(promotion, times(1)).getHealthStats();
    }

    @Test
    void queryAfterTheTtlCallsPromotionAgainAndRefreshesTheEntry() {
        when(promotion.getHealthStats()).thenReturn(stats(120), stats(130));

        cache.getHealthStats();
        clock.advance(FRESH_TTL);
        assertEquals(130, cache.getHealthStats().get("totalUsers"));
        clock.advance(Duration.ofSeconds(30));
        assertEquals(130, cache.getHealthStats().get("totalUsers"));

        verify(promotion, times(2)).getHealthStats();
    }

    @Test
    void servesTheLastStoredValueWhenPromotionIsUnavailable() {
        when(promotion.getHealthStats()).thenReturn(stats(120), degraded());

        cache.getHealthStats();
        clock.advance(Duration.ofMinutes(10));
        Map<String, Object> result = cache.getHealthStats();

        assertEquals(120, result.get("totalUsers"));
        assertEquals(true, result.get("stale"));
        assertEquals(START.toString(), result.get("cachedAt"));
        assertNull(result.get("degraded"));
    }

    @Test
    void keepsTheDegradedPayloadWhenNothingWasStoredAndDoesNotCacheIt() {
        when(promotion.getHealthStats()).thenReturn(degraded());

        assertEquals(true, cache.getHealthStats().get("degraded"));
        assertTrue(redis.values.isEmpty());
    }

    @Test
    void storesEntriesForTheStaleTtl() {
        when(promotion.getHealthStats()).thenReturn(stats(120));

        cache.getHealthStats();

        assertEquals(STALE_TTL, redis.ttls.get(PromotionStatsCache.CAMPUS_KEY));
    }

    @Test
    void cachesEachDepartmentSeparately() {
        when(promotion.getHealthStatsByDepartment("engineering")).thenReturn(stats(40));
        when(promotion.getHealthStatsByDepartment("law")).thenReturn(stats(25));

        assertEquals(40, cache.getHealthStatsByDepartment("engineering").get("totalUsers"));
        assertEquals(25, cache.getHealthStatsByDepartment("law").get("totalUsers"));
        assertEquals(40, cache.getHealthStatsByDepartment("engineering").get("totalUsers"));

        verify(promotion, times(1)).getHealthStatsByDepartment("engineering");
        verify(promotion, times(1)).getHealthStatsByDepartment("law");
        assertTrue(redis.values.containsKey(PromotionStatsCache.DEPARTMENT_KEY_PREFIX + "engineering"));
    }

    @Test
    void goesToPromotionWhenRedisIsDown() {
        StringRedisTemplate brokenRedis = Mockito.mock(StringRedisTemplate.class);
        when(brokenRedis.opsForValue()).thenThrow(new RedisConnectionFailureException("redis is down"));
        PromotionStatsCache withoutRedis = newCache(brokenRedis);
        when(promotion.getHealthStats()).thenReturn(stats(120));

        assertEquals(120, withoutRedis.getHealthStats().get("totalUsers"));
        assertEquals(120, withoutRedis.getHealthStats().get("totalUsers"));

        verify(promotion, times(2)).getHealthStats();
    }

    @Test
    void ignoresAnUnreadableEntry() {
        redis.values.put(PromotionStatsCache.CAMPUS_KEY, "not json");
        when(promotion.getHealthStats()).thenReturn(stats(120));

        Map<String, Object> result = cache.getHealthStats();

        assertEquals(120, result.get("totalUsers"));
        assertFalse(result.containsKey("stale"));
    }

    @Test
    void rejectsInconsistentTtls() {
        assertThrows(IllegalArgumentException.class, () -> new PromotionStatsCache(
                promotion, redis.template, objectMapper, clock, Duration.ZERO, STALE_TTL));
        assertThrows(IllegalArgumentException.class, () -> new PromotionStatsCache(
                promotion, redis.template, objectMapper, clock, FRESH_TTL, Duration.ofSeconds(30)));
    }

    private PromotionStatsCache newCache(StringRedisTemplate template) {
        return new PromotionStatsCache(promotion, template, objectMapper, clock, FRESH_TTL, STALE_TTL);
    }

    private static Map<String, Object> stats(int totalUsers) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("totalUsers", totalUsers);
        body.put("confirmedCount", 3);
        return body;
    }

    private static Map<String, Object> degraded() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("error", "Service unavailable");
        body.put("degraded", true);
        return body;
    }
}
