package com.circleguard.identity.service;

import com.circleguard.identity.model.IdentityMapping;
import com.circleguard.identity.repository.IdentityMappingRepository;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class IdentityVaultServiceTest {

    private final IdentityMappingRepository repository = mock(IdentityMappingRepository.class);
    private final IdentityVaultService service = new IdentityVaultService(repository);

    IdentityVaultServiceTest() {
        ReflectionTestUtils.setField(service, "hashSalt", "unit-test-salt");
    }

    @Test
    void knownIdentityReusesItsAnonymousId() {
        UUID existing = UUID.randomUUID();
        IdentityMapping mapping = IdentityMapping.builder().anonymousId(existing).build();
        when(repository.findByIdentityHash(anyString())).thenReturn(Optional.of(mapping));

        assertEquals(existing, service.getOrCreateAnonymousId("ana@icesi.edu.co"));
        verify(repository, never()).save(any());
    }

    @Test
    void newIdentityIsStoredWithHashAndSalt() {
        UUID created = UUID.randomUUID();
        when(repository.findByIdentityHash(anyString())).thenReturn(Optional.empty());
        when(repository.save(any(IdentityMapping.class))).thenAnswer(inv -> {
            IdentityMapping saved = inv.getArgument(0);
            saved.setAnonymousId(created);
            return saved;
        });

        assertEquals(created, service.getOrCreateAnonymousId("ana@icesi.edu.co"));

        var captor = org.mockito.ArgumentCaptor.forClass(IdentityMapping.class);
        verify(repository).save(captor.capture());
        IdentityMapping stored = captor.getValue();
        assertEquals("ana@icesi.edu.co", stored.getRealIdentity());
        assertEquals(64, stored.getIdentityHash().length());
        assertNotEquals("ana@icesi.edu.co", stored.getIdentityHash());
        assertNotEquals(null, stored.getSalt());
    }

    @Test
    void theHashDependsOnTheIdentity() {
        when(repository.findByIdentityHash(anyString())).thenReturn(Optional.empty());
        when(repository.save(any(IdentityMapping.class))).thenAnswer(inv -> inv.getArgument(0));

        service.getOrCreateAnonymousId("a@icesi.edu.co");
        service.getOrCreateAnonymousId("b@icesi.edu.co");

        var captor = org.mockito.ArgumentCaptor.forClass(IdentityMapping.class);
        verify(repository, org.mockito.Mockito.times(2)).save(captor.capture());
        assertNotEquals(captor.getAllValues().get(0).getIdentityHash(), captor.getAllValues().get(1).getIdentityHash());
    }

    @Test
    void resolvesTheRealIdentityOfAKnownAnonymousId() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id)).thenReturn(Optional.of(IdentityMapping.builder().realIdentity("ana@icesi.edu.co").build()));

        assertEquals("ana@icesi.edu.co", service.resolveRealIdentity(id));
    }

    @Test
    void unknownAnonymousIdIsNotFound() {
        UUID id = UUID.randomUUID();
        when(repository.findById(id)).thenReturn(Optional.empty());

        ResponseStatusException error = assertThrows(ResponseStatusException.class, () -> service.resolveRealIdentity(id));
        assertEquals(HttpStatus.NOT_FOUND, error.getStatusCode());
    }
}
