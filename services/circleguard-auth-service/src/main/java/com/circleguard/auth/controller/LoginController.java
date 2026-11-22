package com.circleguard.auth.controller;

import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.circleguard.auth.client.IdentityClient;
import com.circleguard.auth.client.IdentityServiceUnavailableException;
import com.circleguard.auth.service.JwtTokenService;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

@RestController
@RequestMapping("/api/v1/auth")
@RequiredArgsConstructor
@Slf4j
public class LoginController {

    private static final String MESSAGE_KEY = "message";
    private final AuthenticationManager authManager;
    private final JwtTokenService jwtService;
    private final IdentityClient identityClient;

    @PostMapping("/login")
    public ResponseEntity<Map<String, String>> login(@RequestBody Map<String, String> request) {

        String username = request.get("username");
        String password = request.get("password");

        log.info("Login attempt received");

        try {
            // 1. Authenticate (Dual-Chain)
            Authentication auth = authManager.authenticate(
                    new UsernamePasswordAuthenticationToken(username, password)
            );

            log.info("Authentication successful");

            // 2. Anonymize
            UUID anonymousId = identityClient.getAnonymousId(username);

            // 3. Issue Token
            String token = jwtService.generateToken(anonymousId, auth);

            return ResponseEntity.ok(Map.of(
                    "token", token,
                    "type", "Bearer",
                    "anonymousId", anonymousId.toString()
            ));

        } catch (org.springframework.security.core.AuthenticationException e) {
            log.warn("Authentication failed");

            return ResponseEntity.status(401).body(Map.of(
                    MESSAGE_KEY, "Invalid username or password"
            ));

        } catch (IdentityServiceUnavailableException e) {
            // HU-14: Circuit Breaker open or retries exhausted.
            log.warn("Identity service unavailable during login", e);

            return ResponseEntity.status(503)
                    .header("Retry-After", "15")
                    .body(Map.of(
                            MESSAGE_KEY,
                            "Identity service temporarily unavailable, please retry later"
                    ));

        } catch (Exception e) {
            log.error("Unexpected error during login", e);

            return ResponseEntity.status(500).body(Map.of(
                    MESSAGE_KEY, "Internal server error: " + e.getMessage()
            ));
        }
    }

    @PostMapping("/visitor/handoff")
    public ResponseEntity<Map<String, String>> generateVisitorHandoff(@RequestBody Map<String, String> request) {
        String anonymousIdStr = request.get("anonymousId");
        if (anonymousIdStr == null) {
            return ResponseEntity.badRequest().build();
        }
        
        UUID anonymousId = UUID.fromString(anonymousIdStr);
        
        // Create a dummy authentication for the visitor
        Authentication visitorAuth = new UsernamePasswordAuthenticationToken(
                anonymousIdStr, 
                null, 
                List.of(new org.springframework.security.core.authority.SimpleGrantedAuthority("VISITOR"))
        );
        
        String token = jwtService.generateToken(anonymousId, visitorAuth);
        
        return ResponseEntity.ok(Map.of(
                "token", token,
                "handoffPayload", "HANDOFF_TOKEN:" + anonymousId.toString() + ":" + token
        ));
    }
}
