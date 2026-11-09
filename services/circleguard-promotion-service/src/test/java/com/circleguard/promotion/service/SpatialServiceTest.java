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

class SpatialServiceTest {

    private final BuildingRepository buildings = mock(BuildingRepository.class);
    private final FloorRepository floors = mock(FloorRepository.class);
    private final AccessPointRepository accessPoints = mock(AccessPointRepository.class);
    private final SpatialService service = new SpatialService(buildings, floors, accessPoints);

    @Test
    void createsAndListsBuildings() {
        when(buildings.save(any(Building.class))).thenAnswer(inv -> inv.getArgument(0));
        List<Building> all = List.of(new Building());
        when(buildings.findAll()).thenReturn(all);

        Building created = service.createBuilding("Torre", "T1", "desc");

        assertEquals("Torre", created.getName());
        assertEquals("T1", created.getCode());
        assertEquals("desc", created.getDescription());
        assertEquals(all, service.getAllBuildings());
    }

    @Test
    void addsAFloorToAnExistingBuildingOnly() {
        UUID id = UUID.randomUUID();
        Building building = Building.builder().id(id).build();
        when(buildings.findById(id)).thenReturn(Optional.of(building));
        when(floors.save(any(Floor.class))).thenAnswer(inv -> inv.getArgument(0));
        UUID unknown = UUID.randomUUID();
        when(buildings.findById(unknown)).thenReturn(Optional.empty());

        Floor floor = service.addFloor(id, 2, "P2");

        assertSame(building, floor.getBuilding());
        assertEquals(2, floor.getFloorNumber());
        assertThrows(RuntimeException.class, () -> service.addFloor(unknown, 1, "x"));
    }

    @Test
    void listsFloorsByBuilding() {
        UUID id = UUID.randomUUID();
        List<Floor> expected = List.of(new Floor());
        when(floors.findByBuildingId(id)).thenReturn(expected);

        assertEquals(expected, service.getFloorsByBuilding(id));
    }

    @Test
    void updatesABuildingOrFailsWhenUnknown() {
        UUID id = UUID.randomUUID();
        Building stored = Building.builder().id(id).build();
        when(buildings.findById(id)).thenReturn(Optional.of(stored));
        when(buildings.save(stored)).thenReturn(stored);
        UUID unknown = UUID.randomUUID();
        when(buildings.findById(unknown)).thenReturn(Optional.empty());

        Building updated = service.updateBuilding(id, "n", "c", "d");

        assertEquals("n", updated.getName());
        assertEquals("c", updated.getCode());
        assertEquals("d", updated.getDescription());
        assertThrows(RuntimeException.class, () -> service.updateBuilding(unknown, "n", "c", "d"));
    }

    @Test
    void deletesABuildingOnlyWhenItHasNoFloors() {
        UUID empty = UUID.randomUUID();
        UUID busy = UUID.randomUUID();
        when(floors.findByBuildingId(empty)).thenReturn(List.of());
        when(floors.findByBuildingId(busy)).thenReturn(List.of(new Floor()));

        service.deleteBuilding(empty);

        verify(buildings).deleteById(empty);
        assertThrows(RuntimeException.class, () -> service.deleteBuilding(busy));
        verify(buildings, never()).deleteById(busy);
    }

    @Test
    void updatesAFloorOrFailsWhenUnknown() {
        UUID id = UUID.randomUUID();
        Floor stored = Floor.builder().id(id).build();
        when(floors.findById(id)).thenReturn(Optional.of(stored));
        when(floors.save(stored)).thenReturn(stored);
        UUID unknown = UUID.randomUUID();
        when(floors.findById(unknown)).thenReturn(Optional.empty());

        Floor updated = service.updateFloor(id, 7, "P7");

        assertEquals(7, updated.getFloorNumber());
        assertEquals("P7", updated.getName());
        assertThrows(RuntimeException.class, () -> service.updateFloor(unknown, 1, "x"));
    }

    @Test
    void deletesAFloorOnlyWhenItHasNoAccessPoints() {
        UUID empty = UUID.randomUUID();
        UUID busy = UUID.randomUUID();
        when(accessPoints.findByFloorId(empty)).thenReturn(List.of());
        when(accessPoints.findByFloorId(busy)).thenReturn(List.of(new AccessPoint()));

        service.deleteFloor(empty);

        verify(floors).deleteById(empty);
        assertThrows(RuntimeException.class, () -> service.deleteFloor(busy));
        verify(floors, never()).deleteById(busy);
    }

    @Test
    void registersReadsUpdatesAndDeletesAccessPoints() {
        UUID floorId = UUID.randomUUID();
        Floor floor = Floor.builder().id(floorId).build();
        when(floors.findById(floorId)).thenReturn(Optional.of(floor));
        when(accessPoints.save(any(AccessPoint.class))).thenAnswer(inv -> inv.getArgument(0));
        UUID unknownFloor = UUID.randomUUID();
        when(floors.findById(unknownFloor)).thenReturn(Optional.empty());

        AccessPoint ap = service.registerAccessPoint(floorId, "AA:BB", 1.0, 2.0, "AP-1");
        assertSame(floor, ap.getFloor());
        assertThrows(RuntimeException.class, () -> service.registerAccessPoint(unknownFloor, "m", 0.0, 0.0, "n"));

        UUID apId = UUID.randomUUID();
        AccessPoint stored = AccessPoint.builder().id(apId).build();
        when(accessPoints.findById(apId)).thenReturn(Optional.of(stored));
        when(accessPoints.findByFloorId(floorId)).thenReturn(List.of(stored));
        when(accessPoints.save(stored)).thenReturn(stored);

        assertSame(stored, service.getAccessPoint(apId).orElseThrow());
        assertEquals(List.of(stored), service.getAccessPointsByFloor(floorId));
        AccessPoint updated = service.updateAccessPoint(apId, "CC:DD", 3.0, 4.0, "AP-2");
        assertEquals("CC:DD", updated.getMacAddress());
        assertEquals(4.0, updated.getCoordinateY());
        service.deleteAccessPoint(apId);
        verify(accessPoints).deleteById(apId);

        UUID unknownAp = UUID.randomUUID();
        when(accessPoints.findById(unknownAp)).thenReturn(Optional.empty());
        assertThrows(RuntimeException.class, () -> service.updateAccessPoint(unknownAp, "m", 0.0, 0.0, "n"));
    }
}
