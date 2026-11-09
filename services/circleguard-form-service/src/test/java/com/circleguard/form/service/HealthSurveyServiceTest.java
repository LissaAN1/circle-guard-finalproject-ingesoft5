package com.circleguard.form.service;

import com.circleguard.form.model.HealthSurvey;
import com.circleguard.form.model.Questionnaire;
import com.circleguard.form.model.ValidationStatus;
import com.circleguard.form.repository.HealthSurveyRepository;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.kafka.core.KafkaTemplate;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SuppressWarnings("unchecked")
class HealthSurveyServiceTest {

    private final HealthSurveyRepository repository = mock(HealthSurveyRepository.class);
    private final QuestionnaireService questionnaireService = mock(QuestionnaireService.class);
    private final SymptomMapper symptomMapper = mock(SymptomMapper.class);
    private final KafkaTemplate<String, Object> kafka = mock(KafkaTemplate.class);
    private final HealthSurveyService service =
            new HealthSurveyService(repository, questionnaireService, symptomMapper, kafka);

    private HealthSurvey survey(UUID anonymousId) {
        return HealthSurvey.builder().anonymousId(anonymousId).build();
    }

    @Test
    void submittedSurveyIsSavedAndPublishedWithTheSymptomResult() {
        UUID anonymousId = UUID.randomUUID();
        Questionnaire questionnaire = Questionnaire.builder().title("Q").build();
        HealthSurvey input = survey(anonymousId);
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.of(questionnaire));
        when(symptomMapper.hasSymptoms(input, questionnaire)).thenReturn(true);
        when(repository.save(input)).thenReturn(input);

        HealthSurvey saved = service.submitSurvey(input);

        assertTrue(saved.getHasFever());
        assertTrue(saved.getHasCough());
        ArgumentCaptor<Object> event = ArgumentCaptor.forClass(Object.class);
        verify(kafka).send(eq("survey.submitted"), eq(anonymousId.toString()), event.capture());
        assertEquals(true, ((Map<String, Object>) event.getValue()).get("hasSymptoms"));
    }

    @Test
    void withoutAnActiveQuestionnaireThereAreNoSymptoms() {
        HealthSurvey input = survey(UUID.randomUUID());
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.empty());
        when(repository.save(input)).thenReturn(input);

        HealthSurvey saved = service.submitSurvey(input);

        assertFalse(saved.getHasFever());
        assertFalse(saved.getHasCough());
    }

    @Test
    void legacyFlagsSentByTheClientAreKept() {
        HealthSurvey input = survey(UUID.randomUUID());
        input.setHasFever(true);
        input.setHasCough(false);
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.empty());
        when(repository.save(input)).thenReturn(input);

        HealthSurvey saved = service.submitSurvey(input);

        assertTrue(saved.getHasFever());
        assertFalse(saved.getHasCough());
    }

    @Test
    void surveyWithAnAttachmentWaitsForValidation() {
        HealthSurvey input = survey(UUID.randomUUID());
        input.setAttachmentPath("certificado.pdf");
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.empty());
        when(repository.save(input)).thenReturn(input);

        assertEquals(ValidationStatus.PENDING, service.submitSurvey(input).getValidationStatus());
    }

    @Test
    void pendingSurveysComeFromTheRepository() {
        List<HealthSurvey> pending = List.of(survey(UUID.randomUUID()));
        when(repository.findByAttachmentPathIsNotNullAndValidationStatus(ValidationStatus.PENDING)).thenReturn(pending);

        assertEquals(pending, service.getPendingSurveys());
    }

    @Test
    void approvingASurveyNotifiesThePromotionService() {
        UUID surveyId = UUID.randomUUID();
        UUID anonymousId = UUID.randomUUID();
        UUID adminId = UUID.randomUUID();
        HealthSurvey stored = survey(anonymousId);
        when(repository.findById(surveyId)).thenReturn(Optional.of(stored));

        service.validateSurvey(surveyId, ValidationStatus.APPROVED, adminId);

        assertEquals(ValidationStatus.APPROVED, stored.getValidationStatus());
        assertEquals(adminId, stored.getValidatedBy());
        verify(repository).save(stored);
        verify(kafka).send(eq("certificate.validated"), eq(anonymousId.toString()), any());
    }

    @Test
    void rejectingASurveyDoesNotPublishAnEvent() {
        UUID surveyId = UUID.randomUUID();
        HealthSurvey stored = survey(UUID.randomUUID());
        when(repository.findById(surveyId)).thenReturn(Optional.of(stored));

        service.validateSurvey(surveyId, ValidationStatus.REJECTED, UUID.randomUUID());

        assertEquals(ValidationStatus.REJECTED, stored.getValidationStatus());
        verify(kafka, never()).send(anyString(), anyString(), any());
    }

    @Test
    void validatingAnUnknownSurveyFails() {
        UUID surveyId = UUID.randomUUID();
        when(repository.findById(surveyId)).thenReturn(Optional.empty());

        assertThrows(RuntimeException.class,
                () -> service.validateSurvey(surveyId, ValidationStatus.APPROVED, UUID.randomUUID()));
    }
}
