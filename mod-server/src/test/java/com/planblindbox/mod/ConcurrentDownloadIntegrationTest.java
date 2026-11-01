package com.planblindbox.mod;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties = "mod.ranking.enabled=false")
@AutoConfigureMockMvc
class ConcurrentDownloadIntegrationTest {
    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper mapper;

    @Test void concurrentRetriesCountOnceAndCreateOneOutbox() throws Exception {
        String modId = "com.example.concurrent" + UUID.randomUUID().toString().replace("-", "");
        String manifest = """
            {"schemaVersion":1,"id":"%s","name":"中文并发测试","version":"1.0.0",
             "description":"验证幂等","permissions":["tasks.create"],"dependencies":[],
             "taskTemplates":[{"title":"阅读十页","targetCount":1,"importance":3,"difficulty":2}]}
            """.formatted(modId);
        mvc.perform(post("/api/v1/admin/mods/publish")
            .header("Authorization", "Bearer test-only-token")
            .contentType(MediaType.APPLICATION_JSON)
            .characterEncoding(StandardCharsets.UTF_8.name())
            .content(manifest.getBytes(StandardCharsets.UTF_8)))
            .andExpect(status().isOk());

        String response = mvc.perform(get("/api/v1/mods/" + modId))
            .andExpect(status().isOk()).andReturn().getResponse()
            .getContentAsString(StandardCharsets.UTF_8);
        assertThat(mapper.readTree(response).path("name").asText()).isEqualTo("中文并发测试");

        String requestId = UUID.randomUUID().toString();
        String body = mapper.writeValueAsString(java.util.Map.of("requestId", requestId));
        String uri = "/api/v1/mods/" + modId + "/versions/1.0.0/download";
        int n = 4;
        var ready = new CountDownLatch(n);
        var fire = new CountDownLatch(1);
        var pool = Executors.newFixedThreadPool(n);
        List<java.util.concurrent.Future<JsonNode>> futures = new ArrayList<>();
        try {
            for (int i = 0; i < n; i++) {
                futures.add(pool.submit(() -> {
                    ready.countDown();
                    if (!fire.await(10, TimeUnit.SECONDS)) throw new IllegalStateException("未收到开始信号");
                    String json = mvc.perform(post(uri).contentType(MediaType.APPLICATION_JSON)
                        .content(body)).andExpect(status().isOk()).andReturn()
                        .getResponse().getContentAsString(StandardCharsets.UTF_8);
                    return mapper.readTree(json);
                }));
            }
            assertThat(ready.await(10, TimeUnit.SECONDS)).isTrue();
            fire.countDown();
            int counted = 0;
            for (var future : futures) {
                if (future.get(20, TimeUnit.SECONDS).path("counted").asBoolean()) counted++;
            }
            assertThat(counted).isEqualTo(1);
        } finally {
            fire.countDown();
            pool.shutdownNow();
        }
        assertThat(jdbc.queryForObject(
            "SELECT COUNT(*) FROM mod_download_events WHERE request_id=?", Integer.class, requestId))
            .isEqualTo(1);
        assertThat(jdbc.queryForObject("""
            SELECT COUNT(*) FROM mod_download_outbox o
            JOIN mod_download_events e ON e.id=o.download_event_id WHERE e.request_id=?
            """, Integer.class, requestId)).isEqualTo(1);
    }

    @Test void reusedRequestIdForDifferentModIsRejected() throws Exception {
        String firstId = "com.example.a" + UUID.randomUUID().toString().replace("-", "");
        String secondId = "com.example.b" + UUID.randomUUID().toString().replace("-", "");
        for (String id : List.of(firstId, secondId)) {
            String manifest = """
                {"schemaVersion":1,"id":"%s","name":"请求冲突","version":"1.0.0",
                 "permissions":["tasks.create"],"dependencies":[],"taskTemplates":[]}
                """.formatted(id);
            mvc.perform(post("/api/v1/admin/mods/publish")
                .header("Authorization", "Bearer test-only-token")
                .contentType(MediaType.APPLICATION_JSON).content(manifest.getBytes(StandardCharsets.UTF_8)))
                .andExpect(status().isOk());
        }
        String requestId = UUID.randomUUID().toString();
        String body = mapper.writeValueAsString(java.util.Map.of("requestId", requestId));
        mvc.perform(post("/api/v1/mods/"+firstId+"/versions/1.0.0/download")
            .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isOk());
        mvc.perform(post("/api/v1/mods/"+secondId+"/versions/1.0.0/download")
            .contentType(MediaType.APPLICATION_JSON).content(body)).andExpect(status().isConflict());
    }
}
