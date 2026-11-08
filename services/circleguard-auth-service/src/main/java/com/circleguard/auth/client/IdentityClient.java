package com.circleguard.auth.client;

import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

@Component
public class IdentityClient {

    // In a real microservice, this would use Feign or WebClient
    private final RestTemplate restTemplate = new RestTemplate();
    private final String identityUrl;

    public IdentityClient(@Value("${identity.api.url}") String identityUrl) {
        this.identityUrl = identityUrl;
    }

    public UUID getAnonymousId(String realIdentity) {
        Map<String, String> request = Map.of("realIdentity", realIdentity);
        Map response = restTemplate.postForObject(
            identityUrl + "/api/v1/identities/map",
            request,
            Map.class
        );
        return UUID.fromString(response.get("anonymousId").toString());
    }
}
