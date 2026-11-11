package com.circleguard.auth.client;

import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestTemplate;

import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.http.HttpMethod.POST;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class IdentityClientTest {

    @Test
    void mapsTheRealIdentityToAnAnonymousId() {
        IdentityClient client = new IdentityClient("http://identity.test");
        RestTemplate restTemplate = (RestTemplate) ReflectionTestUtils.getField(client, "restTemplate");
        MockRestServiceServer server = MockRestServiceServer.bindTo(restTemplate).build();
        UUID anonymousId = UUID.randomUUID();
        server.expect(requestTo("http://identity.test/api/v1/identities/map"))
                .andExpect(method(POST))
                .andExpect(content().json("{\"realIdentity\":\"ana@icesi.edu.co\"}"))
                .andRespond(withSuccess("{\"anonymousId\":\"" + anonymousId + "\"}", APPLICATION_JSON));

        assertEquals(anonymousId, client.getAnonymousId("ana@icesi.edu.co"));
        server.verify();
    }
}
