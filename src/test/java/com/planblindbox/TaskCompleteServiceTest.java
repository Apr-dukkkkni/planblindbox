package com.planblindbox;

import com.planblindbox.dto.request.TaskCompleteRequest;
import com.planblindbox.dto.request.TaskUpdateRequest;
import com.planblindbox.dto.response.TaskCompleteResponse;
import com.planblindbox.entity.Task;
import com.planblindbox.entity.TaskRecord;
import com.planblindbox.enums.TaskRecordStatus;
import com.planblindbox.enums.TaskStatus;
import com.planblindbox.mapper.TaskMapper;
import com.planblindbox.mapper.TaskRecordMapper;
import com.planblindbox.service.TaskService;
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

/** 真实 MySQL 集成测试；测试事务结束自动回滚。 */
@SpringBootTest
@Transactional
class TaskCompleteServiceTest {

    @Autowired private JdbcTemplate jdbcTemplate;
    @Autowired private TaskService taskService;
    @Autowired private TaskMapper taskMapper;
    @Autowired private TaskRecordMapper taskRecordMapper;

    @Test
    void shouldAccumulateTodayAndCompleteAcrossDays() {
        // Step3: 进入完成状态后会结算奖励；此测试需提供事务内的奖励规则。
        jdbcTemplate.update("""
                INSERT INTO reward_config (type, coin, exp, water, enabled)
                VALUES ('TASK_COMPLETE', 10, 20, 2, TRUE)
                ON DUPLICATE KEY UPDATE coin=10, exp=20, water=2, enabled=TRUE
                """);
        Task task = newTask(100);
        TaskCompleteResponse first = taskService.complete(task.getUserId(), task.getTaskId(), request(30));
        assertEquals(30L, first.getTotalActualCount());
        assertEquals(70, first.getRemainingCount());
        assertEquals(TaskStatus.IN_PROGRESS, first.getStatus());

        TaskCompleteResponse second = taskService.complete(task.getUserId(), task.getTaskId(), request(40));
        assertEquals(70, second.getTodayActualCount());
        assertEquals(70L, second.getTotalActualCount());
        assertEquals(1, taskRecordMapper.selectByTaskId(task.getTaskId()).size());

        // 模拟历史某一天已完成 20 个；当前总进度 90。
        TaskRecord yesterday = new TaskRecord();
        yesterday.setTaskId(task.getTaskId());
        yesterday.setRecordDate(LocalDate.now().minusDays(1));
        yesterday.setStatus(TaskRecordStatus.IN_PROGRESS);
        yesterday.setActualCount(20);
        assertEquals(1, taskRecordMapper.insert(yesterday));

        TaskCompleteResponse done = taskService.complete(task.getUserId(), task.getTaskId(), request(10));
        assertEquals(TaskStatus.COMPLETED, done.getStatus());
        assertEquals(100L, done.getTotalActualCount());
        assertEquals(0, done.getRemainingCount());
        assertEquals(80, done.getTodayActualCount());
        assertEquals(TaskStatus.COMPLETED,
                taskMapper.selectById(task.getTaskId(), task.getUserId()).getStatus());
        assertEquals(2, taskRecordMapper.selectByTaskId(task.getTaskId()).size());

        TaskRecord today = taskRecordMapper.selectByTaskIdAndDate(task.getTaskId(), LocalDate.now());
        assertEquals(TaskRecordStatus.COMPLETED, today.getStatus());
        assertNotNull(today.getFinishTime());

        // 任务已经完成，禁止重复结算进度。
        assertThrows(ResponseStatusException.class,
                () -> taskService.complete(task.getUserId(), task.getTaskId(), request(1)));
        assertEquals(100L, taskRecordMapper.sumActualCount(task.getTaskId()));
    }

    @Test
    void shouldRejectOverflowAndArchivedTask() {
        Task task = newTask(5);
        ResponseStatusException overflow = assertThrows(ResponseStatusException.class,
                () -> taskService.complete(task.getUserId(), task.getTaskId(), request(6)));
        assertEquals(400, overflow.getStatusCode().value());
        assertEquals(0L, taskRecordMapper.sumActualCount(task.getTaskId()));

        taskService.delete(task.getUserId(), task.getTaskId());
        ResponseStatusException archived = assertThrows(ResponseStatusException.class,
                () -> taskService.complete(task.getUserId(), task.getTaskId(), request(1)));
        assertEquals(409, archived.getStatusCode().value());
    }

    @Test
    void shouldPreventBypassingCompletionByPut() {
        Task task = newTask(10);
        TaskUpdateRequest changeStatus = new TaskUpdateRequest();
        changeStatus.setStatus(TaskStatus.COMPLETED);
        ResponseStatusException ex = assertThrows(ResponseStatusException.class,
                () -> taskService.update(task.getUserId(), task.getTaskId(), changeStatus));
        assertEquals(400, ex.getStatusCode().value());
        assertEquals(TaskStatus.PENDING,
                taskMapper.selectById(task.getTaskId(), task.getUserId()).getStatus());

        taskService.complete(task.getUserId(), task.getTaskId(), request(5));
        TaskUpdateRequest shrinkGoal = new TaskUpdateRequest();
        shrinkGoal.setTargetCount(3);
        ResponseStatusException targetError = assertThrows(ResponseStatusException.class,
                () -> taskService.update(task.getUserId(), task.getTaskId(), shrinkGoal));
        assertEquals(409, targetError.getStatusCode().value());
    }

    private TaskCompleteRequest request(int increment) {
        TaskCompleteRequest request = new TaskCompleteRequest();
        request.setActualCount(increment);
        return request;
    }

    private Task newTask(int goal) {
        GeneratedKeyHolder keys = new GeneratedKeyHolder();
        jdbcTemplate.update(con -> {
            PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO app_user (username, email, password) VALUES (?, ?, ?)",
                    Statement.RETURN_GENERATED_KEYS);
            ps.setString(1, "task-complete-test");
            ps.setString(2, "tc-" + UUID.randomUUID() + "@example.com");
            ps.setString(3, "not-a-real-password");
            return ps;
        }, keys);
        Long userId = Objects.requireNonNull(keys.getKey()).longValue();
        Task task = new Task();
        task.setUserId(userId);
        task.setTitle("集成测试任务");
        task.setTargetCount(goal);
        task.setStatus(TaskStatus.PENDING);
        assertEquals(1, taskMapper.insert(task));
        return task;
    }
}
