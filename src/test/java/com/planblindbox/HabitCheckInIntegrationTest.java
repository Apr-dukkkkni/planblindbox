package com.planblindbox;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.request.HabitCreateRequest;
import com.planblindbox.dto.request.HabitUpdateRequest;
import com.planblindbox.dto.response.HabitCheckInResponse;
import com.planblindbox.enums.HabitStatus;
import com.planblindbox.mapper.HabitRecordMapper;
import com.planblindbox.service.HabitCheckInService;
import com.planblindbox.service.HabitService;
import com.planblindbox.util.BusinessTime;
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
import java.time.LocalDateTime;
import java.util.Objects;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/** 对真实 MySQL 的集成测试；每个测试在结束时回滚。 */
@SpringBootTest
@Transactional
class HabitCheckInIntegrationTest {
    @Autowired private HabitService habitService;
    @Autowired private HabitCheckInService checkInService;
    @Autowired private HabitRecordMapper recordMapper;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private ObjectMapper objectMapper;

    @Test
    void dailyCheckInCreatesOneRecordAndRewardButRejectsSecondCheckIn() throws Exception {
        setRule(true);
        long userId = newUser();
        long habitId = newHabit(userId, businessToday().minusDays(1), null, "{\"type\":\"DAILY\"}");

        HabitCheckInResponse before = checkInService.getTodayStatus(userId, habitId);
        assertFalse(before.getCheckedInToday());
        assertEquals(0, before.getCurrentStreak());
        assertNull(before.getReward());

        HabitCheckInResponse after = checkInService.checkIn(userId, habitId);
        assertTrue(after.getCheckedInToday());
        assertEquals(1, after.getCurrentStreak());
        assertEquals(1, after.getTotalCheckInDays());
        assertTrue(after.getReward().getGranted());
        assertEquals(2, after.getReward().getCoin());
        assertEquals(5L, after.getReward().getExp());
        assertEquals(1, after.getReward().getWater());
        assertEquals(3, countLedgers(userId));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM habit_record WHERE habit_id=?", Integer.class, habitId));
        Long recordId = jdbc.queryForObject("SELECT habit_record_id FROM habit_record WHERE habit_id=?", Long.class, habitId);
        assertEquals(3, jdbc.queryForObject(
                "SELECT COUNT(*) FROM asset_record WHERE source='HABIT_RECORD' AND source_id=?", Integer.class, recordId));
        assertEquals(2, jdbc.queryForObject("SELECT coin FROM user_asset WHERE user_id=?", Integer.class, userId));

        ResponseStatusException duplicate = assertThrows(ResponseStatusException.class,
                () -> checkInService.checkIn(userId, habitId));
        assertEquals(409, duplicate.getStatusCode().value());
        assertEquals(3, countLedgers(userId));
        assertEquals(1, jdbc.queryForObject("SELECT COUNT(*) FROM habit_record WHERE habit_id=?", Integer.class, habitId));
        assertNull(checkInService.getTodayStatus(userId, habitId).getReward());
    }

    @Test
    void weeklyNonScheduledDayCannotCheckIn() throws Exception {
        setRule(true);
        long userId = newUser();
        int tomorrowWeekday = businessToday().plusDays(1).getDayOfWeek().getValue();
        long id = newHabit(userId, businessToday().minusDays(2), null,
                "{\"type\":\"WEEKLY\",\"daysOfWeek\":[" + tomorrowWeekday + "]}");
        assertEquals(409, assertThrows(ResponseStatusException.class,
                () -> checkInService.checkIn(userId, id)).getStatusCode().value());
        assertEquals(0, recordMapper.selectCompletedDates(id).size());
        assertEquals(0, countLedgers(userId));
    }

    @Test
    void weeklyStreakSkipsOtherWeekdays() throws Exception {
        setRule(true);
        long userId = newUser();
        LocalDate today = businessToday();
        int weekday = today.getDayOfWeek().getValue();
        long id = newHabit(userId, today.minusWeeks(2), null,
                "{\"type\":\"WEEKLY\",\"daysOfWeek\":[" + weekday + "]}");
        // 模拟前两周的历史打卡，无需给历史测试数据追发奖励。
        historicalRecord(id, today.minusWeeks(2));
        historicalRecord(id, today.minusWeeks(1));

        assertEquals(2, checkInService.getTodayStatus(userId, id).getCurrentStreak());
        HabitCheckInResponse now = checkInService.checkIn(userId, id);
        assertEquals(3, now.getCurrentStreak());
        assertEquals(3, now.getTotalCheckInDays());
    }

    @Test
    void missedDueDayBreaksStreakButTodayCanRestartIt() throws Exception {
        setRule(true);
        long userId = newUser();
        LocalDate today = businessToday();
        long id = newHabit(userId, today.minusDays(3), null, "{\"type\":\"DAILY\"}");
        historicalRecord(id, today.minusDays(2)); // 昨天漏打
        assertEquals(0, checkInService.getTodayStatus(userId, id).getCurrentStreak());
        assertEquals(1, checkInService.checkIn(userId, id).getCurrentStreak());
        assertEquals(2, checkInService.getTodayStatus(userId, id).getTotalCheckInDays());
    }

    @Test
    void pausedArchivedAndOtherUserCannotCheckIn() throws Exception {
        setRule(true);
        long owner = newUser();
        long outsider = newUser();
        long id = newHabit(owner, businessToday(), null, "{\"type\":\"DAILY\"}");
        assertEquals(404, assertThrows(ResponseStatusException.class,
                () -> checkInService.checkIn(outsider, id)).getStatusCode().value());
        HabitUpdateRequest pause = new HabitUpdateRequest();
        pause.setStatus(HabitStatus.PAUSED);
        habitService.update(owner, id, pause);
        assertEquals(409, assertThrows(ResponseStatusException.class,
                () -> checkInService.checkIn(owner, id)).getStatusCode().value());
        habitService.archive(owner, id);
        assertEquals(409, assertThrows(ResponseStatusException.class,
                () -> checkInService.checkIn(owner, id)).getStatusCode().value());
        assertEquals(0, countLedgers(owner));
    }

    @Test
    void dateRangeBlocksCheckIn() throws Exception {
        setRule(true);
        long userId = newUser();
        long future = newHabit(userId, businessToday().plusDays(1), null, "{\"type\":\"DAILY\"}");
        long expired = newHabit(userId, businessToday().minusDays(5), businessToday().minusDays(1),
                "{\"type\":\"DAILY\"}");
        assertEquals(409, assertThrows(ResponseStatusException.class,
                () -> checkInService.checkIn(userId, future)).getStatusCode().value());
        assertEquals(409, assertThrows(ResponseStatusException.class,
                () -> checkInService.checkIn(userId, expired)).getStatusCode().value());
    }

    @Test
    void disabledRewardStillRecordsCheckIn() throws Exception {
        setRule(false);
        long userId = newUser();
        long id = newHabit(userId, businessToday(), null, "{\"type\":\"DAILY\"}");
        HabitCheckInResponse response = checkInService.checkIn(userId, id);
        assertEquals(1, response.getTotalCheckInDays());
        assertFalse(response.getReward().getGranted());
        assertEquals(0, countLedgers(userId));
        assertEquals(0, jdbc.queryForObject("SELECT COUNT(*) FROM user_asset WHERE user_id=?", Integer.class, userId));
    }


    private LocalDate businessToday() {
        return BusinessTime.businessDate(LocalDateTime.now());
    }

    private void setRule(boolean enabled) {
        jdbc.update("""
                INSERT INTO reward_config (type, coin, exp, water, enabled)
                VALUES ('HABIT_CHECK_IN', 2, 5, 1, ?)
                ON DUPLICATE KEY UPDATE coin=2, exp=5, water=1, enabled=?
                """, enabled, enabled);
    }

    private long newHabit(long userId, LocalDate start, LocalDate end, String ruleJson) throws Exception {
        HabitCreateRequest req = new HabitCreateRequest();
        req.setUserId(userId);
        req.setName("习惯打卡集成测试");
        req.setStartDate(start);
        req.setEndDate(end);
        req.setRepeatRule(objectMapper.readTree(ruleJson));
        return habitService.create(req).getHabitId();
    }

    private void historicalRecord(long habitId, LocalDate date) {
        jdbc.update("""
                INSERT INTO habit_record (habit_id, record_date, status, finish_time, actual_count)
                VALUES (?, ?, 'COMPLETED', NOW(), 1)
                """, habitId, date);
    }

    private int countLedgers(long userId) {
        return jdbc.queryForObject("SELECT COUNT(*) FROM asset_record WHERE user_id=?", Integer.class, userId);
    }

    private long newUser() {
        GeneratedKeyHolder keys = new GeneratedKeyHolder();
        jdbc.update(con -> {
            PreparedStatement statement = con.prepareStatement(
                    "INSERT INTO app_user (username, email, password) VALUES (?, ?, ?)",
                    Statement.RETURN_GENERATED_KEYS);
            statement.setString(1, "check-in-test");
            statement.setString(2, "habit-" + UUID.randomUUID() + "@example.com");
            statement.setString(3, "not-a-real-password");
            return statement;
        }, keys);
        return Objects.requireNonNull(keys.getKey()).longValue();
    }
}
