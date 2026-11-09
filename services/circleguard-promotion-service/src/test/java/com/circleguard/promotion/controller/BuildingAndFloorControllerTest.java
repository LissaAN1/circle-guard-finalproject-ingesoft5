package com.circleguard.promotion.controller;

import com.circleguard.promotion.dto.AccessPointDTO;
import com.circleguard.promotion.dto.BuildingDTO;
import com.circleguard.promotion.dto.FloorDTO;
import com.circleguard.promotion.model.AccessPoint;
import com.circleguard.promotion.model.Building;
import com.circleguard.promotion.model.Floor;
import com.circleguard.promotion.service.AccessPointService;
import com.circleguard.promotion.service.BuildingService;
import com.circleguard.promotion.service.FloorService;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class BuildingAndFloorControllerTest {

    private final BuildingService buildingService = mock(BuildingService.class);
    private final FloorService floorService = mock(FloorService.class);
    private final AccessPointService accessPointService = mock(AccessPointService.class);
    private final BuildingController buildings = new BuildingController(buildingService, floorService);
    private final FloorController floors = new FloorController(floorService, accessPointService);

    private Building building(UUID id) {
        return Building.builder().id(id).name("Torre").code("T1").description("d")
                .latitude(3.3).longitude(-76.5).address("Calle 18").build();
    }

    @Test
    void createBuildingReturnsTheStoredBuilding() {
        UUID id = UUID.randomUUID();
        BuildingDTO request = BuildingDTO.builder().name("Torre").code("T1").description("d")
                .latitude(3.3).longitude(-76.5).address("Calle 18").build();
        when(buildingService.createBuilding("Torre", "T1", "d", 3.3, -76.5, "Calle 18")).thenReturn(building(id));

        BuildingDTO body = buildings.createBuilding(request).getBody();

        assertEquals(id, body.getId());
        assertEquals("Torre", body.getName());
        assertNull(body.getFloors());
    }

    @Test
    void listBuildingsIncludesTheirFloors() {
        UUID id = UUID.randomUUID();
        Building withFloors = building(id);
        withFloors.setFloors(List.of(Floor.builder().id(UUID.randomUUID()).building(withFloors).floorNumber(1).name("P1").build()));
        when(buildingService.getAllBuildings()).thenReturn(List.of(withFloors));

        List<BuildingDTO> body = buildings.listBuildings().getBody();

        assertEquals(1, body.size());
        assertEquals(1, body.get(0).getFloors().size());
        assertEquals(id, body.get(0).getFloors().get(0).getBuildingId());
    }

    @Test
    void getFloorsMapsEveryFloor() {
        UUID buildingId = UUID.randomUUID();
        Floor floor = Floor.builder().id(UUID.randomUUID()).floorNumber(2).name("P2").floorPlanUrl("plan").build();
        when(floorService.getFloorsByBuilding(buildingId)).thenReturn(List.of(floor));

        List<FloorDTO> body = buildings.getFloors(buildingId).getBody();

        assertEquals("P2", body.get(0).getName());
        assertEquals("plan", body.get(0).getFloorPlanUrl());
        assertNull(body.get(0).getBuildingId());
    }

    @Test
    void addFloorDelegatesToTheService() {
        UUID buildingId = UUID.randomUUID();
        Floor floor = Floor.builder().id(UUID.randomUUID()).building(building(buildingId)).floorNumber(4).name("P4").build();
        when(floorService.addFloor(buildingId, 4, "P4")).thenReturn(floor);

        FloorDTO body = buildings.addFloor(buildingId, FloorDTO.builder().floorNumber(4).name("P4").build()).getBody();

        assertEquals(buildingId, body.getBuildingId());
        assertEquals(4, body.getFloorNumber());
    }

    @Test
    void updateBuildingReturnsTheUpdatedData() {
        UUID id = UUID.randomUUID();
        BuildingDTO request = BuildingDTO.builder().name("Nueva").code("N1").description("x")
                .latitude(1.0).longitude(2.0).address("a").build();
        Building updated = building(id);
        updated.setName("Nueva");
        when(buildingService.updateBuilding(id, "Nueva", "N1", "x", 1.0, 2.0, "a")).thenReturn(updated);

        assertEquals("Nueva", buildings.updateBuilding(id, request).getBody().getName());
    }

    @Test
    void deleteBuildingAnswersOk() {
        UUID id = UUID.randomUUID();

        ResponseEntity<Void> response = buildings.deleteBuilding(id);

        assertEquals(200, response.getStatusCode().value());
        verify(buildingService).deleteBuilding(id);
    }

    @Test
    void addAccessPointMapsTheRegisteredAccessPoint() {
        UUID floorId = UUID.randomUUID();
        Floor floor = Floor.builder().id(floorId).build();
        AccessPoint ap = AccessPoint.builder().id(UUID.randomUUID()).floor(floor).macAddress("AA:BB")
                .coordinateX(1.0).coordinateY(2.0).name("AP-1").build();
        when(accessPointService.registerAccessPoint(floorId, "AA:BB", 1.0, 2.0, "AP-1")).thenReturn(ap);
        AccessPointDTO request = AccessPointDTO.builder().macAddress("AA:BB").coordinateX(1.0).coordinateY(2.0).name("AP-1").build();

        AccessPointDTO body = floors.addAccessPoint(floorId, request).getBody();

        assertEquals(floorId, body.getFloorId());
        assertEquals("AA:BB", body.getMacAddress());
    }

    @Test
    void getAccessPointsMapsAccessPointsWithoutFloor() {
        UUID floorId = UUID.randomUUID();
        AccessPoint ap = AccessPoint.builder().id(UUID.randomUUID()).macAddress("CC:DD").name("AP-2").build();
        when(accessPointService.getAccessPointsByFloor(floorId)).thenReturn(List.of(ap));

        List<AccessPointDTO> body = floors.getAccessPoints(floorId).getBody();

        assertEquals("AP-2", body.get(0).getName());
        assertNull(body.get(0).getFloorId());
    }

    @Test
    void updateFloorReturnsTheUpdatedFloor() {
        UUID id = UUID.randomUUID();
        Floor updated = Floor.builder().id(id).floorNumber(5).name("P5").floorPlanUrl("p.png").build();
        when(floorService.updateFloor(id, 5, "P5", "p.png")).thenReturn(updated);

        FloorDTO body = floors.updateFloor(id, FloorDTO.builder().floorNumber(5).name("P5").floorPlanUrl("p.png").build()).getBody();

        assertEquals("p.png", body.getFloorPlanUrl());
    }

    @Test
    void deleteFloorAnswersOk() {
        UUID id = UUID.randomUUID();

        assertEquals(200, floors.deleteFloor(id).getStatusCode().value());
        verify(floorService).deleteFloor(id);
    }
}
