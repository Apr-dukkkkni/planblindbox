package com.planblindbox.mod;

import com.planblindbox.mod.config.RankingInfrastructure;
import com.planblindbox.mod.service.DownloadOutboxPublisher;
import org.junit.jupiter.api.Test;
import org.springframework.amqp.AmqpException;
import org.springframework.amqp.core.MessagePostProcessor;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@SpringBootTest(properties = {
    "mod.ranking.enabled=false",
    // 与其他测试隔离，避免共用 H2 数据库中的 Outbox 记录及后台任务干扰。
    "spring.datasource.url=jdbc:h2:mem:outbox_retry;MODE=MySQL;DB_CLOSE_DELAY=-1;DATABASE_TO_LOWER=TRUE"
})
class OutboxRetryIntegrationTest {
    @Autowired JdbcTemplate jdbc;

    @Test void brokerFailureKeepsPendingAndAckMarksPublished() {
        String modId = "com.example.outbox" + UUID.randomUUID().toString().replace("-", "");
        jdbc.update("INSERT INTO mod_packages(mod_id,name,description,latest_version,enabled) VALUES (?,?,?,?,TRUE)",
            modId, "故障测试", "outbox", "1.0.0");
        jdbc.update("INSERT INTO mod_versions(mod_id,version,manifest_json) VALUES (?,?,?)",
            modId, "1.0.0", "{}");
        String requestId = UUID.randomUUID().toString();
        jdbc.update("INSERT INTO mod_download_events(request_id,mod_id,version) VALUES (?,?,?)",
            requestId, modId, "1.0.0");
        long eventId = jdbc.queryForObject(
            "SELECT id FROM mod_download_events WHERE request_id=?", Long.class, requestId);
        jdbc.update("INSERT INTO mod_download_outbox(download_event_id,mod_id) VALUES (?,?)",
            eventId, modId);
        long outboxId = jdbc.queryForObject(
            "SELECT id FROM mod_download_outbox WHERE download_event_id=?", Long.class, eventId);

        RabbitTemplate rabbit = mock(RabbitTemplate.class);
        doThrow(new AmqpException("模拟消息队列断连"))
            .when(rabbit).convertAndSend(eq(RankingInfrastructure.EXCHANGE),
                eq(RankingInfrastructure.ROUTING_KEY), eq(modId),
                any(MessagePostProcessor.class), any(CorrelationData.class));
        DownloadOutboxPublisher publisher = new DownloadOutboxPublisher(jdbc, rabbit);
        publisher.publishBatch();
        assertThat(jdbc.queryForObject(
            "SELECT status FROM mod_download_outbox WHERE id=?", String.class, outboxId))
            .isEqualTo("PENDING");

        reset(rabbit);
        doAnswer(invocation -> {
            CorrelationData data = invocation.getArgument(4);
            data.getFuture().complete(new CorrelationData.Confirm(true, null));
            return null;
        }).when(rabbit).convertAndSend(eq(RankingInfrastructure.EXCHANGE),
            eq(RankingInfrastructure.ROUTING_KEY), any(),
            any(MessagePostProcessor.class), any(CorrelationData.class));
        publisher.publishBatch();
        assertThat(jdbc.queryForObject(
            "SELECT status FROM mod_download_outbox WHERE id=?", String.class, outboxId))
            .isEqualTo("PUBLISHED");
        assertThat(jdbc.queryForObject(
            "SELECT published_at FROM mod_download_outbox WHERE id=?", java.sql.Timestamp.class, outboxId))
            .isNotNull();
    }
}
