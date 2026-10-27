package com.planblindbox.service;

import com.planblindbox.dto.request.TimeRecordRequest;
import com.planblindbox.dto.response.TimeRecordResponse;

import java.time.LocalDate;
import java.util.List;

public interface TimeRecordService {
    List<TimeRecordResponse> list(Long userId, LocalDate recordDate);
    TimeRecordResponse create(Long userId, TimeRecordRequest request);
    TimeRecordResponse update(Long userId, Long recordId, TimeRecordRequest request);
    void delete(Long userId, Long recordId);
}
