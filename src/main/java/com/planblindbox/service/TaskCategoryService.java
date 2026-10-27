package com.planblindbox.service;

import com.planblindbox.dto.request.TaskCategoryCreateRequest;
import com.planblindbox.dto.request.TaskCategoryUpdateRequest;
import com.planblindbox.dto.response.TaskCategoryResponse;

import java.util.List;

public interface TaskCategoryService {
    List<TaskCategoryResponse> list(Long userId, boolean includeDisabled);
    TaskCategoryResponse create(TaskCategoryCreateRequest request);
    TaskCategoryResponse update(Long userId, Long categoryId, TaskCategoryUpdateRequest request);
}
