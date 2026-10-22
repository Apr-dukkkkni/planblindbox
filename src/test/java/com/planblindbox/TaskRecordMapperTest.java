package com.planblindbox;

import com.planblindbox.entity.Task;
import com.planblindbox.entity.TaskRecord;
import com.planblindbox.enums.TaskRecordStatus;
import com.planblindbox.enums.TaskStatus;
import com.planblindbox.mapper.TaskMapper;
import com.planblindbox.mapper.TaskRecordMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.transaction.annotation.Transactional;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDate;
import java.util.Objects;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.*;

/**
 * MySQL 集成测试：需要本地 plan_blind_box 数据库已建表。
 * 使用 @Transactional，测试结束后回滚，不污染正常任务数据。
 */
@SpringBootTest
@Transactional
class TaskRecordMapperTest {

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Autowired
    private TaskMapper taskMapper;

    @Autowired
    private TaskRecordMapper taskRecordMapper;

    @Test
    void shouldInsertAccumulateAndQueryTaskRecord() {
        // 新建测试用户，不依赖数据库里是否已经有 user_id=1。
        GeneratedKeyHolder keyHolder = new GeneratedKeyHolder();
        jdbcTemplate.update(connection -> {
            PreparedStatement statement = connection.prepareStatement(
                    "INSERT INTO app_user (username, email, password) VALUES (?, ?, ?)",
                    Statement.RETURN_GENERATED_KEYS
            );
            statement.setString(1, "task-record-test");
            statement.setString(2, "test-" + UUID.randomUUID() + "@example.com");
            statement.setString(3, "not-a-real-password");
            return statement;
        }, keyHolder);
        Long userId = Objects.requireNonNull(keyHolder.getKey()).longValue();

        Task task = new Task();
        task.setUserId(userId);
        task.setTitle("背诵100个单词");
        task.setTargetCount(100);
        task.setStatus(TaskStatus.PENDING);
        assertEquals(1, taskMapper.insert(task));
        assertNotNull(task.getTaskId());

        LocalDate today = LocalDate.now();
        TaskRecord yesterday = newRecord(task.getTaskId(), today.minusDays(1), 30);
        TaskRecord todayRecord = newRecord(task.getTaskId(), today, 40);

        assertEquals(1, taskRecordMapper.insert(yesterday));
        assertEquals(1, taskRecordMapper.insert(todayRecord));
        assertNotNull(todayRecord.getTaskRecordId());

        TaskRecord saved = taskRecordMapper.selectByTaskIdAndDate(task.getTaskId(), today);
        assertNotNull(saved);
        assertEquals(40, saved.getActualCount());
        assertEquals(TaskRecordStatus.IN_PROGRESS, saved.getStatus());
        assertEquals(70L, taskRecordMapper.sumActualCount(task.getTaskId()));

        // 同一天追加30，而不是再插入新的一天。
        assertEquals(1, taskRecordMapper.incrementActualCount(todayRecord.getTaskRecordId(), 30));
        TaskRecord updated = taskRecordMapper.selectByTaskIdAndDate(task.getTaskId(), today);
        assertEquals(70, updated.getActualCount());
        assertEquals(100L, taskRecordMapper.sumActualCount(task.getTaskId()));
        assertEquals(2, taskRecordMapper.selectByTaskId(task.getTaskId()).size());
    }

    private TaskRecord newRecord(Long taskId, LocalDate date, int count) {
        TaskRecord record = new TaskRecord();
        record.setTaskId(taskId);
        record.setRecordDate(date);
        record.setStatus(TaskRecordStatus.IN_PROGRESS);
        record.setActualCount(count);
        return record;
    }
}
