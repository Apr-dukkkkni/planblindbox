package com.planblindbox;

import com.planblindbox.dto.request.TaskCreateRequest;
import com.planblindbox.dto.request.TaskUpdateRequest;
import com.planblindbox.dto.response.TaskResponse;
import com.planblindbox.service.TaskService;
import com.planblindbox.util.BusinessTime;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.transaction.annotation.Transactional;

import java.sql.PreparedStatement;
import java.sql.Statement;
import java.time.LocalDateTime;
import java.util.Objects;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;

@SpringBootTest
@Transactional
class TaskDeadlineIntegrationTest {

    @Autowired private JdbcTemplate jdbcTemplate;
    @Autowired private TaskService taskService;

    @Test
    void createWithoutDeadlineUsesNextFiveAmReset() {
        Long userId = createUser();
        LocalDateTime start = LocalDateTime.now().withNano(0).plusMinutes(10);

        TaskResponse created = taskService.create(request(userId, start, null));

        assertEquals(BusinessTime.nextReset(start), created.getEndTime());
    }

    @Test
    void explicitLongDeadlineSurvivesCreateAndUpdateWithoutDeadlineField() {
        Long userId = createUser();
        LocalDateTime start = LocalDateTime.now().withNano(0).plusMinutes(10);
        LocalDateTime customEnd = start.plusDays(14);

        TaskResponse created = taskService.create(request(userId, start, customEnd));
        assertEquals(customEnd, created.getEndTime());

        TaskUpdateRequest update = new TaskUpdateRequest();
        update.setTitle("更新标题但不修改截止时间");
        TaskResponse updated = taskService.update(userId, created.getTaskId(), update);

        assertEquals(customEnd, updated.getEndTime());
    }

    private TaskCreateRequest request(Long userId, LocalDateTime start, LocalDateTime end) {
        TaskCreateRequest request = new TaskCreateRequest();
        request.setUserId(userId);
        request.setTitle("截止时间测试任务");
        request.setStartTime(start);
        request.setEndTime(end);
        request.setTargetCount(1);
        request.setImportance(3);
        request.setUrgency(3);
        request.setDifficulty(3);
        return request;
    }

    private Long createUser() {
        String suffix = UUID.randomUUID().toString();
        GeneratedKeyHolder keys = new GeneratedKeyHolder();
        jdbcTemplate.update(connection -> {
            PreparedStatement statement = connection.prepareStatement(
                    "INSERT INTO app_user (username, email, password) VALUES (?, ?, ?)",
                    Statement.RETURN_GENERATED_KEYS);
            statement.setString(1, "deadline-" + suffix);
            statement.setString(2, "deadline-" + suffix + "@example.com");
            statement.setString(3, "test-only-password");
            return statement;
        }, keys);
        return Objects.requireNonNull(keys.getKey()).longValue();
    }
}
