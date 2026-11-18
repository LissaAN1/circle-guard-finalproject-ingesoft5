package com.circleguard.gateway.service;

import com.circleguard.gateway.config.FeatureToggles;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.test.util.ReflectionTestUtils;

import java.security.Key;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

public class QrValidationServiceTest {

    private QrValidationService service;
    private StringRedisTemplate redisTemplate;
    private ValueOperations<String, String> valueOps;
    private final String secret = "my-super-secret-test-key-32-chars-long";

    @BeforeEach
    void setUp() {
        redisTemplate = Mockito.mock(StringRedisTemplate.class);
        valueOps = Mockito.mock(ValueOperations.class);
        Mockito.when(redisTemplate.opsForValue()).thenReturn(valueOps);
        
        service = new QrValidationService(redisTemplate, new FeatureToggles(true));
        ReflectionTestUtils.setField(service, "qrSecret", secret);
    }

    @Test
    void shouldValidateCorrectTokenAndAllowAccess() {
        String anonymousId = UUID.randomUUID().toString();
        Key key = Keys.hmacShaKeyFor(secret.getBytes());
        String token = Jwts.builder()
                .setSubject(anonymousId)
                .signWith(key, SignatureAlgorithm.HS256)
                .compact();

        Mockito.when(valueOps.get("user:status:" + anonymousId)).thenReturn("CLEAR");

        QrValidationService.ValidationResult result = service.validateToken(token);
        
        assertTrue(result.valid());
        assertEquals("GREEN", result.status());
    }

    @Test
    void shouldDenyAccessForContagiedUser() {
        String anonymousId = UUID.randomUUID().toString();
        Key key = Keys.hmacShaKeyFor(secret.getBytes());
        String token = Jwts.builder()
                .setSubject(anonymousId)
                .signWith(key, SignatureAlgorithm.HS256)
                .compact();

        Mockito.when(valueOps.get("user:status:" + anonymousId)).thenReturn("CONTAGIED");

        QrValidationService.ValidationResult result = service.validateToken(token);

        assertFalse(result.valid());
        assertEquals("RED", result.status());
    }

    @Test
    void shouldDenyAccessForConfirmedUser() {
        String anonymousId = UUID.randomUUID().toString();
        Key key = Keys.hmacShaKeyFor(secret.getBytes());
        String token = Jwts.builder()
                .setSubject(anonymousId)
                .signWith(key, SignatureAlgorithm.HS256)
                .compact();

        Mockito.when(valueOps.get("user:status:" + anonymousId)).thenReturn("CONFIRMED");
        QrValidationService.ValidationResult result = service.validateToken(token);

        assertFalse(result.valid());
        assertEquals("RED", result.status());
        assertTrue(result.message().contains("Access Denied"));
    }

    // HU-15: the suspect-entry policy follows the feature toggle; CONFIRMED is always denied.
    @Test
    void shouldDenySuspectUserWhenToggleIsOn() {
        String anonymousId = UUID.randomUUID().toString();
        Mockito.when(valueOps.get("user:status:" + anonymousId)).thenReturn("POTENTIAL");

        QrValidationService.ValidationResult result = service.validateToken(tokenFor(anonymousId));

        assertFalse(result.valid());
        assertEquals("RED", result.status());
    }

    @Test
    void shouldAdmitSuspectUserWithWarningWhenToggleIsOff() {
        QrValidationService relaxed = relaxedService();
        String anonymousId = UUID.randomUUID().toString();
        Mockito.when(valueOps.get("user:status:" + anonymousId)).thenReturn("SUSPECT");

        QrValidationService.ValidationResult result = relaxed.validateToken(tokenFor(anonymousId));

        assertTrue(result.valid());
        assertEquals("GREEN", result.status());
        assertTrue(result.message().contains("Health Check Recommended"));
    }

    @Test
    void shouldDenyLegacyConfirmedUserWhenToggleIsOff() {
        QrValidationService relaxed = relaxedService();
        String anonymousId = UUID.randomUUID().toString();
        Mockito.when(valueOps.get("user:status:" + anonymousId)).thenReturn("CONTAGIED");

        QrValidationService.ValidationResult result = relaxed.validateToken(tokenFor(anonymousId));

        assertFalse(result.valid());
        assertEquals("RED", result.status());
    }

    // A user without any health event has no key in Redis (null): admitted with either toggle value.
    @Test
    void shouldAdmitUserWithoutStatusKeyWhenToggleIsOn() {
        String anonymousId = UUID.randomUUID().toString();
        Mockito.when(valueOps.get("user:status:" + anonymousId)).thenReturn(null);

        QrValidationService.ValidationResult result = service.validateToken(tokenFor(anonymousId));

        assertTrue(result.valid());
        assertEquals("GREEN", result.status());
        assertEquals("Welcome to Campus", result.message());
    }

    @Test
    void shouldAdmitUserWithoutStatusKeyWhenToggleIsOff() {
        String anonymousId = UUID.randomUUID().toString();
        Mockito.when(valueOps.get("user:status:" + anonymousId)).thenReturn(null);

        QrValidationService.ValidationResult result = relaxedService().validateToken(tokenFor(anonymousId));

        assertTrue(result.valid());
        assertEquals("GREEN", result.status());
        assertEquals("Welcome to Campus", result.message());
    }

    private QrValidationService relaxedService() {
        QrValidationService relaxed = new QrValidationService(redisTemplate, new FeatureToggles(false));
        ReflectionTestUtils.setField(relaxed, "qrSecret", secret);
        return relaxed;
    }

    private String tokenFor(String anonymousId) {
        Key key = Keys.hmacShaKeyFor(secret.getBytes());
        return Jwts.builder().setSubject(anonymousId).signWith(key, SignatureAlgorithm.HS256).compact();
    }
}
