package com.circleguard.auth.service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class QrTokenServiceTest {

    private static final String SECRET = "unit-test-qr-secret-key-with-at-least-32-bytes";

    @Test
    void qrTokenIdentifiesTheAnonymousUser() {
        UUID id = UUID.randomUUID();
        String token = new QrTokenService(SECRET, 60_000).generateQrToken(id);

        Claims claims = Jwts.parserBuilder().setSigningKey(Keys.hmacShaKeyFor(SECRET.getBytes()))
                .build().parseClaimsJws(token).getBody();
        assertEquals(id.toString(), claims.getSubject());
    }

    @Test
    void expiredQrTokenIsRejected() {
        String token = new QrTokenService(SECRET, -1_000).generateQrToken(UUID.randomUUID());

        assertThrows(ExpiredJwtException.class, () -> Jwts.parserBuilder()
                .setSigningKey(Keys.hmacShaKeyFor(SECRET.getBytes())).build().parseClaimsJws(token));
    }
}
