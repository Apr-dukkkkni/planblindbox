package com.planblindbox.service.impl;

import com.planblindbox.dto.request.TimeRecordRequest;
import com.planblindbox.dto.response.TimeRecordResponse;
import com.planblindbox.entity.Task;
import com.planblindbox.entity.TimeRecord;
import com.planblindbox.mapper.AppUserMapper;
import com.planblindbox.mapper.TaskMapper;
import com.planblindbox.mapper.TimeRecordMapper;
import com.planblindbox.service.TimeRecordService;
import com.planblindbox.util.BusinessTime;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;

@Service
@RequiredArgsConstructor
public class TimeRecordServiceImpl implements TimeRecordService {
    private final TimeRecordMapper timeRecordMapper;
    private final AppUserMapper appUserMapper;
    private final TaskMapper taskMapper;

    @Override
    @Transactional(readOnly = true)
    public List<TimeRecordResponse> list(Long userId, LocalDate recordDate) {
        validateUser(userId);
        if (recordDate == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "recordDate 不能为空");
        }
        return timeRecordMapper.selectByUserIdAndDate(userId, recordDate)
                .stream().map(TimeRecordServiceImpl::toResponse).toList();
    }

    @Override
    @Transactional
    public TimeRecordResponse create(Long userId, TimeRecordRequest request) {
        validateUser(userId);
        validateRequest(userId, request);
        TimeRecord record = fromRequest(userId, request);
        if (timeRecordMapper.insert(record) != 1) {
            throw new IllegalStateException("创建时间记录失败");
        }
        return toResponse(record);
    }

    @Override
    @Transactional
    public TimeRecordResponse update(Long userId, Long recordId, TimeRecordRequest request) {
        validateUser(userId);
        TimeRecord record = timeRecordMapper.selectByIdAndUserId(recordId, userId);
        if (record == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "时间记录不存在");
        }
        validateRequest(userId, request);
        TimeRecord updated = fromRequest(userId, request);
        updated.setTimeRecordId(recordId);
        updated.setCreateTime(record.getCreateTime());
        if (timeRecordMapper.update(updated) != 1) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "时间记录不存在");
        }
        return toResponse(updated);
    }

    @Override
    @Transactional
    public void delete(Long userId, Long recordId) {
        validateUser(userId);
        if (timeRecordMapper.delete(recordId, userId) != 1) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "时间记录不存在");
        }
    }

    private void validateUser(Long userId) {
        if (userId == null || userId <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "userId 必须为正整数");
        }
        if (appUserMapper.selectById(userId) == null) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "用户不存在");
        }
    }

    private void validateRequest(Long userId, TimeRecordRequest request) {
        if (request == null || request.getStartTime() == null || request.getEndTime() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "开始时间和结束时间不能为空");
        }
        LocalDateTime start = request.getStartTime();
        LocalDateTime end = request.getEndTime();
        if (!end.isAfter(start)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "结束时间必须晚于开始时间");
        }
        if (end.isAfter(LocalDateTime.now())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "时间记录不能包含未来时间");
        }
        // 一个时间块属于单个业务日；允许跨自然日，但不允许跨凌晨 05:00 的业务日边界。
        LocalDate startDate = BusinessTime.businessDate(start);
        LocalDate endDate = BusinessTime.businessDate(end.minusNanos(1));
        if (!startDate.equals(endDate)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "单条时间记录不能跨越凌晨 05:00 的业务日边界，请拆分记录");
        }
        if (Duration.between(start, end).toMinutes() < 1) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "时间记录至少为 1 分钟");
        }
        if (request.getTaskId() != null) {
            Task task = taskMapper.selectById(request.getTaskId(), userId);
            if (task == null) {
                throw new ResponseStatusException(HttpStatus.NOT_FOUND, "关联任务不存在或不属于该用户");
            }
        }
    }

    private TimeRecord fromRequest(Long userId, TimeRecordRequest request) {
        TimeRecord record = new TimeRecord();
        record.setUserId(userId);
        record.setTaskId(request.getTaskId());
        record.setTitle(request.getTitle().trim());
        record.setCategory(request.getCategory().trim());
        record.setStartTime(request.getStartTime().withNano(0));
        record.setEndTime(request.getEndTime().withNano(0));
        record.setDurationMinutes(Math.toIntExact(Duration.between(
                record.getStartTime(), record.getEndTime()).toMinutes()));
        record.setRecordDate(BusinessTime.businessDate(record.getStartTime()));
        record.setNote(request.getNote() == null || request.getNote().isBlank()
                ? null : request.getNote().trim());
        return record;
    }

    private static TimeRecordResponse toResponse(TimeRecord record) {
        return new TimeRecordResponse(record.getTimeRecordId(), record.getTaskId(), record.getTitle(),
                record.getCategory(), record.getStartTime(), record.getEndTime(),
                record.getDurationMinutes(), record.getRecordDate(), record.getNote());
    }
}
