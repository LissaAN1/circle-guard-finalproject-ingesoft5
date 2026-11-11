package com.circleguard.promotion.task;

import com.circleguard.promotion.repository.graph.UserNodeRepository;
import org.junit.jupiter.api.Test;

import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class GraphCleanupTaskTest {

    private final UserNodeRepository userNodeRepository = mock(UserNodeRepository.class);
    private final GraphCleanupTask task = new GraphCleanupTask(userNodeRepository);

    @Test
    void purgeStaleEncounters_callsRepositoryWithThreshold() {
        when(userNodeRepository.purgeStaleEncounters(anyLong())).thenReturn(42L);

        task.purgeStaleEncounters();

        verify(userNodeRepository).purgeStaleEncounters(anyLong());
    }

    @Test
    void purgeStaleEncounters_nullResult_doesNotThrow() {
        when(userNodeRepository.purgeStaleEncounters(anyLong())).thenReturn(null);

        task.purgeStaleEncounters();

        verify(userNodeRepository).purgeStaleEncounters(anyLong());
    }

    @Test
    void purgeStaleEncounters_repositoryThrows_exceptionIsCaught() {
        when(userNodeRepository.purgeStaleEncounters(anyLong()))
                .thenThrow(new RuntimeException("DB unavailable"));

        task.purgeStaleEncounters();
        // No exception propagated; caught by the task's try-catch
    }
}
