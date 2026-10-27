package com.planblindbox;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.request.HabitCreateRequest;
import com.planblindbox.service.HabitService;
import com.planblindbox.util.BusinessTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDateTime;
import java.util.Objects;
import java.util.UUID;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class HabitCheckInControllerTest {
    @Autowired private MockMvc mvc;
    @Autowired private HabitService habits;
    @Autowired private ObjectMapper mapper;
    @Autowired private JdbcTemplate jdbc;

    @Test
    void postAndGetStatusUseUnifiedResult() throws Exception {
        jdbc.update("""
                INSERT INTO reward_config (type, coin, exp, water, enabled)
                VALUES ('HABIT_CHECK_IN', 2, 5, 1, TRUE)
                ON DUPLICATE KEY UPDATE coin=2, exp=5, water=1, enabled=TRUE
                """);
        long userId = newUser();
        HabitCreateRequest req = new HabitCreateRequest();
        req.setUserId(userId);
        req.setName("HTTP 打卡测试");
        req.setStartDate(BusinessTime.businessDate(LocalDateTime.now()));
        req.setRepeatRule(mapper.readTree("{\"type\":\"DAILY\"}"));
        long habitId = habits.create(req).getHabitId();

        mvc.perform(post("/habits/{id}/check-in", habitId).param("userId", String.valueOf(userId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(200))
                .andExpect(jsonPath("$.data.checkedInToday").value(true))
                .andExpect(jsonPath("$.data.currentStreak").value(1))
                .andExpect(jsonPath("$.data.reward.granted").value(true));

        mvc.perform(get("/habits/{id}/check-in-status", habitId).param("userId", String.valueOf(userId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.checkedInToday").value(true))
                .andExpect(jsonPath("$.data.totalCheckInDays").value(1));

        mvc.perform(post("/habits/{id}/check-in", habitId).param("userId", String.valueOf(userId)))
                .andExpect(status().isConflict());
    }

    private long newUser() {
        GeneratedKeyHolder keys = new GeneratedKeyHolder();
        jdbc.update(con -> {
            PreparedStatement statement = con.prepareStatement(
                    "INSERT INTO app_user (username, email, password) VALUES (?, ?, ?)",
                    Statement.RETURN_GENERATED_KEYS);
            statement.setString(1, "habit-http-test");
            statement.setString(2, "h-http-" + UUID.randomUUID() + "@example.com");
            statement.setString(3, "not-a-real-password");
            return statement;
        }, keys);
        return Objects.requireNonNull(keys.getKey()).longValue();
    }
}
