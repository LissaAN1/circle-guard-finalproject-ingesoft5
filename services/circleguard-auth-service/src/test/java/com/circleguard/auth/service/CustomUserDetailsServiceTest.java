package com.circleguard.auth.service;

import com.circleguard.auth.model.LocalUser;
import com.circleguard.auth.model.Permission;
import com.circleguard.auth.model.Role;
import com.circleguard.auth.repository.LocalUserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UsernameNotFoundException;

import java.util.Optional;
import java.util.Set;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class CustomUserDetailsServiceTest {

    private final LocalUserRepository repository = mock(LocalUserRepository.class);
    private final CustomUserDetailsService service = new CustomUserDetailsService(repository);

    private LocalUser user(boolean active) {
        Permission lookup = Permission.builder().name("identity:lookup").build();
        Role admin = Role.builder().name("ADMIN").permissions(Set.of(lookup)).build();
        return LocalUser.builder().username("ana").password("hash").isActive(active).roles(Set.of(admin)).build();
    }

    @Test
    void activeUserGetsRolesAndPermissionsAsAuthorities() {
        when(repository.findByUsername("ana")).thenReturn(Optional.of(user(true)));

        UserDetails details = service.loadUserByUsername("ana");

        Set<String> authorities = details.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority).collect(Collectors.toSet());
        assertEquals("ana", details.getUsername());
        assertEquals("hash", details.getPassword());
        assertTrue(authorities.contains("ROLE_ADMIN"));
        assertTrue(authorities.contains("identity:lookup"));
    }

    @Test
    void unknownUserIsNotFound() {
        when(repository.findByUsername("nadie")).thenReturn(Optional.empty());

        assertThrows(UsernameNotFoundException.class, () -> service.loadUserByUsername("nadie"));
    }

    @Test
    void disabledUserIsRejected() {
        when(repository.findByUsername("ana")).thenReturn(Optional.of(user(false)));

        assertThrows(DisabledException.class, () -> service.loadUserByUsername("ana"));
    }
}
