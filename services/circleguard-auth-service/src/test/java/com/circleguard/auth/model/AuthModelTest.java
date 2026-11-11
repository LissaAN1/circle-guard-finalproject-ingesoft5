package com.circleguard.auth.model;

import org.junit.jupiter.api.Test;

import java.util.Set;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AuthModelTest {

    @Test
    void userRoleAndPermissionKeepTheirData() {
        UUID id = UUID.randomUUID();
        Permission permission = Permission.builder().id(id).name("identity:lookup").description("lookup").build();
        Role role = Role.builder().name("ADMIN").description("admin").permissions(Set.of(permission)).build();
        LocalUser user = LocalUser.builder().username("ana").email("ana@icesi.edu.co").isActive(true)
                .roles(Set.of(role)).build();

        assertEquals(id, permission.getId());
        assertEquals("lookup", permission.getDescription());
        assertEquals("admin", role.getDescription());
        assertTrue(user.getRoles().contains(role));
        assertEquals("ana@icesi.edu.co", user.getEmail());
    }

    @Test
    void equalityFollowsTheFields() {
        assertEquals(Permission.builder().name("a").build(), Permission.builder().name("a").build());
        assertNotEquals(Permission.builder().name("a").build(), Permission.builder().name("b").build());
        assertEquals(Role.builder().name("r").build().hashCode(), Role.builder().name("r").build().hashCode());
        LocalUser user = new LocalUser();
        user.setUsername("x");
        assertTrue(user.toString().contains("x"));
    }
}
