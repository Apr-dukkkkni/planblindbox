package com.planblindbox;

import com.planblindbox.controller.TodayController;
import com.planblindbox.dto.response.TodayResponse;
import com.planblindbox.service.TodayService;
import org.junit.jupiter.api.Test;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

class TodayControllerTest {
    @Test
    void getTodayUsesUnifiedResultWithoutDatabase() throws Exception {
        TodayService service = mock(TodayService.class);
        TodayResponse response = new TodayResponse();
        response.setDate(LocalDate.of(2026, 10, 22));
        response.setTasks(List.of());
        response.setHabits(List.of());
        response.setAssets(new TodayResponse.Asset());
        TodayResponse.Summary summary = new TodayResponse.Summary();
        summary.setCompletionRate(BigDecimal.ZERO);
        response.setSummary(summary);
        when(service.getToday(1L)).thenReturn(response);

        MockMvc mvc = MockMvcBuilders.standaloneSetup(new TodayController(service)).build();
        mvc.perform(get("/today").param("userId", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.data.date").value("2026-10-22"))
                .andExpect(jsonPath("$.data.tasks").isArray())
                .andExpect(jsonPath("$.data.habits").isArray())
                .andExpect(jsonPath("$.data.assets.coin").value(0))
                .andExpect(jsonPath("$.data.summary.completionRate").value(0));
        verify(service).getToday(1L);
    }
}
