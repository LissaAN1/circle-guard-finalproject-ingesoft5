package com.circleguard.identity.event;

import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

class IdentityAccessEventTest {

    @Test
    void eventCarriesPayloadAndMetadata() {
        UUID anonymousId = UUID.randomUUID();
        Instant now = Instant.now();
        IdentityAccessEvent event = IdentityAccessEvent.builder()
                .eventId("e-1").eventType("IDENTITY_LOOKUP").timestamp(now).source("identity-service")
                .payload(IdentityAccessEvent.IdentityAccessPayload.builder()
                        .anonymousId(anonymousId).requestingUser("admin").accessStatus("GRANTED").build())
                .metadata(IdentityAccessEvent.IdentityAccessMetadata.builder()
                        .correlationId("c-1").version(1).build())
                .build();

        assertEquals("e-1", event.getEventId());
        assertEquals("IDENTITY_LOOKUP", event.getEventType());
        assertEquals(now, event.getTimestamp());
        assertEquals("identity-service", event.getSource());
        assertEquals(anonymousId, event.getPayload().getAnonymousId());
        assertEquals("admin", event.getPayload().getRequestingUser());
        assertEquals("GRANTED", event.getPayload().getAccessStatus());
        assertEquals("c-1", event.getMetadata().getCorrelationId());
        assertEquals(1, event.getMetadata().getVersion());
    }
}
