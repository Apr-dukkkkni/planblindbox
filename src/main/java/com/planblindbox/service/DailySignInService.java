package com.planblindbox.service;

import com.planblindbox.dto.response.DailySignInResponse;
import com.planblindbox.dto.response.DailySignInRecordResponse;
import java.util.List;

public interface DailySignInService {

    DailySignInResponse signIn(Long userId);
    List<DailySignInRecordResponse> getMonthlyRecords(
            Long userId, int year, int month);
}