package com.circleguard.promotion.metrics;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.List;

/**
 * Metricas de negocio de CircleGuard (HU-17 / PI-130).
 * <ul>
 * <li>circleguard_promotions_total{status}: cambios de estado de salud
 * aplicados (promociones/min = rate()*60).</li>
 * <li>circleguard_checkins_total{result}: senales de ubicacion procesadas.</li>
 * <li>circleguard_containment_duration_seconds{outcome}: tiempo de
 * propagacion/contencion de un cambio de estado.</li>
 * </ul>
 * Los valores de las etiquetas se restringen a conjuntos cerrados para no
 * generar cardinalidad ilimitada.
 */
@Component
public class PromotionMetrics {

    static final List<String> STATUSES = List.of("ACTIVE", "SUSPECT", "PROBABLE", "CONFIRMED", "RECOVERED");
    static final List<String> CHECKIN_RESULTS = List.of("resolved", "unknown_access_point", "unmapped_device");

    private final MeterRegistry registry;
    private final Timer containmentOk;
    private final Timer containmentError;

    public PromotionMetrics(MeterRegistry registry) {
        this.registry = registry;
        this.containmentOk = containmentTimer("success");
        this.containmentError = containmentTimer("error");
        // Se registran en 0 para que las series existan desde el arranque (rate() y
        // alertas mas fiables).
        STATUSES.forEach(s -> registry.counter("circleguard.promotions", "status", s));
        CHECKIN_RESULTS.forEach(r -> registry.counter("circleguard.checkins", "result", r));
    }

    private Timer containmentTimer(String outcome) {
        return Timer.builder("circleguard.containment.duration")
                .description("Tiempo en propagar un cambio de estado de salud a los contactos")
                .tag("outcome", outcome)
                .publishPercentileHistogram()
                .serviceLevelObjectives(Duration.ofMillis(500), Duration.ofSeconds(1), Duration.ofSeconds(5),
                        Duration.ofSeconds(15), Duration.ofSeconds(30), Duration.ofSeconds(60))
                .register(registry);
    }

    public void recordPromotion(String status) {
        registry.counter("circleguard.promotions", "status", STATUSES.contains(status) ? status : "OTHER").increment();
    }

    public void recordCheckIn(String result) {
        registry.counter("circleguard.checkins", "result", CHECKIN_RESULTS.contains(result) ? result : "other")
                .increment();
    }

    public void recordContainment(long nanos, boolean success) {
        (success ? containmentOk : containmentError).record(Duration.ofNanos(nanos));
    }
}
