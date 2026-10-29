package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.response.DailySignInResponse;
import com.planblindbox.service.DailySignInService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import com.planblindbox.dto.response.DailySignInRecordResponse;
import java.util.List;

@RestController
@RequestMapping("/daily-sign-in")
@RequiredArgsConstructor
public class DailySignInController {

    private final DailySignInService dailySignInService;

    @PostMapping
    public Result<DailySignInResponse> signIn(
            @RequestParam Long userId) {
        return Result.success(
                dailySignInService.signIn(userId));
    }

    @GetMapping
    public Result<List<DailySignInRecordResponse>> getMonthlyRecords(
            @RequestParam Long userId,
            @RequestParam int year,
            @RequestParam int month) {

        return Result.success(
                dailySignInService.getMonthlyRecords(
                        userId, year, month));
    }
}