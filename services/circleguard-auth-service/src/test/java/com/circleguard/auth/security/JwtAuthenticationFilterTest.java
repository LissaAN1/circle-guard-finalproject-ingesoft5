package com.circleguard.auth.security;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

import java.util.Date;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class JwtAuthenticationFilterTest {

    private static final String SECRET = "unit-test-secret-key-with-at-least-32-bytes!!";
    private final JwtAuthenticationFilter filter = new JwtAuthenticationFilter(SECRET);

    @AfterEach
    void clear() {
        SecurityContextHolder.clearContext();
    }

    private String token(String subject, String secret) {
        return Jwts.builder().setSubject(subject).claim("permissions", List.of("identity:lookup"))
                .setExpiration(new Date(System.currentTimeMillis() + 60_000))
                .signWith(Keys.hmacShaKeyFor(secret.getBytes()), SignatureAlgorithm.HS256).compact();
    }

    private MockFilterChain run(String authorization) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        if (authorization != null) {
            request.addHeader("Authorization", authorization);
        }
        MockFilterChain chain = new MockFilterChain();
        filter.doFilter(request, new MockHttpServletResponse(), chain);
        return chain;
    }

    @Test
    void validBearerTokenAuthenticatesTheRequest() throws Exception {
        MockFilterChain chain = run("Bearer " + token("anon-1", SECRET));

        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        assertNotNull(auth);
        assertEquals("anon-1", auth.getPrincipal());
        assertTrue(auth.getAuthorities().stream().anyMatch(a -> a.getAuthority().equals("identity:lookup")));
        assertNotNull(chain.getRequest());
    }

    @Test
    void tokenSignedWithAnotherKeyLeavesTheRequestAnonymous() throws Exception {
        MockFilterChain chain = run("Bearer " + token("anon-1", "another-secret-key-with-at-least-32-bytes!!!"));

        assertNull(SecurityContextHolder.getContext().getAuthentication());
        assertNotNull(chain.getRequest());
    }

    @Test
    void missingOrNonBearerHeaderIsIgnored() throws Exception {
        run(null);
        run("Basic abc");

        assertNull(SecurityContextHolder.getContext().getAuthentication());
    }
}
