package com.circleguard.promotion.controller;

import com.circleguard.promotion.model.graph.CircleNode;
import com.circleguard.promotion.model.jpa.SystemSettings;
import com.circleguard.promotion.repository.graph.UserNodeRepository;
import com.circleguard.promotion.repository.jpa.SystemSettingsRepository;
import com.circleguard.promotion.service.AutoCircleService;
import com.circleguard.promotion.service.CircleService;
import com.circleguard.promotion.service.LocationResolutionService;
import com.circleguard.promotion.service.MacSessionRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class RemainingControllersTest {

    // ------------------------------------------------------------------ AdminController

    private final SystemSettingsRepository settingsRepo = mock(SystemSettingsRepository.class);
    private final AdminController admin = new AdminController(settingsRepo);

    private SystemSettings defaultSettings() {
        return SystemSettings.builder()
                .id(1L)
                .unconfirmedFencingEnabled(true)
                .autoThresholdSeconds(3600L)
                .mandatoryFenceDays(14)
                .encounterWindowDays(14)
                .build();
    }

    @Test
    void getSettings_whenExists_returnsStoredSettings() {
        SystemSettings stored = defaultSettings();
        when(settingsRepo.getSettings()).thenReturn(Optional.of(stored));

        ResponseEntity<SystemSettings> response = admin.getSettings();

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody().getUnconfirmedFencingEnabled()).isTrue();
    }

    @Test
    void getSettings_whenAbsent_initializesAndReturnsDefaults() {
        when(settingsRepo.getSettings()).thenReturn(Optional.empty());
        when(settingsRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        ResponseEntity<SystemSettings> response = admin.getSettings();

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(settingsRepo).save(any(SystemSettings.class));
    }

    @Test
    void updateSettings_partialUpdate_onlyChangesProvidedFields() {
        SystemSettings existing = defaultSettings();
        when(settingsRepo.getSettings()).thenReturn(Optional.of(existing));
        when(settingsRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        SystemSettings patch = SystemSettings.builder().mandatoryFenceDays(7).build();
        ResponseEntity<SystemSettings> response = admin.updateSettings(patch);

        assertThat(response.getBody().getMandatoryFenceDays()).isEqualTo(7);
        assertThat(response.getBody().getAutoThresholdSeconds()).isEqualTo(3600L);
    }

    @Test
    void updateSettings_whenSettingsAbsent_initializesFirst() {
        when(settingsRepo.getSettings()).thenReturn(Optional.empty());
        when(settingsRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        SystemSettings patch = SystemSettings.builder().unconfirmedFencingEnabled(false).build();
        admin.updateSettings(patch);

        verify(settingsRepo).save(any(SystemSettings.class));
    }

    @Test
    void toggleUnconfirmedFencing_enabledTrue_updatesFlag() {
        SystemSettings existing = defaultSettings();
        when(settingsRepo.getSettings()).thenReturn(Optional.of(existing));
        when(settingsRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        ResponseEntity<SystemSettings> response = admin.toggleUnconfirmedFencing(false);

        assertThat(response.getBody().getUnconfirmedFencingEnabled()).isFalse();
        verify(settingsRepo).save(any(SystemSettings.class));
    }

    @Test
    void toggleUnconfirmedFencing_whenAbsent_initializesFirst() {
        when(settingsRepo.getSettings()).thenReturn(Optional.empty());
        when(settingsRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        admin.toggleUnconfirmedFencing(true);

        verify(settingsRepo).save(any(SystemSettings.class));
    }

    @Test
    void updateSettings_allFieldsProvided_updatesEverything() {
        SystemSettings existing = defaultSettings();
        when(settingsRepo.getSettings()).thenReturn(Optional.of(existing));
        when(settingsRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        SystemSettings patch = SystemSettings.builder()
                .unconfirmedFencingEnabled(false)
                .autoThresholdSeconds(7200L)
                .mandatoryFenceDays(21)
                .encounterWindowDays(30)
                .build();
        ResponseEntity<SystemSettings> response = admin.updateSettings(patch);

        assertThat(response.getBody().getUnconfirmedFencingEnabled()).isFalse();
        assertThat(response.getBody().getAutoThresholdSeconds()).isEqualTo(7200L);
        assertThat(response.getBody().getMandatoryFenceDays()).isEqualTo(21);
        assertThat(response.getBody().getEncounterWindowDays()).isEqualTo(30);
    }

    // ------------------------------------------------------------------ CircleController

    private final CircleService circleService = mock(CircleService.class);
    private final CircleController circles = new CircleController(circleService);

    private CircleNode circle(Long id) {
        return CircleNode.builder().id(id).name("C1").inviteCode("ABC").build();
    }

    @Test
    void createCircle_delegatesToService() {
        when(circleService.createCircle("C1", "loc1")).thenReturn(circle(1L));

        CircleController.CircleCreateRequest req = new CircleController.CircleCreateRequest();
        req.setName("C1");
        req.setLocationId("loc1");

        ResponseEntity<CircleNode> response = circles.createCircle(req);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody().getId()).isEqualTo(1L);
    }

    @Test
    void joinCircle_delegatesToService() {
        when(circleService.joinCircle("user1", "CODE1")).thenReturn(circle(2L));

        ResponseEntity<CircleNode> response = circles.joinCircle("CODE1", "user1");

        assertThat(response.getBody().getId()).isEqualTo(2L);
        verify(circleService).joinCircle("user1", "CODE1");
    }

    @Test
    void addMember_delegatesToService() {
        when(circleService.addMember(1L, "user2")).thenReturn(circle(1L));

        ResponseEntity<CircleNode> response = circles.addMember(1L, "user2");

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(circleService).addMember(1L, "user2");
    }

    @Test
    void getUserCircles_returnsList() {
        when(circleService.getUserCircles("user1")).thenReturn(List.of(circle(1L), circle(2L)));

        ResponseEntity<List<CircleNode>> response = circles.getUserCircles("user1");

        assertThat(response.getBody()).hasSize(2);
    }

    @Test
    void toggleCircleValidity_callsService() {
        ResponseEntity<Void> response = circles.toggleValidity(1L);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(circleService).toggleCircleValidity(1L);
    }

    @Test
    void forceFenceCircle_callsService() {
        ResponseEntity<Void> response = circles.forceFence(1L);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(circleService).forceFenceCircle(1L);
    }

    // ------------------------------------------------------------------ EncounterController

    private final UserNodeRepository userRepo = mock(UserNodeRepository.class);
    private final AutoCircleService autoCircle = mock(AutoCircleService.class);
    private final EncounterController encounters = new EncounterController(userRepo, autoCircle);

    @Test
    void reportEncounter_recordsAndEvaluates() {
        EncounterController.EncounterRequest req = new EncounterController.EncounterRequest();
        req.setSourceId("src");
        req.setTargetId("tgt");
        req.setLocationId("loc1");

        ResponseEntity<Void> response = encounters.reportEncounter(req);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(userRepo).recordEncounter(eq("src"), eq("tgt"), anyLong(), eq("loc1"));
        verify(autoCircle).evaluateEncounter("src", "tgt");
    }

    @Test
    void reportEncounter_nullLocationId_usesDefaultValue() {
        EncounterController.EncounterRequest req = new EncounterController.EncounterRequest();
        req.setSourceId("src");
        req.setTargetId("tgt");

        encounters.reportEncounter(req);

        verify(userRepo).recordEncounter(eq("src"), eq("tgt"), anyLong(), eq("mobile_ble"));
    }

    @Test
    void toggleEncounterValidity_callsRepository() {
        ResponseEntity<Void> response = encounters.toggleValidity(42L);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(userRepo).toggleEncounterValidity(42L);
    }

    @Test
    void forceFenceEncounter_callsRepository() {
        ResponseEntity<Void> response = encounters.forceFence(42L);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(userRepo).forceEncounterFence(42L);
    }

    // ------------------------------------------------------------------ SessionHandshakeController

    private final MacSessionRegistry sessionRegistry = mock(MacSessionRegistry.class);
    private final SessionHandshakeController sessions = new SessionHandshakeController(sessionRegistry);

    @Test
    void handshake_registersSession() {
        Map<String, String> body = Map.of("macAddress", "AA:BB", "anonymousId", "user1");

        ResponseEntity<Void> response = sessions.handshake(body);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(sessionRegistry).registerSession("AA:BB", "user1");
    }

    @Test
    void handshake_missingMac_returnsBadRequest() {
        Map<String, String> body = Map.of("anonymousId", "user1");

        ResponseEntity<Void> response = sessions.handshake(body);

        assertThat(response.getStatusCode().value()).isEqualTo(400);
    }

    @Test
    void handshake_missingAnonymousId_returnsBadRequest() {
        Map<String, String> body = Map.of("macAddress", "AA:BB");

        ResponseEntity<Void> response = sessions.handshake(body);

        assertThat(response.getStatusCode().value()).isEqualTo(400);
    }

    @Test
    void closeSession_delegatesToRegistry() {
        ResponseEntity<Void> response = sessions.closeSession("AA:BB");

        assertThat(response.getStatusCode().value()).isEqualTo(204);
        verify(sessionRegistry).closeSession("AA:BB");
    }

    // ------------------------------------------------------------------ MeshController

    private final UserNodeRepository meshUserRepo = mock(UserNodeRepository.class);
    private final MeshController mesh = new MeshController(meshUserRepo);

    @Test
    void getMeshStats_returnsCounts() {
        when(meshUserRepo.getConfirmedConnectionCount("user1")).thenReturn(5L);
        when(meshUserRepo.getUnconfirmedConnectionCount("user1")).thenReturn(3L);

        ResponseEntity<MeshController.MeshStatsResponse> response = mesh.getMeshStats("user1");

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        assertThat(response.getBody().getConfirmedCount()).isEqualTo(5L);
        assertThat(response.getBody().getUnconfirmedCount()).isEqualTo(3L);
    }

    // ------------------------------------------------------------------ LocationSignalController

    private final LocationResolutionService locationService = mock(LocationResolutionService.class);
    private final LocationSignalController locationSignal = new LocationSignalController(locationService);

    @Test
    void receiveSignal_validRequest_delegatesToService() {
        Map<String, Object> body = Map.of("apMac", "AP1", "deviceMac", "DEV1", "rssi", -65.0);

        ResponseEntity<Void> response = locationSignal.receiveSignal(body);

        assertThat(response.getStatusCode().value()).isEqualTo(200);
        verify(locationService).processSignal("AP1", "DEV1", -65.0);
    }
}
