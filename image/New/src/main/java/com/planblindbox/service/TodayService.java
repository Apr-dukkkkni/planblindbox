package com.planblindbox.service;

import com.planblindbox.dto.response.TodayResponse;

public interface TodayService {
    TodayResponse getToday(Long userId);

    /** sort 支持 time（默认）、importance；无效值返回 400。 */
    TodayResponse getToday(Long userId, String sort);
}
