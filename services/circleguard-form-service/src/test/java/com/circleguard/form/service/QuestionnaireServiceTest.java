package com.circleguard.form.service;

import com.circleguard.form.model.Question;
import com.circleguard.form.model.Questionnaire;
import com.circleguard.form.repository.QuestionnaireRepository;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class QuestionnaireServiceTest {

    private final QuestionnaireRepository repository = mock(QuestionnaireRepository.class);
    private final QuestionnaireService service = new QuestionnaireService(repository);

    private Questionnaire questionnaire(boolean active) {
        return Questionnaire.builder().id(UUID.randomUUID()).title("Q").isActive(active).build();
    }

    @Test
    void listsAllQuestionnaires() {
        List<Questionnaire> all = List.of(questionnaire(true), questionnaire(false));
        when(repository.findAll()).thenReturn(all);

        assertEquals(all, service.getAllQuestionnaires());
    }

    @Test
    void activeQuestionnaireIsTheLatestActiveVersion() {
        Questionnaire active = questionnaire(true);
        when(repository.findFirstByIsActiveTrueOrderByVersionDesc()).thenReturn(Optional.of(active));

        assertSame(active, service.getActiveQuestionnaire().orElseThrow());
    }

    @Test
    void savingLinksEveryQuestionToItsQuestionnaire() {
        Questionnaire q = questionnaire(false);
        Question question = new Question();
        q.setQuestions(new ArrayList<>(List.of(question)));
        when(repository.save(q)).thenReturn(q);

        service.saveQuestionnaire(q);

        assertSame(q, question.getQuestionnaire());
    }

    @Test
    void savingWithoutQuestionsStillWorks() {
        Questionnaire q = questionnaire(false);
        when(repository.save(q)).thenReturn(q);

        assertSame(q, service.saveQuestionnaire(q));
    }

    @Test
    void activatingOneDeactivatesTheOthers() {
        Questionnaire previous = questionnaire(true);
        Questionnaire target = questionnaire(false);
        Questionnaire inactive = questionnaire(false);
        when(repository.findAll()).thenReturn(List.of(previous, target, inactive));
        when(repository.findById(target.getId())).thenReturn(Optional.of(target));

        service.activateQuestionnaire(target.getId());

        assertFalse(previous.getIsActive());
        assertTrue(target.getIsActive());
        verify(repository).save(previous);
        verify(repository).save(target);
        verify(repository, never()).save(inactive);
    }

    @Test
    void activatingAnUnknownIdOnlyDeactivates() {
        UUID unknown = UUID.randomUUID();
        Questionnaire previous = questionnaire(true);
        when(repository.findAll()).thenReturn(List.of(previous));
        when(repository.findById(unknown)).thenReturn(Optional.empty());

        service.activateQuestionnaire(unknown);

        assertFalse(previous.getIsActive());
    }
}
