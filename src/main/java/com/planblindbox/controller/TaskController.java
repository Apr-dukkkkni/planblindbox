package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.request.TaskCompleteRequest;
import com.planblindbox.dto.response.TaskCompleteResponse;
import com.planblindbox.dto.request.TaskCreateRequest;
import com.planblindbox.dto.request.TaskUpdateRequest;
import com.planblindbox.dto.response.TaskResponse;
import com.planblindbox.service.TaskService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/tasks")
@RequiredArgsConstructor
public class TaskController {

    private final TaskService taskService;


    @PostMapping
    public Result<TaskResponse> create(
            @Valid @RequestBody TaskCreateRequest request
    ) {

        return Result.success(
                taskService.create(request)
        );
    }


    @GetMapping("/{taskId}")
    public Result<TaskResponse> getById(
            @PathVariable Long taskId,
            @RequestParam Long userId
    ) {

        return Result.success(
                taskService.getById(userId, taskId)
        );
    }


    @GetMapping
    public Result<List<TaskResponse>> list(
            @RequestParam Long userId
    ) {

        return Result.success(
                taskService.list(userId)
        );
    }


    @PutMapping("/{taskId}")
    public Result<TaskResponse> update(
            @PathVariable Long taskId,
            @RequestParam Long userId,
            @Valid @RequestBody TaskUpdateRequest request
    ) {

        return Result.success(
                taskService.update(
                        userId,
                        taskId,
                        request
                )
        );
    }


    /** 追加今日执行量；达到 targetCount 后任务自动完成。 */
    @PostMapping("/{taskId}/complete")
    public Result<TaskCompleteResponse> complete(
            @PathVariable Long taskId,
            @RequestParam Long userId,
            @Valid @RequestBody TaskCompleteRequest request
    ) {
        return Result.success(taskService.complete(userId, taskId, request));
    }


    @DeleteMapping("/{taskId}")
    public Result<Void> delete(
            @PathVariable Long taskId,
            @RequestParam Long userId
    ) {

        taskService.delete(userId, taskId);

        return Result.success();
    }
}