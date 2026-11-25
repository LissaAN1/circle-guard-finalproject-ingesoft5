package com.circleguard.promotion.metrics;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class PromotionMetricsTest {

    private final SimpleMeterRegistry registry = new SimpleMeterRegistry();
    private final PromotionMetrics metrics = new PromotionMetrics(registry);

    @Test
    void promotionsAreCountedPerStatusAndUnknownStatusesCollapseToOther() {
        metrics.recordPromotion("CONFIRMED");
        metrics.recordPromotion("CONFIRMED");
        metrics.recordPromotion("not-a-status");
        assertEquals(2.0, registry.get("circleguard.promotions").tag("status", "CONFIRMED").counter().count());
        assertEquals(1.0, registry.get("circleguard.promotions").tag("status", "OTHER").counter().count());
    }

    @Test
    void checkInsAreCountedPerResult() {
        metrics.recordCheckIn("resolved");
        metrics.recordCheckIn("unknown_access_point");
        metrics.recordCheckIn("weird");
        assertEquals(1.0, registry.get("circleguard.checkins").tag("result", "resolved").counter().count());
        assertEquals(1.0, registry.get("circleguard.checkins").tag("result", "unknown_access_point").counter().count());
        assertEquals(1.0, registry.get("circleguard.checkins").tag("result", "other").counter().count());
    }

    @Test
    void containmentTimeIsRecordedByOutcome() {
        metrics.recordContainment(2_000_000_000L, true);
        metrics.recordContainment(1_000_000_000L, false);
        var ok = registry.get("circleguard.containment.duration").tag("outcome", "success").timer();
        var err = registry.get("circleguard.containment.duration").tag("outcome", "error").timer();
        assertEquals(1, ok.count());
        assertEquals(2.0, ok.totalTime(java.util.concurrent.TimeUnit.SECONDS), 0.001);
        assertEquals(1, err.count());
    }
}
