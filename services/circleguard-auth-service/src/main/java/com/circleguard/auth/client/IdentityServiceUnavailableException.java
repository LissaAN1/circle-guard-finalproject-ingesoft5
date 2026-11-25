package com.circleguard.auth.client;

/**
 * HU-14: raised by the {@link IdentityClient} fallback when identity-service cannot answer, either
 * because the retries were exhausted or because the Circuit Breaker is open. The login endpoint maps
 * it to HTTP 503 so the client knows the failure is temporary.
 */
public class IdentityServiceUnavailableException extends RuntimeException {

    public IdentityServiceUnavailableException(String message, Throwable cause) {
        super(message, cause);
    }
}
