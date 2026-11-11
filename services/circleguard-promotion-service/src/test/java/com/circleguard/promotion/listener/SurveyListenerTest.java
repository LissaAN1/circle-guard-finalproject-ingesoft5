package com.circleguard.promotion.listener;

import com.circleguard.promotion.service.HealthStatusService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.HashMap;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class SurveyListenerTest {

    @Mock
    private HealthStatusService healthStatusService;

    @InjectMocks
    private SurveyListener surveyListener;

    // ------------------------------------------------------------------ onSurveySubmitted

    @Test
    void onSurveySubmitted_WithSymptoms_PromotesToSuspect() {
        Map<String, Object> event = Map.of(
            "anonymousId", "tester-123",
            "hasSymptoms", true
        );

        surveyListener.onSurveySubmitted(event);

        verify(healthStatusService).updateStatus("tester-123", "SUSPECT");
    }

    @Test
    void onSurveySubmitted_WithoutSymptoms_DoesNothing() {
        Map<String, Object> event = Map.of(
            "anonymousId", "tester-123",
            "hasSymptoms", false
        );

        surveyListener.onSurveySubmitted(event);

        verify(healthStatusService, never()).updateStatus(anyString(), anyString());
    }

    @Test
    void onSurveySubmitted_NullAnonymousId_DoesNothing() {
        Map<String, Object> event = new HashMap<>();
        event.put("anonymousId", null);
        event.put("hasSymptoms", true);

        surveyListener.onSurveySubmitted(event);

        verify(healthStatusService, never()).updateStatus(anyString(), anyString());
    }

    @Test
    void onSurveySubmitted_ServiceThrows_ExceptionIsCaughtAndNotPropagated() {
        Map<String, Object> event = Map.of("anonymousId", "tester-123", "hasSymptoms", true);
        doThrow(new RuntimeException("downstream error")).when(healthStatusService).updateStatus(any(), any());

        surveyListener.onSurveySubmitted(event);

        verify(healthStatusService).updateStatus("tester-123", "SUSPECT");
    }

    // ------------------------------------------------------------------ onCertificateValidated

    @Test
    void onCertificateValidated_Approved_RestoresToActive() {
        Map<String, Object> event = Map.of("anonymousId", "tester-456", "status", "APPROVED");

        surveyListener.onCertificateValidated(event);

        verify(healthStatusService).updateStatus("tester-456", "ACTIVE");
    }

    @Test
    void onCertificateValidated_NotApproved_DoesNothing() {
        Map<String, Object> event = Map.of("anonymousId", "tester-456", "status", "REJECTED");

        surveyListener.onCertificateValidated(event);

        verify(healthStatusService, never()).updateStatus(anyString(), anyString());
    }

    @Test
    void onCertificateValidated_NullAnonymousId_DoesNothing() {
        Map<String, Object> event = new HashMap<>();
        event.put("anonymousId", null);
        event.put("status", "APPROVED");

        surveyListener.onCertificateValidated(event);

        verify(healthStatusService, never()).updateStatus(anyString(), anyString());
    }

    @Test
    void onCertificateValidated_ServiceThrows_ExceptionIsCaughtAndNotPropagated() {
        Map<String, Object> event = Map.of("anonymousId", "tester-456", "status", "APPROVED");
        doThrow(new RuntimeException("downstream error")).when(healthStatusService).updateStatus(any(), any());

        surveyListener.onCertificateValidated(event);

        verify(healthStatusService).updateStatus("tester-456", "ACTIVE");
    }
}
