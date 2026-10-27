package com.planblindbox;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.response.HabitCheckInResponse;
import com.planblindbox.dto.response.TodayResponse;
import com.planblindbox.entity.AppUser;
import com.planblindbox.entity.Habit;
import com.planblindbox.entity.Task;
import com.planblindbox.entity.TaskRecord;
import com.planblindbox.entity.UserAsset;
import com.planblindbox.enums.HabitStatus;
import com.planblindbox.enums.TaskRecordStatus;
import com.planblindbox.enums.TaskStatus;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.HabitMapper;
import com.planblindbox.mapper.TaskMapper;
import com.planblindbox.mapper.TaskRecordMapper;
import com.planblindbox.mapper.UserAssetMapper;
import com.planblindbox.service.HabitCheckInService;
import com.planblindbox.service.impl.TodayServiceImpl;
import com.planblindbox.util.BusinessTime;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TodayServiceTest {
    @Mock AppUserMapper appUserMapper;
    @Mock TaskMapper taskMapper;
    @Mock TaskRecordMapper taskRecordMapper;
    @Mock HabitMapper habitMapper;
    @Mock HabitCheckInService habitCheckInService;
    @Mock UserAssetMapper userAssetMapper;
    private TodayServiceImpl service;

    @BeforeEach
    void setUp() {
        service = new TodayServiceImpl(appUserMapper, taskMapper, taskRecordMapper, habitMapper,
                habitCheckInService, userAssetMapper, new ObjectMapper());
    }

    private void givenUser() {
        when(appUserMapper.selectById(1L)).thenReturn(new AppUser());
    }

    @Test
    void todayTaskProgressCompletedTodayAndOverdue() {
        givenUser();
        LocalDateTime now = LocalDateTime.now();
        LocalDate today = BusinessTime.businessDate(now);

// 当天业务周期开始于 05:00
        LocalDateTime businessDayStart = today.atTime(5, 0);

// 两个任务都在当前业务日开始
        Task partial = task(
                10,
                TaskStatus.IN_PROGRESS,
                businessDayStart
        );

        Task finished = task(
                11,
                TaskStatus.COMPLETED,
                businessDayStart
        );

// 今天已经完成的任务
        finished.setEndTime(now.plusHours(2));
        when(taskMapper.selectByUserId(1L)).thenReturn(List.of(partial, finished));
        when(habitMapper.selectByUserId(1L)).thenReturn(List.of());

        TaskRecord todayPartial = record(10, today, 30, TaskRecordStatus.IN_PROGRESS);
        TaskRecord todayFinished = record(11, today, 20, TaskRecordStatus.COMPLETED);
        when(taskRecordMapper.selectByTaskIdAndDate(10L, today)).thenReturn(todayPartial);
        when(taskRecordMapper.selectByTaskIdAndDate(11L, today)).thenReturn(todayFinished);
        when(taskRecordMapper.sumActualCount(10L)).thenReturn(70L);
        when(taskRecordMapper.sumActualCount(11L)).thenReturn(100L);

        TodayResponse response = service.getToday(1L);
        assertEquals(today, response.getDate());
        assertEquals(2, response.getTasks().size());
        var a = response.getTasks().get(0);
        assertEquals(30, a.getTodayActualCount());
        assertEquals(70L, a.getTotalActualCount());
        assertEquals(30L, a.getRemainingCount());
        assertFalse(a.isOverdue());
        // 验证截止时间为下一个凌晨 5 点
        assertEquals(
                BusinessTime.nextReset(businessDayStart),
                a.getEndTime()
        );
        assertFalse(a.isCompletedToday());
        var b = response.getTasks().get(1);
        assertTrue(b.isCompletedToday());
        assertFalse(b.isOverdue());
        assertEquals(1, response.getSummary().getTaskCompleted());
        assertEquals(0, response.getSummary().getHabitTotal());
        assertEquals(0, response.getSummary().getCompletionRate().compareTo(new java.math.BigDecimal("50.00")));
        assertEquals(0, response.getAssets().getCoin());
        assertEquals(0L, response.getAssets().getExp());
        assertEquals(0, response.getAssets().getWater());
    }

    @Test
    void excludeFutureCancelledArchivedAndPreviouslyCompleted() {
        givenUser();
        LocalDate today =
                BusinessTime.businessDate(LocalDateTime.now()); today = LocalDate.now();
        Task future = task(1, TaskStatus.PENDING, today.plusDays(1).atStartOfDay());
        Task oldCompleted = task(2, TaskStatus.COMPLETED, today.minusDays(1).atStartOfDay());
        Task cancelled = task(3, TaskStatus.CANCELLED, null);
        Task archived = task(4, TaskStatus.ARCHIVED, null);
        Task normal = task(5, TaskStatus.PENDING, null);
        when(taskMapper.selectByUserId(1L)).thenReturn(List.of(future, oldCompleted, cancelled, archived, normal));
        when(habitMapper.selectByUserId(1L)).thenReturn(List.of());
        when(taskRecordMapper.sumActualCount(5L)).thenReturn(0L);

        TodayResponse response = service.getToday(1L);
        assertEquals(1, response.getTasks().size());
        assertEquals(Long.valueOf(5L), response.getTasks().get(0).getTaskId());
        assertEquals(1, response.getSummary().getTaskTotal());
        verify(taskRecordMapper, never()).sumActualCount(2L);
    }

    @Test
    void weeklyHabitMustMatchWeekdayAndStatusAndAssets() throws Exception {
        givenUser();
        LocalDate today = LocalDate.now();
        int weekday = today.getDayOfWeek().getValue();
        int otherDay = weekday == 7 ? 1 : weekday + 1;
        Habit todayWeekly = habit(10, HabitStatus.ACTIVE, today.minusWeeks(2),
                "{\"type\":\"WEEKLY\",\"daysOfWeek\":[" + weekday + "]}");
        Habit notScheduled = habit(11, HabitStatus.ACTIVE, today.minusWeeks(2),
                "{\"type\":\"WEEKLY\",\"daysOfWeek\":[" + otherDay + "]}");
        Habit paused = habit(12, HabitStatus.PAUSED, today.minusDays(2), "{\"type\":\"DAILY\"}");
        Habit notStarted = habit(13, HabitStatus.ACTIVE, today.plusDays(1), "{\"type\":\"DAILY\"}");
        Habit daily = habit(14, HabitStatus.ACTIVE, today.minusDays(1), "{\"type\":\"DAILY\"}");
        Habit expired = habit(15, HabitStatus.ACTIVE, today.minusDays(8), "{\"type\":\"DAILY\"}");
        expired.setEndDate(today.minusDays(1));
        when(habitMapper.selectByUserId(1L))
                .thenReturn(List.of(todayWeekly, notScheduled, paused, notStarted, daily, expired));
        when(taskMapper.selectByUserId(1L)).thenReturn(List.of());
        HabitCheckInResponse checked = new HabitCheckInResponse();
        checked.setCheckedInToday(true);
        checked.setCurrentStreak(3);
        checked.setTotalCheckInDays(9);
        HabitCheckInResponse unchecked = new HabitCheckInResponse();
        unchecked.setCheckedInToday(false);
        unchecked.setCurrentStreak(2);
        unchecked.setTotalCheckInDays(5);
        when(habitCheckInService.getTodayStatus(1L, 10L)).thenReturn(checked);
        when(habitCheckInService.getTodayStatus(1L, 14L)).thenReturn(unchecked);
        UserAsset asset = new UserAsset();
        asset.setCoin(20);
        asset.setExp(40L);
        asset.setWater(2);
        when(userAssetMapper.selectByUserId(1L)).thenReturn(asset);

        TodayResponse response = service.getToday(1L);
        assertEquals(List.of(10L, 14L), response.getHabits().stream().map(TodayResponse.HabitItem::getHabitId).toList());
        assertEquals(3, response.getHabits().get(0).getCurrentStreak());
        assertEquals(9, response.getHabits().get(0).getTotalCheckInDays());
        assertEquals(1, response.getSummary().getHabitCheckedIn());
        assertEquals(0, response.getSummary().getCompletionRate().compareTo(new java.math.BigDecimal("50.00")));
        assertEquals(20, response.getAssets().getCoin());
        assertEquals(40L, response.getAssets().getExp());
        assertEquals(2, response.getAssets().getWater());
        verify(habitCheckInService, times(2)).getTodayStatus(eq(1L), any());
    }

    @Test
    void noTasksOrHabitsGivesZeroCompletion() {
        givenUser();
        when(taskMapper.selectByUserId(1L)).thenReturn(List.of());
        when(habitMapper.selectByUserId(1L)).thenReturn(List.of());
        TodayResponse response = service.getToday(1L);
        assertEquals(0, response.getSummary().getTaskTotal());
        assertEquals(0, response.getSummary().getHabitTotal());
        assertEquals(0, response.getSummary().getCompletionRate().intValue());
    }

    @Test
    void rejectInvalidOrUnknownUserBeforeQueryingTasks() {
        ResponseStatusException bad = assertThrows(ResponseStatusException.class, () -> service.getToday(-1L));
        assertEquals(HttpStatus.BAD_REQUEST, bad.getStatusCode());
        ResponseStatusException missing = assertThrows(ResponseStatusException.class, () -> service.getToday(17L));
        assertEquals(HttpStatus.NOT_FOUND, missing.getStatusCode());
        verifyNoInteractions(taskMapper, habitMapper, userAssetMapper);
    }

    private static Task task(long id, TaskStatus status, LocalDateTime start) {
        Task result = new Task();
        result.setTaskId(id);
        result.setTitle("task " + id);
        result.setStatus(status);
        result.setStartTime(start);
        result.setTargetCount(100);
        return result;
    }

    private static TaskRecord record(long taskId, LocalDate date, int count, TaskRecordStatus status) {
        TaskRecord result = new TaskRecord();
        result.setTaskId(taskId);
        result.setRecordDate(date);
        result.setActualCount(count);
        result.setStatus(status);
        return result;
    }

    private static Habit habit(long id, HabitStatus status, LocalDate start, String rule) {
        Habit result = new Habit();
        result.setHabitId(id);
        result.setName("habit " + id);
        result.setStatus(status);
        result.setStartDate(start);
        result.setRepeatRule(rule);
        return result;
    }
}
