package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.request.TimeRecordRequest;
import com.planblindbox.dto.response.TimeRecordResponse;
import com.planblindbox.service.TimeRecordService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.List;

@RestController
@RequestMapping("/time-records")
@RequiredArgsConstructor
public class TimeRecordController {
    private final TimeRecordService timeRecordService;

    @GetMapping
    public Result<List<TimeRecordResponse>> list(@RequestParam Long userId,
                                                 @RequestParam String date) {
        try {
            return Result.success(timeRecordService.list(userId, LocalDate.parse(date)));
        } catch (DateTimeParseException exception) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "date 格式应为 yyyy-MM-dd");
        }
    }

    @PostMapping
    public Result<TimeRecordResponse> create(@RequestParam Long userId,
                                             @Valid @RequestBody TimeRecordRequest request) {
        return Result.success(timeRecordService.create(userId, request));
    }

    @PutMapping("/{recordId}")
    public Result<TimeRecordResponse> update(@PathVariable Long recordId,
                                             @RequestParam Long userId,
                                             @Valid @RequestBody TimeRecordRequest request) {
        return Result.success(timeRecordService.update(userId, recordId, request));
    }

    @DeleteMapping("/{recordId}")
    public Result<Void> delete(@PathVariable Long recordId, @RequestParam Long userId) {
        timeRecordService.delete(userId, recordId);
        return Result.success();
    }
}
