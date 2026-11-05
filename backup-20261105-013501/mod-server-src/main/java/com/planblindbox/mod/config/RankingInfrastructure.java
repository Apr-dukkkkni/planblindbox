package com.planblindbox.mod.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.EnableScheduling;

/** 在线排行榜独立开关。关闭时不连接 RabbitMQ/Redis，保留 MySQL 查询。 */
@Configuration
@ConditionalOnProperty(name = "mod.ranking.enabled", havingValue = "true")
@EnableScheduling
public class RankingInfrastructure {
    public static final String EXCHANGE = "plan.mod.events";
    public static final String QUEUE = "plan.mod.download.ranking";
    public static final String ROUTING_KEY = "download.count";

    @Bean
    TopicExchange modDownloadExchange() {
        return new TopicExchange(EXCHANGE, true, false);
    }

    @Bean
    Queue modDownloadRankingQueue() {
        return QueueBuilder.durable(QUEUE).build();
    }

    @Bean
    Binding modDownloadRankingBinding(Queue modDownloadRankingQueue, TopicExchange modDownloadExchange) {
        return BindingBuilder.bind(modDownloadRankingQueue).to(modDownloadExchange).with(ROUTING_KEY);
    }
}
