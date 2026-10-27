package com.planblindbox.service.impl;

import com.planblindbox.dto.request.TaskCategoryCreateRequest;
import com.planblindbox.dto.request.TaskCategoryUpdateRequest;
import com.planblindbox.dto.response.TaskCategoryResponse;
import com.planblindbox.entity.TaskCategory;
import com.planblindbox.mapper.TaskCategoryMapper;
import com.planblindbox.service.TaskCategoryService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;

@Service
@RequiredArgsConstructor
public class TaskCategoryServiceImpl implements TaskCategoryService {
    private final TaskCategoryMapper mapper;

    private record DefaultCategory(String name, String color, String icon) {}

    private static final List<DefaultCategory> DEFAULTS = List.of(
            new DefaultCategory("学习", "#4F7CAC", "book"),
            new DefaultCategory("工作", "#7A6F9B", "briefcase"),
            new DefaultCategory("运动", "#E07A5F", "fitness"),
            new DefaultCategory("健康", "#5B8E7D", "heart"),
            new DefaultCategory("生活", "#C89F5D", "home"),
            new DefaultCategory("其他", "#607D8B", "more")
    );

    @Override
    @Transactional
    public List<TaskCategoryResponse> list(Long userId, boolean includeDisabled) {
        if (userId == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "userId 不能为空");
        }
        ensureDefaults(userId);
        return mapper.selectByUserId(userId, includeDisabled).stream()
                .map(this::toResponse)
                .toList();
    }

    @Override
    @Transactional
    public TaskCategoryResponse create(TaskCategoryCreateRequest request) {
        String name = normalizeName(request.getName());
        if (mapper.countByUserAndName(request.getUserId(), name) > 0) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "该分类名称已存在");
        }

        TaskCategory category = new TaskCategory();
        category.setUserId(request.getUserId());
        category.setName(name);
        category.setColor(normalizeColor(request.getColor()));
        category.setIcon(request.getIcon());
        category.setDefaultCategory(false);
        category.setEnabled(true);
        mapper.insert(category);
        return toResponse(mapper.selectById(request.getUserId(), category.getCategoryId()));
    }

    @Override
    @Transactional
    public TaskCategoryResponse update(Long userId, Long categoryId,
                                       TaskCategoryUpdateRequest request) {
        TaskCategory category = mapper.selectById(userId, categoryId);
        if (category == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "任务分类不存在");
        }

        if (request.getName() != null) {
            String name = normalizeName(request.getName());
            if (!name.equals(category.getName())
                    && mapper.countByUserAndName(userId, name) > 0) {
                throw new ResponseStatusException(HttpStatus.CONFLICT, "该分类名称已存在");
            }
            category.setName(name);
        }
        if (request.getColor() != null) {
            category.setColor(normalizeColor(request.getColor()));
        }
        if (request.getEnabled() != null) {
            category.setEnabled(request.getEnabled());
        }

        mapper.update(category);
        return toResponse(mapper.selectById(userId, categoryId));
    }

    private void ensureDefaults(Long userId) {
        if (mapper.countByUserId(userId) > 0) return;
        for (DefaultCategory item : DEFAULTS) {
            mapper.insertDefaultIfAbsent(userId, item.name(), item.color(), item.icon());
        }
    }

    private String normalizeName(String name) {
        if (name == null || name.trim().isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "分类名称不能为空");
        }
        String normalized = name.trim();
        if (normalized.length() > 50) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "分类名称不能超过 50 个字符");
        }
        return normalized;
    }

    private String normalizeColor(String color) {
        if (color == null || color.isBlank()) return "#607D8B";
        String normalized = color.trim();
        if (!normalized.matches("^#[0-9A-Fa-f]{6}$")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "颜色必须是 #RRGGBB 格式");
        }
        return normalized.toUpperCase();
    }

    private TaskCategoryResponse toResponse(TaskCategory category) {
        TaskCategoryResponse response = new TaskCategoryResponse();
        response.setCategoryId(category.getCategoryId());
        response.setName(category.getName());
        response.setColor(category.getColor());
        response.setIcon(category.getIcon());
        response.setDefaultCategory(category.getDefaultCategory());
        response.setEnabled(category.getEnabled());
        response.setCreateTime(category.getCreateTime());
        response.setUpdateTime(category.getUpdateTime());
        return response;
    }
}
