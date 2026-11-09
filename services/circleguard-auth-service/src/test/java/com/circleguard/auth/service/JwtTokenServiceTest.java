package com.circleguard.auth.service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JwtTokenServiceTest {

    private static final String SECRET = "unit-test-secret-key-with-at-least-32-bytes!!";

    @Test
    void generatedTokenCarriesSubjectAndPermissions() {
        JwtTokenService service = new JwtTokenService(SECRET, 60_000);
        UUID anonymousId = UUID.randomUUID();
        var auth = new UsernamePasswordAuthenticationToken("user", "pw",
                List.of(new SimpleGrantedAuthority("identity:lookup"), new SimpleGrantedAuthority("ROLE_ADMIN")));

        String token = service.generateToken(anonymousId, auth);

        Claims claims = Jwts.parserBuilder().setSigningKey(Keys.hmacShaKeyFor(SECRET.getBytes()))
                .build().parseClaimsJws(token).getBody();
        assertEquals(anonymousId.toString(), claims.getSubject());
        List<?> permissions = claims.get("permissions", List.class);
        assertTrue(permissions.contains("identity:lookup"));
        assertTrue(permissions.contains("ROLE_ADMIN"));
        assertTrue(claims.getExpiration().after(claims.getIssuedAt()));
    }

    @Test
    void tokenSignedWithAnotherKeyIsRejected() {
        String token = new JwtTokenService(SECRET, 60_000).generateToken(UUID.randomUUID(),
                new UsernamePasswordAuthenticationToken("u", "p", List.of()));

        var otherKey = Keys.hmacShaKeyFor("another-secret-key-with-at-least-32-bytes!!!".getBytes());
        assertThrows(io.jsonwebtoken.security.SignatureException.class,
                () -> Jwts.parserBuilder().setSigningKey(otherKey).build().parseClaimsJws(token));
    }

    @Test
    void shortSecretIsRefused() {
        assertThrows(io.jsonwebtoken.security.WeakKeyException.class, () -> new JwtTokenService("short", 1000));
    }
}
