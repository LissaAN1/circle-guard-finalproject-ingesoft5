package com.circleguard.gateway.config;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.UUID;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * HU-15: the same compiled gateway behaves differently depending only on the value of
 * FEATURE_DENY_SUSPECT_ENTRY, the key the ConfigMap circleguard-config provides in Kubernetes.
 *
 * <p>Each nested class starts the whole application with a different value of that variable and calls the
 * real endpoint; no code or image changes between them. Redis is mocked.
 */
class SuspectEntryToggleTest {

    abstract static class GateScenario {

        @Autowired
        MockMvc mockMvc;

        @MockBean
        StringRedisTemplate redisTemplate;

        @Value("${qr.secret}")
        String qrSecret;

        @SuppressWarnings("unchecked")
        private final ValueOperations<String, String> valueOps = Mockito.mock(ValueOperations.class);

        @BeforeEach
        void stubRedis() {
            Mockito.when(redisTemplate.opsForValue()).thenReturn(valueOps);
        }

        ResultActions validateUserWithStatus(String healthStatus) throws Exception {
            String anonymousId = UUID.randomUUID().toString();
            Mockito.when(valueOps.get("user:status:" + anonymousId)).thenReturn(healthStatus);
            String token = Jwts.builder()
                    .setSubject(anonymousId)
                    .signWith(Keys.hmacShaKeyFor(qrSecret.getBytes()), SignatureAlgorithm.HS256)
                    .compact();
            return mockMvc.perform(post("/api/v1/gate/validate")
                    .contentType(MediaType.APPLICATION_JSON)
                    .content("{\"token\":\"" + token + "\"}"));
        }

        ResultActions info() throws Exception {
            return mockMvc.perform(get("/actuator/info"));
        }
    }

    /** Without the variable the strict HU-07 policy applies. */
    @Nested
    @SpringBootTest
    @AutoConfigureMockMvc
    class WhenTheVariableIsNotSet extends GateScenario {

        @Test
        void suspectUsersAreDenied() throws Exception {
            validateUserWithStatus("SUSPECT")
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.valid").value(false))
                    .andExpect(jsonPath("$.status").value("RED"));
        }
    }

    @Nested
    @SpringBootTest(properties = "FEATURE_DENY_SUSPECT_ENTRY=true")
    @AutoConfigureMockMvc
    class WhenTheConfigMapDeniesSuspectEntry extends GateScenario {

        @Test
        void suspectAndProbableUsersAreDenied() throws Exception {
            validateUserWithStatus("SUSPECT").andExpect(jsonPath("$.valid").value(false));
            validateUserWithStatus("PROBABLE").andExpect(jsonPath("$.valid").value(false));
        }

        @Test
        void usersWithoutAStatusKeyEnter() throws Exception {
            validateUserWithStatus(null)
                    .andExpect(jsonPath("$.valid").value(true))
                    .andExpect(jsonPath("$.status").value("GREEN"))
                    .andExpect(jsonPath("$.message").value("Welcome to Campus"));
        }

        @Test
        void infoShowsTheActiveToggle() throws Exception {
            info().andExpect(status().isOk())
                    .andExpect(jsonPath("$.features.deny-suspect-entry").value("true"));
        }
    }

    @Nested
    @SpringBootTest(properties = "FEATURE_DENY_SUSPECT_ENTRY=false")
    @AutoConfigureMockMvc
    class WhenTheConfigMapAllowsSuspectEntry extends GateScenario {

        @Test
        void suspectAndProbableUsersEnterWithAWarning() throws Exception {
            validateUserWithStatus("SUSPECT")
                    .andExpect(jsonPath("$.valid").value(true))
                    .andExpect(jsonPath("$.status").value("GREEN"))
                    .andExpect(jsonPath("$.message").value("Welcome to Campus: Health Check Recommended"));
            validateUserWithStatus("PROBABLE").andExpect(jsonPath("$.valid").value(true));
        }

        @Test
        void confirmedUsersAreStillDenied() throws Exception {
            validateUserWithStatus("CONFIRMED")
                    .andExpect(jsonPath("$.valid").value(false))
                    .andExpect(jsonPath("$.status").value("RED"));
        }

        @Test
        void healthyUsersAreUnaffected() throws Exception {
            validateUserWithStatus("ACTIVE").andExpect(jsonPath("$.valid").value(true));
            // No key in Redis: the user never had a health event.
            validateUserWithStatus(null)
                    .andExpect(jsonPath("$.valid").value(true))
                    .andExpect(jsonPath("$.message").value("Welcome to Campus"));
        }

        @Test
        void infoShowsTheActiveToggle() throws Exception {
            info().andExpect(jsonPath("$.features.deny-suspect-entry").value("false"));
        }
    }
}
