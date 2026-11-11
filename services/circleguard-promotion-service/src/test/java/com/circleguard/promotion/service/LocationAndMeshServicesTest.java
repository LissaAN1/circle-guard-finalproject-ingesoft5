package com.circleguard.promotion.service;

import com.circleguard.promotion.model.AccessPoint;
import com.circleguard.promotion.model.Building;
import com.circleguard.promotion.model.Floor;
import com.circleguard.promotion.model.graph.CircleNode;
import com.circleguard.promotion.repository.graph.CircleNodeRepository;
import com.circleguard.promotion.repository.graph.UserNodeRepository;
import com.circleguard.promotion.repository.jpa.AccessPointRepository;
import org.junit.jupiter.api.Test;
import org.springframework.data.redis.core.SetOperations;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.ValueOperations;
import org.springframework.kafka.core.KafkaTemplate;

import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SuppressWarnings("unchecked")
class LocationAndMeshServicesTest {

    // ---- MacSessionRegistry -------------------------------------------------------------------

    private final StringRedisTemplate redis = mock(StringRedisTemplate.class);
    private final ValueOperations<String, String> values = mock(ValueOperations.class);
    private final SetOperations<String, String> sets = mock(SetOperations.class);

    LocationAndMeshServicesTest() {
        when(redis.opsForValue()).thenReturn(values);
        when(redis.opsForSet()).thenReturn(sets);
    }

    @Test
    void sessionRegistryNormalizesTheMacAddress() {
        MacSessionRegistry registry = new MacSessionRegistry(redis);
        when(values.get("session:mac:aa:bb")).thenReturn("anon-1");

        registry.registerSession("AA:BB", "anon-1");

        verify(values).set("session:mac:aa:bb", "anon-1", Duration.ofHours(8));
        assertEquals("anon-1", registry.getAnonymousId("AA:BB"));
        registry.closeSession("AA:BB");
        verify(redis).delete("session:mac:aa:bb");
    }

    // ---- LocationResolutionService ------------------------------------------------------------

    private final AccessPointRepository accessPoints = mock(AccessPointRepository.class);
    private final MacSessionRegistry sessions = mock(MacSessionRegistry.class);
    private final GraphService graph = mock(GraphService.class);
    private final KafkaTemplate<String, Object> kafka = mock(KafkaTemplate.class);
    private final LocationResolutionService location =
            new LocationResolutionService(accessPoints, sessions, graph, kafka, redis);

    private AccessPoint accessPoint() {
        Building building = Building.builder().id(UUID.randomUUID()).build();
        Floor floor = Floor.builder().id(UUID.randomUUID()).building(building).floorNumber(2).build();
        return AccessPoint.builder().id(UUID.randomUUID()).floor(floor).coordinateX(1.0).coordinateY(2.0).name("AP").build();
    }

    @Test
    void unknownAccessPointIsIgnored() {
        when(accessPoints.findByMacAddress("ap-mac")).thenReturn(Optional.empty());

        location.processSignal("ap-mac", "device", -50.0);

        verify(kafka, never()).send(anyString(), anyString(), any());
    }

    @Test
    void deviceWithoutAnActiveSessionIsIgnored() {
        when(accessPoints.findByMacAddress("ap-mac")).thenReturn(Optional.of(accessPoint()));
        when(sessions.getAnonymousId("device")).thenReturn(null);

        location.processSignal("ap-mac", "device", -50.0);

        verify(kafka, never()).send(anyString(), anyString(), any());
        verify(graph, never()).detectAndFormCircles(anyString());
    }

    @Test
    void resolvedSignalIsPublishedAndRecordsEncountersWithOthersAtTheSameAccessPoint() {
        AccessPoint ap = accessPoint();
        String locationId = ap.getId().toString();
        when(accessPoints.findByMacAddress("ap-mac")).thenReturn(Optional.of(ap));
        when(sessions.getAnonymousId("device")).thenReturn("me");
        when(sets.members("spatial:location:" + locationId)).thenReturn(Set.of("me", "other"));

        location.processSignal("ap-mac", "device", -61.5);

        verify(kafka).send(eq("proximity.detected"), eq("me"), any());
        verify(graph).recordEncounter("me", "other", locationId);
        verify(graph, never()).recordEncounter("me", "me", locationId);
        verify(sets).add("spatial:location:" + locationId, "me");
        verify(redis).expire("spatial:location:" + locationId, Duration.ofMinutes(10));
        verify(graph).detectAndFormCircles(locationId);
    }

    @Test
    void firstUserAtAnAccessPointRecordsNoEncounter() {
        AccessPoint ap = accessPoint();
        when(accessPoints.findByMacAddress("ap-mac")).thenReturn(Optional.of(ap));
        when(sessions.getAnonymousId("device")).thenReturn("me");
        when(sets.members(anyString())).thenReturn(null);

        location.processSignal("ap-mac", "device", -70.0);

        verify(graph, never()).recordEncounter(anyString(), anyString(), anyString());
        verify(graph).detectAndFormCircles(ap.getId().toString());
    }

    // ---- AutoCircleService --------------------------------------------------------------------

    private final UserNodeRepository users = mock(UserNodeRepository.class);
    private final CircleNodeRepository circles = mock(CircleNodeRepository.class);
    private final CircleService circleService = mock(CircleService.class);
    private final AutoCircleService auto = new AutoCircleService(users, circles, circleService);

    @Test
    void sameOrMissingUsersAreSkipped() {
        auto.evaluateEncounter(null, "b");
        auto.evaluateEncounter("a", null);
        auto.evaluateEncounter("a", "a");

        verify(users, never()).getCumulativeEncounterDuration(anyString(), anyString());
    }

    @Test
    void shortEncountersDoNotCreateACircle() {
        when(users.getCumulativeEncounterDuration("a", "b")).thenReturn(600L);

        auto.evaluateEncounter("a", "b");

        verify(circles, never()).save(any(CircleNode.class));
    }

    @Test
    void anHourTogetherCreatesAnAutomaticCircleAndJoinsBothUsers() {
        when(users.getCumulativeEncounterDuration("a", "b")).thenReturn(3600L);
        when(circles.findCommonCircles("a", "b")).thenReturn(List.of());

        auto.evaluateEncounter("a", "b");

        var captor = org.mockito.ArgumentCaptor.forClass(CircleNode.class);
        verify(circles).save(captor.capture());
        CircleNode created = captor.getValue();
        assertEquals(true, created.getIsAutoGenerated());
        assertEquals(true, created.getInviteCode().startsWith("AUTO-"));
        verify(circleService).joinCircle("a", created.getInviteCode());
        verify(circleService).joinCircle("b", created.getInviteCode());
    }

    @Test
    void usersAlreadySharingAnAutomaticCircleAreNotConnectedAgain() {
        when(users.getCumulativeEncounterDuration("a", "b")).thenReturn(7200L);
        CircleNode existing = CircleNode.builder().isAutoGenerated(true).build();
        when(circles.findCommonCircles("a", "b")).thenReturn(List.of(existing));

        auto.evaluateEncounter("a", "b");

        verify(circles, never()).save(any(CircleNode.class));
    }
}
