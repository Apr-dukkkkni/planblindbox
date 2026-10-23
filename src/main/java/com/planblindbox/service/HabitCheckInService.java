package com.planblindbox.service;

import com.planblindbox.dto.response.HabitCheckInResponse;

public interface HabitCheckInService {
    HabitCheckInResponse checkIn(Long userId, Long habitId);
    HabitCheckInResponse getTodayStatus(Long userId, Long habitId);
}
