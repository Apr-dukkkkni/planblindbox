package com.planblindbox.mod.auth;

import java.util.concurrent.Executor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

@Configuration @EnableAsync
public class MailExecutorConfig {
    @Bean("mailExecutor") Executor mailExecutor() {
        ThreadPoolTaskExecutor e=new ThreadPoolTaskExecutor();
        e.setCorePoolSize(1);e.setMaxPoolSize(2);e.setQueueCapacity(30);
        e.setThreadNamePrefix("password-email-");e.initialize();return e;
    }
}
