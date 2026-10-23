package com.planblindbox.service;

import com.planblindbox.dto.response.TodayResponse;

public interface TodayService {
    TodayResponse getToday(Long userId);
}
