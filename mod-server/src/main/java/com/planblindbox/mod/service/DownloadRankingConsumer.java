package com.planblindbox.mod.service;

import com.planblindbox.mod.config.RankingInfrastructure;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/** 收到消息时从 MySQL 重新计算绝对值，而非 ZINCRBY；重复消息不会重复计数。 */
@Component
@ConditionalOnProperty(name = "mod.ranking.enabled", havingValue = "true")
public class DownloadRankingConsumer {
    private static final Logger log = LoggerFactory.getLogger(DownloadRankingConsumer.class);
    private final RankingService ranking;

    public DownloadRankingConsumer(RankingService ranking) {
        this.ranking = ranking;
    }

    @RabbitListener(queues = RankingInfrastructure.QUEUE)
    public void downloaded(String modId) {
        try {
            ranking.refreshOne(modId);
        } catch (Exception e) {
            // 消费消息只负责通知，MySQL 保留完整事实，周期对账可自动补齐。
            // 不因 Redis 短暂故障让 RabbitMQ 陷入无休止的重试循环。
            log.warn("Redis 消费失败，后续 MySQL 对账恢复 Mod {}：{}", modId, e.toString());
        }
    }
}
