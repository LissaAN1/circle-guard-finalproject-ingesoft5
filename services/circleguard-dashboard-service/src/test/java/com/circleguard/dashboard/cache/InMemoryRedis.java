package com.circleguard.dashboard.cache;

import org.mockito.Mockito;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;

/**
 * Test double for Redis: a {@link StringRedisTemplate} whose GET/SET work on a map, so the unit tests run
 * without a Redis server (pipeline Test stage, no Docker). The TTL passed on SET is recorded, not applied.
 */
final class InMemoryRedis {

    final Map<String, String> values = new HashMap<>();
    final Map<String, Duration> ttls = new HashMap<>();
    final StringRedisTemplate template = Mockito.mock(StringRedisTemplate.class);

    @SuppressWarnings("unchecked")
    InMemoryRedis() {
        ValueOperations<String, String> ops = Mockito.mock(ValueOperations.class);
        Mockito.when(template.opsForValue()).thenReturn(ops);
        Mockito.when(ops.get(anyString())).thenAnswer(inv -> values.get(inv.<String>getArgument(0)));
        Mockito.doAnswer(inv -> {
            values.put(inv.getArgument(0), inv.getArgument(1));
            ttls.put(inv.getArgument(0), inv.getArgument(2));
            return null;
        }).when(ops).set(anyString(), anyString(), any(Duration.class));
    }
}
