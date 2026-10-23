package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.response.TodayResponse;
import com.planblindbox.service.TodayService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/today")
@RequiredArgsConstructor
public class TodayController {
    private final TodayService todayService;

    @GetMapping
    public Result<TodayResponse> getToday(@RequestParam Long userId) {
        return Result.success(todayService.getToday(userId));
    }
}
