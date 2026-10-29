package com.planblindbox;

import com.planblindbox.dto.request.TaskCompleteRequest;
import com.planblindbox.dto.response.TaskCompleteResponse;
import com.planblindbox.entity.Task;
import com.planblindbox.enums.TaskStatus;
import com.planblindbox.mapper.TaskMapper;
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
import java.util.Objects;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 真实 MySQL 集成测试，使用测试事务，新增用户和任务在测试结束时回滚。
 * 测试中的奖励配置也仅在事务内临时覆盖。
 */
@SpringBootTest
@Transactional
class TaskRewardIntegrationTest {
    @Autowired private JdbcTemplate jdbcTemplate;
    @Autowired private TaskService taskService;
    @Autowired private TaskMapper taskMapper;

    @Test
    void shouldRewardOnlyOnFirstCompletionAndCreateThreeRecords() {
        setRule(true);
        long userId = newUser();
        Task task = newTask(userId, 60);

        TaskCompleteResponse first = taskService.complete(userId, task.getTaskId(), increment(30));
        assertEquals(TaskStatus.IN_PROGRESS, first.getStatus());
        assertNull(first.getReward());
        assertEquals(0, countLedgers(userId, task.getTaskId()));
        assertEquals(0, jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM user_asset WHERE user_id=?", Integer.class, userId));

        TaskCompleteResponse second = taskService.complete(userId, task.getTaskId(), increment(30));
        assertEquals(TaskStatus.COMPLETED, second.getStatus());
        assertEquals(60L, second.getTotalActualCount());
        assertNotNull(second.getReward());
        assertTrue(second.getReward().getGranted());
        assertEquals(8, second.getReward().getCoin());
        assertEquals(80L, second.getReward().getExp());
        assertEquals(0, second.getReward().getWater());

        assertEquals(8, second.getReward().getCoinBalance());
        assertEquals(80L, second.getReward().getExpBalance());
        assertEquals(0, second.getReward().getWaterBalance());

        assertEquals(2, countLedgers(userId, task.getTaskId()));

        assertThrows(ResponseStatusException.class,
                () -> taskService.complete(userId, task.getTaskId(), increment(1)));
        assertEquals(2, countLedgers(userId, task.getTaskId()));
        assertEquals(8, jdbcTemplate.queryForObject(
                "SELECT coin FROM user_asset WHERE user_id=?",
                Integer.class, userId));
    }

    @Test
    void shouldAccumulateAssetsAcrossTwoDifferentTasks() {
        setRule(true);
        long userId = newUser();
        Task task1 = newTask(userId, 1);
        Task task2 = newTask(userId, 1);
        taskService.complete(userId, task1.getTaskId(), increment(1));
        TaskCompleteResponse second = taskService.complete(userId, task2.getTaskId(), increment(1));
        assertEquals(16, second.getReward().getCoinBalance());
        assertEquals(160L, second.getReward().getExpBalance());
        assertEquals(0, second.getReward().getWaterBalance());

        assertEquals(4, countLedgers(userId, task1.getTaskId())
                + countLedgers(userId, task2.getTaskId()));
    }

    @Test
    void disabledRuleShouldAllowCompletionWithoutAssetChange() {
        setRule(false);
        long userId = newUser();
        Task task = newTask(userId, 1);
        TaskCompleteResponse response = taskService.complete(userId, task.getTaskId(), increment(1));
        assertEquals(TaskStatus.COMPLETED, response.getStatus());
        assertFalse(response.getReward().getGranted());
        assertEquals(0, countLedgers(userId, task.getTaskId()));
        assertEquals(0, jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM user_asset WHERE user_id=?", Integer.class, userId));
    }

    @Test
    void invalidRewardRuleShouldThrowInsteadOfIssuingPartialAssets() {
        setRule(true);
        jdbcTemplate.update("UPDATE reward_config SET coin=-1 WHERE type='TASK_COMPLETE'");
        long userId = newUser();
        Task task = newTask(userId, 1);
        IllegalStateException thrown = assertThrows(IllegalStateException.class,
                () -> taskService.complete(userId, task.getTaskId(), increment(1)));
        assertTrue(thrown.getMessage().contains("奖励配置不合法"));
        assertEquals(0, countLedgers(userId, task.getTaskId()));
        // 测试事务外层由 @Transactional 管理；异常时应触发实际运行环境的事务整体回滚。
    }

    private void setRule(boolean enabled) {
        jdbcTemplate.update("""
                INSERT INTO reward_config (type, coin, exp, water, enabled)
                VALUES ('TASK_COMPLETE', 10, 20, 2, ?)
                ON DUPLICATE KEY UPDATE coin=10, exp=20, water=2, enabled=?
                """, enabled, enabled);
    }

    private int countLedgers(long userId, long taskId) {
        return jdbcTemplate.queryForObject("""
                SELECT COUNT(*) FROM asset_record
                WHERE user_id=? AND source='TASK' AND source_id=? AND action='TASK_COMPLETE'
                """, Integer.class, userId, taskId);
    }

    private TaskCompleteRequest increment(int amount) {
        TaskCompleteRequest request = new TaskCompleteRequest();
        request.setActualCount(amount);
        return request;
    }

    private long newUser() {
        GeneratedKeyHolder keys = new GeneratedKeyHolder();
        jdbcTemplate.update(con -> {
            PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO app_user (username, email, password) VALUES (?, ?, ?)",
                    Statement.RETURN_GENERATED_KEYS);
            ps.setString(1, "task-reward-test");
            ps.setString(2, "tr-" + UUID.randomUUID() + "@example.com");
            ps.setString(3, "not-a-real-password");
            return ps;
        }, keys);
        return Objects.requireNonNull(keys.getKey()).longValue();
    }

    private Task newTask(long userId, int target) {
        Task task = new Task();
        task.setUserId(userId);
        task.setTitle("奖励结算集成测试");
        task.setTargetCount(target);
        task.setImportance(3);
        task.setDifficulty(3);
        task.setStatus(TaskStatus.PENDING);
        assertEquals(1, taskMapper.insert(task));
        return task;
    }
}
