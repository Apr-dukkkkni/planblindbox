package com.planblindbox.mod;

import org.junit.jupiter.api.Test;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
@WithMockUser(username = "mod-integration-test")
class ModCatalogIntegrationTest {
    @Autowired MockMvc mvc;
    private final String raw="""
        {"schemaVersion":1,"id":"com.example.reading","name":"阅读模板","version":"1.0.0",
        "description":"每天阅读","permissions":["tasks.create"],"dependencies":[],
        "taskTemplates":[{"title":"读十页","targetCount":10,"importance":3,"difficulty":2}]}
        """;
    @Test void publishAndIdempotentDownloadAndUnauthorized() throws Exception {
        mvc.perform(post("/api/v1/admin/mods/publish").contentType(MediaType.APPLICATION_JSON).content(raw))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/api/v1/admin/mods/publish").header("Authorization","Bearer test-only-token")
                .contentType(MediaType.APPLICATION_JSON).content(raw))
                .andExpect(status().isOk()).andExpect(jsonPath("$.status").value("PUBLISHED"));
        mvc.perform(get("/api/v1/mods")).andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value("com.example.reading"))
                .andExpect(jsonPath("$[0].downloads").value(0));
        String request="{\"requestId\":\"c697e897-12f2-4c41-851e-b6e12dab89cb\"}";
        mvc.perform(post("/api/v1/mods/com.example.reading/versions/1.0.0/download")
                .contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isOk()).andExpect(jsonPath("$.counted").value(true));
        mvc.perform(post("/api/v1/mods/com.example.reading/versions/1.0.0/download")
                .contentType(MediaType.APPLICATION_JSON).content(request))
                .andExpect(status().isOk()).andExpect(jsonPath("$.counted").value(false));
        mvc.perform(get("/api/v1/mods/com.example.reading"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.downloads").value(1));
        mvc.perform(get("/api/v1/mods/com.example.reading/versions/1.0.0/manifest"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.id").value("com.example.reading"));
        mvc.perform(post("/api/v1/admin/mods/publish").header("Authorization","Bearer test-only-token")
                .contentType(MediaType.APPLICATION_JSON).content(raw))
                .andExpect(status().isConflict());
    }
}
