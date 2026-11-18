package com.circleguard.gateway.service;

import com.circleguard.gateway.config.FeatureToggles;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import java.security.Key;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class QrValidationService {
    private final StringRedisTemplate redisTemplate;
    private final FeatureToggles featureToggles;

    @Value("${qr.secret}")
    private String qrSecret;

    private static final String STATUS_KEY_PREFIX = "user:status:";

    // HU-07: promotion-service stores CONFIRMED, SUSPECT and PROBABLE in Redis.
    // CONTAGIED and POTENTIAL are legacy values kept for compatibility with older clients.
    private static final Set<String> CONFIRMED_STATUSES = Set.of("CONFIRMED", "CONTAGIED");
    private static final Set<String> SUSPECT_STATUSES = Set.of("SUSPECT", "PROBABLE", "POTENTIAL");

    public ValidationResult validateToken(String token) {
        try {
            Key key = Keys.hmacShaKeyFor(qrSecret.getBytes());
            Claims claims = Jwts.parserBuilder()
                    .setSigningKey(key)
                    .build()
                    .parseClaimsJws(token)
                    .getBody();

            String anonymousId = claims.getSubject();
            
            // Check Redis for current Health Status
            String status = redisTemplate.opsForValue().get(STATUS_KEY_PREFIX + anonymousId);

            // No key means no health event for this user (promotion only writes one on a status change):
            // the user is healthy. Set.of(...).contains(null) would throw, so it is handled first.
            if (status == null) {
                return new ValidationResult(true, "GREEN", "Welcome to Campus");
            }
            if (CONFIRMED_STATUSES.contains(status)) {
                return new ValidationResult(false, "RED", "Access Denied: Health Risk Detected");
            }
            if (SUSPECT_STATUSES.contains(status)) {
                // HU-15: the policy for suspect cases is a feature toggle (ConfigMap circleguard-config).
                if (featureToggles.denySuspectEntry()) {
                    return new ValidationResult(false, "RED", "Access Denied: Health Risk Detected");
                }
                return new ValidationResult(true, "GREEN", "Welcome to Campus: Health Check Recommended");
            }

            return new ValidationResult(true, "GREEN", "Welcome to Campus");
            
        } catch (Exception e) {
            return new ValidationResult(false, "RED", "Invalid or Expired Token");
        }
    }

    public record ValidationResult(boolean valid, String status, String message) {}
}
