package com.planblindbox.service;

import com.planblindbox.dto.request.HabitCreateRequest;
import com.planblindbox.dto.request.HabitUpdateRequest;
import com.planblindbox.dto.response.HabitResponse;

import java.util.List;

public interface HabitService {
    HabitResponse create(HabitCreateRequest request);
    HabitResponse getById(Long userId, Long habitId);
    List<HabitResponse> list(Long userId);
    HabitResponse update(Long userId, Long habitId, HabitUpdateRequest request);
    void archive(Long userId, Long habitId);
    List<HabitResponse> getArchived(Long userId);

    HabitResponse restore(Long userId, Long habitId);
}
