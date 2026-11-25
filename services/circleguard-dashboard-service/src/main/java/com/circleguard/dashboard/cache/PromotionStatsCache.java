package com.circleguard.dashboard.cache;

import com.circleguard.dashboard.client.PromotionClient;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.function.Supplier;

/**
 * HU-16: cache-aside of the promotion-service statistics in Redis.
 *
 * <ol>
 *   <li>Look in Redis first. An entry younger than {@code fresh-ttl} is returned without calling
 *       promotion-service.</li>
 *   <li>On a miss (or an older entry) call promotion-service through {@link PromotionClient}, which keeps
 *       the HU-14 Retry and Circuit Breaker, and store the answer with the time it was read.</li>
 *   <li>If promotion-service is unavailable (the client returns its degraded payload), answer with the last
 *       value stored, marked {@code stale=true} with its {@code cachedAt}. The entry is kept for
 *       {@code stale-ttl} for this purpose.</li>
 * </ol>
 *
 * <p>Redis is an optimisation, not a dependency: if it fails, the request goes to promotion-service as it
 * did before this story.
 */
@Component
@Slf4j
public class PromotionStatsCache {

    static final String KEY_PREFIX = "dashboard:promotion-stats:";
    static final String CAMPUS_KEY = KEY_PREFIX + "campus";
    static final String DEPARTMENT_KEY_PREFIX = KEY_PREFIX + "department:";

    private static final TypeReference<CachedStats> CACHED_STATS = new TypeReference<>() { };

    private final PromotionClient promotionClient;
    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;
    private final Clock clock;
    private final Duration freshTtl;
    private final Duration staleTtl;

    public PromotionStatsCache(PromotionClient promotionClient,
                               StringRedisTemplate redis,
                               ObjectMapper objectMapper,
                               Clock clock,
                               @Value("${circleguard.dashboard.cache.fresh-ttl:60s}") Duration freshTtl,
                               @Value("${circleguard.dashboard.cache.stale-ttl:24h}") Duration staleTtl) {
        if (freshTtl.isNegative() || freshTtl.isZero() || staleTtl.compareTo(freshTtl) < 0) {
            throw new IllegalArgumentException("Cache TTLs must satisfy 0 < fresh-ttl <= stale-ttl");
        }
        this.promotionClient = promotionClient;
        this.redis = redis;
        this.objectMapper = objectMapper;
        this.clock = clock;
        this.freshTtl = freshTtl;
        this.staleTtl = staleTtl;
    }

    /** Campus-wide statistics (promotion {@code GET /api/v1/health-status/stats}). */
    public Map<String, Object> getHealthStats() {
        return get(CAMPUS_KEY, promotionClient::getHealthStats);
    }

    /** Statistics of one department (promotion {@code GET /api/v1/health-status/stats/department/{d}}). */
    public Map<String, Object> getHealthStatsByDepartment(String department) {
        return get(DEPARTMENT_KEY_PREFIX + department, () -> promotionClient.getHealthStatsByDepartment(department));
    }

    private Map<String, Object> get(String key, Supplier<Map<String, Object>> promotion) {
        Optional<CachedStats> cached = read(key);
        Instant now = clock.instant();

        if (cached.isPresent() && cached.get().ageAt(now).compareTo(freshTtl) < 0) {
            log.debug("Cache hit for {}", key);
            return cached.get().data();
        }

        Map<String, Object> fresh = promotion.get();
        if (!isDegraded(fresh)) {
            write(key, new CachedStats(now, fresh));
            return fresh;
        }

        if (cached.isPresent()) {
            log.warn("promotion-service unavailable; serving last known value of {} from {}", key, cached.get().cachedAt());
            return stale(cached.get());
        }
        // Nothing stored yet: keep the HU-14 degraded payload.
        return fresh;
    }

    private Optional<CachedStats> read(String key) {
        try {
            String json = redis.opsForValue().get(key);
            return json == null ? Optional.empty() : Optional.of(objectMapper.readValue(json, CACHED_STATS));
        } catch (DataAccessException e) {
            log.warn("Redis unavailable, reading {} from promotion-service: {}", key, e.toString());
        } catch (JsonProcessingException | IllegalArgumentException e) {
            log.warn("Ignoring unreadable cache entry {}: {}", key, e.toString());
        }
        return Optional.empty();
    }

    private void write(String key, CachedStats entry) {
        try {
            redis.opsForValue().set(key, objectMapper.writeValueAsString(entry), staleTtl);
        } catch (DataAccessException | JsonProcessingException e) {
            log.warn("Could not cache {}: {}", key, e.toString());
        }
    }

    private static boolean isDegraded(Map<String, Object> stats) {
        return stats == null || Boolean.TRUE.equals(stats.get("degraded"));
    }

    private static Map<String, Object> stale(CachedStats entry) {
        Map<String, Object> body = new LinkedHashMap<>(entry.data());
        body.put("stale", true);
        body.put("cachedAt", entry.cachedAt().toString());
        return body;
    }

    /** What is stored in Redis: the statistics and when they were read from promotion-service. */
    record CachedStats(Instant cachedAt, Map<String, Object> data) {
        Duration ageAt(Instant now) {
            return Duration.between(cachedAt, now);
        }
    }
}
