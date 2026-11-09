package com.circleguard.promotion.service;

import com.circleguard.promotion.model.graph.CircleNode;
import com.circleguard.promotion.model.graph.UserNode;
import com.circleguard.promotion.repository.graph.CircleNodeRepository;
import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CircleServiceTest {

    private final CircleNodeRepository circles = mock(CircleNodeRepository.class);
    private final HealthStatusService health = mock(HealthStatusService.class);
    private final CircleService service = new CircleService(circles, health);

    private CircleNode circle(UserNode... members) {
        return CircleNode.builder().id(1L).name("Mesh").members(new HashSet<>(Set.of(members))).build();
    }

    private UserNode user(String id, String status) {
        return UserNode.builder().anonymousId(id).status(status).build();
    }

    @Test
    void invalidatingACircleResolvesItsMembers() {
        CircleNode circle = circle(user("u1", "SUSPECT"), user("u2", "ACTIVE"));
        when(circles.findById(1L)).thenReturn(Optional.of(circle));

        service.toggleCircleValidity(1L);

        assertFalse(circle.getIsValid());
        verify(circles).save(circle);
        verify(health).resolveStatus("u1");
        verify(health).resolveStatus("u2");
    }

    @Test
    void revalidatingACircleDoesNotTouchTheMembers() {
        CircleNode circle = circle(user("u1", "SUSPECT"));
        circle.setIsValid(false);
        when(circles.findById(1L)).thenReturn(Optional.of(circle));

        service.toggleCircleValidity(1L);

        assertTrue(circle.getIsValid());
        verify(health, never()).resolveStatus(anyString());
    }

    @Test
    void togglingAnUnknownCircleFails() {
        when(circles.findById(9L)).thenReturn(Optional.empty());

        assertThrows(RuntimeException.class, () -> service.toggleCircleValidity(9L));
    }

    @Test
    void forceFencePromotesOnlyActiveMembersToProbable() {
        CircleNode circle = circle(user("active", "ACTIVE"), user("sick", "CONFIRMED"));
        when(circles.findById(1L)).thenReturn(Optional.of(circle));

        service.forceFenceCircle(1L);

        assertTrue(circle.getForceFence());
        verify(circles).save(circle);
        verify(health).updateStatus("active", "PROBABLE");
        verify(health, never()).updateStatus("sick", "PROBABLE");
    }

    @Test
    void forceFenceOnAnUnknownCircleFails() {
        when(circles.findById(9L)).thenReturn(Optional.empty());

        assertThrows(RuntimeException.class, () -> service.forceFenceCircle(9L));
    }

    @Test
    void createsACircleWithAFreshInviteCode() {
        when(circles.existsByInviteCode(anyString())).thenReturn(true, false);
        when(circles.save(any(CircleNode.class))).thenAnswer(inv -> inv.getArgument(0));

        CircleNode created = service.createCircle("Mesh", "loc-1");

        assertEquals("Mesh", created.getName());
        assertEquals("loc-1", created.getLocationId());
        assertTrue(created.getIsActive());
        assertTrue(created.getInviteCode().matches("MESH-[A-Z2-9]{4}"));
        verify(circles, org.mockito.Mockito.times(2)).existsByInviteCode(anyString());
    }

    @Test
    void joinsACircleByInviteCodeOrFails() {
        CircleNode joined = circle();
        when(circles.joinCircle("u1", "MESH-ABCD")).thenReturn(Optional.of(joined));
        when(circles.joinCircle("u1", "BAD")).thenReturn(Optional.empty());

        assertSame(joined, service.joinCircle("u1", "MESH-ABCD"));
        assertThrows(RuntimeException.class, () -> service.joinCircle("u1", "BAD"));
    }

    @Test
    void addsAMemberManuallyOrFails() {
        CircleNode circle = circle();
        when(circles.addUserToCircle("u1", 1L)).thenReturn(Optional.of(circle));
        when(circles.addUserToCircle("u2", 1L)).thenReturn(Optional.empty());

        assertSame(circle, service.addMember(1L, "u1"));
        assertThrows(RuntimeException.class, () -> service.addMember(1L, "u2"));
    }

    @Test
    void listsTheCirclesOfAUser() {
        List<CircleNode> expected = List.of(circle());
        when(circles.findCirclesByUser("u1")).thenReturn(expected);

        assertEquals(expected, service.getUserCircles("u1"));
    }
}
