package com.planblindbox.service;

import com.planblindbox.dto.request.TaskCompleteRequest;
import com.planblindbox.dto.response.TaskCompleteResponse;
import com.planblindbox.dto.request.TaskCreateRequest;
import com.planblindbox.dto.request.TaskUpdateRequest;
import com.planblindbox.dto.response.TaskResponse;

import java.util.List;

public interface TaskService {

    TaskResponse create(TaskCreateRequest request);

    TaskResponse getById(
            Long userId,
            Long taskId
    );

    List<TaskResponse> list(Long userId);

    TaskResponse update(
            Long userId,
            Long taskId,
            TaskUpdateRequest request
    );

    TaskCompleteResponse complete(Long userId, Long taskId, TaskCompleteRequest request);

    void delete(
            Long userId,
            Long taskId
    );
}