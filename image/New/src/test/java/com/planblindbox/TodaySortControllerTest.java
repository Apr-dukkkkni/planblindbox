package com.planblindbox;

import com.planblindbox.controller.TodayController;
import com.planblindbox.dto.response.TodayResponse;
import com.planblindbox.service.TodayService;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.LocalDate;
import java.util.List;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

class TodaySortControllerTest {
    private TodayResponse data() {
        TodayResponse response = new TodayResponse();
        response.setDate(LocalDate.of(2026, 10, 23));
        TodayResponse.TaskItem task = new TodayResponse.TaskItem();
        task.setTaskId(11L);
        task.setImportance(5);
        task.setDifficulty(2);
        response.setTasks(List.of(task));
        response.setHabits(List.of());
        response.setAssets(new TodayResponse.Asset());
        response.setSummary(new TodayResponse.Summary());
        return response;
    }

    @Test
    void sortImportancePassesQueryToServiceAndIncludesBothIndependentFields() throws Exception {
        TodayService service = mock(TodayService.class);
        when(service.getToday(1L, "importance")).thenReturn(data());
        MockMvc mvc = MockMvcBuilders.standaloneSetup(new TodayController(service)).build();
        mvc.perform(get("/today").param("userId", "1").param("sort", "importance"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.data.date").value("2026-10-23"))
                .andExpect(jsonPath("$.data.tasks[0].importance").value(5))
                .andExpect(jsonPath("$.data.tasks[0].difficulty").value(2));
        verify(service).getToday(1L, "importance");
    }

    @Test
    void noSortKeepsOldServiceMethodForBackwardCompatibility() throws Exception {
        TodayService service = mock(TodayService.class);
        when(service.getToday(1L)).thenReturn(data());
        MockMvc mvc = MockMvcBuilders.standaloneSetup(new TodayController(service)).build();
        mvc.perform(get("/today").param("userId", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200));
        verify(service).getToday(1L);
        verify(service, never()).getToday(eq(1L), anyString());
    }
}
