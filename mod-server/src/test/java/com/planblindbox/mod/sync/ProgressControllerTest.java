package com.planblindbox.mod.sync;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class ProgressControllerTest {
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new ProgressController()).build();
    }

    @Test
    void legacySnapshotGetIsGone() throws Exception {
        mvc.perform(get("/api/v1/me/progress"))
            .andExpect(status().isGone());
    }

    @Test
    void legacySnapshotPutIsGone() throws Exception {
        mvc.perform(put("/api/v1/me/progress")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"expectedRevision\":0,\"schemaVersion\":1,\"payload\":{}}"))
            .andExpect(status().isGone());
    }
}
