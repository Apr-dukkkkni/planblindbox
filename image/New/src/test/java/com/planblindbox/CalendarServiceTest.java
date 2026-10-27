package com.planblindbox;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.response.CalendarDayResponse;
import com.planblindbox.dto.response.CalendarMonthResponse;
import com.planblindbox.entity.AppUser;
import com.planblindbox.entity.Habit;
import com.planblindbox.entity.Task;
import com.planblindbox.enums.HabitStatus;
import com.planblindbox.enums.TaskStatus;
import com.planblindbox.mapper.*;
import com.planblindbox.service.CalendarService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CalendarServiceTest {
    @Mock AppUserMapper appUserMapper;
    @Mock StatsMapper statsMapper;
    @Mock TaskMapper taskMapper;
    @Mock TaskRecordMapper taskRecordMapper;
    @Mock HabitMapper habitMapper;
    @Mock HabitRecordMapper habitRecordMapper;
    @Spy ObjectMapper objectMapper = new ObjectMapper();
    CalendarService service;
    @Mock
    TimeRecordMapper timeRecordMapper;

    @BeforeEach
    void setUp() {
        service = new CalendarService(
                appUserMapper,
                statsMapper,
                taskMapper,
                taskRecordMapper,
                habitMapper,
                habitRecordMapper,
                timeRecordMapper,
                objectMapper
        );
    }

    @Test
    void monthResponseIncludesEveryDateAndZeroFillsMissingActivity() {
        when(appUserMapper.selectById(1L)).thenReturn(new AppUser());
        StatsMapper.DailyCount taskCount = new StatsMapper.DailyCount();
        taskCount.setDay(LocalDate.of(2026, 10, 8));
        taskCount.setCompletedCount(2L);
        StatsMapper.DailyCount habitCount = new StatsMapper.DailyCount();
        habitCount.setDay(LocalDate.of(2026, 10, 8));
        habitCount.setCompletedCount(1L);
        when(statsMapper.completedTasks(eq(1L), any(), any())).thenReturn(List.of(taskCount));
        when(statsMapper.completedHabits(eq(1L), any(), any())).thenReturn(List.of(habitCount));

        CalendarMonthResponse response = service.getMonth(1L, YearMonth.of(2026, 10));

        assertEquals("2026-10", response.month());
        assertEquals(31, response.days().size());
        assertEquals(2, response.days().get(7).completedTasks());
        assertEquals(1, response.days().get(7).habitCheckIns());
        assertEquals(0, response.days().get(0).completedTasks());
        assertEquals(0, response.days().get(0).habitCheckIns());
    }

    @Test
    void dayDetailShowsTasksAndHabitsScheduledForThatBusinessDate() {
        LocalDate date = LocalDate.of(2026, 10, 26);
        when(appUserMapper.selectById(1L)).thenReturn(new AppUser());

        Task task = new Task();
        task.setTaskId(10L);
        task.setTitle("复习 Java");
        task.setStartTime(date.atTime(10, 0));
        task.setEndTime(date.plusDays(1).atTime(5, 0));
        task.setCreateTime(date.atTime(10, 0));
        task.setStatus(TaskStatus.PENDING);
        task.setTargetCount(3);
        when(taskMapper.selectAllByUserIdForCalendar(1L)).thenReturn(List.of(task));
        when(taskRecordMapper.selectByUserIdAndDate(1L, date)).thenReturn(List.of());

        Habit habit = new Habit();
        habit.setHabitId(20L);
        habit.setName("每日阅读");
        habit.setStartDate(date.minusDays(10));
        habit.setRepeatRule("{\"type\":\"DAILY\"}");
        habit.setStatus(HabitStatus.ACTIVE);
        when(habitMapper.selectAllByUserIdForCalendar(1L)).thenReturn(List.of(habit));
        when(habitRecordMapper.selectByUserIdAndDate(1L, date)).thenReturn(List.of());

        CalendarDayResponse response = service.getDay(1L, date);

        assertEquals(date, response.date());
        assertEquals(1, response.tasks().size());
        assertEquals("PENDING", response.tasks().get(0).status());
        assertEquals(1, response.habits().size());
        assertEquals("每日阅读", response.habits().get(0).name());
        assertEquals(false, response.habits().get(0).checkedIn());
    }
}
