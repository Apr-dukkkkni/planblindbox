package com.planblindbox.mod.service;

import com.planblindbox.mod.config.RankingInfrastructure;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.MessageDeliveryMode;
import org.springframework.amqp.rabbit.connection.CorrelationData;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

/** Outbox 至少一次投递。崩溃后可能重发，消费者以 MySQL 绝对计数实现幂等。 */
@Component
@ConditionalOnProperty(name = "mod.ranking.enabled", havingValue = "true")
public class DownloadOutboxPublisher {
    private static final Logger log = LoggerFactory.getLogger(DownloadOutboxPublisher.class);
    private final JdbcTemplate jdbc;
    private final RabbitTemplate rabbit;

    public DownloadOutboxPublisher(JdbcTemplate jdbc, RabbitTemplate rabbit) {
        this.jdbc = jdbc;
        this.rabbit = rabbit;
        this.rabbit.setMandatory(true);
    }

    @Scheduled(initialDelay = 4000, fixedDelayString = "${mod.ranking.publish-interval-ms:2000}")
    public void publishBatch() {
        List<Map<String, Object>> pending = jdbc.queryForList(
            "SELECT id,mod_id FROM mod_download_outbox WHERE status='PENDING' ORDER BY id LIMIT 50");
        for (Map<String, Object> row : pending) {
            long id = ((Number) row.get("id")).longValue();
            String modId = (String) row.get("mod_id");
            try {
                // Publisher confirm：收到 broker ACK 后才标记已发布。
                CorrelationData correlation = new CorrelationData(UUID.randomUUID().toString());
                rabbit.convertAndSend(
                    RankingInfrastructure.EXCHANGE,
                    RankingInfrastructure.ROUTING_KEY,
                    modId,
                    message -> {
                        message.getMessageProperties().setDeliveryMode(MessageDeliveryMode.PERSISTENT);
                        return message;
                    }, correlation);
                var confirm = correlation.getFuture().get(5, TimeUnit.SECONDS);
                if (!confirm.isAck()) {
                    log.warn("Outbox {} 未获 broker ACK：{}", id, confirm.getReason());
                    break;
                }
                jdbc.update("UPDATE mod_download_outbox SET status='PUBLISHED',published_at=CURRENT_TIMESTAMP WHERE id=? AND status='PENDING'", id);
            } catch (Exception e) {
                log.warn("Outbox 投递暂停，保留待发事件 {}：{}", id, e.toString());
                break;
            }
        }
    }
}
