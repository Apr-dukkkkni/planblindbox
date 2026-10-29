package com.planblindbox.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.time.ZoneId;

@Configuration
public class BusinessClockConfig {

    @Bean
    public Clock businessClock() {
        return Clock.system(ZoneId.of("Asia/Shanghai"));
    }
}