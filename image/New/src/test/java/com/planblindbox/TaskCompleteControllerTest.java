package com.planblindbox;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** 验证 Controller 路由存在、请求 DTO 校验有效；不需要数据库写入。 */
@SpringBootTest
@AutoConfigureMockMvc
class TaskCompleteControllerTest {
    @Autowired private MockMvc mockMvc;

    @Test
    void missingCountShouldReturn400() throws Exception {
        mockMvc.perform(post("/tasks/{taskId}/complete", 123)
                        .param("userId", "1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
    }
}
