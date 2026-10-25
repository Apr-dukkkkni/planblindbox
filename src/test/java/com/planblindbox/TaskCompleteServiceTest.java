package com.planblindbox;

import com.planblindbox.dto.request.TaskCompleteRequest;
import com.planblindbox.dto.request.TaskUpdateRequest;
import com.planblindbox.dto.response.TaskCompleteResponse;
import com.planblindbox.entity.Habit;
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

    // 测试1：从0开始，超额提交后自动封顶
    @Test
    void shouldCapOverflowToTarget() {
        // 创建目标数量为5的任务
        Task task = newTask(5);

        // 提交6次，预期实际只记录5次
        TaskCompleteResponse response = taskService.complete(
                task.getUserId(),
                task.getTaskId(),
                request(6)
        );

        // 验证返回结果
        assertEquals(5, response.getIncrementCount());
        assertEquals(5L, response.getTotalActualCount());
        assertEquals(0, response.getRemainingCount());
        assertEquals(TaskStatus.COMPLETED, response.getStatus());

        // 验证持久化层记录的累计数量
        assertEquals(
                5L,
                taskRecordMapper.sumActualCount(task.getTaskId())
        );
    }


    // 测试2：已完成部分进度，超额提交自动补齐
    @Test
    void shouldCapOverflowToRemaining() {
        // 创建目标数量为10的任务
        Task task = newTask(10);

        // 第一次提交8次
        TaskCompleteResponse first = taskService.complete(
                task.getUserId(),
                task.getTaskId(),
                request(8)
        );

        // 此时尚未完成任务
        assertEquals(8, first.getIncrementCount());
        assertEquals(8L, first.getTotalActualCount());
        assertEquals(2, first.getRemainingCount());
        assertEquals(TaskStatus.IN_PROGRESS, first.getStatus());

        // 第二次提交5次，但实际只剩2次
        TaskCompleteResponse second = taskService.complete(
                task.getUserId(),
                task.getTaskId(),
                request(5)
        );

        // 验证自动补齐结果
        assertEquals(2, second.getIncrementCount());
        assertEquals(10L, second.getTotalActualCount());
        assertEquals(0, second.getRemainingCount());
        assertEquals(TaskStatus.COMPLETED, second.getStatus());

        // 验证累计进度没有超过目标
        assertEquals(
                10L,
                taskRecordMapper.sumActualCount(task.getTaskId())
        );

        // 完成后再次提交，应该被拒绝
        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> taskService.complete(
                        task.getUserId(),
                        task.getTaskId(),
                        request(1)
                )
        );

        assertEquals(409, exception.getStatusCode().value());

        // 拒绝后，累计数量必须保持不变
        assertEquals(
                10L,
                taskRecordMapper.sumActualCount(task.getTaskId())
        );
    }


    // 测试3：已归档任务不允许继续记录
    @Test
    void shouldRejectArchivedTask() {
        // 创建任务
        Task task = newTask(5);

        // 归档任务
        taskService.delete(
                task.getUserId(),
                task.getTaskId()
        );

        // 归档后尝试记录进度
        ResponseStatusException exception = assertThrows(
                ResponseStatusException.class,
                () -> taskService.complete(
                        task.getUserId(),
                        task.getTaskId(),
                        request(1)
                )
        );

        // 预期返回409冲突
        assertEquals(409, exception.getStatusCode().value());

        // 验证没有新增执行数量
        assertEquals(
                0L,
                taskRecordMapper.sumActualCount(task.getTaskId())
        );
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
