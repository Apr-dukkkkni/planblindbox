package com.planblindbox.mod.api;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.util.Arrays;

@Configuration
public class CorsConfig implements WebMvcConfigurer {
    @Value("${mod.allowed-origins:http://localhost:3000}") private String origins;
    @Override public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/v1/**")
           .allowedOrigins(Arrays.stream(origins.split(",")).map(String::trim).toArray(String[]::new))
           .allowedMethods("GET","POST","PATCH","OPTIONS")
           .allowedHeaders("Authorization","Content-Type");
    }
}
