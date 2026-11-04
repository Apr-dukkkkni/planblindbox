package com.planblindbox.mod;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(properties = "mod.ranking.enabled=false")
@AutoConfigureMockMvc
@WithMockUser(username = "mod-integration-test")
class RankingIntegrationTest {
    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate jdbc;
    @Autowired ObjectMapper mapper;

    @Test void acceptedDownloadCreatesOneOutboxAndRankingFallsBackToMysql() throws Exception {
        String id = "com.example.rank" + UUID.randomUUID().toString().replace("-", "");
        String raw = """
            {"schemaVersion":1,"id":"%s","name":"排行榜测试","version":"1.0.0",
             "description":"测试","permissions":["tasks.create"],"dependencies":[],
             "taskTemplates":[{"title":"阅读","targetCount":1,"importance":3,"difficulty":2}]}
            """.formatted(id);
        mvc.perform(post("/api/v1/admin/mods/publish")
            .header("Authorization", "Bearer test-only-token")
            .contentType(MediaType.APPLICATION_JSON).content(raw)).andExpect(status().isOk());
        String requestId = UUID.randomUUID().toString();
        String request = mapper.writeValueAsString(java.util.Map.of("requestId", requestId));
        String uri = "/api/v1/mods/" + id + "/versions/1.0.0/download";
        mvc.perform(post(uri).contentType(MediaType.APPLICATION_JSON).content(request))
            .andExpect(status().isOk()).andExpect(jsonPath("$.counted").value(true));
        mvc.perform(post(uri).contentType(MediaType.APPLICATION_JSON).content(request))
            .andExpect(status().isOk()).andExpect(jsonPath("$.counted").value(false));
        Integer downloads = jdbc.queryForObject(
            "SELECT COUNT(*) FROM mod_download_events WHERE mod_id=?", Integer.class, id);
        Integer outbox = jdbc.queryForObject("""
            SELECT COUNT(*) FROM mod_download_outbox o
            JOIN mod_download_events e ON e.id=o.download_event_id WHERE e.mod_id=?
            """, Integer.class, id);
        assertThat(downloads).isEqualTo(1);
        assertThat(outbox).isEqualTo(1);
        mvc.perform(get("/api/v1/mods/ranking?limit=50"))
            .andExpect(status().isOk()).andExpect(jsonPath("$[?(@.id == '%s')].downloads".formatted(id)).value(org.hamcrest.Matchers.hasItem(1)));
    }
}
