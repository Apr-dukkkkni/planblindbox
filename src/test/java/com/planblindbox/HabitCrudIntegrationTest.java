package com.planblindbox;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.request.HabitCreateRequest;
import com.planblindbox.dto.request.HabitUpdateRequest;
import com.planblindbox.dto.response.HabitResponse;
import com.planblindbox.enums.HabitStatus;
import com.planblindbox.mapper.HabitMapper;
import com.planblindbox.service.HabitService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDate;
import java.util.Objects;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/** 真实 MySQL 集成测试；测试数据在结束后自动回滚。 */
@SpringBootTest
@Transactional
class HabitCrudIntegrationTest {
    @Autowired private HabitService habitService;
    @Autowired private HabitMapper habitMapper;
    @Autowired private JdbcTemplate jdbcTemplate;
    @Autowired private ObjectMapper objectMapper;

    @Test
    void createAndQueryDailyHabit() throws Exception {
        long user = newUser();
        HabitResponse result = habitService.create(request(user, "每天阅读", "{\"type\":\"DAILY\"}"));
        assertNotNull(result.getHabitId());
        assertEquals(HabitStatus.ACTIVE, result.getStatus());
        assertEquals("DAILY", result.getRepeatRule().get("type").asText());
        assertEquals("每天阅读", habitService.getById(user, result.getHabitId()).getName());
        assertEquals(1, habitService.list(user).size());
        assertNotNull(habitMapper.selectById(result.getHabitId(), user).getRepeatRule());
        assertEquals("DAILY", objectMapper.readTree(jdbcTemplate.queryForObject(
                "SELECT repeat_rule FROM habit WHERE habit_id=?", String.class, result.getHabitId()))
                .get("type").asText());
    }

    @Test
    void updateScheduleAndPauseThenResume() throws Exception {
        long user = newUser();
        long id = habitService.create(request(user, "运动", "{\"type\":\"DAILY\"}" )).getHabitId();
        HabitUpdateRequest change = new HabitUpdateRequest();
        change.setName("工作日运动");
        change.setRepeatRule(rule("{\"type\":\"WEEKLY\",\"daysOfWeek\":[1,3,5]}"));
        change.setStatus(HabitStatus.PAUSED);
        change.setEndDate(LocalDate.of(2026, 12, 31));
        HabitResponse updated = habitService.update(user, id, change);
        assertEquals("工作日运动", updated.getName());
        assertEquals(HabitStatus.PAUSED, updated.getStatus());
        assertEquals(3, updated.getRepeatRule().get("daysOfWeek").size());
        assertEquals(LocalDate.of(2026, 12, 31), updated.getEndDate());
        assertEquals(1, habitService.list(user).size()); // PAUSED 仍可见

        HabitUpdateRequest resume = new HabitUpdateRequest();
        resume.setStatus(HabitStatus.ACTIVE);
        assertEquals(HabitStatus.ACTIVE, habitService.update(user, id, resume).getStatus());
    }

    @Test
    void archiveShouldKeepRowButRemoveFromList() throws Exception {
        long user = newUser();
        long oldId = habitService.create(request(user, "旧习惯", "{\"type\":\"DAILY\"}")).getHabitId();
        long newId = habitService.create(request(user, "新习惯", "{\"type\":\"DAILY\"}")).getHabitId();
        habitService.archive(user, oldId);
        assertEquals(HabitStatus.ARCHIVED, habitService.getById(user, oldId).getStatus());
        assertEquals(1, habitService.list(user).size());
        assertEquals(Long.valueOf(newId), habitService.list(user).get(0).getHabitId());
        assertEquals(2, jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM habit WHERE user_id=?", Integer.class, user));
        assertThrows(ResponseStatusException.class,
                () -> habitService.update(user, oldId, new HabitUpdateRequest()));
        assertThrows(ResponseStatusException.class, () -> habitService.archive(user, oldId));
    }

    @Test
    void invalidRuleAndInvalidDateShouldBeRejected() throws Exception {
        long user = newUser();
        HabitCreateRequest badDays = request(user, "不合法的周计划",
                "{\"type\":\"WEEKLY\",\"daysOfWeek\":[1,1,8]}");
        assertThrows(ResponseStatusException.class, () -> habitService.create(badDays));
        HabitCreateRequest badDate = request(user, "不合法日期", "{\"type\":\"DAILY\"}");
        badDate.setEndDate(LocalDate.of(2026, 9, 1));
        assertThrows(ResponseStatusException.class, () -> habitService.create(badDate));
        HabitCreateRequest unsupported = request(user, "未知周期", "{\"type\":\"MONTHLY\"}");
        assertThrows(ResponseStatusException.class, () -> habitService.create(unsupported));
        assertTrue(habitService.list(user).isEmpty());
    }

    @Test
    void oneUserCannotReadUpdateOrArchiveAnotherUsersHabit() throws Exception {
        long owner = newUser();
        long other = newUser();
        long habitId = habitService.create(request(owner, "私人习惯", "{\"type\":\"DAILY\"}")).getHabitId();
        assertThrows(ResponseStatusException.class, () -> habitService.getById(other, habitId));
        assertThrows(ResponseStatusException.class,
                () -> habitService.update(other, habitId, new HabitUpdateRequest()));
        assertThrows(ResponseStatusException.class, () -> habitService.archive(other, habitId));
        assertEquals(HabitStatus.ACTIVE, habitService.getById(owner, habitId).getStatus());
    }

    private HabitCreateRequest request(long user, String name, String json) throws Exception {
        HabitCreateRequest r = new HabitCreateRequest();
        r.setUserId(user);
        r.setName(name);
        r.setStartDate(LocalDate.of(2026, 10, 22));
        r.setRepeatRule(rule(json));
        return r;
    }

    private JsonNode rule(String json) throws Exception {
        return objectMapper.readTree(json);
    }

    private long newUser() {
        GeneratedKeyHolder keys = new GeneratedKeyHolder();
        jdbcTemplate.update(con -> {
            PreparedStatement statement = con.prepareStatement(
                    "INSERT INTO app_user (username, email, password) VALUES (?, ?, ?)",
                    Statement.RETURN_GENERATED_KEYS);
            statement.setString(1, "habit-test");
            statement.setString(2, "ht-" + UUID.randomUUID() + "@example.com");
            statement.setString(3, "not-a-real-password");
            return statement;
        }, keys);
        return Objects.requireNonNull(keys.getKey()).longValue();
    }
}
