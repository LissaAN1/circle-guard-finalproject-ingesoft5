package com.circleguard.auth.security;

import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.core.Authentication;
import org.springframework.security.ldap.authentication.LdapAuthenticationProvider;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DualChainAuthenticationProviderTest {

    private final LdapAuthenticationProvider ldap = mock(LdapAuthenticationProvider.class);
    private final DaoAuthenticationProvider local = mock(DaoAuthenticationProvider.class);
    private final DualChainAuthenticationProvider provider = new DualChainAuthenticationProvider(ldap, local);
    private final Authentication request = new UsernamePasswordAuthenticationToken("ana", "pw");

    @Test
    void ldapSuccessSkipsTheLocalDatabase() {
        Authentication ok = new UsernamePasswordAuthenticationToken("ana", null, List.of());
        when(ldap.authenticate(request)).thenReturn(ok);

        assertSame(ok, provider.authenticate(request));
        verify(local, never()).authenticate(request);
    }

    @Test
    void ldapFailureFallsBackToTheLocalDatabase() {
        Authentication ok = new UsernamePasswordAuthenticationToken("ana", null, List.of());
        when(ldap.authenticate(request)).thenThrow(new BadCredentialsException("ldap"));
        when(local.authenticate(request)).thenReturn(ok);

        assertSame(ok, provider.authenticate(request));
    }

    @Test
    void bothChainsFailingFailsTheLogin() {
        when(ldap.authenticate(request)).thenThrow(new BadCredentialsException("ldap"));
        when(local.authenticate(request)).thenThrow(new BadCredentialsException("local"));

        assertThrows(BadCredentialsException.class, () -> provider.authenticate(request));
    }

    @Test
    void supportsOnlyUsernamePasswordTokens() {
        assertTrue(provider.supports(UsernamePasswordAuthenticationToken.class));
        assertFalse(provider.supports(String.class));
    }
}
