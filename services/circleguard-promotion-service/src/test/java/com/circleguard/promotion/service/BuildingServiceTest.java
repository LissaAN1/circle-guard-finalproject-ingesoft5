package com.circleguard.promotion.service;

import com.circleguard.promotion.model.Building;
import com.circleguard.promotion.model.Floor;
import com.circleguard.promotion.repository.jpa.BuildingRepository;
import com.circleguard.promotion.repository.jpa.FloorRepository;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class BuildingServiceTest {

    private final BuildingRepository buildings = mock(BuildingRepository.class);
    private final FloorRepository floors = mock(FloorRepository.class);
    private final BuildingService service = new BuildingService(buildings, floors);

    @Test
    void createsABuildingWithAllItsData() {
        when(buildings.save(any(Building.class))).thenAnswer(inv -> inv.getArgument(0));

        Building created = service.createBuilding("Torre", "T1", "Torre principal", 3.34, -76.53, "Calle 18");

        assertEquals("Torre", created.getName());
        assertEquals("T1", created.getCode());
        assertEquals("Torre principal", created.getDescription());
        assertEquals(3.34, created.getLatitude());
        assertEquals(-76.53, created.getLongitude());
        assertEquals("Calle 18", created.getAddress());
    }

    @Test
    void listsAllBuildings() {
        List<Building> all = List.of(new Building(), new Building());
        when(buildings.findAll()).thenReturn(all);

        assertEquals(all, service.getAllBuildings());
    }

    @Test
    void updatesAnExistingBuilding() {
        UUID id = UUID.randomUUID();
        Building stored = Building.builder().id(id).name("old").build();
        when(buildings.findById(id)).thenReturn(Optional.of(stored));
        when(buildings.save(stored)).thenReturn(stored);

        Building updated = service.updateBuilding(id, "new", "N1", "desc", 1.0, 2.0, "addr");

        assertEquals("new", updated.getName());
        assertEquals("N1", updated.getCode());
        assertEquals("addr", updated.getAddress());
    }

    @Test
    void updatingAnUnknownBuildingFails() {
        UUID id = UUID.randomUUID();
        when(buildings.findById(id)).thenReturn(Optional.empty());

        assertThrows(RuntimeException.class, () -> service.updateBuilding(id, "n", "c", "d", 0.0, 0.0, "a"));
    }

    @Test
    void deletesABuildingWithoutFloors() {
        UUID id = UUID.randomUUID();
        when(floors.findByBuildingId(id)).thenReturn(List.of());

        service.deleteBuilding(id);

        verify(buildings).deleteById(id);
    }

    @Test
    void refusesToDeleteABuildingThatStillHasFloors() {
        UUID id = UUID.randomUUID();
        when(floors.findByBuildingId(id)).thenReturn(List.of(new Floor()));

        assertThrows(RuntimeException.class, () -> service.deleteBuilding(id));
        verify(buildings, never()).deleteById(id);
    }
}
