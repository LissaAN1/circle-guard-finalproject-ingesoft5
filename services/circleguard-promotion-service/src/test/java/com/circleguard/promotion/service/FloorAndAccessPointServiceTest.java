package com.circleguard.promotion.service;

import com.circleguard.promotion.model.AccessPoint;
import com.circleguard.promotion.model.Building;
import com.circleguard.promotion.model.Floor;
import com.circleguard.promotion.repository.jpa.AccessPointRepository;
import com.circleguard.promotion.repository.jpa.BuildingRepository;
import com.circleguard.promotion.repository.jpa.FloorRepository;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class FloorAndAccessPointServiceTest {

    private final BuildingRepository buildings = mock(BuildingRepository.class);
    private final FloorRepository floors = mock(FloorRepository.class);
    private final AccessPointRepository accessPoints = mock(AccessPointRepository.class);
    private final FloorService floorService = new FloorService(buildings, floors, accessPoints);
    private final AccessPointService apService = new AccessPointService(accessPoints, floors);

    @Test
    void addsAFloorToAnExistingBuilding() {
        UUID buildingId = UUID.randomUUID();
        Building building = Building.builder().id(buildingId).build();
        when(buildings.findById(buildingId)).thenReturn(Optional.of(building));
        when(floors.save(any(Floor.class))).thenAnswer(inv -> inv.getArgument(0));

        Floor floor = floorService.addFloor(buildingId, 3, "Tercer piso");

        assertSame(building, floor.getBuilding());
        assertEquals(3, floor.getFloorNumber());
        assertEquals("Tercer piso", floor.getName());
    }

    @Test
    void addingAFloorToAnUnknownBuildingFails() {
        UUID buildingId = UUID.randomUUID();
        when(buildings.findById(buildingId)).thenReturn(Optional.empty());

        assertThrows(RuntimeException.class, () -> floorService.addFloor(buildingId, 1, "x"));
    }

    @Test
    void listsTheFloorsOfABuilding() {
        UUID buildingId = UUID.randomUUID();
        List<Floor> expected = List.of(new Floor());
        when(floors.findByBuildingId(buildingId)).thenReturn(expected);

        assertEquals(expected, floorService.getFloorsByBuilding(buildingId));
    }

    @Test
    void updatingAnUnknownFloorFails() {
        UUID id = UUID.randomUUID();
        when(floors.findById(id)).thenReturn(Optional.empty());

        assertThrows(RuntimeException.class, () -> floorService.updateFloor(id, 1, "x", "u"));
    }

    @Test
    void updateKeepsTheFieldsThatAreNotProvided() {
        UUID id = UUID.randomUUID();
        Floor stored = Floor.builder().id(id).floorNumber(2).name("old").floorPlanUrl("plan").build();
        when(floors.findById(id)).thenReturn(Optional.of(stored));
        when(floors.save(stored)).thenReturn(stored);

        Floor updated = floorService.updateFloor(id, null, "new", null);

        assertEquals(2, updated.getFloorNumber());
        assertEquals("new", updated.getName());
        assertEquals("plan", updated.getFloorPlanUrl());
    }

    @Test
    void deletesAFloorWithoutAccessPoints() {
        UUID id = UUID.randomUUID();
        when(accessPoints.findByFloorId(id)).thenReturn(List.of());

        floorService.deleteFloor(id);

        verify(floors).deleteById(id);
    }

    @Test
    void refusesToDeleteAFloorWithAccessPoints() {
        UUID id = UUID.randomUUID();
        when(accessPoints.findByFloorId(id)).thenReturn(List.of(new AccessPoint()));

        assertThrows(RuntimeException.class, () -> floorService.deleteFloor(id));
        verify(floors, never()).deleteById(id);
    }

    @Test
    void registersAnAccessPointOnAFloor() {
        UUID floorId = UUID.randomUUID();
        Floor floor = Floor.builder().id(floorId).build();
        when(floors.findById(floorId)).thenReturn(Optional.of(floor));
        when(accessPoints.save(any(AccessPoint.class))).thenAnswer(inv -> inv.getArgument(0));

        AccessPoint ap = apService.registerAccessPoint(floorId, "AA:BB:CC:DD:EE:FF", 1.5, 2.5, "AP-1");

        assertSame(floor, ap.getFloor());
        assertEquals("AA:BB:CC:DD:EE:FF", ap.getMacAddress());
        assertEquals(1.5, ap.getCoordinateX());
        assertEquals(2.5, ap.getCoordinateY());
        assertEquals("AP-1", ap.getName());
    }

    @Test
    void registeringOnAnUnknownFloorFails() {
        UUID floorId = UUID.randomUUID();
        when(floors.findById(floorId)).thenReturn(Optional.empty());

        assertThrows(RuntimeException.class, () -> apService.registerAccessPoint(floorId, "m", 0.0, 0.0, "n"));
    }

    @Test
    void readsAccessPointsById() {
        UUID id = UUID.randomUUID();
        AccessPoint ap = new AccessPoint();
        when(accessPoints.findById(id)).thenReturn(Optional.of(ap));
        when(accessPoints.findByFloorId(id)).thenReturn(List.of(ap));

        assertSame(ap, apService.getAccessPoint(id).orElseThrow());
        assertEquals(List.of(ap), apService.getAccessPointsByFloor(id));
    }

    @Test
    void updatesAndDeletesAnAccessPoint() {
        UUID id = UUID.randomUUID();
        AccessPoint stored = AccessPoint.builder().id(id).name("old").build();
        when(accessPoints.findById(id)).thenReturn(Optional.of(stored));
        when(accessPoints.save(stored)).thenReturn(stored);

        AccessPoint updated = apService.updateAccessPoint(id, "11:22", 4.0, 5.0, "new");
        apService.deleteAccessPoint(id);

        assertEquals("new", updated.getName());
        assertEquals("11:22", updated.getMacAddress());
        assertEquals(4.0, updated.getCoordinateX());
        verify(accessPoints).deleteById(id);
    }

    @Test
    void updatingAnUnknownAccessPointFails() {
        UUID id = UUID.randomUUID();
        when(accessPoints.findById(id)).thenReturn(Optional.empty());

        assertThrows(RuntimeException.class, () -> apService.updateAccessPoint(id, "m", 0.0, 0.0, "n"));
    }
}
