package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.response.CalendarDayResponse;
import com.planblindbox.dto.response.CalendarMonthResponse;
import com.planblindbox.dto.response.StatsResponse;
import com.planblindbox.service.CalendarService;
import com.planblindbox.service.StatsService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;

@RestController
@RequestMapping("/stats")
@RequiredArgsConstructor
public class StatsController {
    private final StatsService statsService;
    private final CalendarService calendarService;

    @GetMapping
    public Result<StatsResponse> getStats(
            @RequestParam Long userId,
            @RequestParam(defaultValue = "7") int days) {
        return Result.success(statsService.getStats(userId, days));
    }

    /** 获取指定月份的每日任务完成数与习惯打卡数。month 格式为 yyyy-MM。 */
    @GetMapping("/calendar")
    public Result<CalendarMonthResponse> getCalendarMonth(
            @RequestParam Long userId,
            @RequestParam String month) {
        try {
            return Result.success(calendarService.getMonth(userId, YearMonth.parse(month)));
        } catch (DateTimeParseException exception) {
            throw new org.springframework.web.server.ResponseStatusException(
                    org.springframework.http.HttpStatus.BAD_REQUEST,
                    "month 格式应为 yyyy-MM");
        }
    }

    /** 获取指定业务日期的任务与习惯记录。date 格式为 yyyy-MM-dd。 */
    @GetMapping("/calendar/day")
    public Result<CalendarDayResponse> getCalendarDay(
            @RequestParam Long userId,
            @RequestParam String date) {
        try {
            return Result.success(calendarService.getDay(userId, LocalDate.parse(date)));
        } catch (DateTimeParseException exception) {
            throw new org.springframework.web.server.ResponseStatusException(
                    org.springframework.http.HttpStatus.BAD_REQUEST,
                    "date 格式应为 yyyy-MM-dd");
        }
    }
}
