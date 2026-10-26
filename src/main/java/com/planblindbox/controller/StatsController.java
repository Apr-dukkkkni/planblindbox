package com.planblindbox.controller;

import com.planblindbox.common.Result;
import com.planblindbox.dto.response.StatsResponse;
import com.planblindbox.service.StatsService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/stats")
@RequiredArgsConstructor
public class StatsController {
    private final StatsService statsService;

    @GetMapping
    public Result<StatsResponse> getStats(
            @RequestParam Long userId,
            @RequestParam(defaultValue = "7") int days) {
        return Result.success(statsService.getStats(userId, days));
    }
}
