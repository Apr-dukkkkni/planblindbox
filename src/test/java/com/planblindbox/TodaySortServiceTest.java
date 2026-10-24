package com.planblindbox;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.planblindbox.dto.response.TodayResponse;
import com.planblindbox.entity.AppUser;
import com.planblindbox.entity.Task;
import com.planblindbox.entity.TaskRecord;
import com.planblindbox.enums.TaskRecordStatus;
import com.planblindbox.enums.TaskStatus;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.HabitMapper;
import com.planblindbox.mapper.TaskMapper;
import com.planblindbox.mapper.TaskRecordMapper;
import com.planblindbox.mapper.UserAssetMapper;
import com.planblindbox.service.HabitCheckInService;
import com.planblindbox.service.impl.TodayServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TodaySortServiceTest {
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

    private void givenTasks(Task... tasks) {
        when(appUserMapper.selectById(1L)).thenReturn(new AppUser());
        when(taskMapper.selectByUserId(1L)).thenReturn(List.of(tasks));
        when(habitMapper.selectByUserId(1L)).thenReturn(List.of());
    }

    private Task task(long id, Integer importance, Integer difficulty, LocalDateTime due) {
        Task task = new Task();
        task.setTaskId(id);
        task.setTitle("任务 " + id);
        task.setStatus(TaskStatus.PENDING);
        task.setTargetCount(1);
        task.setImportance(importance);
        task.setDifficulty(difficulty);
        task.setEndTime(due);
        return task;
    }

    private List<Long> ids(TodayResponse response) {
        return response.getTasks().stream().map(TodayResponse.TaskItem::getTaskId).toList();
    }

    @Test
    void defaultAndTimeSortByEarlierDeadlineWithNoDeadlineLast() {
        LocalDateTime now = LocalDateTime.now();
        Task importantLater = task(10, 5, 5, now.plusHours(8));
        Task lessImportantSooner = task(20, 1, 1, now.plusHours(2));
        Task noDeadline = task(30, 4, 3, null);
        givenTasks(importantLater, noDeadline, lessImportantSooner);

        TodayResponse response = service.getToday(1L);
        assertEquals(List.of(20L, 10L, 30L), ids(response));
        assertEquals(1, response.getTasks().get(0).getImportance());
        assertEquals(1, response.getTasks().get(0).getDifficulty());
    }

    @Test
    void importanceSortUsesFiveAsHighestAndNullAsThreeOnlyForSorting() {
        LocalDateTime now = LocalDateTime.now();
        Task low = task(10, 1, 5, now.plusHours(1));
        Task unspecified = task(20, null, null, now.plusHours(2));
        Task high = task(30, 5, 1, now.plusDays(3));
        givenTasks(low, unspecified, high);

        TodayResponse response = service.getToday(1L, "importance");
        assertEquals(List.of(30L, 20L, 10L), ids(response));
        assertEquals(1, response.getTasks().get(0).getDifficulty()); // 难度不参与排序
        assertNull(response.getTasks().get(1).getImportance()); // 原始数据不被改成 3
    }

    @Test
    void importanceTiesSortByDeadlineThenId() {
        LocalDateTime due = LocalDateTime.now().plusHours(8);
        Task secondId = task(2, 4, 1, due);
        Task firstId = task(1, 4, 5, due);
        Task earlier = task(3, 4, 2, due.minusHours(1));
        givenTasks(secondId, firstId, earlier);

        assertEquals(List.of(3L, 1L, 2L), ids(service.getToday(1L, "IMPORTANCE")));
    }

    @Test
    void todayCompletedTasksAlwaysComeAfterPendingOnEitherSort() {
        LocalDateTime now = LocalDateTime.now();
        Task completed = task(1, 5, 5, now.minusHours(3));
        completed.setStatus(TaskStatus.COMPLETED);
        Task pending = task(2, 1, 1, now.plusDays(1));
        givenTasks(completed, pending);
        TaskRecord record = new TaskRecord();
        record.setStatus(TaskRecordStatus.COMPLETED);
        record.setRecordDate(LocalDate.now());
        record.setActualCount(1);
        when(taskRecordMapper.selectByTaskIdAndDate(1L, LocalDate.now())).thenReturn(record);

        assertEquals(List.of(2L, 1L), ids(service.getToday(1L, "importance")));
    }

    @Test
    void invalidSortIsBadRequestWithoutDatabaseAccess() {
        ResponseStatusException ex = assertThrows(ResponseStatusException.class,
                () -> service.getToday(1L, "priority_score"));
        assertEquals(HttpStatus.BAD_REQUEST, ex.getStatusCode());
        ResponseStatusException blank = assertThrows(ResponseStatusException.class,
                () -> service.getToday(1L, ""));
        assertEquals(HttpStatus.BAD_REQUEST, blank.getStatusCode());
        verifyNoInteractions(appUserMapper, taskMapper, habitMapper, userAssetMapper);
    }
}
