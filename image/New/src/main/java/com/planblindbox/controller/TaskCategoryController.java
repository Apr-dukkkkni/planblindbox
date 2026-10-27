package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.request.TaskCategoryCreateRequest;
import com.planblindbox.dto.request.TaskCategoryUpdateRequest;
import com.planblindbox.dto.response.TaskCategoryResponse;
import com.planblindbox.service.TaskCategoryService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/task-categories")
@RequiredArgsConstructor
public class TaskCategoryController {
    private final TaskCategoryService service;

    @GetMapping
    public Result<List<TaskCategoryResponse>> list(
            @RequestParam Long userId,
            @RequestParam(defaultValue = "false") boolean includeDisabled) {
        return Result.success(service.list(userId, includeDisabled));
    }

    @PostMapping
    public Result<TaskCategoryResponse> create(
            @Valid @RequestBody TaskCategoryCreateRequest request) {
        return Result.success(service.create(request));
    }

    @PutMapping("/{categoryId}")
    public Result<TaskCategoryResponse> update(
            @PathVariable Long categoryId,
            @RequestParam Long userId,
            @Valid @RequestBody TaskCategoryUpdateRequest request) {
        return Result.success(service.update(userId, categoryId, request));
    }
}
