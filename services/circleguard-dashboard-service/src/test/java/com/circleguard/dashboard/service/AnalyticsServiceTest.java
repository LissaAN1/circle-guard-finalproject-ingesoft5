package com.circleguard.dashboard.service;

import com.circleguard.dashboard.cache.PromotionStatsCache;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.when;

/** HU-16: the statistics come from the cache and k-anonymity still applies to a stale value. */
class AnalyticsServiceTest {

    private final PromotionStatsCache cache = Mockito.mock(PromotionStatsCache.class);
    private final AnalyticsService service =
            new AnalyticsService(Mockito.mock(JdbcTemplate.class), cache, new KAnonymityFilter());

    @Test
    void campusSummaryComesFromTheCache() {
        when(cache.getHealthStats()).thenReturn(Map.of("totalUsers", 120));

        assertEquals(120, service.getCampusSummary().get("totalUsers"));
    }

    @Test
    void appliesKAnonymityToAStaleDepartmentValue() {
        Map<String, Object> stale = new LinkedHashMap<>();
        stale.put("totalUsers", 40);
        stale.put("confirmedCount", 2);
        stale.put("stale", true);
        when(cache.getHealthStatsByDepartment("law")).thenReturn(stale);

        Map<String, Object> result = service.getDepartmentStats("law");

        assertEquals("<5", result.get("confirmedCount"));
        assertEquals(true, result.get("stale"));
    }
}
