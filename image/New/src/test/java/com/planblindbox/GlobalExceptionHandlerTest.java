package com.planblindbox;

import com.planblindbox.common.Result;
import com.planblindbox.dto.request.TaskCompleteRequest;
import com.planblindbox.exception.BusinessException;
import com.planblindbox.exception.GlobalExceptionHandler;
import jakarta.validation.Valid;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.validation.beanvalidation.LocalValidatorFactoryBean;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** 不依赖 MySQL，确认 HTTP 状态码和 Result.code 一致。 */
class GlobalExceptionHandlerTest {
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        LocalValidatorFactoryBean validator = new LocalValidatorFactoryBean();
        validator.afterPropertiesSet();
        mvc = MockMvcBuilders.standaloneSetup(new DummyController())
                .setControllerAdvice(new GlobalExceptionHandler())
                .setValidator(validator)
                .build();
    }

    @ParameterizedTest
    @ValueSource(ints = {400, 404, 409})
    void businessExceptionPreservesStatus(int expected) throws Exception {
        mvc.perform(get("/_error-test/business").param("status", String.valueOf(expected)))
                .andExpect(result -> assertEquals(expected, result.getResponse().getStatus()))
                .andExpect(jsonPath("$.code").value(expected))
                .andExpect(jsonPath("$.message").value("业务错误"))
                .andExpect(jsonPath("$.data").value(org.hamcrest.Matchers.nullValue()));
    }

    @Test
    void existingResponseStatusExceptionIsUnified() throws Exception {
        mvc.perform(get("/_error-test/legacy"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value(409))
                .andExpect(jsonPath("$.message").value("今天已经打过卡了"));
    }

    @Test
    void invalidDtoProduces400() throws Exception {
        mvc.perform(post("/_error-test/complete")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"actualCount\":0}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400))
                .andExpect(jsonPath("$.message").value(org.hamcrest.Matchers.containsString("actualCount")));
    }

    @Test
    void brokenJsonProduces400() throws Exception {
        mvc.perform(post("/_error-test/complete")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{not json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400));
    }

    @Test
    void invalidQueryTypeProduces400() throws Exception {
        mvc.perform(get("/_error-test/typed").param("userId", "abc"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400));
    }

    @Test
    void missingQueryParameterProduces400() throws Exception {
        mvc.perform(get("/_error-test/typed"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value(400));
    }

    @Test
    void unexpectedExceptionIsSanitized() throws Exception {
        mvc.perform(get("/_error-test/internal"))
                .andExpect(status().isInternalServerError())
                .andExpect(jsonPath("$.code").value(500))
                .andExpect(jsonPath("$.message").value("服务器内部错误"))
                .andExpect(result -> assertFalse(result.getResponse().getContentAsString()
                        .contains("SENSITIVE_DATABASE_PASSWORD")));
    }

    @RestController
    @RequestMapping("/_error-test")
    static class DummyController {
        @GetMapping("/business")
        Result<Void> business(@RequestParam int status) {
            throw new BusinessException(HttpStatus.valueOf(status), "业务错误");
        }

        @GetMapping("/legacy")
        Result<Void> legacy() {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "今天已经打过卡了");
        }

        @PostMapping("/complete")
        Result<Void> complete(@Valid @RequestBody TaskCompleteRequest request) {
            return Result.success();
        }

        @GetMapping("/typed")
        Result<Void> typed(@RequestParam Long userId) {
            return Result.success();
        }

        @GetMapping("/internal")
        Result<Void> internal() {
            throw new IllegalStateException("SENSITIVE_DATABASE_PASSWORD");
        }
    }
}
