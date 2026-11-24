package com.planblindbox.mod;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
class ModCapabilityAuthorizationIntegrationTest {
    private static final String MOD_ID = "com.example.approvaltest";
    private static final String VERSION = "1.0.0";
    private static final long USER_ID = 987654321L;
    private static final String CAPABILITY = "host.tasks.create";

    @Autowired MockMvc mvc;
    @Autowired JdbcTemplate jdbc;

    private final String manifest = """
      {"manifestVersion":1,"id":"com.example.approvaltest","version":"1.0.0",
       "name":{"zh-CN":"审批测试 MOD"},"description":"backend capability approval integration test",
       "publisher":{"id":"publisher.example"},"type":"content","contentKind":"task_template",
       "runtime":{"type":"declarative","apiVersion":"1","entrypoint":"content/task-templates.json"},
       "compatibility":{"hostApi":"^1.0.0","platforms":["android"]},
       "ui":{"allowedModes":["modal"],"defaultMode":"modal"},
       "storage":{"local":{"enabled":false,"quotaMiB":0,"persistent":false}},
       "permissions":[{"capability":"host.tasks.create","required":true,"reason":"用户选择模板后创建任务"}],
       "dependencies":[],"assets":{}}
      """;

    @BeforeEach
    void clean() {
        jdbc.update("DELETE FROM mod_capability_approval_audit WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM user_mod_capability_grant_audit WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM user_mod_capability_grant WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM mod_capability_approval WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM mod_download_events WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM mod_versions WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM mod_packages WHERE mod_id=?", MOD_ID);
        jdbc.update("DELETE FROM community_user WHERE user_id=?", USER_ID);
        jdbc.update("INSERT INTO community_user(user_id,username,email,password_hash,gender,status,credential_version) VALUES (?,?,?,?,?,?,?)",
                USER_ID, "cap-test", "cap-test@example.invalid", null, "unspecified", "ACTIVE", 0L);
    }

    @Test
    void v1PublishRequiresBothAdminApprovalAndUserGrantAndSupportsRevocation() throws Exception {
        mvc.perform(post("/api/v1/admin/mods/publish").header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content(manifest))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(MOD_ID));

        mvc.perform(get("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID)))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.adminApproved").value(false))
                .andExpect(jsonPath("$.userGranted").value(false))
                .andExpect(jsonPath("$.effective").value(false));

        mvc.perform(put("/api/v1/admin/mods/{id}/versions/{version}/capabilities/{cap}/approval", MOD_ID, VERSION, CAPABILITY)
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"approved\":true,\"reason\":\"通过安全审查\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.adminApproved").value(true))
                .andExpect(jsonPath("$.effective").value(false));

        mvc.perform(put("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID))))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"granted\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.adminApproved").value(true))
                .andExpect(jsonPath("$.userGranted").value(true))
                .andExpect(jsonPath("$.effective").value(true));

        mvc.perform(delete("/api/v1/me/mods/{id}/versions/{version}/capabilities/{cap}", MOD_ID, VERSION, CAPABILITY)
                        .with(jwt().jwt(token -> token.subject(Long.toString(USER_ID)))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userGranted").value(false))
                .andExpect(jsonPath("$.effective").value(false));
    }

    @Test
    void adminCannotApproveCapabilityNotDeclaredByManifest() throws Exception {
        mvc.perform(post("/api/v1/admin/mods/publish").header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content(manifest))
                .andExpect(status().isOk());
        mvc.perform(put("/api/v1/admin/mods/{id}/versions/{version}/capabilities/{cap}/approval", MOD_ID, VERSION, "host.habits.create")
                        .header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"approved\":true}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void legacyManifestPublishRemainsSupported() throws Exception {
        String legacy = """
          {"schemaVersion":1,"id":"com.example.legacyapproval","name":"Legacy","version":"1.0.0",
           "permissions":["tasks.create"],"dependencies":[],"taskTemplates":[]}
          """;
        mvc.perform(post("/api/v1/admin/mods/publish").header("Authorization", "Bearer test-only-token")
                        .contentType(MediaType.APPLICATION_JSON).content(legacy))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("PUBLISHED"));
    }
}
